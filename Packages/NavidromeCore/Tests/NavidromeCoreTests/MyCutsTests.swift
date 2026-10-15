import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct MyCutsTests {
    /// A library of `count` songs; every tenth is rated Rocks (5), every
    /// tenth plus one Don't Hate It (3), every tenth plus two Meh (2).
    private final class Library: @unchecked Sendable {
        let songs: [Song]
        var pageRequests: [Int] = []

        init(count: Int) {
            songs = (0..<count).map { index in
                let rating: Int? = switch index % 10 {
                case 0: 5
                case 1: 3
                case 2: 2
                default: nil
                }
                return Song(id: "so-\(index)", title: "Song \(index)", userRating: rating)
            }
        }

        func page(_ count: Int, _ offset: Int) -> [Song] {
            pageRequests.append(offset)
            guard offset < songs.count else { return [] }
            return Array(songs[offset..<min(offset + count, songs.count)])
        }
    }

    /// The clock tests move forward.
    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    private func pool(_ library: Library, _ clock: Clock = Clock()) -> RatedSongPool {
        RatedSongPool(fetchPage: { count, offset in library.page(count, offset) }, now: { clock.now })
    }

    @Test func findsTheRatedSongsInTheWholeLibrary() async throws {
        let library = Library(count: 4_321)
        let found = try await pool(library).songs()
        #expect(found.librarySize == 4_321)
        // Rocks (indexes 0, 10… 4320: 433) and Don't Hate It (1, 11… 4311: 432);
        // Meh and unrated are left out.
        #expect(found.songs.count == 433 + 432)
        #expect(found.songs.allSatisfy { [3, 5].contains($0.userRating ?? 0) })
        // Pages four at a time until one comes back short: the third set of
        // four (4,000 to 5,500) holds the short page at 4,000.
        #expect(library.pageRequests.max() == 5_500)
        #expect(library.pageRequests.count == 12)
    }

    @Test func rememberedForAWhileThenLooksAgain() async throws {
        let library = Library(count: 100)
        let clock = Clock()
        let pool = pool(library, clock)
        _ = try await pool.songs()
        let asked = library.pageRequests.count
        clock.now += 60
        _ = try await pool.songs()
        #expect(library.pageRequests.count == asked)
        clock.now += RatedSongPool.lifetime
        _ = try await pool.songs()
        #expect(library.pageRequests.count > asked)
    }

    @Test func aServerThatListsNothingHasAnEmptyLibrary() async throws {
        let found = try await pool(Library(count: 0)).songs()
        #expect(found == RatedSongs(songs: [], librarySize: 0))
    }

    @Test func asksForEverySongBySearchingForNothing() async throws {
        let transport = FakeTransport(.json(TestServer.ok))
        _ = try await TestServer.client(transport).allSongs(count: 500, offset: 1_000)
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path.hasSuffix("search3"))
        #expect(url.queryParameters["query"] == "")
        #expect(url.queryParameters["songCount"] == "500")
        #expect(url.queryParameters["songOffset"] == "1000")
        #expect(url.queryParameters["albumCount"] == "0")
        #expect(url.queryParameters["artistCount"] == "0")
    }

    // MARK: Playing

    private func makeEngine() -> PlaybackEngine {
        PlaybackEngine(
            player: FakeAudioPlayer(), session: FakeAudioSession(), nowPlaying: FakeNowPlaying(), urls: FakeStreamURLs(),
            store: InMemoryQueueStore(), scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler()
        )
    }

    private func model(
        _ engine: PlaybackEngine, includeFavorites: Bool = true, rated: @escaping @Sendable () async throws -> RatedSongs
    ) -> SpinOffModel {
        SpinOffModel(
            engine: engine,
            sources: .init(similarToSong: { _ in [] }, similarToArtist: { _ in [] }, random: { _ in [] }, rated: rated),
            keepSpinning: { false },
            includeFavorites: { includeFavorites }
        )
    }

    private func rated(_ count: Int) -> [Song] {
        (1...count).map { Song(id: "r-\($0)", title: "Rated \($0)", userRating: 5) }
    }

    /// Waits up to two seconds for a refill to arrive.
    private func settle(until done: () -> Bool) async {
        for _ in 0..<200 where !done() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func playsRatedSongsShuffledAsAnEndlessQueue() async {
        let pool = rated(60)
        let engine = makeEngine()
        let shuffle = model(engine) { RatedSongs(songs: pool, librarySize: 1_000) }
        await shuffle.startRated()
        #expect(engine.spinOff == .rated)
        #expect(engine.queue.entries.count == SpinOffModel.batchSize)
        #expect(Set(engine.queue.entries.map(\.song.id)).isSubset(of: Set(pool.map(\.id))))
        #expect(SpinOffSeed.rated.heading == "My Cuts")
        withExtendedLifetime(shuffle) {}
    }

    @Test func topsUpWithSongsNotYetPlayedThenReshuffles() async {
        let pool = rated(30)
        let engine = makeEngine()
        let shuffle = model(engine) { RatedSongs(songs: pool, librarySize: 1_000) }
        await shuffle.startRated()
        // Running low: the 5 rated songs not yet queued come next.
        engine.jump(to: engine.queue.entries[23].id)
        await settle { engine.queue.entries.count == 30 }
        #expect(engine.queue.entries.count == 30)
        #expect(Set(engine.queue.entries.map(\.song.id)).count == 30)
        // All played: a fresh shuffle of them all.
        engine.jump(to: engine.queue.entries[28].id)
        await settle { engine.queue.entries.count > 30 }
        #expect(engine.queue.entries.count == 30 + SpinOffModel.batchSize)
        withExtendedLifetime(shuffle) {}
    }

    @Test func saysWhenNothingIsRated() async {
        let engine = makeEngine()
        let shuffle = model(engine) { RatedSongs(songs: [], librarySize: 500) }
        await shuffle.startRated()
        #expect(engine.queue.isEmpty)
        #expect(shuffle.notice?.contains("Nothing in My Cuts yet") == true)
    }

    @Test func saysWhenTheServerCantListItsSongs() async {
        let engine = makeEngine()
        let shuffle = model(engine) { RatedSongs(songs: [], librarySize: 0) }
        await shuffle.startRated()
        #expect(shuffle.notice?.contains("didn't list its songs") == true)
    }

    @Test func saysWhenTheServerCantBeReached() async {
        let engine = makeEngine()
        let shuffle = model(engine) { throw URLError(.notConnectedToInternet) }
        await shuffle.startRated()
        #expect(shuffle.notice?.contains("Check your connection") == true)
    }

    @Test func aRatedShuffleIsSavedWithTheQueue() throws {
        let snapshot = QueueSnapshot(queue: PlaybackQueue(songs: rated(2)), position: 0, spinOff: .rated)
        let restored = try JSONDecoder().decode(QueueSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(restored.spinOff == .rated)
    }

    // MARK: Favorites

    @Test func favoritesAreKeptAsCandidates() async throws {
        let library = Library(count: 10)
        let starred = Song(id: "fav", title: "Favorite", isStarred: true)
        let pool = RatedSongPool(fetchPage: { count, offset in offset == 0 ? library.songs + [starred] : [] })
        let found = try await pool.songs()
        #expect(found.songs.contains { $0.id == "fav" })
    }

    @Test func favoritesCountUnlessRatedMeh() {
        let favorite = Song(id: "fav", title: "Favorite", isStarred: true)
        let mehFavorite = Song(id: "meh-fav", title: "Meh Favorite", isStarred: true, userRating: 2)
        let rocks = Song(id: "rocks", title: "Rocks", userRating: 5)
        #expect(RatedSongPool.qualifies(favorite, includeFavorites: true))
        #expect(!RatedSongPool.qualifies(favorite, includeFavorites: false))
        #expect(!RatedSongPool.qualifies(mehFavorite, includeFavorites: true))
        #expect(RatedSongPool.qualifies(rocks, includeFavorites: false))
    }

    @Test func favoritesPlayOnlyWhenIncluded() async {
        let favorites = (1...5).map { Song(id: "fav-\($0)", title: "Favorite \($0)", isStarred: true) }
        let found = RatedSongs(songs: favorites + rated(3), librarySize: 100)
        let withFavorites = makeEngine()
        let on = model(withFavorites, includeFavorites: true) { found }
        await on.startRated()
        #expect(withFavorites.queue.entries.count == 8)
        let without = makeEngine()
        let off = model(without, includeFavorites: false) { found }
        await off.startRated()
        #expect(Set(without.queue.entries.map(\.song.id)) == ["r-1", "r-2", "r-3"])
        withExtendedLifetime([on, off]) {}
    }

    @Test func favoritesAreIncludedByDefault() throws {
        #expect(StreamingSettings().myCutsIncludeFavorites)
        let older = try JSONDecoder().decode(StreamingSettings.self, from: Data(#"{"wifiQuality":0,"cellularQuality":192}"#.utf8))
        #expect(older.myCutsIncludeFavorites)
    }
}
