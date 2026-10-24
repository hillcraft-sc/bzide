import Foundation
import Testing
@testable import NavidromeCore

/// A car connecting (CarPlay or Bluetooth) often sends play by itself; for a
/// few seconds that play is ignored unless the user asked for it (Gitea #27).
@MainActor
struct ConnectionPlayGuardTests {
    private let songs = [Song(id: "so-1", title: "Dawn", duration: 200), Song(id: "so-2", title: "Noon", duration: 210)]
    private let player = FakeAudioPlayer()
    private let session = FakeAudioSession()
    private let nowPlaying = FakeNowPlaying()
    private let store = InMemoryQueueStore()
    private let clock = Clock()

    /// A time the test moves by hand.
    @MainActor final class Clock {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    /// A paused queue, as after the car was turned off.
    private func makeEngine() -> PlaybackEngine {
        store.save(QueueSnapshot(queue: PlaybackQueue(songs: songs), position: 42))
        return PlaybackEngine(
            player: player, session: session, nowPlaying: nowPlaying, urls: FakeStreamURLs(), store: store,
            scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler(),
            now: { [clock] in clock.now }
        )
    }

    @Test func theCarsPlayIsIgnoredJustAfterItConnects() {
        let engine = makeEngine()
        session.report(.autoplayDeviceConnected)
        clock.now += 1
        nowPlaying.send(.play)
        #expect(!engine.status.isActive)
        nowPlaying.send(.togglePlayPause)
        #expect(!engine.status.isActive)
    }

    @Test func theCarPlayScreenConnectingCountsToo() {
        let engine = makeEngine()
        engine.carPlayConnected()
        nowPlaying.send(.play)
        #expect(!engine.status.isActive)
    }

    @Test func playWorksOnceTheMomentHasPassed() {
        let engine = makeEngine()
        session.report(.autoplayDeviceConnected)
        clock.now += ConnectionPlayGuard.window
        nowPlaying.send(.play)
        #expect(engine.status.isActive)
    }

    @Test func playWhenCarPlayConnectsLetsItThrough() {
        let engine = makeEngine()
        engine.playsWhenDeviceConnects = { true }
        session.report(.autoplayDeviceConnected)
        nowPlaying.send(.play)
        #expect(engine.status.isActive)
    }

    @Test func pauseIsNeverIgnored() {
        let engine = makeEngine()
        engine.play()
        #expect(engine.status.isActive)
        session.report(.autoplayDeviceConnected)
        nowPlaying.send(.togglePlayPause)
        #expect(!engine.status.isActive)
    }

    @Test func choosingSomethingInTheAppStillPlays() {
        let engine = makeEngine()
        engine.carPlayConnected()
        engine.play(songs: songs)
        #expect(engine.status.isActive)
    }

    @Test func withoutAConnectionPlayWorks() {
        let engine = makeEngine()
        nowPlaying.send(.play)
        #expect(engine.status.isActive)
    }
}
