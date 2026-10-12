import Foundation
import Testing
@testable import NavidromeCore

struct QueueEditingTests {
    private let songs = (1...5).map { Song(id: "so-\($0)", title: "Song \($0)") }

    private func ids(_ queue: PlaybackQueue) -> [String] {
        queue.entries.map(\.song.id)
    }

    @Test func removesOneUpcomingEntry() {
        var queue = PlaybackQueue(songs: songs, startIndex: 1)
        let target = queue.upNext[queue.upNext.startIndex + 1].id // so-4
        let removed = queue.removeUpcoming(target)
        #expect(removed)
        #expect(ids(queue) == ["so-1", "so-2", "so-3", "so-5"])
        #expect(queue.current?.song.id == "so-2")
    }

    @Test func theCurrentAndPlayedEntriesCannotBeRemoved() {
        var queue = PlaybackQueue(songs: songs, startIndex: 1)
        let current = queue.removeUpcoming(queue.entries[1].id)
        let played = queue.removeUpcoming(queue.entries[0].id)
        let unknown = queue.removeUpcoming(UUID())
        #expect(!current && !played && !unknown)
        #expect(ids(queue) == songs.map(\.id))
    }

    @Test func aRepeatedSongLosesOnlyTheChosenEntry() {
        var queue = PlaybackQueue(songs: [songs[0], songs[1], songs[1]])
        let removed = queue.removeUpcoming(queue.entries[2].id)
        #expect(removed)
        #expect(ids(queue) == ["so-1", "so-2"])
    }

    @Test func movesDownLikeAList() {
        // Up next is so-2…so-5; drag so-2 to after so-4 (destination 3).
        var queue = PlaybackQueue(songs: songs)
        queue.moveUpcoming(fromOffsets: [0], toOffset: 3)
        #expect(ids(queue) == ["so-1", "so-3", "so-4", "so-2", "so-5"])
    }

    @Test func movesUpLikeAList() {
        var queue = PlaybackQueue(songs: songs)
        queue.moveUpcoming(fromOffsets: [3], toOffset: 0)
        #expect(ids(queue) == ["so-1", "so-5", "so-2", "so-3", "so-4"])
    }

    @Test func movesToTheEndAndKeepsSeveralInOrder() {
        var queue = PlaybackQueue(songs: songs)
        queue.moveUpcoming(fromOffsets: [0, 2], toOffset: 4)
        #expect(ids(queue) == ["so-1", "so-3", "so-5", "so-2", "so-4"])
    }

    @Test func playedEntriesStayPut() {
        var queue = PlaybackQueue(songs: songs, startIndex: 2)
        queue.moveUpcoming(fromOffsets: [1], toOffset: 0)
        #expect(ids(queue) == ["so-1", "so-2", "so-3", "so-5", "so-4"])
        #expect(queue.current?.song.id == "so-3")
    }

    @Test func outOfRangeMovesChangeNothing() {
        var queue = PlaybackQueue(songs: songs)
        queue.moveUpcoming(fromOffsets: [9], toOffset: 0)
        #expect(ids(queue) == songs.map(\.id))
        var empty = PlaybackQueue()
        empty.moveUpcoming(fromOffsets: [0], toOffset: 1)
        #expect(empty.isEmpty)
    }
}

@MainActor
struct EngineQueueEditingTests {
    private let songs = (1...4).map { Song(id: "so-\($0)", title: "Song \($0)", duration: 200) }
    private let player = FakeAudioPlayer()
    private let nowPlaying = FakeNowPlaying()
    private let store = InMemoryQueueStore()

    private func makeEngine() -> PlaybackEngine {
        PlaybackEngine(
            player: player, session: FakeAudioSession(), nowPlaying: nowPlaying, urls: FakeStreamURLs(),
            store: store, scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler()
        )
    }

    @Test func removingTheNextSongBuffersTheOneAfter() throws {
        let engine = makeEngine()
        engine.play(songs: songs)
        let loadsBefore = player.setItemsCalls.count
        let next = engine.queue.upNext.first?.id

        engine.removeFromQueue(try #require(next))

        #expect(player.setItemsCalls.count == loadsBefore)
        #expect(player.isPlaying)
        #expect(engine.queue.upNext.map(\.song.id) == ["so-3", "so-4"])
        #expect(player.loadedEntryIDs == [engine.queue.current?.id, engine.queue.upNext.first?.id])
        player.finishCurrentItem()
        #expect(engine.queue.current?.song.id == "so-3")
    }

    @Test func removingALaterSongLeavesTheBufferAlone() {
        let engine = makeEngine()
        engine.play(songs: songs)
        let swapsBefore = player.replacedUpcoming.count
        engine.removeFromQueue(engine.queue.entries[3].id)
        #expect(player.replacedUpcoming.count == swapsBefore)
        #expect(engine.queue.upNext.map(\.song.id) == ["so-2", "so-3"])
    }

    @Test func removingTheOnlyUpcomingSongEmptiesTheBuffer() {
        let engine = makeEngine()
        engine.play(songs: Array(songs.prefix(2)))
        engine.removeFromQueue(engine.queue.entries[1].id)
        #expect(player.loadedEntryIDs == [engine.queue.current?.id])
        #expect(nowPlaying.latest?.hasNext == false)
    }

    @Test func theCurrentSongCannotBeRemoved() {
        let engine = makeEngine()
        engine.play(songs: songs)
        engine.removeFromQueue(engine.queue.entries[0].id)
        #expect(engine.queue.entries.count == 4)
        #expect(player.isPlaying)
    }

    @Test func movingANewSongToTheFrontSwapsTheBuffer() {
        let engine = makeEngine()
        engine.play(songs: songs)
        engine.moveUpcoming(fromOffsets: [2], toOffset: 0)
        #expect(engine.queue.upNext.map(\.song.id) == ["so-4", "so-2", "so-3"])
        #expect(player.loadedEntryIDs == [engine.queue.current?.id, engine.queue.upNext.first?.id])
        player.finishCurrentItem()
        #expect(engine.queue.current?.song.id == "so-4")
    }

    @Test func reorderingBehindTheNextSongLeavesTheBufferAlone() {
        let engine = makeEngine()
        engine.play(songs: songs)
        let swapsBefore = player.replacedUpcoming.count
        engine.moveUpcoming(fromOffsets: [2], toOffset: 1)
        #expect(engine.queue.upNext.map(\.song.id) == ["so-2", "so-4", "so-3"])
        #expect(player.replacedUpcoming.count == swapsBefore)
    }

    @Test func editsAreSaved() throws {
        let engine = makeEngine()
        engine.play(songs: songs)
        engine.moveUpcoming(fromOffsets: [0], toOffset: 3)
        engine.removeFromQueue(engine.queue.entries[1].id)
        let saved = try #require(store.load())
        #expect(saved.queue.entries.map(\.song.id) == ["so-1", "so-4", "so-2"])
    }

    @Test func aRestoredQueueIsNotLoadedJustToEdit() {
        store.save(QueueSnapshot(queue: PlaybackQueue(songs: songs), position: 30))
        let engine = makeEngine()
        engine.moveUpcoming(fromOffsets: [0], toOffset: 3)
        engine.removeFromQueue(engine.queue.entries[1].id)
        #expect(player.setItemsCalls.isEmpty)
        #expect(player.replacedUpcoming.isEmpty)
        #expect(engine.status == .paused)
    }
}
