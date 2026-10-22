import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct SpinOffTests {
    private let seedSong = Song(id: "seed", title: "Phase", genre: "Rock")

    private func songs(_ prefix: String, _ count: Int) -> [Song] {
        (1...count).map { Song(id: "\(prefix)-\($0)", title: "\(prefix) \($0)") }
    }

    /// The server's answers, with a count of each kind of request.
    private final class Server: @unchecked Sendable {
        var similar: [Song] = []
        var genreMix: [String: [Song]] = [:]
        var libraryMix: [Song] = []
        var fails = false
        var randomGenres: [String?] = []

        var sources: SpinOffModel.Sources {
            .init(
                similarToSong: { _ in try self.answer(self.similar) },
                similarToArtist: { _ in try self.answer(self.similar) },
                random: { genre in
                    self.randomGenres.append(genre)
                    return try self.answer(genre.map { self.genreMix[$0] ?? [] } ?? self.libraryMix)
                }
            )
        }

        private func answer(_ songs: [Song]) throws -> [Song] {
            if fails { throw URLError(.notConnectedToInternet) }
            return songs
        }
    }

    private func makeEngine(store: InMemoryQueueStore = InMemoryQueueStore()) -> PlaybackEngine {
        PlaybackEngine(
            player: FakeAudioPlayer(), session: FakeAudioSession(), nowPlaying: FakeNowPlaying(), urls: FakeStreamURLs(),
            store: store, scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler()
        )
    }

    // The engine holds its Spin Off model weakly (the app's Library keeps it),
    // so every test keeps its model alive to the end.

    /// Waits for the refill the engine asked for: until `done` (at most two
    /// seconds), or a moment when nothing should change. The refill's fetch
    /// finishes off the main actor, so yielding alone isn't enough.
    private func settle(until done: (() -> Bool)? = nil) async {
        // A moment (0.3 s) when nothing should change; up to 2 s for a result.
        for _ in 0..<(done == nil ? 30 : 200) {
            if let done, done() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Choosing songs

    @Test func similarSongsComeFirstWithoutRepeats() async {
        let server = Server()
        server.similar = songs("similar", 40) + [Song(id: "queued", title: "Queued"), Song(id: "similar-1", title: "Again")]
        let batch = await SpinOffModel.batch(for: SpinOffSeed(song: seedSong), excluding: ["queued"], sources: server.sources)
        #expect(batch?.mixedFrom == nil)
        #expect(batch?.songs.count == SpinOffModel.batchSize)
        let ids = batch?.songs.map(\.id) ?? []
        #expect(!ids.contains("queued"))
        #expect(Set(ids).count == ids.count)
        #expect(server.randomGenres.isEmpty)
    }

    @Test func withoutSimilarSongsItMixesTheGenre() async {
        let server = Server()
        server.genreMix["Rock"] = songs("rock", 10)
        let batch = await SpinOffModel.batch(for: SpinOffSeed(song: seedSong), excluding: [], sources: server.sources)
        #expect(batch?.mixedFrom == "Rock")
        #expect(batch?.songs.count == 10)
        #expect(SpinOffModel.mixNotice(batch!) == "Similar songs aren't available from this server, so this is a mix of Rock.")
    }

    @Test func withoutAGenreItMixesTheLibrary() async {
        let server = Server()
        server.libraryMix = songs("any", 5)
        // An artist has no genre; a song whose genre has nothing new falls through too.
        let batch = await SpinOffModel.batch(for: .artist(id: "ar-1", name: "Band"), excluding: [], sources: server.sources)
        #expect(batch?.mixedFrom == "")
        #expect(server.randomGenres == [nil])
        #expect(SpinOffModel.mixNotice(batch!)?.contains("a random mix from your library") == true)
    }

    @Test func nothingAnywhereIsNil() async {
        let server = Server()
        server.fails = true
        #expect(await SpinOffModel.batch(for: SpinOffSeed(song: seedSong), excluding: [], sources: server.sources) == nil)
    }

    // MARK: Spinning off

    @Test func spinningOffPlaysTheSongThenSimilarOnes() async {
        let server = Server()
        server.similar = songs("similar", 30)
        let engine = makeEngine()
        let spinOff = SpinOffModel(engine: engine, sources: server.sources, keepSpinning: { false })
        await spinOff.start(from: seedSong)
        #expect(engine.queue.current?.song.id == "seed")
        #expect(engine.queue.entries.count == 1 + SpinOffModel.batchSize)
        #expect(engine.spinOff == SpinOffSeed(song: seedSong))
        #expect(spinOff.notice == nil)
    }

    @Test func aMixSaysWhy() async {
        let server = Server()
        server.genreMix["Rock"] = songs("rock", 30)
        let engine = makeEngine()
        let spinOff = SpinOffModel(engine: engine, sources: server.sources, keepSpinning: { false })
        await spinOff.start(from: seedSong)
        #expect(spinOff.notice?.contains("a mix of Rock") == true)
    }

    @Test func nothingFoundLeavesTheQueueAlone() async {
        let server = Server()
        server.fails = true
        let engine = makeEngine()
        engine.play(songs: songs("album", 3))
        let spinOff = SpinOffModel(engine: engine, sources: server.sources, keepSpinning: { false })
        await spinOff.start(from: seedSong)
        #expect(engine.queue.entries.map(\.song.id) == ["album-1", "album-2", "album-3"])
        #expect(spinOff.notice?.contains("Couldn't spin off") == true)
    }

    @Test func itGrowsWhenRunningLow() async {
        let server = Server()
        server.similar = songs("similar", 3)
        let engine = makeEngine()
        let spinOff = SpinOffModel(engine: engine, sources: server.sources, keepSpinning: { false })
        await spinOff.start(from: seedSong)
        #expect(engine.queue.entries.count == 4)
        // Moving on leaves two songs: more are fetched, none already queued.
        server.similar = songs("similar", 3) + songs("more", 5)
        engine.next()
        await settle { engine.queue.entries.count == 9 }
        #expect(engine.queue.entries.count == 9)
        #expect(Set(engine.queue.entries.suffix(5).map(\.song.id)) == ["more-1", "more-2", "more-3", "more-4", "more-5"])
        withExtendedLifetime(spinOff) {}
    }

    @Test func keepSpinningCarriesOnFromTheLastSong() async {
        let server = Server()
        server.similar = songs("similar", 5)
        let engine = makeEngine()
        // A box, as the closure is sendable: the setting turned on below.
        final class Setting: @unchecked Sendable { var keepSpinning = false }
        let setting = Setting()
        let spinOff = SpinOffModel(engine: engine, sources: server.sources, keepSpinning: { setting.keepSpinning })
        engine.play(songs: [seedSong])
        await settle()
        #expect(engine.queue.entries.count == 1)
        #expect(engine.spinOff == nil)
        setting.keepSpinning = true
        engine.play(songs: [seedSong])
        await settle { engine.queue.entries.count == 6 }
        #expect(engine.queue.entries.count == 6)
        #expect(engine.spinOff == SpinOffSeed(song: seedSong))
        withExtendedLifetime(spinOff) {}
    }

    @Test func keepSpinningWaitsForTheLastSong() async {
        let server = Server()
        server.similar = songs("similar", 5)
        let engine = makeEngine()
        let spinOff = SpinOffModel(engine: engine, sources: server.sources, keepSpinning: { true })
        engine.play(songs: songs("album", 2))
        await settle()
        // Two songs left but not on the last: an album plays out first.
        #expect(engine.queue.entries.count == 2)
        withExtendedLifetime(spinOff) {}
    }

    @Test func repeatStopsItGrowing() async {
        let server = Server()
        server.similar = songs("similar", 5)
        let engine = makeEngine()
        let spinOff = SpinOffModel(engine: engine, sources: server.sources, keepSpinning: { true })
        engine.cycleRepeatMode()
        engine.play(songs: [seedSong])
        await settle()
        #expect(engine.queue.entries.count == 1)
        withExtendedLifetime(spinOff) {}
    }

    @Test func startingASpinOffTurnsRepeatOffSoItGrows() async {
        let server = Server()
        server.similar = songs("similar", 3)
        let engine = makeEngine()
        engine.setRepeatMode(.all)
        let spinOff = SpinOffModel(engine: engine, sources: server.sources, keepSpinning: { false })
        await spinOff.start(from: seedSong)
        #expect(engine.repeatMode == .off)
        server.similar = songs("more", 5)
        engine.next()
        await settle { engine.queue.entries.count == 9 }
        #expect(engine.queue.entries.count == 9)
        withExtendedLifetime(spinOff) {}
    }

    @Test func skippingWhileItFetchesStillAddsTheSongs() async {
        let server = Server()
        server.similar = songs("similar", 3)
        let engine = makeEngine()
        let gate = Gate()
        let gated = SpinOffModel.Sources(
            similarToSong: { id in
                await gate.wait()
                return try await server.sources.similarToSong(id)
            },
            similarToArtist: server.sources.similarToArtist,
            random: server.sources.random
        )
        let spinOff = SpinOffModel(engine: engine, sources: gated, keepSpinning: { false })
        let starting = Task { await spinOff.start(from: seedSong) }
        await gate.open()
        await starting.value
        #expect(engine.queue.entries.count == 4)
        // Running low starts a fetch, held back; the user skips twice meanwhile.
        await gate.close()
        server.similar = songs("more", 5)
        engine.next()
        await settle()
        engine.next()
        engine.next()
        await gate.open()
        await settle { engine.queue.entries.count == 9 }
        #expect(engine.queue.entries.count == 9)
        #expect(engine.spinOff == SpinOffSeed(song: seedSong))
        withExtendedLifetime(spinOff) {}
    }

    /// Holds fetches back until opened.
    private actor Gate {
        private var isOpen = true
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiting.append($0) }
        }

        func close() {
            isOpen = false
        }

        func open() {
            isOpen = true
            waiting.forEach { $0.resume() }
            waiting = []
        }
    }

    @Test func playingSomethingElseEndsTheSpinOff() async {
        let server = Server()
        server.similar = songs("similar", 30)
        let engine = makeEngine()
        let spinOff = SpinOffModel(engine: engine, sources: server.sources, keepSpinning: { false })
        await spinOff.start(from: seedSong)
        engine.play(songs: songs("album", 10))
        #expect(engine.spinOff == nil)
    }

    @Test func aSpinOffIsSavedWithTheQueue() async {
        let store = InMemoryQueueStore()
        let server = Server()
        server.similar = songs("similar", 30)
        let engine = makeEngine(store: store)
        let spinOff = SpinOffModel(engine: engine, sources: server.sources, keepSpinning: { false })
        await spinOff.start(from: seedSong)
        let relaunched = makeEngine(store: store)
        #expect(relaunched.spinOff == SpinOffSeed(song: seedSong))
    }

    @Test func aQueueSavedBeforeSpinOffsLoadsAsNotOne() throws {
        // Written the way older versions did: no spin-off key at all.
        let older = try JSONEncoder().encode(QueueSnapshot(queue: PlaybackQueue(songs: songs("album", 2)), position: 12))
        #expect(String(decoding: older, as: UTF8.self).contains("spinOff") == false)
        let snapshot = try JSONDecoder().decode(QueueSnapshot.self, from: older)
        #expect(snapshot.spinOff == nil)
        #expect(snapshot.queue.entries.count == 2)
    }

    @Test func keepSpinningIsOffByDefault() {
        #expect(StreamingSettings().keepSpinning == false)
    }

    // MARK: Server requests

    @Test func asksTheServerForSimilarSongs() async throws {
        let body = #"{"subsonic-response":{"status":"ok","version":"1.16.1","similarSongs":{"song":[{"id":"so-9","title":"Nine"}]}}}"#
        let transport = FakeTransport(.json(body))
        let found = try await TestServer.client(transport).similarSongs(toSongID: "so-1", count: 30)
        #expect(found.map(\.id) == ["so-9"])
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path.hasSuffix("getSimilarSongs"))
        #expect(url.queryParameters["id"] == "so-1")
        #expect(url.queryParameters["count"] == "30")
    }

    @Test func aServerWithoutSimilarSongsAnswersEmpty() async throws {
        let transport = FakeTransport(.json(#"{"subsonic-response":{"status":"ok","version":"1.16.1","similarSongs2":{}}}"#))
        #expect(try await TestServer.client(transport).similarSongs(toArtistID: "ar-1").isEmpty)
    }

    @Test func randomSongsCanBeOneGenre() async throws {
        let transport = FakeTransport(.json(TestServer.ok))
        _ = try await TestServer.client(transport).randomSongs(size: 25, genre: "Rock")
        let url = try #require(await transport.requests.first?.url)
        #expect(url.queryParameters["genre"] == "Rock")
        #expect(url.queryParameters["size"] == "25")
    }
}
