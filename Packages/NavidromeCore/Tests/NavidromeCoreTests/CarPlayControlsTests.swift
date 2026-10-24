import Foundation
import Testing
@testable import NavidromeCore

/// What CarPlay's Now Playing buttons and Library tab rely on (Gitea #28).
@MainActor
struct CarPlayControlsTests {
    private let songs = [Song(id: "so-1", title: "Dawn", duration: 200), Song(id: "so-2", title: "Noon", duration: 210), Song(id: "so-3", title: "Dusk", duration: 220)]
    private let nowPlaying = FakeNowPlaying()

    private func makeEngine() -> PlaybackEngine {
        PlaybackEngine(
            player: FakeAudioPlayer(), session: FakeAudioSession(), nowPlaying: nowPlaying, urls: FakeStreamURLs(),
            store: InMemoryQueueStore(), scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler()
        )
    }

    @Test func nowPlayingSaysWhetherShuffleAndRepeatAreOn() {
        let engine = makeEngine()
        engine.play(songs: songs)
        #expect(nowPlaying.latest?.isShuffled == false)
        #expect(nowPlaying.latest?.repeatMode == .off)
        engine.toggleShuffle()
        engine.setRepeatMode(.one)
        #expect(nowPlaying.latest?.isShuffled == true)
        #expect(nowPlaying.latest?.repeatMode == .one)
    }

    @Test func carPlaysShuffleAndRepeatButtonsChangeThem() {
        let engine = makeEngine()
        engine.play(songs: songs)
        nowPlaying.send(.setShuffle(true))
        #expect(engine.isShuffled)
        // Already on: stays on, rather than toggling off.
        nowPlaying.send(.setShuffle(true))
        #expect(engine.isShuffled)
        nowPlaying.send(.setShuffle(false))
        #expect(!engine.isShuffled)
        nowPlaying.send(.setRepeat(.all))
        #expect(engine.repeatMode == .all)
    }

    @Test func topRatedIsTheServersHighestList() async throws {
        let transport = FakeTransport(.json(TestServer.ok))
        _ = try? await TestServer.client(transport).albumList(.highest, size: 10, offset: 0)
        let url = try #require(await transport.requests.first?.url)
        #expect(url.queryParameters["type"] == "highest")
    }

    @Test func topRatedIsntAPhoneSort() {
        #expect(!AlbumSort.phoneSorts.contains(.highest))
        #expect(AlbumSort.highest.title == "Top Rated")
    }
}
