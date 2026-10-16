import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct OnAirTrackerTests {
    private let player = FakeAudioPlayer()
    private let nowPlaying = FakeNowPlaying()
    private static let stream = URL(string: "https://stream.example.com/waves")!
    private static let station = RadioStation(id: "rs-1", name: "Night Waves", streamURL: stream, logoURL: URL(string: "https://example.com/logo.png"))
    private static let owned = Song(id: "so-1", title: "Karma Police", artist: "Radiohead", coverArtID: "al-ok")
    nonisolated private static let cover = URL(string: "https://covers.example.org/front-500.jpg")!

    private final class Switch {
        var on: Bool
        init(_ on: Bool) { self.on = on }
    }

    private func makeEngine() -> PlaybackEngine {
        PlaybackEngine(player: player, session: FakeAudioSession(), nowPlaying: nowPlaying, urls: FakeStreamURLs(), store: InMemoryQueueStore(), scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler())
    }

    private func tracker(_ engine: PlaybackEngine, library: [Song], lookUp: Switch) -> OnAirTracker {
        let match = OnAirMatchModel { query async throws(SubsonicError) in
            library.filter { "\($0.artist ?? "") \($0.title)" == query }
        }
        let info = OnAirInfoModel { song in
            OnAirDetails(title: song.title, artist: song.artist, recordingID: "rec-\(song.title)", coverURL: Self.cover)
        }
        return OnAirTracker(engine: engine, match: match, info: info, lookUpOnline: { lookUp.on })
    }

    private func announce(_ title: String, on engine: PlaybackEngine) {
        guard let entry = engine.queue.current?.id else { return }
        player.onEvent?(.streamTitle(entry, title))
    }

    /// Waits for the tracker's lookups (fakes answer at once).
    private func settle(_ engine: PlaybackEngine, until done: () -> Bool) async {
        for _ in 0..<200 where !done() { await Task.yield() }
    }

    @Test func aSongYouOwnShowsYourCoverEverywhere() async {
        let engine = makeEngine()
        engine.play(songs: [Song(station: Self.station, stream: Self.stream)])
        let tracking = tracker(engine, library: [Self.owned], lookUp: Switch(true))
        tracking.start()
        announce("Radiohead - Karma Police", on: engine)
        await settle(engine) { engine.onAirCoverArtID != nil }
        #expect(engine.onAirCoverArtID == "al-ok")
        #expect(engine.currentCoverArtID == "al-ok")
        // The lock screen gets it too.
        #expect(nowPlaying.latest?.coverArtID == "al-ok")
    }

    @Test func otherwiseMusicBrainzsCoverOnlyWithLookupsOn() async {
        let engine = makeEngine()
        engine.play(songs: [Song(station: Self.station, stream: Self.stream)])
        let lookUp = Switch(false)
        let tracking = tracker(engine, library: [], lookUp: lookUp)
        tracking.start()
        announce("Blur - Song 2", on: engine)
        await tracking.refresh()
        #expect(engine.onAirCoverArtID == nil)
        // Without one: the station's logo.
        #expect(engine.currentCoverArtID == Self.station.coverArtID)

        lookUp.on = true
        await tracking.refresh()
        #expect(engine.onAirCoverArtID == StationLogo.coverArtID(for: Self.cover))
    }

    @Test func aNewEntryClearsTheCover() async {
        let engine = makeEngine()
        engine.play(songs: [Song(station: Self.station, stream: Self.stream)])
        let tracking = tracker(engine, library: [Self.owned], lookUp: Switch(true))
        tracking.start()
        announce("Radiohead - Karma Police", on: engine)
        await settle(engine) { engine.onAirCoverArtID != nil }
        engine.play(songs: [Self.owned])
        await settle(engine) { engine.onAirCoverArtID == nil }
        #expect(engine.onAirCoverArtID == nil)
        #expect(engine.currentCoverArtID == "al-ok")
    }
}
