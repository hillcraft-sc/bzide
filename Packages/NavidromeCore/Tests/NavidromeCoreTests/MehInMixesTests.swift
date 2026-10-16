import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct MehInMixesTests {
    private let meh = Song(id: "meh", title: "Meh", userRating: 2)
    private let alsoMeh = Song(id: "meh-1", title: "One Star", userRating: 1)
    private let rocks = Song(id: "rocks", title: "Love", userRating: 5)
    private let unrated = Song(id: "unrated", title: "Unrated")

    @Test func mehSongsAreLeftOutUnlessIncluded() {
        #expect(!Rating.suitsMix(meh, includeMeh: false))
        #expect(!Rating.suitsMix(alsoMeh, includeMeh: false))
        #expect(Rating.suitsMix(rocks, includeMeh: false))
        #expect(Rating.suitsMix(unrated, includeMeh: false))
        #expect(Rating.suitsMix(meh, includeMeh: true))
    }

    @Test func mehSongsAreLeftOutByDefault() throws {
        #expect(StreamingSettings().includeMehInMixes == false)
        let older = try JSONDecoder().decode(StreamingSettings.self, from: Data(#"{"wifiQuality":0,"cellularQuality":192}"#.utf8))
        #expect(older.includeMehInMixes == false)
    }

    // MARK: Random Mix

    private func randomMix(serving songs: [Song], downloaded: [Song] = [], fails: Bool = false, includeMeh: Bool, played: @escaping ([Song]) -> Void) -> RandomMixModel {
        RandomMixModel(
            fetch: { _ async throws(SubsonicError) in
                if fails { throw .network(.notConnectedToInternet) }
                return songs
            },
            downloadedSongs: { downloaded },
            includeMeh: { includeMeh },
            play: played
        )
    }

    @Test func randomMixSkipsMehSongs() async {
        var queue: [Song] = []
        await randomMix(serving: [meh, rocks, unrated, alsoMeh], includeMeh: false) { queue = $0 }.start()
        #expect(queue.map(\.id) == ["rocks", "unrated"])
        await randomMix(serving: [meh, rocks], includeMeh: true) { queue = $0 }.start()
        #expect(queue.map(\.id) == ["meh", "rocks"])
    }

    @Test func randomMixFromDownloadsSkipsMehSongsToo() async {
        var queue: [Song] = []
        await randomMix(serving: [], downloaded: [meh, unrated], fails: true, includeMeh: false) { queue = $0 }.start()
        #expect(queue.map(\.id) == ["unrated"])
    }

    // MARK: Spin Off

    private func sources(similar: [Song]) -> SpinOffModel.Sources {
        .init(similarToSong: { _ in similar }, similarToArtist: { _ in similar }, random: { _ in [] })
    }

    @Test func spinOffDoesntSuggestMehSongs() async {
        let seed = SpinOffSeed(song: Song(id: "seed", title: "Seed"))
        let left = await SpinOffModel.batch(for: seed, excluding: [], includeMeh: false, sources: sources(similar: [meh, rocks, unrated]))
        #expect(Set(left?.songs.map(\.id) ?? []) == ["rocks", "unrated"])
        let kept = await SpinOffModel.batch(for: seed, excluding: [], includeMeh: true, sources: sources(similar: [meh, rocks]))
        #expect(Set(kept?.songs.map(\.id) ?? []) == ["meh", "rocks"])
    }

    @Test func aMehSongYouSpinOffFromStillPlays() async {
        let engine = PlaybackEngine(
            player: FakeAudioPlayer(), session: FakeAudioSession(), nowPlaying: FakeNowPlaying(), urls: FakeStreamURLs(),
            store: InMemoryQueueStore(), scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler()
        )
        let spinOff = SpinOffModel(engine: engine, sources: sources(similar: [alsoMeh, rocks]), keepSpinning: { false }, includeMeh: { false })
        await spinOff.start(from: meh)
        #expect(engine.queue.entries.map(\.song.id) == ["meh", "rocks"])
    }
}
