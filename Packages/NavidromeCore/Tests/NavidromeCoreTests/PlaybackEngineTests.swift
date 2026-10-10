import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct PlaybackEngineTests {
    private let songs = (1...4).map { Song(id: "so-\($0)", title: "Song \($0)", duration: 200) }
    private let player = FakeAudioPlayer()
    private let session = FakeAudioSession()
    private let nowPlaying = FakeNowPlaying()
    private let store = InMemoryQueueStore()

    private func makeEngine(urls: FakeStreamURLs = FakeStreamURLs()) -> PlaybackEngine {
        PlaybackEngine(player: player, session: session, nowPlaying: nowPlaying, urls: urls, store: store)
    }

    private func ids(_ engine: PlaybackEngine, _ indices: Int...) -> [QueueEntry.ID] {
        indices.map { engine.queue.entries[$0].id }
    }

    // MARK: Starting playback

    @Test func playLoadsCurrentAndNextThenPlays() {
        let engine = makeEngine()
        engine.play(songs: songs, startIndex: 1)
        #expect(engine.queue.current?.song.id == "so-2")
        #expect(player.loadedEntryIDs == ids(engine, 1, 2))
        #expect(player.isPlaying)
        #expect(engine.status == .playing)
        #expect(engine.duration == 200)
        #expect(store.load()?.queue == engine.queue)
    }

    @Test func singleSongQueueLoadsOneItem() {
        let engine = makeEngine()
        engine.play(songs: [songs[0]])
        #expect(player.loaded.count == 1)
    }

    @Test func playingAnEmptyListClearsEverything() {
        let engine = makeEngine()
        engine.play(songs: songs)
        engine.play(songs: [])
        #expect(engine.queue.isEmpty)
        #expect(engine.status == .idle)
        #expect(player.loaded.isEmpty)
    }

    // MARK: Gapless advance

    @Test func trackEndingAdvancesQueueAndPreloadsTheOneAfter() {
        let engine = makeEngine()
        engine.play(songs: songs)
        player.report(.timeChanged(150))

        player.finishCurrentItem()

        #expect(engine.queue.current?.song.id == "so-2")
        #expect(engine.position == 0)
        // Current and next are loaded again, without reloading the current one.
        #expect(player.loadedEntryIDs == ids(engine, 1, 2))
        #expect(player.setItemsCalls.count == 1)
        #expect(store.load()?.queue.currentIndex == 1)
    }

    @Test func lastTrackEndingStopsOnItRewound() {
        let engine = makeEngine()
        engine.play(songs: songs, startIndex: 3)
        player.report(.timeChanged(199))

        player.finishCurrentItem()

        #expect(engine.queue.current?.song.id == "so-4")
        #expect(engine.status == .paused)
        #expect(engine.position == 0)

        // Play starts the last track again from the top.
        engine.play()
        #expect(player.setItemsCalls.last?.startPosition == 0)
        #expect(player.loadedEntryIDs == ids(engine, 3))
    }

    // MARK: Next and previous

    @Test func nextSkipsToThePreloadedTrack() {
        let engine = makeEngine()
        engine.play(songs: songs)
        engine.next()
        #expect(engine.queue.current?.song.id == "so-2")
        #expect(player.setItemsCalls.count == 1)
        #expect(player.loadedEntryIDs == ids(engine, 1, 2))
    }

    @Test func nextOnTheLastTrackDoesNothing() {
        let engine = makeEngine()
        engine.play(songs: songs, startIndex: 3)
        engine.next()
        #expect(engine.queue.current?.song.id == "so-4")
        #expect(engine.status == .playing)
    }

    @Test func previousEarlyInATrackGoesBackAndKeepsPlaying() {
        let engine = makeEngine()
        engine.play(songs: songs, startIndex: 2)
        player.report(.timeChanged(2))

        engine.previous()

        #expect(engine.queue.current?.song.id == "so-2")
        #expect(player.setItemsCalls.last?.items.map(\.entryID) == ids(engine, 1, 2))
        #expect(player.isPlaying)
    }

    @Test func previousLaterInATrackRestartsIt() {
        let engine = makeEngine()
        engine.play(songs: songs, startIndex: 2)
        player.report(.timeChanged(30))

        engine.previous()

        #expect(engine.queue.current?.song.id == "so-3")
        #expect(player.seeks == [0])
        #expect(engine.position == 0)
    }

    @Test func previousOnTheFirstTrackRestartsIt() {
        let engine = makeEngine()
        engine.play(songs: songs)
        player.report(.timeChanged(1))
        engine.previous()
        #expect(engine.queue.current?.song.id == "so-1")
        #expect(player.seeks == [0])
    }

    @Test func jumpLoadsTheChosenEntry() {
        let engine = makeEngine()
        engine.play(songs: songs)
        let target = engine.queue.entries[3].id
        engine.jump(to: target)
        #expect(engine.queue.current?.id == target)
        #expect(player.loadedEntryIDs == [target])
        #expect(player.isPlaying)
    }

    // MARK: Pause, seek and saving position

    @Test func pauseSavesThePosition() {
        let engine = makeEngine()
        engine.play(songs: songs)
        player.report(.timeChanged(42))
        engine.pause()
        #expect(engine.status == .paused)
        #expect(store.load()?.position == 42)
    }

    @Test func positionIsSavedEveryTenSecondsWhilePlaying() {
        let engine = makeEngine()
        engine.play(songs: songs)
        player.report(.timeChanged(9.5))
        #expect(store.load()?.position == 0)
        player.report(.timeChanged(10.5))
        #expect(store.load()?.position == 10.5)
        player.report(.timeChanged(15))
        #expect(store.load()?.position == 10.5)
    }

    @Test func seekIsClampedToTheTrack() {
        let engine = makeEngine()
        engine.play(songs: songs)
        engine.seek(to: 500)
        engine.seek(to: -5)
        #expect(player.seeks == [200, 0])
    }

    @Test func playerDurationReplacesMetadataDuration() {
        let engine = makeEngine()
        engine.play(songs: songs)
        player.report(.durationKnown(201.4))
        #expect(engine.duration == 201.4)
    }

    // MARK: Restoring after relaunch

    @Test func restoresSavedQueuePausedWithoutLoadingAnything() {
        var queue = PlaybackQueue(songs: songs)
        queue.advance()
        store.save(QueueSnapshot(queue: queue, position: 73))

        let engine = makeEngine()

        #expect(engine.queue == queue)
        #expect(engine.position == 73)
        #expect(engine.status == .paused)
        #expect(player.setItemsCalls.isEmpty)
    }

    @Test func playAfterRestoreResumesAtTheSavedPosition() {
        store.save(QueueSnapshot(queue: PlaybackQueue(songs: songs, startIndex: 1), position: 73))
        let engine = makeEngine()

        engine.play()

        #expect(player.setItemsCalls.count == 1)
        #expect(player.setItemsCalls[0].startPosition == 73)
        #expect(player.loadedEntryIDs == ids(engine, 1, 2))
        #expect(player.isPlaying)
    }

    @Test func nextWhileRestoredMovesTheQueueWithoutLoading() {
        store.save(QueueSnapshot(queue: PlaybackQueue(songs: songs), position: 73))
        let engine = makeEngine()
        engine.next()
        #expect(engine.queue.current?.song.id == "so-2")
        #expect(engine.position == 0)
        #expect(player.setItemsCalls.isEmpty)
    }

    @Test func unreadableSaveStartsEmpty() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "queue-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("garbage".utf8).write(to: file)

        let engine = PlaybackEngine(player: player, session: session, nowPlaying: nowPlaying, urls: FakeStreamURLs(), store: FileQueueStore(fileURL: file))

        #expect(engine.queue.isEmpty)
        #expect(engine.status == .idle)
    }

    // MARK: Appending

    @Test func appendingWhileOnTheLastTrackPreloadsTheNewNext() {
        let engine = makeEngine()
        engine.play(songs: [songs[0]])
        engine.append([songs[1]])
        #expect(player.loadedEntryIDs == ids(engine, 0, 1))
    }

    @Test func appendingToAnEmptyQueueDoesNotStartPlayback() {
        let engine = makeEngine()
        engine.append([songs[0]])
        #expect(engine.queue.current?.song.id == "so-1")
        #expect(engine.status == .paused)
        #expect(!player.isPlaying)
        #expect(player.setItemsCalls.isEmpty)
    }

    // MARK: Failures

    @Test func failedCurrentTrackShowsAndPlayRetries() {
        let engine = makeEngine()
        engine.play(songs: songs)
        let current = engine.queue.entries[0].id

        player.report(.itemFailed(current, message: "The network connection was lost."))
        #expect(engine.status == .failed("The network connection was lost."))
        // A later status event doesn't hide the failure.
        player.report(.statusChanged(.paused))
        #expect(engine.status == .failed("The network connection was lost."))

        engine.play()
        #expect(player.setItemsCalls.count == 2)
        #expect(engine.status == .playing)
    }

    @Test func failedPreloadedTrackDoesNotInterruptTheCurrentOne() {
        let engine = makeEngine()
        engine.play(songs: songs)
        player.report(.itemFailed(engine.queue.entries[1].id, message: "Not found"))
        #expect(engine.status == .playing)
    }

    @Test func missingStreamURLFailsTheTrack() {
        let engine = makeEngine(urls: FakeStreamURLs(failingSongIDs: ["so-1"]))
        engine.play(songs: songs)
        guard case .failed = engine.status else {
            Issue.record("Expected failed status, got \(engine.status)")
            return
        }
        #expect(!player.isPlaying)
    }
}
