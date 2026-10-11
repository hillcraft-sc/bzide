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
