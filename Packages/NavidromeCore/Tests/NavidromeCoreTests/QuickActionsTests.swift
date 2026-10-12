import Foundation
import Synchronization
import Testing
@testable import NavidromeCore

/// A library held in memory, recording which albums were fetched.
private final class FakeLibraryServer: Sendable {
    struct State {
        var albums: [String: Album] = [:]
        var playlists: [String: Playlist] = [:]
        var artists: [String: Artist] = [:]
        var albumFetches: [String] = []
        var failingAlbum: String?
    }

    let state = Mutex(State())
    static let notFound = SubsonicError.server(code: 70, message: "Not found")

    var server: QuickActions.Server {
        QuickActions.Server(
            album: { id async throws(SubsonicError) in
                try self.state.withLock { state throws(SubsonicError) in
                    state.albumFetches.append(id)
                    if state.failingAlbum == id { throw .network(.notConnectedToInternet) }
                    guard let album = state.albums[id] else { throw Self.notFound }
                    return album
                }
            },
            playlist: { id async throws(SubsonicError) in
                try self.state.withLock { state throws(SubsonicError) in
                    guard let playlist = state.playlists[id] else { throw Self.notFound }
                    return playlist
                }
            },
            artist: { id async throws(SubsonicError) in
                try self.state.withLock { state throws(SubsonicError) in
                    guard let artist = state.artists[id] else { throw Self.notFound }
                    return artist
                }
            }
        )
    }
}

@MainActor
struct QuickActionsTests {
    private let fake = FakeLibraryServer()

    private final class Handled {
        var calls: [(QuickActions.Action, QuickActions.Resolved)] = []
        var songIDs: [[String]] { calls.map { $0.1.songs.map(\.id) } }
    }

    private func makeModel(_ handled: Handled) -> QuickActions {
        QuickActions(server: fake.server) { handled.calls.append(($0, $1)) }
    }

    private static func album(_ id: String, year: Int?, songs: ClosedRange<Int>) -> Album {
        Album(id: id, name: id, year: year, songs: songs.map { Song(id: "\(id)-\($0)", title: "\($0)") })
    }

    /// The artist as `getArtist` returns it: albums with counts but no songs.
    private func addArtist(_ id: String, albums: [Album]) {
        fake.state.withLock { state in
            for album in albums { state.albums[album.id] = album }
            let summaries = albums.map { Album(id: $0.id, name: $0.name, songCount: $0.songs.count, year: $0.year) }
            state.artists[id] = Artist(id: id, name: "Artist \(id)", albums: summaries)
        }
    }

    @Test func anAlbumIsFetchedThenHandledWithItsDownload() async {
        let album = Self.album("al-1", year: 2019, songs: 1...3)
        fake.state.withLock { $0.albums["al-1"] = album }
        let handled = Handled()
        await makeModel(handled).perform(.download, on: .album(id: "al-1"))

        #expect(handled.calls.map(\.0) == [.download])
        #expect(handled.songIDs == [["al-1-1", "al-1-2", "al-1-3"]])
        // Not compared whole: each collection records when it was made (`addedAt`).
        let download = handled.calls.first?.1.download
        #expect(download?.id == DownloadCollection.id(.album, serverID: "al-1"))
        #expect(download?.name == album.name)
        #expect(download?.songs == album.songs)
    }

    @Test func aPlaylistIsFetchedThenHandled() async {
        let playlist = Playlist(id: "pl-1", name: "Morning", songs: [Song(id: "so-1", title: "One")])
        fake.state.withLock { $0.playlists["pl-1"] = playlist }
        let handled = Handled()
        await makeModel(handled).perform(.shuffle, on: .playlist(id: "pl-1"))
        #expect(handled.calls.map(\.0) == [.shuffle])
        #expect(handled.songIDs == [["so-1"]])
        #expect(handled.calls.first?.1.download?.id == DownloadCollection.id(.playlist, serverID: "pl-1"))
    }

    @Test func songsAtHandNeedNoFetch() async {
        let handled = Handled()
        await makeModel(handled).perform(.addToPlaylist, on: .songs([Song(id: "so-1", title: "One")]))
        #expect(handled.songIDs == [["so-1"]])
        #expect(fake.state.withLock { $0.albumFetches }.isEmpty)
    }

    @Test func anArtistPlaysOldestAlbumFirstEachInTrackOrder() async {
        addArtist("ar-1", albums: [
            Self.album("new", year: 2020, songs: 1...2),
            Self.album("undated", year: nil, songs: 1...1),
            Self.album("old", year: 1999, songs: 1...2),
        ])
        let handled = Handled()
        await makeModel(handled).perform(.play, on: .artist(id: "ar-1"))
        #expect(handled.songIDs == [["old-1", "old-2", "new-1", "new-2", "undated-1"]])
        #expect(handled.calls.first?.1.download == nil)
    }

    @Test func manyAlbumsKeepTheirOrder() async {
        // More albums than are fetched at once.
        let albums = (1...9).map { Self.album("al-\($0)", year: 2000 + $0, songs: 1...1) }
        addArtist("ar-1", albums: albums)
        let handled = Handled()
        await makeModel(handled).perform(.addToQueue, on: .artist(id: "ar-1"))
        #expect(handled.songIDs == [(1...9).map { "al-\($0)-1" }])
    }

    @Test func aBigArtistAsksFirst() async {
        addArtist("ar-1", albums: [Self.album("a", year: 2000, songs: 1...60), Self.album("b", year: 2001, songs: 1...41)])
        let handled = Handled()
        let model = makeModel(handled)
        await model.perform(.addToPlaylist, on: .artist(id: "ar-1"))

        #expect(handled.calls.isEmpty)
        #expect(fake.state.withLock { $0.albumFetches }.isEmpty)
        #expect(model.confirmation?.songCount == 101)
        #expect(model.confirmation?.action == .addToPlaylist)

        await model.confirm()
        #expect(model.confirmation == nil)
        #expect(handled.calls.map(\.0) == [.addToPlaylist])
        #expect(handled.songIDs.first?.count == 101)
    }

    @Test func aBigArtistCanBeCancelled() async {
        addArtist("ar-1", albums: [Self.album("a", year: 2000, songs: 1...101)])
        let handled = Handled()
        let model = makeModel(handled)
        await model.perform(.play, on: .artist(id: "ar-1"))
        model.cancelConfirmation()
        await model.confirm()
        #expect(handled.calls.isEmpty)
    }

    @Test func exactlyTheThresholdDoesNotAsk() async {
        addArtist("ar-1", albums: [Self.album("a", year: 2000, songs: 1...QuickActions.confirmationThreshold)])
        let handled = Handled()
        let model = makeModel(handled)
        await model.perform(.play, on: .artist(id: "ar-1"))
        #expect(model.confirmation == nil)
        #expect(handled.calls.count == 1)
    }

    @Test func oneFailingAlbumFailsTheArtist() async {
        addArtist("ar-1", albums: [Self.album("a", year: 2000, songs: 1...2), Self.album("b", year: 2001, songs: 1...2)])
        fake.state.withLock { $0.failingAlbum = "b" }
        let handled = Handled()
        let model = makeModel(handled)
        await model.perform(.play, on: .artist(id: "ar-1"))
        #expect(handled.calls.isEmpty)
        #expect(model.error == SubsonicError.network(.notConnectedToInternet).localizedDescription)

        model.dismissError()
        #expect(model.error == nil)
    }

    @Test func nothingToPlaySaysSo() async {
        fake.state.withLock { $0.albums["al-1"] = Album(id: "al-1", name: "Empty") }
        let handled = Handled()
        let model = makeModel(handled)
        await model.perform(.play, on: .album(id: "al-1"))
        #expect(handled.calls.isEmpty)
        #expect(model.error == "There are no songs to play.")
    }

    @Test func aSecondChoiceForTheSameThingWhileLoadingIsIgnored() async {
        let gate = GatedFetch<String, Album>()
        let handled = Handled()
        let model = QuickActions(
            server: QuickActions.Server(
                album: { id async throws(SubsonicError) in try await gate.fetch(id) },
                playlist: { _ async throws(SubsonicError) in throw FakeLibraryServer.notFound },
                artist: { _ async throws(SubsonicError) in throw FakeLibraryServer.notFound }
            ),
            handle: { handled.calls.append(($0, $1)) }
        )
        let first = Task { @MainActor in await model.perform(.addToQueue, on: .album(id: "al-1")) }
        await gate.waitForCalls(1)
        await model.perform(.addToQueue, on: .album(id: "al-1"))
        gate.reply(to: 0, with: .success(Self.album("al-1", year: nil, songs: 1...1)))
        await first.value
        #expect(gate.requests.count == 1)
        #expect(handled.calls.count == 1)
    }
}
