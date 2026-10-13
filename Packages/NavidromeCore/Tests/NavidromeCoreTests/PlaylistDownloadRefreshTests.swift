import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct PlaylistDownloadRefreshTests {
    private let root = URL.temporaryDirectory.appending(path: "PlaylistDownloadRefreshTests-\(UUID().uuidString)")
    private let transport: FakeDownloadTransport

    init() {
        transport = FakeDownloadTransport(scratch: root.appending(path: "scratch"))
    }

    private func makeManager() -> DownloadManager {
        DownloadManager(
            directory: root.appending(path: "Downloads"),
            transport: transport,
            downloadURL: { URL(string: "https://music.example.test/rest/download?id=\($0)")! },
            allowsCellular: { false }
        )
    }

    private func songs(_ ids: [Int]) -> [Song] {
        ids.map { Song(id: "so-\($0)", title: "Song \($0)", suffix: "flac") }
    }

    private func playlist(_ ids: [Int], name: String = "Morning") -> Playlist {
        Playlist(id: "pl-1", name: name, songCount: ids.count, songs: songs(ids))
    }

    /// What the server answers for each playlist id, and how often it's asked.
    private final class Server: @unchecked Sendable {
        var playlists: [String: Playlist] = [:]
        var reachable = true
        var asks = 0

        func fetch(_ id: String) throws(SubsonicError) -> Playlist {
            asks += 1
            guard reachable else { throw .network(.notConnectedToInternet) }
            guard let playlist = playlists[id] else { throw .server(code: 70, message: "Playlist not found") }
            return playlist
        }
    }

    /// The clock tests move forward.
    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    private func refresher(_ manager: DownloadManager, _ server: Server, _ clock: Clock = Clock()) -> PlaylistDownloadRefresher {
        PlaylistDownloadRefresher(downloads: manager, fetch: { id async throws(SubsonicError) in try server.fetch(id) }, now: { clock.now })
    }

    /// Downloads the playlist and finishes every song.
    private func downloaded(_ manager: DownloadManager, _ playlist: Playlist) {
        manager.download(DownloadCollection(playlist: playlist))
        for song in playlist.songs { transport.finish(song.id) }
    }

    private func downloadedSongIDs(_ manager: DownloadManager) -> [String] {
        manager.collection(id: DownloadCollection.id(.playlist, serverID: "pl-1"))?.songs.map(\.id) ?? []
    }

    @Test func songsAddedOnTheServerDownloadAndRemovedOnesGo() async {
        let manager = makeManager()
        downloaded(manager, playlist([1, 2, 3]))
        let addedAt = manager.collection(id: "playlist:pl-1")?.addedAt
        let server = Server()
        server.playlists["pl-1"] = playlist([2, 3, 4], name: "Morning Mix")
        let changed = await refresher(manager, server).refreshAllIfDue()
        #expect(changed == 1)
        #expect(downloadedSongIDs(manager) == ["so-2", "so-3", "so-4"])
        #expect(manager.collection(id: "playlist:pl-1")?.name == "Morning Mix")
        #expect(manager.collection(id: "playlist:pl-1")?.addedAt == addedAt)
        // The new song downloads; the removed one's file is gone.
        #expect(transport.startedSongIDs.last == "so-4")
        #expect(manager.localFile(forSongID: "so-1") == nil)
        #expect(manager.localFile(forSongID: "so-2") != nil)
    }

    @Test func aNewOrderIsFollowed() async {
        let manager = makeManager()
        downloaded(manager, playlist([1, 2, 3]))
        let server = Server()
        server.playlists["pl-1"] = playlist([3, 1, 2])
        await refresher(manager, server).refreshAllIfDue()
        #expect(downloadedSongIDs(manager) == ["so-3", "so-1", "so-2"])
    }

    @Test func anUnchangedPlaylistIsLeftAlone() async {
        let manager = makeManager()
        downloaded(manager, playlist([1, 2]))
        let server = Server()
        server.playlists["pl-1"] = playlist([1, 2])
        #expect(await refresher(manager, server).refreshAllIfDue() == 0)
    }

    @Test func checksAreSpacedOut() async {
        let manager = makeManager()
        downloaded(manager, playlist([1, 2]))
        let server = Server()
        server.playlists["pl-1"] = playlist([1, 2])
        let clock = Clock()
        let refresher = refresher(manager, server, clock)
        await refresher.refreshAllIfDue()
        clock.now += 60
        await refresher.refreshAllIfDue()
        #expect(server.asks == 1)
        clock.now += PlaylistDownloadRefresher.interval
        await refresher.refreshAllIfDue()
        #expect(server.asks == 2)
    }

    @Test func offlineNothingChangesAndItTriesAgainNextTime() async {
        let manager = makeManager()
        downloaded(manager, playlist([1, 2]))
        let server = Server()
        server.playlists["pl-1"] = playlist([1, 2, 3])
        server.reachable = false
        let refresher = refresher(manager, server)
        #expect(await refresher.refreshAllIfDue() == 0)
        #expect(downloadedSongIDs(manager) == ["so-1", "so-2"])
        // Back online moments later: checked straight away, not after the interval.
        server.reachable = true
        #expect(await refresher.refreshAllIfDue() == 1)
        #expect(downloadedSongIDs(manager) == ["so-1", "so-2", "so-3"])
    }

    @Test func aPlaylistDeletedOnTheServerKeepsItsDownload() async {
        let manager = makeManager()
        downloaded(manager, playlist([1, 2]))
        let server = Server()
        let refresher = refresher(manager, server)
        await refresher.refreshAllIfDue()
        #expect(downloadedSongIDs(manager) == ["so-1", "so-2"])
        #expect(manager.localFile(forSongID: "so-1") != nil)
        // The server answered, so it isn't asked again until the interval passes.
        await refresher.refreshAllIfDue()
        #expect(server.asks == 1)
    }

    @Test func albumsAndPlaylistsNotDownloadedArentTouched() async {
        let manager = makeManager()
        manager.download(DownloadCollection(kind: .album, serverID: "al-1", name: "Album", songs: songs([7])))
        let server = Server()
        await refresher(manager, server).refreshAllIfDue()
        #expect(server.asks == 0)
        #expect(manager.refresh(playlist([1])) == false)
        #expect(manager.collection(id: "playlist:pl-1") == nil)
    }

    @Test func aPlaylistFetchedAnywayUpdatesItsDownload() async {
        let manager = makeManager()
        downloaded(manager, playlist([1]))
        let server = Server()
        let refresher = refresher(manager, server)
        refresher.refresh(playlist([1, 2]))
        #expect(downloadedSongIDs(manager) == ["so-1", "so-2"])
        // And by id, after adding songs to it in the app.
        server.playlists["pl-1"] = playlist([1, 2, 5])
        await refresher.refresh(playlistID: "pl-1")
        #expect(downloadedSongIDs(manager) == ["so-1", "so-2", "so-5"])
    }

    @Test func aSongInAnotherDownloadKeepsItsFile() async {
        let manager = makeManager()
        downloaded(manager, playlist([1, 2]))
        manager.download(DownloadCollection(kind: .album, serverID: "al-1", name: "Album", songs: songs([1])))
        let server = Server()
        server.playlists["pl-1"] = playlist([2])
        await refresher(manager, server).refreshAllIfDue()
        #expect(manager.localFile(forSongID: "so-1") != nil)
    }
}
