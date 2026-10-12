import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct SongDownloadTests {
    private let root = URL.temporaryDirectory.appending(path: "SongDownloadTests-\(UUID().uuidString)")
    private let transport: FakeDownloadTransport

    init() {
        transport = FakeDownloadTransport(scratch: root.appending(path: "scratch"))
    }

    private func makeManager(transport: FakeDownloadTransport? = nil) -> DownloadManager {
        DownloadManager(
            directory: root.appending(path: "Downloads"),
            transport: transport ?? self.transport,
            downloadURL: { URL(string: "https://music.example.test/rest/download?id=\($0)")! },
            allowsCellular: { false }
        )
    }

    private let dawn = Song(id: "so-1", title: "Dawn", artist: "Aurora Lines", coverArtID: "al-1", suffix: "flac")
    private let noon = Song(id: "so-2", title: "Noon", artist: "Aurora Lines", suffix: "flac")

    @Test func aSongDownloadsOnItsOwn() throws {
        let manager = makeManager()
        let single = DownloadCollection(song: dawn)
        #expect(single.id == "song:so-1")
        #expect(single.name == "Dawn")
        #expect(single.coverArtID == "al-1")

        manager.download(single)
        #expect(transport.startedSongIDs == ["so-1"])
        #expect(manager.membership(ofSong: "so-1") == .own)
        transport.finish("so-1")
        #expect(manager.localFile(forSongID: "so-1") != nil)
    }

    @Test func songsAreListedApartFromAlbumsNewestFirst() {
        let manager = makeManager()
        manager.download(DownloadCollection(kind: .album, serverID: "al-9", name: "Album", songs: [noon], addedAt: Date(timeIntervalSince1970: 1)))
        manager.download(DownloadCollection(kind: .song, serverID: "so-1", name: "Dawn", artist: "Aurora Lines", songs: [dawn], addedAt: Date(timeIntervalSince1970: 2)))
        manager.download(DownloadCollection(kind: .song, serverID: "so-2", name: "Noon", songs: [noon], addedAt: Date(timeIntervalSince1970: 3)))

        #expect(manager.collections(matching: "").map(\.id) == ["album:al-9"])
        #expect(manager.songDownloads(matching: "").map(\.id) == ["song:so-2", "song:so-1"])
        // Searched by title: both test songs share an artist.
        #expect(manager.songDownloads(matching: "dawn").map(\.id) == ["song:so-1"])
        #expect(manager.songDownloads(matching: "aurora").map(\.id) == ["song:so-2", "song:so-1"])
    }

    @Test func membershipTellsOwnFromPartOfAnAlbum() {
        let manager = makeManager()
        manager.download(DownloadCollection(kind: .album, serverID: "al-1", name: "Album", songs: [dawn, noon]))
        #expect(manager.membership(ofSong: "so-1") == .inCollection)
        #expect(manager.membership(ofSong: "so-3") == .none)
        manager.download(DownloadCollection(song: dawn))
        #expect(manager.membership(ofSong: "so-1") == .own)
    }

    @Test func removingTheSongKeepsTheFileWhileItsAlbumNeedsIt() {
        let manager = makeManager()
        manager.download(DownloadCollection(song: dawn))
        transport.finish("so-1")
        manager.download(DownloadCollection(kind: .album, serverID: "al-1", name: "Album", songs: [dawn]))

        manager.remove(collectionID: "song:so-1")
        #expect(manager.localFile(forSongID: "so-1") != nil)
        #expect(manager.membership(ofSong: "so-1") == .inCollection)

        manager.remove(collectionID: "album:al-1")
        #expect(manager.localFile(forSongID: "so-1") == nil)
        #expect(manager.membership(ofSong: "so-1") == .none)
    }

    @Test func aSongDownloadSurvivesARelaunch() {
        let manager = makeManager()
        manager.download(DownloadCollection(song: dawn))
        transport.finish("so-1")
        let relaunched = makeManager(transport: FakeDownloadTransport(scratch: root.appending(path: "scratch")))
        #expect(relaunched.songDownloads(matching: "").map(\.id) == ["song:so-1"])
        #expect(relaunched.localFile(forSongID: "so-1") != nil)
    }
}
