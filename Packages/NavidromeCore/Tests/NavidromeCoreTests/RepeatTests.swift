import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct RepeatTests {
    private let songs = (1...3).map { Song(id: "so-\($0)", title: "Song \($0)", duration: 60) }
    private let player = FakeAudioPlayer()
    private let nowPlaying = FakeNowPlaying()
    private let store = InMemoryQueueStore()
    private let scrobbler = FakeScrobbler()

    private func makeEngine() -> PlaybackEngine {
        PlaybackEngine(
            player: player, session: FakeAudioSession(), nowPlaying: nowPlaying, urls: FakeStreamURLs(),
            store: store, scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: scrobbler
        )
    }

    private func entryIDs(_ engine: PlaybackEngine, _ indices: Int...) -> [QueueEntry.ID] {
        indices.map { engine.queue.entries[$0].id }
    }

    private func listen(to seconds: Double) {
        var time = 0.0
        while time < seconds {
            time += 0.5
            player.report(.timeChanged(time))
        }
    }

    @Test func theButtonStepsOffAllOne() {
        let engine = makeEngine()
        #expect(engine.repeatMode == .off)
        engine.cycleRepeatMode()
        #expect(engine.repeatMode == .all)
        engine.cycleRepeatMode()
        #expect(engine.repeatMode == .one)
        engine.cycleRepeatMode()
        #expect(engine.repeatMode == .off)
    }

    // MARK: Repeat all

    @Test func repeatAllPreloadsTheFirstTrackOnTheLast() {
        let engine = makeEngine()
        engine.play(songs: songs, startIndex: 2)
        #expect(player.loadedEntryIDs == entryIDs(engine, 2))

        engine.setRepeatMode(.all)
        #expect(player.loadedEntryIDs == entryIDs(engine, 2, 0))
        #expect(nowPlaying.latest?.hasNext == true)
    }

    @Test func repeatAllWrapsToTheStartWithoutReloading() {
        let engine = makeEngine()
        engine.setRepeatMode(.all)
        engine.play(songs: songs, startIndex: 2)
        let loadsBefore = player.setItemsCalls.count

        player.finishCurrentItem()

        #expect(engine.queue.current?.song.id == "so-1")
        #expect(engine.status == .playing)
        #expect(player.setItemsCalls.count == loadsBefore)
        #expect(player.loadedEntryIDs == entryIDs(engine, 0, 1))
    }

    @Test func nextOnTheLastTrackWrapsWithRepeatAll() {
        let engine = makeEngine()
        engine.setRepeatMode(.all)
        engine.play(songs: songs, startIndex: 2)
        engine.next()
        #expect(engine.queue.current?.song.id == "so-1")
    }

    @Test func aSingleSongWithRepeatAllPlaysAgain() {
        let engine = makeEngine()
        engine.setRepeatMode(.all)
        engine.play(songs: [songs[0]])
        #expect(player.loadedEntryIDs == entryIDs(engine, 0))

        player.finishCurrentItem()

        #expect(engine.queue.current?.song.id == "so-1")
        #expect(engine.status == .playing)
        #expect(player.setItemsCalls.last?.startPosition == 0)
    }

    // MARK: Repeat one

    @Test func repeatOneReplaysTheTrackAsANewPlay() {
        let engine = makeEngine()
        engine.setRepeatMode(.one)
        engine.play(songs: songs)
        #expect(player.loadedEntryIDs == entryIDs(engine, 0))

        listen(to: 40)
        player.finishCurrentItem()
        #expect(engine.queue.current?.song.id == "so-1")
        #expect(engine.status == .playing)
        #expect(engine.position == 0)

        listen(to: 40)
        #expect(scrobbler.submitted.map(\.songID) == ["so-1", "so-1"])
    }

    @Test func nextStillMovesOnWithRepeatOne() {
        let engine = makeEngine()
        engine.setRepeatMode(.one)
        engine.play(songs: songs)
        engine.next()
        #expect(engine.queue.current?.song.id == "so-2")
        #expect(engine.repeatMode == .one)
        #expect(engine.status == .playing)
        #expect(player.loadedEntryIDs == entryIDs(engine, 1))
    }

    @Test func switchingRepeatOneOnAndOffChangesThePreloadedTrack() {
        let engine = makeEngine()
        engine.play(songs: songs)
        #expect(player.loadedEntryIDs == entryIDs(engine, 0, 1))

        engine.setRepeatMode(.one)
        #expect(player.loadedEntryIDs == entryIDs(engine, 0))
        #expect(player.isPlaying)

        engine.setRepeatMode(.off)
        #expect(player.loadedEntryIDs == entryIDs(engine, 0, 1))
    }

    @Test func repeatOneOnTheLastTrackKeepsPlaying() {
        let engine = makeEngine()
        engine.setRepeatMode(.one)
        engine.play(songs: songs, startIndex: 2)
        player.finishCurrentItem()
        #expect(engine.queue.current?.song.id == "so-3")
        #expect(engine.status == .playing)
    }

    // MARK: Off and persistence

    @Test func withRepeatOffTheQueueStillEnds() {
        let engine = makeEngine()
        engine.play(songs: songs, startIndex: 2)
        player.finishCurrentItem()
        #expect(engine.queue.isEmpty)
    }

    @Test func theModeSurvivesARelaunch() {
        let engine = makeEngine()
        engine.play(songs: songs)
        engine.setRepeatMode(.one)
        #expect(store.load()?.repeatMode == .one)
        #expect(makeEngine().repeatMode == .one)
    }

    @Test func aQueueSavedBeforeRepeatExistedHasRepeatOff() throws {
        let saved = try JSONEncoder().encode(QueueSnapshot(queue: PlaybackQueue(songs: songs), position: 5))
        var object = try #require(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        object["repeatMode"] = nil
        let old = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(QueueSnapshot.self, from: old)
        #expect(decoded.repeatMode == .off)
        #expect(decoded.position == 5)
    }
}
