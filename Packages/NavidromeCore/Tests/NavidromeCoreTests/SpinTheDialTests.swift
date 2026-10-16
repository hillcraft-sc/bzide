import Foundation
import Testing
@testable import NavidromeCore

/// A repeatable random number generator (SplitMix64).
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct GenreTagsTests {
    @Test func genresBecomeRadioBrowserTags() {
        #expect(GenreTags.tags(fromGenre: "Hip-Hop/Rap; R&B") == ["hip hop", "rap", "r&b"])
        #expect(GenreTags.tags(fromGenre: "  Classic_Rock ") == ["classic rock"])
        #expect(GenreTags.tags(fromGenre: "") == [])
    }

    @Test func relatedTagsAreTheSameMusic() {
        #expect(GenreTags.related("rock", "Classic Rock"))
        #expect(GenreTags.related("Hip-Hop", "hip hop"))
        #expect(!GenreTags.related("jazz", "rock"))
    }
}

struct TasteProfileTests {
    private static let now = Date(timeIntervalSince1970: 10_000_000)

    private static func play(_ genre: String?, daysAgo: Double) -> PlayHistoryEntry {
        PlayHistoryEntry(song: Song(id: UUID().uuidString, title: "Song", genre: genre), playedAt: now.addingTimeInterval(-daysAgo * 86_400))
    }

    @Test func recentPlaysCountMoreAndFavoritesAdd() {
        let profile = TasteProfile.fromListening(
            history: [Self.play("Jazz", daysAgo: 0), Self.play("Rock", daysAgo: 30), Self.play(nil, daysAgo: 0)],
            favorites: [Song(id: "f", title: "Fav", genre: "Rock")],
            now: Self.now
        )
        #expect(abs((profile.weights["jazz"] ?? 0) - 1) < 0.0001)
        // Half for a month-old play, plus a half for the favorite.
        #expect(abs((profile.weights["rock"] ?? 0) - 1) < 0.0001)
        #expect(profile.weights.count == 2)
    }

    @Test func theLibraryWeighsGenresBySize() {
        let profile = TasteProfile.fromLibrary([Genre(name: "Jazz", songCount: 300), Genre(name: "Blues", albumCount: 4)])
        #expect(profile.weights == ["jazz": 300, "blues": 4])
    }

    @Test func restrictingKeepsOnlyTheChosenGenres() {
        let profile = TasteProfile(weights: ["jazz": 5, "classic rock": 2, "pop": 9])
        #expect(profile.restricted(to: ["rock"]).weights == ["classic rock": 2])
        // None of them in the profile: all of them, equally.
        #expect(profile.restricted(to: ["Ambient", "Folk"]).weights == ["ambient": 1, "folk": 1])
        #expect(profile.knows("rock"))
        #expect(!profile.knows("metal"))
    }

    @Test func picksFollowTheWeightsButReachTheLongTail() {
        let profile = TasteProfile(weights: ["jazz": 100, "blues": 1])
        var random = SeededRandom(state: 7)
        var counts: [String: Int] = [:]
        for _ in 0..<1000 { counts[profile.pick(using: &random) ?? "", default: 0] += 1 }
        #expect((counts["jazz"] ?? 0) > 850)
        #expect((counts["blues"] ?? 0) > 20)
        #expect(TasteProfile(weights: [:]).pick(using: &random) == nil)
    }

    @Test func settingsDefaultAndDecodeLeniently() throws {
        let settings = try JSONDecoder().decode(DialSettings.self, from: Data(#"{"mode":"nonsense","genres":["jazz"]}"#.utf8))
        #expect(settings == DialSettings(mode: .myTaste, genres: ["jazz"]))
        #expect(StreamingSettings().spinTheDial == DialSettings())
    }
}

struct DialLogTests {
    @Test func remembersTheLatestAndKeepsALimit() {
        let file = FileManager.default.temporaryDirectory.appending(path: "DialLog-\(UUID().uuidString).json")
        let log = DialLog(fileURL: file)
        for index in 0..<(DialLog.capacity + 10) { log.record("s\(index)") }
        log.record("s5") // played again: moves to the end
        let reopened = DialLog(fileURL: file)
        #expect(reopened.all.count == DialLog.capacity)
        #expect(!reopened.all.contains("s0"))
        #expect(reopened.recent(1) == ["s5"])
    }
}

@MainActor
struct SpinTheDialModelTests {
    private actor Asked {
        var queries: [RadioBrowserClient.Query] = []
        var counted: [String] = []
        func add(_ query: RadioBrowserClient.Query) { queries.append(query) }
        func count(_ id: String) { counted.append(id) }
    }

    private final class Played {
        var stations: [RadioStation] = []
    }

    private static func station(_ id: String, country: String? = "US") -> RadioBrowserStation {
        RadioBrowserStation(id: id, name: "Station \(id)", streamURL: URL(string: "https://stream.example.com/\(id)")!, countryCode: country)
    }

    private struct World {
        var history: [PlayHistoryEntry] = []
        var genres: [Genre] = []
        var tags: [RadioBrowserClient.Tag] = []
        var saved: Set<URL> = []
        /// Stations for each tag (nil: no tag).
        var stations: [String?: [RadioBrowserStation]] = [:]
        var failing = false
    }

    private func model(_ world: World, asked: Asked, played: Played, log: DialLog = DialLog(fileURL: nil)) -> SpinTheDialModel {
        SpinTheDialModel(
            sources: .init(
                stations: { query in
                    await asked.add(query)
                    if world.failing { throw URLError(.notConnectedToInternet) }
                    return world.stations[query.tag] ?? []
                },
                history: { world.history },
                favorites: { [] },
                libraryGenres: { world.genres },
                popularTags: { world.tags },
                savedStreams: { world.saved },
                play: { played.stations.append($0) },
                countPlay: { id in await asked.count(id) }
            ),
            log: log,
            random: SeededRandom(state: 42)
        )
    }

    private static let jazzHistory = [PlayHistoryEntry(song: Song(id: "so-1", title: "So What", genre: "Jazz"), playedAt: .now)]

    @Test func myTasteTunesToAGenreYouPlay() async {
        let asked = Asked(), played = Played()
        let dial = model(World(history: Self.jazzHistory, stations: ["jazz": [Self.station("j1")]]), asked: asked, played: played)
        await dial.spin(DialSettings(), countryCode: "US")
        let query = await asked.queries.first
        #expect(query?.tag == "jazz")
        #expect(query?.tagIsLoose == true)
        #expect(query?.order == .topRated)
        #expect(query?.countryCode == nil)
        #expect(played.stations.map(\.id) == ["dial:j1"])
        #expect(SpinTheDialModel.isDialed(Song(station: played.stations[0], stream: played.stations[0].streamURL)))
        #expect(dial.tuned?.message == "Tuned to Station j1 · jazz · US")
        while await asked.counted.isEmpty { await Task.yield() }
        #expect(await asked.counted == ["j1"])
    }

    @Test func spinningAgainAvoidsRecentStations() async {
        let asked = Asked(), played = Played()
        let world = World(history: Self.jazzHistory, stations: ["jazz": [Self.station("j1"), Self.station("j2")]])
        let dial = model(world, asked: asked, played: played)
        await dial.spin(DialSettings(), countryCode: nil)
        await dial.spin(DialSettings(), countryCode: nil)
        #expect(Set(played.stations.map(\.id)) == ["dial:j1", "dial:j2"])
    }

    @Test func withoutHistoryMyTasteUsesTheLibraryThenAnything() async {
        let asked = Asked(), played = Played()
        let library = World(genres: [Genre(name: "Blues", songCount: 10)], stations: ["blues": [Self.station("b1")]])
        await model(library, asked: asked, played: played).spin(DialSettings(), countryCode: nil)
        #expect(played.stations.map(\.id) == ["dial:b1"])

        let empty = World(stations: [nil: [Self.station("r1")]])
        let anything = Asked()
        await model(empty, asked: anything, played: played).spin(DialSettings(), countryCode: nil)
        #expect(await anything.queries.first?.tag == nil)
        #expect(await anything.queries.first?.order == .random)
        #expect(played.stations.last?.id == "dial:r1")
    }

    @Test func surpriseMeIsAnyStationAndRestrictionsApply() async {
        let asked = Asked(), played = Played()
        let dial = model(World(history: Self.jazzHistory, stations: [nil: [Self.station("r1")]]), asked: asked, played: played)
        await dial.spin(DialSettings(mode: .surpriseMe, myCountryOnly: true, minimumBitrate: 192), countryCode: "CA")
        let query = await asked.queries.first
        #expect(query?.tag == nil)
        #expect(query?.order == .random)
        #expect(query?.countryCode == "CA")
        #expect(query?.minimumBitrate == 192)
        #expect(played.stations.count == 1)
    }

    @Test func chosenGenresLimitTheDial() async {
        let asked = Asked(), played = Played()
        let world = World(history: Self.jazzHistory, stations: ["ambient": [Self.station("a1")]])
        await model(world, asked: asked, played: played).spin(DialSettings(genres: ["Ambient"]), countryCode: nil)
        #expect(await asked.queries.map(\.tag) == ["ambient"])
        #expect(played.stations.map(\.id) == ["dial:a1"])
    }

    @Test func somethingNewAvoidsYourGenresSavedAndDialedStations() async {
        let asked = Asked(), played = Played()
        let log = DialLog(fileURL: nil)
        log.record("old")
        let world = World(
            history: Self.jazzHistory,
            genres: [Genre(name: "Rock", songCount: 50)],
            tags: [.init(name: "jazz", stationCount: 900), .init(name: "classic rock", stationCount: 800), .init(name: "news", stationCount: 700), .init(name: "reggae", stationCount: 300)],
            saved: [URL(string: "https://stream.example.com/saved")!],
            stations: ["reggae": [Self.station("old"), Self.station("saved"), Self.station("fresh")]]
        )
        await model(world, asked: asked, played: played, log: log).spin(DialSettings(mode: .somethingNew), countryCode: nil)
        // Jazz (played), classic rock (in the library) and news (not a genre) are left out.
        #expect(await asked.queries.first?.tag == "reggae")
        #expect(played.stations.map(\.id) == ["dial:fresh"])
    }

    @Test func nothingFoundOrOfflineIsExplained() async {
        let played = Played()
        let none = model(World(history: Self.jazzHistory), asked: Asked(), played: played)
        await none.spin(DialSettings(), countryCode: nil)
        #expect(none.error == "Couldn't find a station. Try spinning again.")
        await none.spin(DialSettings(minimumBitrate: 320), countryCode: nil)
        #expect(none.error?.contains("Try fewer restrictions") == true)

        let offline = model(World(history: Self.jazzHistory, failing: true), asked: Asked(), played: played)
        await offline.spin(DialSettings(), countryCode: nil)
        #expect(offline.error == "Couldn't reach Radio Browser. Check your connection and try again.")
        #expect(played.stations.isEmpty)
    }
}

@MainActor
struct SaveDialedStationTests {
    private static let station = RadioBrowserStation(
        id: "j1", name: "Night Jazz", streamURL: URL(string: "https://stream.example.com/j1")!,
        homePageURL: URL(string: "https://jazz.example.com")!, faviconURL: URL(string: "https://jazz.example.com/logo.png")!,
        tags: ["jazz"], countryCode: "US", codec: "MP3", bitrate: 128
    )

    private func dial(tuningTo station: RadioBrowserStation?) async -> SpinTheDialModel {
        let model = SpinTheDialModel(
            sources: .init(
                stations: { _ in station.map { [$0] } ?? [] },
                history: { [PlayHistoryEntry(song: Song(id: "so-1", title: "So What", genre: "Jazz"), playedAt: .now)] },
                favorites: { [] }, libraryGenres: { [] }, popularTags: { [] }, savedStreams: { [] },
                play: { _ in }, countPlay: { _ in }
            ),
            log: DialLog(fileURL: nil), random: SeededRandom(state: 1)
        )
        if station != nil { await model.spin(DialSettings(), countryCode: nil) }
        return model
    }

    private static func playing(_ station: RadioBrowserStation) -> Song {
        let radio = SpinTheDialModel.dialStation(station)
        return Song(station: radio, stream: radio.streamURL)
    }

    @Test func theTunedStationIsSavedWithAllItsDetails() async throws {
        let model = await dial(tuningTo: Self.station)
        // The banner going away doesn't lose what was tuned to.
        model.dismissNotice()
        #expect(model.notice == nil)
        let savable = try #require(model.savable(Self.playing(Self.station)))
        #expect(savable.draft == RadioStationDraft(name: "Night Jazz", streamURL: "https://stream.example.com/j1", homePageURL: "https://jazz.example.com"))
        #expect(savable.details == StationDetails(Self.station))
        #expect(savable.stream == Self.station.streamURL)
    }

    @Test func afterARelaunchWhatThePlayingEntryKept() async throws {
        let model = await dial(tuningTo: nil)
        let savable = try #require(model.savable(Self.playing(Self.station)))
        #expect(savable.draft.name == "Night Jazz")
        #expect(savable.draft.streamURL == "https://stream.example.com/j1")
        #expect(savable.details?.logoURL?.absoluteString == "https://jazz.example.com/logo.png")
        #expect(savable.details?.countryCode == nil)
    }

    @Test func onlyDialedStationsCanBeSavedThisWay() async {
        let model = await dial(tuningTo: Self.station)
        let saved = RadioStation(id: "rs-1", name: "Saved", streamURL: Self.station.streamURL)
        #expect(model.savable(Song(station: saved, stream: saved.streamURL)) == nil)
        #expect(model.savable(Song(id: "so-1", title: "A Song")) == nil)
    }
}

@MainActor
struct StationSkipperTests {
    @Test func nextOnADialedStationAsksTheSkipper() {
        let engine = PlaybackEngine(
            player: FakeAudioPlayer(), session: FakeAudioSession(), nowPlaying: FakeNowPlaying(), urls: FakeStreamURLs(),
            store: InMemoryQueueStore(), scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler()
        )
        let stream = URL(string: "https://stream.example.com/j1")!
        let dialed = SpinTheDialModel.dialStation(RadioBrowserStation(id: "j1", name: "Jazz", streamURL: stream))
        engine.play(songs: [Song(station: dialed, stream: stream)])
        #expect(!engine.canGoNext)

        var skipped = 0
        engine.stationSkipper = .init(canSkip: { SpinTheDialModel.isDialed($0) }, skip: { _ in skipped += 1 })
        #expect(engine.canGoNext)
        engine.next()
        #expect(skipped == 1)

        // A saved station isn't the dial's.
        let saved = RadioStation(id: "rs-1", name: "Saved", streamURL: stream)
        engine.play(songs: [Song(station: saved, stream: stream)])
        #expect(!engine.canGoNext)
    }
}
