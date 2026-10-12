import Foundation
import Testing
@testable import NavidromeCore

/// The audio session activates asynchronously; the player must start only once
/// it's active, and never for a request the user has since replaced or cancelled.
@MainActor
struct AsyncActivationTests {
    private let player = FakeAudioPlayer()
    private let session = FakeAudioSession()
    private let songs = (1...3).map { Song(id: "so-\($0)", title: "Song \($0)", duration: 200) }

    init() {
        session.completesImmediately = false
    }

    private func makeEngine() -> PlaybackEngine {
        PlaybackEngine(
            player: player, session: session, nowPlaying: FakeNowPlaying(), urls: FakeStreamURLs(),
            store: InMemoryQueueStore(), scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler()
        )
    }

    @Test func thePlayerStartsOnlyOnceTheSessionIsActive() {
        let engine = makeEngine()
        engine.play(songs: songs)
        #expect(engine.status == .buffering)
        #expect(!player.isPlaying)
        // The loaded player reports itself paused meanwhile; that isn't shown.
        player.report(.statusChanged(.paused))
        #expect(engine.status == .buffering)

        session.finishActivation()
        #expect(player.isPlaying)
        #expect(engine.status == .playing)
    }

    @Test func pausingBeforeItsActiveMeansItNeverStarts() {
        let engine = makeEngine()
        engine.play(songs: songs)
        engine.pause()
        session.finishActivation()
        #expect(!player.isPlaying)
        #expect(engine.status == .paused)
    }

    @Test func skippingWhileWaitingPlaysTheNewSongOnceActive() {
        let engine = makeEngine()
        engine.play(songs: songs)
        // The next song is preloaded, so the player just moves to it; the
        // waiting activation still applies and starts it.
        engine.next()
        #expect(engine.queue.current?.song.id == "so-2")
        #expect(!player.isPlaying)
        session.finishActivation()
        #expect(player.isPlaying)
        #expect(engine.queue.current?.song.id == "so-2")
    }

    @Test func anInterruptionBeforeItsActiveCancelsIt() {
        let engine = makeEngine()
        engine.play(songs: songs)
        session.report(.interruptionBegan)
        session.finishActivation()
        #expect(!player.isPlaying)
        #expect(engine.status == .paused)
    }

    @Test func mediaServicesGoingDownCancelsIt() {
        let engine = makeEngine()
        engine.play(songs: songs)
        session.report(.mediaServicesLost)
        session.finishActivation()
        #expect(!player.isPlaying)
    }

    @Test func aRefusedActivationFailsWithoutPlaying() {
        let engine = makeEngine()
        engine.play(songs: songs)
        session.finishActivation(AudioSessionError(message: "Busy"))
        #expect(!player.isPlaying)
        #expect(engine.status == .failed("Can't play right now: Busy"))
        // Play tries again.
        engine.play()
        session.finishActivation()
        #expect(player.isPlaying)
    }

    @Test func playingANewQueueReplacesAWaitingOne() {
        let engine = makeEngine()
        engine.play(songs: songs)
        engine.play(songs: [Song(id: "x-1", title: "Other", duration: 100)])
        session.finishActivation()
        #expect(!player.isPlaying)
        session.finishActivation()
        #expect(player.isPlaying)
        #expect(engine.queue.current?.song.id == "x-1")
    }
}
