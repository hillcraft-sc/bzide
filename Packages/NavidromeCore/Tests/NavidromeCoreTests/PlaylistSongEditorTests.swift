import Foundation
import Synchronization
import Testing
@testable import NavidromeCore

struct PlaylistSongEditTests {
    @Test func removalsStayRemovals() {
        #expect(PlaylistSongEdit(from: ["a", "b", "c", "d"], to: ["a", "c"]) == PlaylistSongEdit(removingIndexes: [1, 3], addingSongIDs: []))
        #expect(PlaylistSongEdit(from: ["a", "b"], to: []) == PlaylistSongEdit(removingIndexes: [0, 1], addingSongIDs: []))
    }

    @Test func aRepeatedSongIsRemovedByPosition() {
        // The second "a" goes; the first stays.
        #expect(PlaylistSongEdit(from: ["a", "b", "a"], to: ["a", "b"]) == PlaylistSongEdit(removingIndexes: [2], addingSongIDs: []))
    }

    @Test func aMoveReplacesEverythingFromTheFirstDifference() {
        // "d" to the second place: a stays, b c d go, then d b c come back.
        #expect(PlaylistSongEdit(from: ["a", "b", "c", "d"], to: ["a", "d", "b", "c"])
            == PlaylistSongEdit(removingIndexes: [1, 2, 3], addingSongIDs: ["d", "b", "c"]))
        // Swapping the last two touches only them.
        #expect(PlaylistSongEdit(from: ["a", "b", "c", "d"], to: ["a", "b", "d", "c"])
            == PlaylistSongEdit(removingIndexes: [2, 3], addingSongIDs: ["d", "c"]))
    }

    @Test func noChangeIsEmpty() {
        #expect(PlaylistSongEdit(from: ["a", "b"], to: ["a", "b"]).isEmpty)
    }
}

/// A playlist held in memory that applies edits the way the server does:
/// removals by position, then additions at the end.
private final class FakePlaylist: Sendable {
    struct State {
        var songIDs: [String]
        var edits: [PlaylistSongEdit] = []
        var failure: SubsonicError?
    }

    let state: Mutex<State>

    init(_ songIDs: [String]) {
        state = Mutex(State(songIDs: songIDs))
    }

    var server: PlaylistSongEditor.Server {
        PlaylistSongEditor.Server(
            playlist: { id async throws(SubsonicError) in
                let ids = self.state.withLock { $0.songIDs }
                return Playlist(id: id, name: "Mix", songs: ids.map { Song(id: $0, title: $0) })
            },
            edit: { _, edit async throws(SubsonicError) in
                try self.state.withLock { state throws(SubsonicError) in
                    if let failure = state.failure { throw failure }
                    state.edits.append(edit)
                    let removing = Set(edit.removingIndexes)
                    state.songIDs = state.songIDs.enumerated().filter { !removing.contains($0.offset) }.map(\.element)
                        + edit.addingSongIDs
                }
            }
        )
    }

    var songIDs: [String] { state.withLock { $0.songIDs } }
}

@MainActor
struct PlaylistSongEditorTests {
    private func songs(_ ids: [String]) -> [Song] {
        ids.map { Song(id: $0, title: $0) }
    }

    @Test func removingTakesTheSongOutOfThePlaylistOnly() async {
        let server = FakePlaylist(["a", "b", "c"])
        let editor = PlaylistSongEditor(playlistID: "pl-1", server: server.server)
        var reloads = 0
        #expect(await editor.remove(atOffsets: [1], from: songs(["a", "b", "c"]), reload: { reloads += 1 }))
        #expect(server.songIDs == ["a", "c"])
        #expect(reloads == 1)
        #expect(editor.error == nil)
    }

    @Test func movingSavesTheNewOrder() async {
        let server = FakePlaylist(["a", "b", "c", "d"])
        let editor = PlaylistSongEditor(playlistID: "pl-1", server: server.server)
        // Drag "d" (offset 3) to before "b" (offset 1).
        #expect(await editor.move(fromOffsets: [3], toOffset: 1, in: songs(["a", "b", "c", "d"]), reload: {}))
        #expect(server.songIDs == ["a", "d", "b", "c"])
        // Drag "a" to the end (past the last row).
        #expect(await editor.move(fromOffsets: [0], toOffset: 4, in: songs(["a", "d", "b", "c"]), reload: {}))
        #expect(server.songIDs == ["d", "b", "c", "a"])
    }

    @Test func theChangeShowsUntilThePageHasReloaded() async {
        let server = FakePlaylist(["a", "b"])
        let editor = PlaylistSongEditor(playlistID: "pl-1", server: server.server)
        var shownDuringReload: [String] = []
        await editor.remove(atOffsets: [0], from: songs(["a", "b"]), reload: {
            shownDuringReload = editor.shown(self.songs(["a", "b"])).map(\.id)
        })
        #expect(shownDuringReload == ["b"])
        // Afterwards the page's own (reloaded) songs show.
        #expect(editor.shown(songs(["b"])).map(\.id) == ["b"])
    }

    @Test func aPlaylistChangedElsewhereIsReloadedNotEdited() async {
        let server = FakePlaylist(["a", "b", "c"])
        let editor = PlaylistSongEditor(playlistID: "pl-1", server: server.server)
        var reloads = 0
        // The page still shows an older version.
        #expect(!(await editor.remove(atOffsets: [0], from: songs(["x", "a", "b", "c"]), reload: { reloads += 1 })))
        #expect(server.state.withLock { $0.edits.isEmpty })
        #expect(server.songIDs == ["a", "b", "c"])
        #expect(reloads == 1)
        #expect(editor.error != nil)
    }

    @Test func aFailedChangeGoesBackAndSaysWhy() async {
        let server = FakePlaylist(["a", "b"])
        server.state.withLock { $0.failure = .server(code: 50, message: "Not allowed") }
        let editor = PlaylistSongEditor(playlistID: "pl-1", server: server.server)
        var reloads = 0
        #expect(!(await editor.remove(atOffsets: [0], from: songs(["a", "b"]), reload: { reloads += 1 })))
        #expect(editor.shown(songs(["a", "b"])).map(\.id) == ["a", "b"])
        #expect(reloads == 0)
        #expect(editor.error != nil)
        editor.dismissError()
        #expect(editor.error == nil)
    }

    @Test func aMoveToTheSamePlaceSendsNothing() async {
        let server = FakePlaylist(["a", "b"])
        let editor = PlaylistSongEditor(playlistID: "pl-1", server: server.server)
        #expect(!(await editor.move(fromOffsets: [0], toOffset: 1, in: songs(["a", "b"]), reload: {})))
        #expect(server.state.withLock { $0.edits.isEmpty })
    }
}
