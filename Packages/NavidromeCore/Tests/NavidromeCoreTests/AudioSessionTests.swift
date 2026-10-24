import AVFoundation
import Testing
@testable import NavidromeCore

@MainActor
struct EngineAudioSessionTests {
    private let songs = (1...3).map { Song(id: "so-\($0)", title: "Song \($0)", duration: 200) }
    private let player = FakeAudioPlayer()
    private let session = FakeAudioSession()
    private let nowPlaying = FakeNowPlaying()

    private func playingEngine() -> PlaybackEngine {
        let engine = PlaybackEngine(player: player, session: session, nowPlaying: nowPlaying, urls: FakeStreamURLs(), store: InMemoryQueueStore(), scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler())
        engine.play(songs: songs)
        return engine
    }

    @Test func playActivatesTheSession() {
        _ = playingEngine()
        #expect(session.activationCount == 1)
    }

    @Test func refusedSessionFailsWithoutPlaying() {
        session.activationError = AudioSessionError(message: "Session is busy")
        let engine = playingEngine()
        #expect(engine.status == .failed("Can't play right now: Session is busy"))
        #expect(!player.isPlaying)
    }

    @Test func interruptionPausesAndResumesWhenTheSystemSaysSo() {
        let engine = playingEngine()
        session.report(.interruptionBegan)
        #expect(engine.status == .paused)
        #expect(!player.isPlaying)

        session.report(.interruptionEnded(shouldResume: true))
        #expect(engine.status == .playing)
        #expect(player.isPlaying)
    }

    @Test func interruptionStaysPausedWithoutTheResumeHint() {
        let engine = playingEngine()
        session.report(.interruptionBegan)
        session.report(.interruptionEnded(shouldResume: false))
        #expect(engine.status == .paused)
    }

    @Test func interruptionWhilePausedNeverStartsPlayback() {
        let engine = playingEngine()
        engine.pause()
        session.report(.interruptionBegan)
        session.report(.interruptionEnded(shouldResume: true))
        #expect(engine.status == .paused)
    }

    @Test func userChoiceDuringInterruptionWins() {
        let engine = playingEngine()
        session.report(.interruptionBegan)
        engine.play()
        engine.pause()
        session.report(.interruptionEnded(shouldResume: true))
        #expect(engine.status == .paused)
    }

    @Test func losingTheOutputDevicePausesAndStaysPaused() {
        let engine = playingEngine()
        session.report(.outputDeviceLost)
        #expect(engine.status == .paused)
        #expect(!player.isPlaying)

        // A later interruption ending must not restart playback on the speaker.
        session.report(.interruptionEnded(shouldResume: true))
        #expect(engine.status == .paused)
    }
}

/// How AVAudioSession notification contents map to engine events.
struct SystemAudioSessionParsingTests {
    @Test func systemDeactivationIsAnInterruption() {
        #expect(SystemAudioSession.deactivationEvent(source: .system) == .interruptionBegan)
    }

    @Test func ourOwnDeactivationIsNotAnInterruption() {
        #expect(SystemAudioSession.deactivationEvent(source: .app) == nil)
    }

    @Test func resumptionFollowsTheRecommendation() {
        #expect(SystemAudioSession.resumptionEvent(recommendation: .shouldResume) == .interruptionEnded(shouldResume: true))
        #expect(SystemAudioSession.resumptionEvent(recommendation: .shouldNotResume) == .interruptionEnded(shouldResume: false))
        #expect(SystemAudioSession.resumptionEvent(recommendation: nil) == .interruptionEnded(shouldResume: false))
    }

    @Test func routeChanges() {
        let lost = AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
        let added = AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
        let category = AVAudioSession.RouteChangeReason.categoryChange.rawValue
        #expect(SystemAudioSession.routeChangeEvent(reason: lost, outputs: [.builtInSpeaker]) == .outputDeviceLost)
        // A car or Bluetooth device connecting may send play by itself.
        #expect(SystemAudioSession.routeChangeEvent(reason: added, outputs: [.carAudio]) == .autoplayDeviceConnected)
        #expect(SystemAudioSession.routeChangeEvent(reason: added, outputs: [.bluetoothA2DP]) == .autoplayDeviceConnected)
        // Wired headphones don't.
        #expect(SystemAudioSession.routeChangeEvent(reason: added, outputs: [.headphones]) == nil)
        #expect(SystemAudioSession.routeChangeEvent(reason: category, outputs: [.carAudio]) == nil)
        #expect(SystemAudioSession.routeChangeEvent(reason: nil, outputs: []) == nil)
    }
}
