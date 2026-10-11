import Foundation
import Testing
@testable import NavidromeCore

@MainActor
final class FakeDownloadTransport: DownloadTransport {
    struct Start: Equatable {
        let songID: String
        let url: URL
        let allowsCellular: Bool
    }

    var onEvent: (@MainActor (DownloadEvent) -> Void)?
    private(set) var started: [Start] = []
    private(set) var cancelled: [String] = []
    /// What the system reports as still running, for relaunch tests.
    var systemActive: Set<String> = []
    private let scratch: URL

    init(scratch: URL) {
        self.scratch = scratch
    }

    var startedSongIDs: [String] { started.map(\.songID) }

    func start(songID: String, from url: URL, allowsCellular: Bool) {
        started.append(Start(songID: songID, url: url, allowsCellular: allowsCellular))
    }

    func cancel(songID: String) {
        cancelled.append(songID)
    }

    func activeSongIDs() async -> Set<String> {
        systemActive
    }

    /// Writes a small file standing in for the download and reports it finished.
    func finish(_ songID: String, fileExtension: String? = nil) {
        let file = scratch.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try? Data("audio of \(songID)".utf8).write(to: file)
        onEvent?(.finished(songID: songID, file: file, fileExtension: fileExtension))
    }

    func fail(_ songID: String, message: String = "The network connection was lost.") {
        onEvent?(.failed(songID: songID, message: message))
    }

    func progress(_ songID: String, _ fraction: Double) {
        onEvent?(.progress(songID: songID, fraction: fraction))
    }
}

@MainActor
final class FakeArtworkPinning: ArtworkPinning {
    private(set) var requests: [Set<String>] = []

    func keepOffline(coverArtIDs: Set<String>) {
        requests.append(coverArtIDs)
    }
}

@MainActor
struct DownloadManagerTests {
    private let root = URL.temporaryDirectory.appending(path: "DownloadManagerTests-\(UUID().uuidString)")
    private let transport: FakeDownloadTransport

    init() {
        transport = FakeDownloadTransport(scratch: root.appending(path: "scratch"))
    }

    private var directory: URL { root.appending(path: "Downloads") }

    private let artwork = FakeArtworkPinning()

    private func makeManager(transport: FakeDownloadTransport? = nil, allowsCellular: Bool = false) -> DownloadManager {
        DownloadManager(
            directory: directory,
            transport: transport ?? self.transport,
            downloadURL: { URL(string: "https://music.example.test/rest/download?id=\($0)")! },
            allowsCellular: { allowsCellular },
            artwork: artwork
        )
    }

    private func songs(_ range: ClosedRange<Int>) -> [Song] {
        range.map { Song(id: "so-\($0)", title: "Song \($0)", suffix: "flac") }
    }

    private func album(_ id: String, _ songs: [Song], addedAt: Date = Date()) -> DownloadCollection {
        DownloadCollection(kind: .album, serverID: id, name: "Album \(id)", songs: songs, addedAt: addedAt)
    }

    @Test func downloadsAFewAtATimeAndStartsTheNextWhenOneFinishes() {
        let manager = makeManager()
        let collection = album("al-1", songs(1...5))
        manager.download(collection)
        #expect(transport.startedSongIDs == ["so-1", "so-2", "so-3"])
        #expect(manager.state(ofSong: "so-4") == .waiting)

        transport.finish("so-2")
        #expect(transport.startedSongIDs == ["so-1", "so-2", "so-3", "so-4"])
        #expect(manager.state(ofSong: "so-2") == .done)
    }

    @Test func aFinishedSongPlaysFromItsFile() throws {
        let manager = makeManager()
        manager.download(album("al-1", songs(1...1)))
        transport.finish("so-1")

        let file = try #require(manager.localFile(forSongID: "so-1"))
        #expect(file.lastPathComponent == "so-1.flac")
        #expect(try String(contentsOf: file, encoding: .utf8) == "audio of so-1")
        #expect(manager.totalBytes == Int64("audio of so-1".utf8.count))
    }

    @Test func downloadsSurviveARelaunch() {
        let manager = makeManager()
        manager.download(album("al-1", songs(1...1)))
        transport.finish("so-1")

        let relaunched = makeManager(transport: FakeDownloadTransport(scratch: root.appending(path: "scratch")))
        #expect(relaunched.collections.map(\.id) == ["album:al-1"])
        #expect(relaunched.localFile(forSongID: "so-1") != nil)
    }

    @Test func relaunchAdoptsDownloadsTheSystemKeptRunning() async {
        let manager = makeManager()
        manager.download(album("al-1", songs(1...4)))

        let newTransport = FakeDownloadTransport(scratch: root.appending(path: "scratch"))
        newTransport.systemActive = ["so-1"]
        let relaunched = makeManager(transport: newTransport)
        await relaunched.resume()

        // so-1 is still running in the system; the rest start fresh.
        #expect(newTransport.startedSongIDs == ["so-2", "so-3"])
        #expect(relaunched.state(ofSong: "so-1") == .downloading(progress: nil))
        newTransport.finish("so-1")
        #expect(relaunched.localFile(forSongID: "so-1") != nil)
    }

    @Test func systemDownloadsNothingWantsAreCancelledOnRelaunch() async {
        transport.systemActive = ["so-99"]
        let manager = makeManager()
        await manager.resume()
        #expect(transport.cancelled == ["so-99"])
    }

    @Test func statusCountsDoneAndPartialProgress() {
        let manager = makeManager()
        let collection = album("al-1", songs(1...4))
        manager.download(collection)
        transport.finish("so-1")
        transport.progress("so-2", 0.5)

        let status = manager.status(of: collection)
        #expect(status.doneCount == 1)
        #expect(status.progress == 1.5 / 4)
        #expect(!status.isComplete)
    }

    @Test func tinyProgressStepsAreSkipped() {
        let manager = makeManager()
        manager.download(album("al-1", songs(1...1)))
        transport.progress("so-1", 0.5)
        transport.progress("so-1", 0.505)
        #expect(manager.state(ofSong: "so-1") == .downloading(progress: 0.5))
        transport.progress("so-1", 0.52)
        #expect(manager.state(ofSong: "so-1") == .downloading(progress: 0.52))
    }

    @Test func aSongSharedByTwoDownloadsStaysUntilBothAreRemoved() {
        let manager = makeManager()
        let shared = songs(1...1)
        manager.download(album("al-1", shared))
        manager.download(DownloadCollection(kind: .playlist, serverID: "pl-1", name: "Mix", songs: shared))
        transport.finish("so-1")
        #expect(transport.startedSongIDs == ["so-1"])

        manager.remove(collectionID: "album:al-1")
        #expect(manager.localFile(forSongID: "so-1") != nil)

        manager.remove(collectionID: "playlist:pl-1")
        #expect(manager.localFile(forSongID: "so-1") == nil)
        #expect(manager.totalBytes == 0)
    }

    @Test func removingStopsItsRunningDownloads() {
        let manager = makeManager()
        manager.download(album("al-1", songs(1...2)))
        manager.remove(collectionID: "album:al-1")
        #expect(Set(transport.cancelled) == ["so-1", "so-2"])
        #expect(manager.state(ofSong: "so-1") == .notDownloaded)
    }

    @Test func aDownloadFinishingAfterRemovalIsThrownAway() {
        let manager = makeManager()
        manager.download(album("al-1", songs(1...1)))
        manager.remove(collectionID: "album:al-1")
        transport.finish("so-1")
        #expect(manager.localFile(forSongID: "so-1") == nil)
        #expect(manager.totalBytes == 0)
    }

    @Test func failuresWaitForRetry() {
        let manager = makeManager()
        let collection = album("al-1", songs(1...1))
        manager.download(collection)
        transport.fail("so-1")
        #expect(manager.state(ofSong: "so-1") == .failed("The network connection was lost."))
        #expect(manager.status(of: collection).failedCount == 1)
        #expect(transport.started.count == 1)

        manager.retryFailed(in: collection)
        #expect(transport.startedSongIDs == ["so-1", "so-1"])
        #expect(manager.state(ofSong: "so-1") == .downloading(progress: nil))
    }

    @Test func olderDownloadsGoFirst() {
        let manager = makeManager()
        manager.download(album("al-2", songs(10...10), addedAt: Date(timeIntervalSince1970: 2)))
        manager.download(album("al-1", songs(1...3), addedAt: Date(timeIntervalSince1970: 1)))
        // al-2 started first as it was alone; then al-1, the older, fills the free slots.
        #expect(transport.startedSongIDs == ["so-10", "so-1", "so-2"])
    }

    @Test func redownloadingUpdatesTheSongList() {
        let manager = makeManager()
        manager.download(DownloadCollection(kind: .playlist, serverID: "pl-1", name: "Mix", songs: songs(1...2)))
        transport.finish("so-1")
        transport.finish("so-2")

        manager.download(DownloadCollection(kind: .playlist, serverID: "pl-1", name: "Mix", songs: songs(2...3)))
        #expect(manager.localFile(forSongID: "so-1") == nil)
        #expect(manager.localFile(forSongID: "so-2") != nil)
        #expect(transport.startedSongIDs.last == "so-3")
        #expect(manager.collections.count == 1)
    }

    @Test func extensionComesFromTheServerWhenTheSongHasNone() {
        let manager = makeManager()
        manager.download(album("al-1", [Song(id: "so-1", title: "No suffix")]))
        transport.finish("so-1", fileExtension: "mp3")
        #expect(manager.localFile(forSongID: "so-1")?.lastPathComponent == "so-1.mp3")
    }

    @Test func cellularSettingIsPassedToEachDownload() {
        let manager = makeManager(allowsCellular: true)
        manager.download(album("al-1", songs(1...1)))
        #expect(transport.started.first?.allowsCellular == true)
    }

    @Test func removeAllDeletesEverything() {
        let manager = makeManager()
        manager.download(album("al-1", songs(1...1)))
        manager.download(album("al-2", songs(2...2)))
        transport.finish("so-1")
        manager.removeAll()
        #expect(manager.collections.isEmpty)
        #expect(manager.localFile(forSongID: "so-1") == nil)
        #expect(transport.cancelled == ["so-2"])
    }

    @Test func coversOfDownloadedMusicAreKeptOffline() async {
        let manager = makeManager()
        let compilation = [
            Song(id: "so-1", title: "One", coverArtID: "al-1"),
            Song(id: "so-2", title: "Two", coverArtID: "mf-2"),
        ]
        manager.download(DownloadCollection(kind: .album, serverID: "al-1", name: "Mix", coverArtID: "al-1", songs: compilation))
        #expect(artwork.requests.last == ["al-1", "mf-2"])

        manager.download(DownloadCollection(kind: .playlist, serverID: "pl-1", name: "List", coverArtID: "pl-1", songs: []))
        #expect(artwork.requests.last == ["al-1", "mf-2", "pl-1"])

        manager.remove(collectionID: "album:al-1")
        #expect(artwork.requests.last == ["pl-1"])

        manager.removeAll()
        #expect(artwork.requests.last == [])

        // Launch retries covers that couldn't be fetched last time.
        await manager.resume()
        #expect(artwork.requests.count == 5)
    }
}
