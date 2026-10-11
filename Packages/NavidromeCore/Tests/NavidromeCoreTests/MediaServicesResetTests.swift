import Foundation
import Testing
@testable import NavidromeCore

/// When the system's audio services restart, the player is rebuilt and
/// playback carries on as it was.
@MainActor
struct MediaServicesResetTests {
    private let songs = (1...3).map { Song(id: "so-\($0)", title: "Song \($0)", duration: 60) }
    private let player = FakeAudioPlayer()
    private let session = FakeAudioSession()
    private let nowPlaying = FakeNowPlaying()
    private let store = InMemoryQueueStore()
    private let scheduler = FakeScheduler()
    private let network = FakeNetworkMonitor()
    private let scrobbler = FakeScrobbler()
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func playingEngine() -> PlaybackEngine {
        let engine = PlaybackEngine(
            player: player, session: session, nowPlaying: nowPlaying, urls: FakeStreamURLs(), store: store,
            scheduler: scheduler, network: network, scrobbler: scrobbler, now: { [start] in start }
        )
        engine.play(songs: songs)
        return engine
    }

    private func tick(from: TimeInterval, to: TimeInterval) {
        var time = from
        while time < to {
            time += 0.5
            player.report(.timeChanged(time))
        }
    }

    @Test func resetWhilePlayingRebuildsAndResumesWhereItWas() {
        let engine = playingEngine()
        player.finishCurrentItem()
        player.report(.timeChanged(25))

        session.report(.mediaServicesReset)

        #expect(player.rebuildCount == 1)
        #expect(engine.status == .playing)
        #expect(player.isPlaying)
        #expect(engine.queue.current?.song.id == "so-2")
        #expect(player.setItemsCalls.last?.startPosition == 25)
        #expect(player.loadedEntryIDs == [engine.queue.current?.id, engine.queue.upNext.first?.id])
        // The session is set up again before playing.
        #expect(session.activationCount == 2)
    }

    @Test func resetWhilePausedRebuildsAndStaysPaused() {
        let engine = playingEngine()
        player.report(.timeChanged(25))
        engine.pause()
        let loadsBefore = player.setItemsCalls.count

        session.report(.mediaServicesReset)

        #expect(player.rebuildCount == 1)
        #expect(engine.status == .paused)
        #expect(!player.isPlaying)
        #expect(player.setItemsCalls.count == loadsBefore)

        // The dead player is gone, so play loads the track again at the same spot.
        engine.play()
        #expect(player.setItemsCalls.last?.startPosition == 25)
        #expect(engine.status == .playing)
    }

    @Test func resetSavesTheQueueAndPosition() throws {
        let engine = playingEngine()
        player.report(.timeChanged(7))
        session.report(.mediaServicesReset)
        #expect(engine.position == 7)
        let snapshot = try #require(store.load())
        #expect(snapshot.position == 7)
        #expect(snapshot.queue.current?.song.id == "so-1")
    }

    @Test func resetResendsNowPlayingEvenIfUnchanged() {
        let engine = playingEngine()
        engine.pause()
        let countBefore = nowPlaying.updates.count

        session.report(.mediaServicesReset)

        #expect(nowPlaying.updates.count == countBefore + 1)
        #expect(nowPlaying.latest?.title == "Song 1")
        #expect(nowPlaying.latest?.isPlaying == false)
    }

    @Test func resetContinuesTheSamePlayForScrobbling() {
        let engine = playingEngine()
        tick(from: 0, to: 20)

        session.report(.mediaServicesReset)
        tick(from: 20, to: 60)

        #expect(engine.queue.current?.song.id == "so-1")
        #expect(scrobbler.nowPlayingSongIDs == ["so-1"])
        #expect(scrobbler.submitted == [PendingScrobble(songID: "so-1", playedAt: start)])
    }

    @Test func resetWhileReconnectingCancelsTheRetryAndResumes() {
        let engine = playingEngine()
        player.report(.timeChanged(30))
        player.report(.itemFailed(engine.queue.current!.id, message: "The network connection was lost."))
        #expect(engine.status == .reconnecting)

        session.report(.mediaServicesReset)

        #expect(scheduler.pendingDelays.isEmpty)
        #expect(engine.status == .playing)
        #expect(player.setItemsCalls.last?.startPosition == 30)
    }

    @Test func lossWhilePlayingIgnoresTheDeadPlayerAndResumesOnReset() {
        let engine = playingEngine()
        player.report(.timeChanged(25))

        session.report(.mediaServicesLost)
        #expect(engine.status == .paused)
        // What the dying player reports must not count as a pause or a failure.
        player.report(.statusChanged(.paused))
        player.report(.itemFailed(engine.queue.current!.id, message: "Cannot Complete Action"))
        player.report(.itemFailed(engine.queue.upNext.first!.id, message: "Cannot Complete Action"))
        #expect(engine.status == .paused)
        #expect(scheduler.pendingDelays.isEmpty)

        session.report(.mediaServicesReset)
        #expect(player.rebuildCount == 1)
        #expect(engine.status == .playing)
        #expect(player.setItemsCalls.last?.startPosition == 25)
    }

    /// Seen on device: the tracks can fail just before the loss is announced.
    @Test func tracksFailingJustBeforeTheLossStillResumeOnReset() {
        let engine = playingEngine()
        player.report(.timeChanged(25))

        player.report(.itemFailed(engine.queue.current!.id, message: "Cannot Complete Action"))
        player.report(.itemFailed(engine.queue.upNext.first!.id, message: "Cannot Complete Action"))
        session.report(.mediaServicesLost)
        #expect(engine.status == .paused)
        #expect(scheduler.pendingDelays.isEmpty)

        session.report(.mediaServicesReset)
        #expect(engine.status == .playing)
        #expect(player.setItemsCalls.last?.startPosition == 25)
    }

    @Test func lossWhilePausedStaysPausedAfterReset() {
        let engine = playingEngine()
        engine.pause()
        session.report(.mediaServicesLost)
        session.report(.mediaServicesReset)
        #expect(engine.status == .paused)
        #expect(!player.isPlaying)
    }

    @Test func playDuringTheOutageWaitsForTheReset() {
        let engine = playingEngine()
        engine.pause()
        session.report(.mediaServicesLost)
        let activationsBefore = session.activationCount

        engine.play()
        #expect(engine.status == .reconnecting)
        #expect(session.activationCount == activationsBefore)

        session.report(.mediaServicesReset)
        #expect(engine.status == .playing)
        #expect(session.activationCount == activationsBefore + 1)
    }

    @Test func pauseDuringTheOutageCancelsTheResume() {
        let engine = playingEngine()
        session.report(.mediaServicesLost)
        engine.pause()
        session.report(.mediaServicesReset)
        #expect(engine.status == .paused)
    }

    @Test func networkReturningDuringTheOutageDoesNothing() {
        let engine = playingEngine()
        session.report(.mediaServicesLost)
        engine.play()
        let loadsBefore = player.setItemsCalls.count
        network.becomeAvailable()
        #expect(player.setItemsCalls.count == loadsBefore)
        #expect(engine.status == .reconnecting)
    }

    @Test func resetWithAnEmptyQueueDoesNothingVisible() {
        let engine = PlaybackEngine(
            player: player, session: session, nowPlaying: nowPlaying, urls: FakeStreamURLs(), store: store,
            scheduler: scheduler, network: FakeNetworkMonitor(), scrobbler: scrobbler
        )
        session.report(.mediaServicesReset)
        #expect(engine.status == .idle)
        #expect(player.setItemsCalls.isEmpty)
        #expect(nowPlaying.latest == nil)
    }
}
