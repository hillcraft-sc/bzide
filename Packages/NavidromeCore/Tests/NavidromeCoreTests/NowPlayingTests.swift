import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct NowPlayingTests {
    private let songs = [
        Song(id: "so-1", title: "Dawn", album: "First Light", artist: "Aurora Lines", coverArtID: "al-1", duration: 200),
        Song(id: "so-2", title: "Noon", album: "First Light", artist: "Aurora Lines", coverArtID: "al-1", duration: 210),
    ]
    private let player = FakeAudioPlayer()
    private let nowPlaying = FakeNowPlaying()
    private let store = InMemoryQueueStore()

    private func makeEngine() -> PlaybackEngine {
        PlaybackEngine(player: player, session: FakeAudioSession(), nowPlaying: nowPlaying, urls: FakeStreamURLs(), store: store)
    }

    @Test func emptyQueueClearsNowPlaying() {
        _ = makeEngine()
        #expect(nowPlaying.updates.count == 1)
        #expect(nowPlaying.latest == nil)
    }

    @Test func restoredQueueShowsPausedTrackAtSavedPosition() {
        store.save(QueueSnapshot(queue: PlaybackQueue(songs: songs), position: 42))
        _ = makeEngine()
        #expect(nowPlaying.latest == NowPlayingInfo(
            title: "Dawn", artist: "Aurora Lines", album: "First Light", coverArtID: "al-1",
            duration: 200, elapsed: 42, isPlaying: false, hasNext: true, hasPrevious: false
        ))
    }

    @Test func playingShowsTheTrackAsPlaying() {
        let engine = makeEngine()
        engine.play(songs: songs)
        #expect(nowPlaying.latest?.title == "Dawn")
        #expect(nowPlaying.latest?.isPlaying == true)
        #expect(nowPlaying.latest?.elapsed == 0)
    }

    @Test func timeTicksAreNotSentButPauseSendsTheElapsedTime() {
        let engine = makeEngine()
        engine.play(songs: songs)
        let countBefore = nowPlaying.updates.count
        player.report(.timeChanged(30))
        player.report(.timeChanged(30.5))
        #expect(nowPlaying.updates.count == countBefore)

        engine.pause()
        #expect(nowPlaying.latest?.elapsed == 30.5)
        #expect(nowPlaying.latest?.isPlaying == false)
    }

    @Test func trackChangeUpdatesInfoAndButtons() {
        let engine = makeEngine()
        engine.play(songs: songs)
        player.finishCurrentItem()
        #expect(nowPlaying.latest?.title == "Noon")
        #expect(nowPlaying.latest?.duration == 210)
        #expect(nowPlaying.latest?.hasNext == false)
        #expect(nowPlaying.latest?.hasPrevious == true)
    }

    @Test func seekSendsTheNewPosition() {
        let engine = makeEngine()
        engine.play(songs: songs)
        engine.seek(to: 120)
        #expect(nowPlaying.latest?.elapsed == 120)
    }

    @Test func unchangedStateIsNotResent() {
        let engine = makeEngine()
        engine.play(songs: songs)
        let countBefore = nowPlaying.updates.count
        player.report(.statusChanged(.playing))
        #expect(nowPlaying.updates.count == countBefore)
    }

    @Test func remoteCommandsDriveTheEngine() {
        let engine = makeEngine()
        engine.play(songs: songs)

        nowPlaying.send(.pause)
        #expect(engine.status == .paused)
        nowPlaying.send(.play)
        #expect(engine.status == .playing)
        nowPlaying.send(.togglePlayPause)
        #expect(engine.status == .paused)

        nowPlaying.send(.next)
        #expect(engine.queue.current?.song.id == "so-2")
        nowPlaying.send(.previous)
        #expect(engine.queue.current?.song.id == "so-1")

        nowPlaying.send(.seek(to: 50))
        #expect(engine.position == 50)
    }
}
