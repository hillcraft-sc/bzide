import Foundation
import Testing
@testable import NavidromeCore

struct QueueInsertNextTests {
    private let songs = (1...4).map { Song(id: "so-\($0)", title: "Song \($0)") }
    private let extra = [Song(id: "x-1", title: "Extra 1"), Song(id: "x-2", title: "Extra 2")]

    @Test func insertsRightAfterTheCurrentEntry() {
        var queue = PlaybackQueue(songs: songs, startIndex: 1)
        queue.insertNext(extra)
        #expect(queue.entries.map(\.song.id) == ["so-1", "so-2", "x-1", "x-2", "so-3", "so-4"])
        #expect(queue.current?.song.id == "so-2")
    }

    @Test func theNewestPlayNextGoesFirst() {
        var queue = PlaybackQueue(songs: songs)
        queue.insertNext([extra[0]])
        queue.insertNext([extra[1]])
        #expect(queue.upNext.map(\.song.id) == ["x-2", "x-1", "so-2", "so-3", "so-4"])
    }

    @Test func onAnEmptyQueueItStartsTheQueue() {
        var queue = PlaybackQueue()
        queue.insertNext(extra)
        #expect(queue.current?.song.id == "x-1")
        #expect(queue.entries.count == 2)
    }
}

@MainActor
struct EnginePlayNextTests {
    private let songs = (1...3).map { Song(id: "so-\($0)", title: "Song \($0)", duration: 200) }
    private let player = FakeAudioPlayer()
    private let nowPlaying = FakeNowPlaying()
    private let store = InMemoryQueueStore()

    private func makeEngine() -> PlaybackEngine {
        PlaybackEngine(
            player: player, session: FakeAudioSession(), nowPlaying: nowPlaying, urls: FakeStreamURLs(),
            store: store, scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler()
        )
    }

    @Test func swapsTheBufferedNextTrackWithoutTouchingTheCurrentOne() {
        let engine = makeEngine()
        engine.play(songs: songs)
        let loadsBefore = player.setItemsCalls.count

        engine.playNext([Song(id: "x-1", title: "Extra")])

        #expect(player.setItemsCalls.count == loadsBefore)
        #expect(player.isPlaying)
        #expect(player.replacedUpcoming.map(\.url.absoluteString).last?.hasSuffix("id=x-1") == true)
        #expect(player.loadedEntryIDs == [engine.queue.current?.id, engine.queue.upNext.first?.id])
        #expect(engine.queue.upNext.map(\.song.id) == ["x-1", "so-2", "so-3"])
    }

    @Test func theInsertedSongPlaysWhenTheCurrentOneEnds() {
        let engine = makeEngine()
        engine.play(songs: songs)
        engine.playNext([Song(id: "x-1", title: "Extra")])
        player.finishCurrentItem()
        #expect(engine.queue.current?.song.id == "x-1")
        #expect(engine.queue.upNext.first?.song.id == "so-2")
    }

    @Test func onTheLastTrackItBecomesTheNextTrack() {
        let engine = makeEngine()
        engine.play(songs: songs, startIndex: 2)
        engine.playNext([Song(id: "x-1", title: "Extra")])
        #expect(engine.queue.hasNext)
        #expect(nowPlaying.latest?.hasNext == true)
        #expect(player.loadedEntryIDs.count == 2)
    }

    @Test func aRestoredQueueIsNotLoadedJustToInsert() {
        store.save(QueueSnapshot(queue: PlaybackQueue(songs: songs), position: 30))
        let engine = makeEngine()
        engine.playNext([Song(id: "x-1", title: "Extra")])
        #expect(player.setItemsCalls.isEmpty)
        #expect(player.replacedUpcoming.isEmpty)
        #expect(engine.status == .paused)
        #expect(engine.queue.upNext.first?.song.id == "x-1")
    }

    @Test func theInsertIsSaved() throws {
        let engine = makeEngine()
        engine.play(songs: songs)
        engine.playNext([Song(id: "x-1", title: "Extra")])
        let saved = try #require(store.load())
        #expect(saved.queue.upNext.first?.song.id == "x-1")
    }

    @Test func onAnEmptyQueueItQueuesWithoutPlaying() {
        let engine = makeEngine()
        engine.playNext([Song(id: "x-1", title: "Extra")])
        #expect(engine.queue.current?.song.id == "x-1")
        #expect(engine.status == .paused)
    }
}
