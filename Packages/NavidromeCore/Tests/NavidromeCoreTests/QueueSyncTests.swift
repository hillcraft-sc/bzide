import Foundation
import Synchronization
import Testing
@testable import NavidromeCore

@MainActor
struct QueueSyncTests {
    private let songs = (1...4).map { Song(id: "so-\($0)", title: "Song \($0)", duration: 200) }

    final class Server: Sendable {
        let saved = Mutex<[ServerPlayQueue]>([])
        let stored = Mutex<ServerPlayQueue?>(nil)
        let limit: Int

        init(stored: ServerPlayQueue? = nil, limit: Int = QueueSync.postSongLimit) {
            self.stored.withLock { $0 = stored }
            self.limit = limit
        }

        var sources: QueueSync.Sources {
            QueueSync.Sources(
                save: { queue in self.saved.withLock { $0.append(queue) } },
                load: { self.stored.withLock { $0 } },
                songLimit: { self.limit }
            )
        }

        var saves: [ServerPlayQueue] { saved.withLock { $0 } }
    }

    private func makeEngine() -> PlaybackEngine {
        PlaybackEngine(player: FakeAudioPlayer(), session: FakeAudioSession(), nowPlaying: FakeNowPlaying(), urls: FakeStreamURLs(), store: InMemoryQueueStore(), scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler())
    }

    private func file() -> URL {
        URL.temporaryDirectory.appending(path: "QueueSync-\(UUID().uuidString).json")
    }

    private func sync(_ engine: PlaybackEngine, _ server: Server, isOn: Bool = true, fileURL: URL? = nil) -> QueueSync {
        QueueSync(engine: engine, sources: server.sources, isOn: { isOn }, fileURL: fileURL, sleep: { _ in })
    }

    /// Lets the scheduled save run.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func aChangeSavesTheQueueOnce() async {
        let engine = makeEngine()
        let server = Server()
        let sync = sync(engine, server)
        sync.start()
        engine.play(songs: songs, startIndex: 1)
        await settle()
        #expect(server.saves.map(\.songs) == [songs])
        #expect(server.saves.first?.currentIndex == 1)
        // Nothing new: not saved again.
        await sync.saveNow()
        #expect(server.saves.count == 1)
    }

    @Test func offDoesNothing() async {
        let engine = makeEngine()
        let server = Server(stored: ServerPlayQueue(songs: songs, currentIndex: 0, position: 0))
        let sync = sync(engine, server, isOn: false)
        sync.start()
        engine.play(songs: songs)
        await settle()
        await sync.checkServer()
        #expect(server.saves.isEmpty)
        #expect(sync.offer == nil)
    }

    @Test func stationsArentSaved() async {
        let engine = makeEngine()
        let server = Server()
        let sync = sync(engine, server)
        let station = Song(station: RadioStation(id: "rs-1", name: "Night Waves", streamURL: URL(string: "https://example.com/live")!), stream: URL(string: "https://example.com/live")!)
        engine.play(songs: [station])
        #expect(await sync.songsToSave() == nil)
        engine.play(songs: [songs[0], station, songs[1]], startIndex: 2)
        let saved = await sync.songsToSave()
        #expect(saved?.songs == [songs[0], songs[1]])
        #expect(saved?.currentIndex == 1)
    }

    @Test func aLongQueueIsAWindowAroundTheCurrentSong() async {
        let engine = makeEngine()
        let many = (1...40).map { Song(id: "so-\($0)", title: "Song \($0)") }
        let sync = sync(engine, Server(limit: 15))
        engine.play(songs: many, startIndex: 20)
        let saved = await sync.songsToSave()
        #expect(saved?.songs.count == 15)
        #expect(saved?.songs.first?.id == "so-11")
        #expect(saved?.current?.id == "so-21")
        // Near the end, the window ends with the queue.
        engine.play(songs: many, startIndex: 38)
        #expect(await sync.songsToSave()?.songs.last?.id == "so-40")
        #expect(await sync.songsToSave()?.current?.id == "so-39")
    }

    @Test func aQueueSavedElsewhereIsOfferedAndContinues() async {
        let engine = makeEngine()
        let elsewhere = ServerPlayQueue(songs: songs, currentIndex: 2, position: 75, changedBy: "Feishin")
        let sync = sync(engine, Server(stored: elsewhere))
        await sync.checkServer()
        #expect(sync.offer == elsewhere)
        sync.continueOffer()
        #expect(sync.offer == nil)
        #expect(engine.queue.current?.song == songs[2])
        #expect(engine.position == 75)
    }

    @Test func whatThisDeviceSavedIsntOffered() async {
        let engine = makeEngine()
        let server = Server()
        let sync = sync(engine, server)
        sync.start()
        engine.play(songs: songs)
        await settle()
        server.stored.withLock { $0 = server.saves.last }
        await sync.checkServer()
        #expect(sync.offer == nil)
    }

    @Test func aDeclinedQueueIsntOfferedAgainEvenAfterRelaunch() async {
        let url = file()
        let elsewhere = ServerPlayQueue(songs: songs, currentIndex: 1, position: 30)
        let server = Server(stored: elsewhere)
        let first = sync(makeEngine(), server, fileURL: url)
        await first.checkServer()
        first.declineOffer()
        let relaunched = sync(makeEngine(), server, fileURL: url)
        await relaunched.checkServer()
        #expect(relaunched.offer == nil)
        // A newer one is.
        server.stored.withLock { $0?.currentIndex = 3 }
        await relaunched.checkServer()
        #expect(relaunched.offer?.currentIndex == 3)
    }

    @Test func savingHereDropsTheOffer() async {
        let engine = makeEngine()
        let sync = sync(engine, Server(stored: ServerPlayQueue(songs: songs, currentIndex: 1, position: 0)))
        sync.start()
        await sync.checkServer()
        #expect(sync.offer != nil)
        engine.play(songs: [songs[3]])
        await settle()
        #expect(sync.offer == nil)
    }

    @Test func theOfferSaysWhereItsFrom() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var queue = ServerPlayQueue(songs: songs, currentIndex: 0, position: 0, changed: now.addingTimeInterval(-300), changedBy: "Feishin")
        #expect(queue.offerTitle == "Continue “Song 1”?")
        #expect(queue.offerDetail(now: now).hasPrefix("From Feishin, "))
        queue.changedBy = "Bzide"
        #expect(queue.offerDetail(now: now).hasPrefix("From Bzide on another device, "))
        queue.changed = nil
        queue.changedBy = nil
        #expect(queue.offerDetail(now: now) == "From another device")
    }
}

struct PlayQueueRequestTests {
    private func items(_ url: URL, _ name: String) -> [String] {
        (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).filter { $0.name == name }.compactMap(\.value)
    }

    @Test func savingByIDNamesTheCurrentSong() async throws {
        let transport = FakeTransport(.json(TestServer.ok))
        try await TestServer.client(transport).savePlayQueue(songIDs: ["a", "b", "a"], currentIndex: 1, position: 12.5, byIndex: false, post: false)
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path() == "/rest/savePlayQueue")
        #expect(items(url, "id") == ["a", "b", "a"])
        #expect(items(url, "current") == ["b"])
        #expect(items(url, "position") == ["12500"])
    }

    @Test func savingByIndexNamesItsPosition() async throws {
        let transport = FakeTransport(.json(TestServer.ok))
        try await TestServer.client(transport).savePlayQueue(songIDs: ["a", "b", "a"], currentIndex: 2, position: 0, byIndex: true, post: false)
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path() == "/rest/savePlayQueueByIndex")
        #expect(items(url, "currentIndex") == ["2"])
        #expect(items(url, "current").isEmpty)
    }

    @Test func theSavedQueueIsRead() async throws {
        let json = #"""
        {"subsonic-response": {"status": "ok", "version": "1.16.1", "playQueue": {
          "current": "b", "position": 61500, "username": "listener",
          "changed": "2026-10-24T02:19:35.784818075Z", "changedBy": "Feishin",
          "entry": [{"id": "a", "title": "A"}, {"id": "b", "title": "B"}]
        }}}
        """#
        let queue = try #require(try await TestServer.client(FakeTransport(.json(json))).playQueue(byIndex: false))
        #expect(queue.songs.map(\.id) == ["a", "b"])
        #expect(queue.currentIndex == 1)
        #expect(queue.position == 61.5)
        #expect(queue.changedBy == "Feishin")
        // Nanoseconds, as Navidrome writes them, read to well within a millisecond.
        let changed = try #require(queue.changed)
        let expected = try #require(MediaDates.date("2026-10-24T02:19:35.784Z"))
        #expect(abs(changed.timeIntervalSince(expected)) < 0.001)
    }

    @Test func theSavedQueueIsReadByIndex() async throws {
        let json = #"""
        {"subsonic-response": {"status": "ok", "version": "1.16.1", "playQueueByIndex": {
          "currentIndex": 2, "username": "listener", "changed": "2026-10-24T02:19:35Z", "changedBy": "Bzide",
          "entry": [{"id": "a", "title": "A"}, {"id": "b", "title": "B"}, {"id": "a", "title": "A"}]
        }}}
        """#
        let queue = try #require(try await TestServer.client(FakeTransport(.json(json))).playQueue(byIndex: true))
        #expect(queue.currentIndex == 2)
        #expect(queue.position == 0)
    }

    @Test func noSavedQueueIsNil() async throws {
        let empty = #"{"subsonic-response": {"status": "ok", "version": "1.16.1", "playQueue": {}}}"#
        #expect(try await TestServer.client(FakeTransport(.json(empty))).playQueue(byIndex: false) == nil)
        #expect(try await TestServer.client(FakeTransport(.json(TestServer.ok))).playQueue(byIndex: false) == nil)
        let notFound = TestServer.failed(code: 70, message: "No play queue")
        #expect(try await TestServer.client(FakeTransport(.json(notFound))).playQueue(byIndex: false) == nil)
    }
}
