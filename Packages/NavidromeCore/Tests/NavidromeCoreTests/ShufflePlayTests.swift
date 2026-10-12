import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct ShufflePlayTests {
    @Test func shufflePlaysEverySongOnceFromTheStart() {
        let songs = (1...20).map { Song(id: "so-\($0)", title: "Song \($0)", duration: 200) }
        let player = FakeAudioPlayer()
        let engine = PlaybackEngine(
            player: player, session: FakeAudioSession(), nowPlaying: FakeNowPlaying(), urls: FakeStreamURLs(),
            store: InMemoryQueueStore(), scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler()
        )
        engine.playShuffled(songs)
        let queued = engine.queue.entries.map(\.song.id)
        #expect(Set(queued) == Set(songs.map(\.id)))
        #expect(queued.count == songs.count)
        #expect(engine.queue.current?.song.id == queued.first)
        #expect(engine.status == .playing)
    }
}

/// Same numbers every run, so shuffled orders can be checked exactly.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct QueueShuffleTests {
    private let songs = (1...8).map { Song(id: "so-\($0)", title: "Song \($0)") }

    private func ids(_ entries: some Collection<QueueEntry>) -> [String] {
        entries.map(\.song.id)
    }

    @Test func shufflingTouchesOnlyWhatsUpNext() {
        var queue = PlaybackQueue(songs: songs, startIndex: 2)
        var generator = SeededGenerator(state: 7)
        queue.shuffleUpcoming(using: &generator)
        #expect(ids(queue.entries.prefix(3)) == ["so-1", "so-2", "so-3"])
        #expect(queue.current?.song.id == "so-3")
        #expect(Set(ids(queue.upNext)) == Set(ids(songs.dropFirst(3).map { QueueEntry(song: $0) })))
        #expect(ids(queue.upNext) != ["so-4", "so-5", "so-6", "so-7", "so-8"])
    }

    @Test func restoringPutsUpNextBackInOrder() {
        var queue = PlaybackQueue(songs: songs)
        let origin = queue.entries.map(\.id)
        var generator = SeededGenerator(state: 3)
        queue.shuffleUpcoming(using: &generator)
        queue.restoreUpcoming(order: origin)
        #expect(ids(queue.entries) == ids(songs.map { QueueEntry(song: $0) }))
    }

    @Test func songsAddedWhileShuffledKeepTheirPlaces() {
        var queue = PlaybackQueue(songs: Array(songs.prefix(4)))
        let origin = queue.entries.map(\.id)
        var generator = SeededGenerator(state: 11)
        queue.shuffleUpcoming(using: &generator)
        queue.insertNext([Song(id: "x-1", title: "Next")])
        queue.append([Song(id: "x-2", title: "Last")])
        queue.restoreUpcoming(order: origin)
        #expect(ids(queue.entries) == ["so-1", "x-1", "so-2", "so-3", "so-4", "x-2"])
    }

    @Test func removedEntriesAreSimplyGone() {
        var queue = PlaybackQueue(songs: Array(songs.prefix(4)))
        let origin = queue.entries.map(\.id)
        queue.shuffleUpcoming()
        _ = queue.removeUpcoming(queue.entries.first { $0.song.id == "so-3" }?.id ?? UUID())
        queue.restoreUpcoming(order: origin)
        #expect(ids(queue.entries) == ["so-1", "so-2", "so-4"])
    }
}

@MainActor
struct EngineShuffleModeTests {
    private let songs = (1...12).map { Song(id: "so-\($0)", title: "Song \($0)", duration: 200) }
    private let player = FakeAudioPlayer()
    private let store = InMemoryQueueStore()

    private func makeEngine() -> PlaybackEngine {
        PlaybackEngine(
            player: player, session: FakeAudioSession(), nowPlaying: FakeNowPlaying(), urls: FakeStreamURLs(),
            store: store, scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler()
        )
    }

    private func ids(_ entries: some Collection<QueueEntry>) -> [String] {
        entries.map(\.song.id)
    }

    @Test func turningShuffleOnShufflesUpNextAndKeepsTheSongPlaying() {
        let engine = makeEngine()
        engine.play(songs: songs, startIndex: 3)
        let loadsBefore = player.setItemsCalls.count
        #expect(!engine.isShuffled)

        engine.toggleShuffle()
        #expect(engine.isShuffled)
        #expect(engine.queue.current?.song.id == "so-4")
        #expect(Set(ids(engine.queue.upNext)) == Set((5...12).map { "so-\($0)" }))
        #expect(ids(engine.queue.entries.prefix(3)) == ["so-1", "so-2", "so-3"])
        #expect(player.setItemsCalls.count == loadsBefore)
        #expect(player.isPlaying)
        // The buffered next track is whatever now comes next.
        #expect(player.loadedEntryIDs == [engine.queue.current?.id, engine.queue.upNext.first?.id])
    }

    @Test func turningItOffRestoresTheOrder() {
        let engine = makeEngine()
        engine.play(songs: songs)
        engine.toggleShuffle()
        engine.toggleShuffle()
        #expect(!engine.isShuffled)
        #expect(ids(engine.queue.entries) == songs.map(\.id))
        #expect(player.loadedEntryIDs == [engine.queue.current?.id, engine.queue.upNext.first?.id])
    }

    @Test func shufflePlayTurnsShuffleOnAndOffGivesTheRestInOrder() {
        let engine = makeEngine()
        engine.playShuffled(songs)
        #expect(engine.isShuffled)
        let current = engine.queue.current?.song.id
        engine.toggleShuffle()
        // Everything not played yet, in album order, after the song that's playing.
        #expect(engine.queue.current?.song.id == current)
        #expect(ids(engine.queue.upNext) == songs.map(\.id).filter { $0 != current })
    }

    @Test func playingInOrderTurnsShuffleOff() {
        let engine = makeEngine()
        engine.playShuffled(songs)
        engine.play(songs: songs)
        #expect(!engine.isShuffled)
        #expect(ids(engine.queue.entries) == songs.map(\.id))
    }

    @Test func shuffleIsSavedAndRestored() {
        let engine = makeEngine()
        engine.play(songs: songs)
        engine.toggleShuffle()
        let shuffled = ids(engine.queue.entries)

        let relaunched = makeEngine()
        #expect(relaunched.isShuffled)
        #expect(ids(relaunched.queue.entries) == shuffled)
        relaunched.toggleShuffle()
        #expect(ids(relaunched.queue.entries) == songs.map(\.id))
    }

    @Test func aRadioStationCantBeShuffled() {
        let engine = makeEngine()
        let stream = URL(string: "https://radio.example.org/live")!
        engine.play(songs: [Song(station: RadioStation(id: "rs-1", name: "Live", streamURL: stream), stream: stream)])
        engine.toggleShuffle()
        #expect(!engine.isShuffled)
    }

    @Test func aQueueSavedBeforeShuffleExistedIsInOrder() throws {
        let saved = try JSONEncoder().encode(QueueSnapshot(queue: PlaybackQueue(songs: songs), position: 0))
        var json = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        json["shuffleOrigin"] = nil
        let old = try JSONDecoder().decode(QueueSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.shuffleOrigin == nil)
    }
}
