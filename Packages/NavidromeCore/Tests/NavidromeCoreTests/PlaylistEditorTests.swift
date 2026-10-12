import Foundation
import Synchronization
import Testing
@testable import NavidromeCore

/// A playlist server held in memory, recording every change.
private final class FakePlaylistServer: Sendable {
    struct State {
        var playlists: [Playlist] = []
        var albums: [String: [Song]] = [:]
        var creates: [(name: String, songIDs: [String])] = []
        var adds: [(playlistID: String, songIDs: [String])] = []
        var listCalls = 0
        var failure: SubsonicError?
        var createReturnsNothing = false
    }

    let state = Mutex(State())

    var server: PlaylistEditor.Server {
        PlaylistEditor.Server(
            playlists: { () async throws(SubsonicError) in
                try self.state.withLock { state throws(SubsonicError) in
                    state.listCalls += 1
                    if let failure = state.failure { throw failure }
                    return state.playlists
                }
            },
            playlist: { id async throws(SubsonicError) in
                try self.state.withLock { state throws(SubsonicError) in
                    if let failure = state.failure { throw failure }
                    guard let playlist = state.playlists.first(where: { $0.id == id }) else { throw .server(code: 70, message: "Not found") }
                    return playlist
                }
            },
            albumSongs: { id async throws(SubsonicError) in
                self.state.withLock { $0.albums[id] ?? [] }
            },
            create: { name, songIDs async throws(SubsonicError) in
                try self.state.withLock { state throws(SubsonicError) in
                    if let failure = state.failure { throw failure }
                    state.creates.append((name, songIDs))
                    let playlist = Playlist(id: "pl-new", name: name, owner: "listener")
                    state.playlists.append(playlist)
                    return state.createReturnsNothing ? nil : playlist
                }
            },
            add: { id, songIDs async throws(SubsonicError) in
                try self.state.withLock { state throws(SubsonicError) in
                    if let failure = state.failure { throw failure }
                    state.adds.append((id, songIDs))
                }
            }
        )
    }
}

@MainActor
struct PlaylistEditorTests {
    private let fake = FakePlaylistServer()

    private func makeEditor() -> PlaylistEditor {
        PlaylistEditor(username: "listener", server: fake.server)
    }

    private static func songs(_ range: ClosedRange<Int>) -> [Song] {
        range.map { Song(id: "so-\($0)", title: "Song \($0)") }
    }

    private let morning = Playlist(id: "pl-1", name: "Morning", owner: "listener", songs: songs(1...2))

    @Test func offersOnlyOwnedPlaylistsByName() async {
        fake.state.withLock {
            $0.playlists = [
                Playlist(id: "pl-3", name: "zebra", owner: "listener"),
                Playlist(id: "pl-2", name: "Shared", owner: "someone-else"),
                Playlist(id: "pl-1", name: "Apple", owner: "listener"),
                Playlist(id: "pl-4", name: "Unknown owner"),
            ]
        }
        let editor = makeEditor()
        await editor.loadPlaylists()
        guard case .loaded(let playlists) = editor.playlists else {
            Issue.record("Expected playlists, got \(editor.playlists)")
            return
        }
        #expect(playlists.map(\.id) == ["pl-1", "pl-4", "pl-3"])
    }

    @Test func addsOnlySongsNotAlreadyThere() async {
        fake.state.withLock { $0.playlists = [morning] }
        let editor = makeEditor()
        // so-2 is in the playlist; so-3 is offered twice.
        let worked = await editor.add(.songs(Self.songs(2...3) + Self.songs(3...4)), to: morning)

        #expect(worked)
        let adds = fake.state.withLock { $0.adds }
        #expect(adds.map(\.playlistID) == ["pl-1"])
        #expect(adds.map(\.songIDs) == [["so-3", "so-4"]])
        #expect(editor.confirmation == "Added 2 songs to “Morning”. 2 were already there.")
        #expect(editor.error == nil)
    }

    @Test func nothingNewSendsNothing() async {
        fake.state.withLock { $0.playlists = [morning] }
        let editor = makeEditor()
        await editor.add(.songs(Self.songs(1...2)), to: morning)
        #expect(fake.state.withLock { $0.adds }.isEmpty)
        #expect(editor.confirmation == "All 2 songs are already in “Morning”.")

        await editor.add(.songs(Self.songs(1...1)), to: morning)
        #expect(editor.confirmation == "That song is already in “Morning”.")
    }

    @Test func anAlbumIsFetchedThenAdded() async {
        fake.state.withLock {
            $0.playlists = [morning]
            $0.albums["al-1"] = Self.songs(5...5)
        }
        let editor = makeEditor()
        await editor.add(.album(id: "al-1"), to: morning)
        #expect(fake.state.withLock { $0.adds }.map(\.songIDs) == [["so-5"]])
        #expect(editor.confirmation == "Added 1 song to “Morning”.")
    }

    @Test func longListsGoInChunks() async {
        let empty = Playlist(id: "pl-1", name: "Big", owner: "listener")
        fake.state.withLock { $0.playlists = [empty] }
        let editor = makeEditor()
        await editor.add(.songs(Self.songs(1...250)), to: empty)
        let chunks = fake.state.withLock { $0.adds }.map(\.songIDs)
        #expect(chunks.map(\.count) == [100, 100, 50])
        #expect(chunks.flatMap { $0 } == Self.songs(1...250).map(\.id))
    }

    @Test func createKeepsTheSongsInOrderWithRepeats() async {
        let editor = makeEditor()
        let queue = Self.songs(1...2) + Self.songs(1...1)
        let worked = await editor.create(named: "  Road Trip ", with: .songs(queue))

        #expect(worked)
        let creates = fake.state.withLock { $0.creates }
        #expect(creates.map(\.name) == ["Road Trip"])
        #expect(creates.map(\.songIDs) == [["so-1", "so-2", "so-1"]])
        #expect(editor.confirmation == "Created “Road Trip” with 3 songs.")
    }

    @Test func aLongNewPlaylistIsCreatedThenFilled() async {
        let editor = makeEditor()
        await editor.create(named: "Long", with: .songs(Self.songs(1...150)))
        #expect(fake.state.withLock { $0.creates }.map(\.songIDs.count) == [100])
        let adds = fake.state.withLock { $0.adds }
        #expect(adds.map(\.playlistID) == ["pl-new"])
        #expect(adds.map(\.songIDs.count) == [50])
    }

    @Test func aLongNewPlaylistNeedsTheServerToReturnIt() async {
        fake.state.withLock { $0.createReturnsNothing = true }
        let editor = makeEditor()
        let worked = await editor.create(named: "Long", with: .songs(Self.songs(1...150)))
        #expect(!worked)
        #expect(editor.error != nil)
        #expect(editor.confirmation == nil)

        // A short one doesn't need the id.
        #expect(await editor.create(named: "Short", with: .songs(Self.songs(1...3))))
    }

    @Test func anEmptyPlaylistCanBeCreated() async {
        let editor = makeEditor()
        #expect(await editor.create(named: "Later", with: .songs([])))
        #expect(fake.state.withLock { $0.creates }.map(\.songIDs) == [[]])
        #expect(editor.confirmation == "Created “Later”.")
    }

    @Test func aBlankNameCreatesNothing() async {
        let editor = makeEditor()
        #expect(await editor.create(named: "   ", with: .songs(Self.songs(1...3))) == false)
        #expect(fake.state.withLock { $0.creates }.isEmpty)
    }

    @Test func failureIsShownWithoutAConfirmation() async {
        let refused = SubsonicError.server(code: 50, message: "Not allowed")
        fake.state.withLock { $0.failure = refused }
        let editor = makeEditor()
        let worked = await editor.add(.songs(Self.songs(1...1)), to: morning)
        #expect(!worked)
        #expect(editor.error == refused.localizedDescription)
        #expect(editor.confirmation == nil)

        editor.dismissError()
        #expect(editor.error == nil)
    }

    @Test func playlistsReloadAfterAChange() async {
        fake.state.withLock { $0.playlists = [morning] }
        let editor = makeEditor()
        await editor.create(named: "New", with: .songs(Self.songs(1...1)))
        #expect(fake.state.withLock { $0.listCalls } == 1)
        guard case .loaded(let playlists) = editor.playlists else {
            Issue.record("Expected playlists")
            return
        }
        #expect(playlists.map(\.name) == ["Morning", "New"])
    }

    @Test func confirmationWording() {
        #expect(PlaylistEditor.addedMessage(added: 1, skipped: 1, to: "A") == "Added 1 song to “A”. 1 was already there.")
        #expect(PlaylistEditor.addedMessage(added: 3, skipped: 0, to: "A") == "Added 3 songs to “A”.")
    }

    @Test func chunking() {
        #expect([Int]().chunks(of: 2).isEmpty)
        #expect([1, 2, 3, 4, 5].chunks(of: 2) == [[1, 2], [3, 4], [5]])
    }
}

/// Checks what the playlist calls send and how their replies are read.
struct PlaylistRequestTests {
    private func items(_ url: URL, _ name: String) -> [String] {
        (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).filter { $0.name == name }.compactMap(\.value)
    }

    @Test func createSendsTheNameAndEverySongInOrder() async throws {
        let transport = FakeTransport(.json(TestServer.ok))
        let created = try await TestServer.client(transport).createPlaylist(name: "Road Trip", songIDs: ["so-2", "so-1"])
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path() == "/rest/createPlaylist")
        #expect(items(url, "name") == ["Road Trip"])
        #expect(items(url, "songId") == ["so-2", "so-1"])
        // No playlist in the reply (older servers) is not an error.
        #expect(created == nil)
    }

    @Test func createReadsTheNewPlaylist() async throws {
        let created = try await TestServer.client(FakeTransport(fixture: "getPlaylist")).createPlaylist(name: "Morning", songIDs: [])
        #expect(created?.id == "pl-1")
    }

    @Test func addSendsThePlaylistAndEverySong() async throws {
        let transport = FakeTransport(.json(TestServer.ok))
        try await TestServer.client(transport).addToPlaylist(id: "pl-1", songIDs: ["so-1", "so-1", "so-3"])
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path() == "/rest/updatePlaylist")
        #expect(items(url, "playlistId") == ["pl-1"])
        #expect(items(url, "songIdToAdd") == ["so-1", "so-1", "so-3"])
    }
}
