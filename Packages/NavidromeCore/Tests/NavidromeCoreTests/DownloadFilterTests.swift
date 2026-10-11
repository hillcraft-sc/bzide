import Foundation
import Testing
@testable import NavidromeCore

struct DownloadFilterTests {
    private let collection = DownloadCollection(
        kind: .album, serverID: "al-1", name: "Café Sessions", artist: "Aurora Lines",
        songs: [Song(id: "so-1", title: "Dawn Chorus", artist: "Guest Singer")]
    )

    @Test func matchesNameArtistAndSongs() {
        #expect(collection.matches("sessions"))
        #expect(collection.matches("AURORA"))
        #expect(collection.matches("chorus"))
        #expect(collection.matches("guest"))
        #expect(!collection.matches("jazz"))
    }

    @Test func ignoresAccentsAndSurroundingSpaces() {
        #expect(collection.matches("  cafe "))
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(collection.matches(""))
        #expect(collection.matches("   "))
    }

    @Test @MainActor func managerFiltersNewestFirst() {
        let root = URL.temporaryDirectory.appending(path: "DownloadFilterTests-\(UUID().uuidString)")
        let manager = DownloadManager(
            directory: root,
            transport: FakeDownloadTransport(scratch: root.appending(path: "scratch")),
            downloadURL: { URL(string: "https://music.example.test/rest/download?id=\($0)")! },
            allowsCellular: { false }
        )
        manager.download(DownloadCollection(kind: .album, serverID: "a", name: "Blue Morning", songs: [], addedAt: Date(timeIntervalSince1970: 1)))
        manager.download(DownloadCollection(kind: .album, serverID: "b", name: "Blue Evening", songs: [], addedAt: Date(timeIntervalSince1970: 2)))
        manager.download(DownloadCollection(kind: .album, serverID: "c", name: "Red", songs: [], addedAt: Date(timeIntervalSince1970: 3)))
        #expect(manager.collections(matching: "blue").map(\.serverID) == ["b", "a"])
        #expect(manager.collections(matching: "").map(\.serverID) == ["c", "b", "a"])
    }
}
