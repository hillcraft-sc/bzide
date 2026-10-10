import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct RecoveryTests {
    private let songs = (1...3).map { Song(id: "so-\($0)", title: "Song \($0)", duration: 200) }
    private let player = FakeAudioPlayer()
    private let scheduler = FakeScheduler()
    private let network = FakeNetworkMonitor()

    private func playingEngine() -> PlaybackEngine {
        let engine = PlaybackEngine(
            player: player, session: FakeAudioSession(), nowPlaying: FakeNowPlaying(),
            urls: FakeStreamURLs(), store: InMemoryQueueStore(), scheduler: scheduler, network: network, scrobbler: FakeScrobbler()
        )
        engine.play(songs: songs)
        return engine
    }

    private func failCurrent(_ engine: PlaybackEngine) {
        player.report(.itemFailed(engine.queue.current!.id, message: "The network connection was lost."))
    }

    @Test func failureWhilePlayingReconnectsAtTheSamePosition() {
        let engine = playingEngine()
        player.report(.timeChanged(87))

        failCurrent(engine)
        #expect(engine.status == .reconnecting)
        #expect(scheduler.pendingDelays == [.seconds(1)])

        scheduler.fireNext()
        #expect(player.setItemsCalls.count == 2)
        #expect(player.setItemsCalls.last?.startPosition == 87)
        #expect(engine.status == .playing)
        #expect(engine.queue.current?.song.id == "so-1")
    }

    @Test func retriesBackOffThenGiveUp() {
        let engine = playingEngine()
        for expectedDelay in [Duration.seconds(1), .seconds(2), .seconds(4)] {
            failCurrent(engine)
            #expect(engine.status == .reconnecting)
            #expect(scheduler.pendingDelays == [expectedDelay])
            scheduler.fireNext()
        }
        failCurrent(engine)
        #expect(engine.status == .failed("The network connection was lost."))
        #expect(scheduler.pendingDelays.isEmpty)
    }

    @Test func briefPlaybackAfterARetryDoesNotResetTheBudget() {
        let engine = playingEngine()
        player.report(.timeChanged(30))
        failCurrent(engine)
        scheduler.fireNext()
        player.report(.timeChanged(35))  // only 5 seconds since the retry

        failCurrent(engine)
        #expect(scheduler.pendingDelays == [.seconds(2)])
    }

    @Test func sustainedPlaybackAfterARetryResetsTheBudget() {
        let engine = playingEngine()
        player.report(.timeChanged(30))
        failCurrent(engine)
        scheduler.fireNext()
        player.report(.timeChanged(40.5))

        failCurrent(engine)
        #expect(scheduler.pendingDelays == [.seconds(1)])
    }

    @Test func failureWhilePausedWaitsForTheUser() {
        let engine = playingEngine()
        engine.pause()
        failCurrent(engine)
        #expect(engine.status == .failed("The network connection was lost."))
        #expect(scheduler.pendingDelays.isEmpty)
    }

    @Test func pausingWhileReconnectingCancelsTheRetry() {
        let engine = playingEngine()
        failCurrent(engine)
        engine.togglePlayPause()
        #expect(engine.status == .paused)
        #expect(scheduler.pendingDelays.isEmpty)
    }

    @Test func skippingWhileReconnectingCancelsTheRetry() {
        let engine = playingEngine()
        failCurrent(engine)
        engine.jump(to: engine.queue.entries[2].id)
        #expect(scheduler.pendingDelays.isEmpty)
        #expect(engine.queue.current?.song.id == "so-3")
    }

    @Test func staleReportsFromTheFailedPlayerAreIgnored() {
        let engine = playingEngine()
        failCurrent(engine)
        player.report(.statusChanged(.paused))
        #expect(engine.status == .reconnecting)
    }

    @Test func networkReturningRetriesImmediately() {
        let engine = playingEngine()
        failCurrent(engine)
        network.becomeAvailable()
        #expect(scheduler.pendingDelays.isEmpty)
        #expect(player.setItemsCalls.count == 2)
        #expect(engine.status == .playing)
    }

    @Test func networkReturningRevivesAPlaybackThatGaveUp() {
        let engine = playingEngine()
        for _ in 0..<3 {
            failCurrent(engine)
            scheduler.fireNext()
        }
        failCurrent(engine)
        #expect(engine.status == .failed("The network connection was lost."))

        network.becomeAvailable()
        #expect(engine.status == .playing)
    }

    @Test func networkReturningDoesNotStartAPausedPlayer() {
        let engine = playingEngine()
        engine.pause()
        failCurrent(engine)
        network.becomeAvailable()
        #expect(engine.status == .failed("The network connection was lost."))
        #expect(player.setItemsCalls.count == 1)
    }

    @Test func stallThatRecoversOnItsOwnNeedsNoReload() {
        let engine = playingEngine()
        player.report(.stalled(engine.queue.current!.id))
        #expect(scheduler.pendingDelays == [.seconds(10)])
        player.report(.statusChanged(.playing))
        #expect(scheduler.pendingDelays.isEmpty)
        #expect(player.setItemsCalls.count == 1)
    }

    @Test func stallThatPersistsReloadsAtTheSamePosition() {
        let engine = playingEngine()
        player.report(.timeChanged(42))
        player.report(.statusChanged(.buffering))
        player.report(.stalled(engine.queue.current!.id))

        scheduler.fireNext()  // grace period over, still buffering
        #expect(engine.status == .reconnecting)
        scheduler.fireNext()  // first retry
        #expect(player.setItemsCalls.last?.startPosition == 42)
        #expect(engine.status == .playing)
    }

    @Test func failedPreloadIsRebuiltWithoutTouchingTheCurrentTrack() {
        let engine = playingEngine()
        let nextID = engine.queue.entries[1].id
        player.report(.itemFailed(nextID, message: "Timed out"))
        #expect(engine.status == .playing)
        #expect(scheduler.pendingDelays == [.seconds(1)])

        scheduler.fireNext()
        #expect(player.replacedUpcoming.map(\.entryID) == [nextID])
        #expect(player.setItemsCalls.count == 1)
        #expect(player.loadedEntryIDs == [engine.queue.entries[0].id, nextID])
    }
}
