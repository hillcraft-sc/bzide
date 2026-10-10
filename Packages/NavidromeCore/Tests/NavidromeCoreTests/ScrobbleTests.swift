import Foundation
import Testing
@testable import NavidromeCore

struct ScrobbleTrackerTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Feeds half-second ticks from `from` to `to`, like the player does.
    private func listen(_ tracker: inout ScrobbleTracker, from: TimeInterval, to: TimeInterval) -> Int {
        var crossings = 0
        var time = from
        while time < to {
            time += 0.5
            if tracker.observe(time: time) { crossings += 1 }
        }
        return crossings
    }

    @Test func shortTrackNeedsHalfItsLength() {
        var tracker = ScrobbleTracker()
        tracker.begin(songID: "so-1", duration: 200, position: 0, at: start)
        #expect(tracker.threshold == 100)
        let beforeHalfway = listen(&tracker, from: 0, to: 99.5)
        let atHalfway = listen(&tracker, from: 99.5, to: 100)
        #expect(beforeHalfway == 0)
        #expect(atHalfway == 1)
    }

    @Test func longTrackNeedsFourMinutes() {
        var tracker = ScrobbleTracker()
        tracker.begin(songID: "so-1", duration: 1200, position: 0, at: start)
        #expect(tracker.threshold == 240)
    }

    @Test func unknownDurationNeedsFourMinutes() {
        var tracker = ScrobbleTracker()
        tracker.begin(songID: "so-1", duration: nil, position: 0, at: start)
        #expect(tracker.threshold == 240)
    }

    @Test func crossesOnlyOncePerPlay() {
        var tracker = ScrobbleTracker()
        tracker.begin(songID: "so-1", duration: 200, position: 0, at: start)
        let crossings = listen(&tracker, from: 0, to: 200)
        #expect(crossings == 1)
    }

    @Test func seekingForwardEarnsNothing() {
        var tracker = ScrobbleTracker()
        tracker.begin(songID: "so-1", duration: 200, position: 0, at: start)
        _ = listen(&tracker, from: 0, to: 10)
        tracker.seeked(to: 150)
        let crossings = listen(&tracker, from: 150, to: 200)
        #expect(crossings == 0)
        #expect(tracker.play?.listened == 60)
    }

    @Test func unannouncedJumpsAreTreatedAsSeeks() {
        // A jump the engine didn't report as a seek (e.g. a reload) still earns nothing.
        var tracker = ScrobbleTracker()
        tracker.begin(songID: "so-1", duration: 200, position: 0, at: start)
        _ = tracker.observe(time: 0.5)
        _ = tracker.observe(time: 120)
        #expect(tracker.play?.listened == 0.5)
    }

    @Test func seekingBackKeepsWhatWasListened() {
        var tracker = ScrobbleTracker()
        tracker.begin(songID: "so-1", duration: 200, position: 0, at: start)
        _ = listen(&tracker, from: 0, to: 60)
        tracker.seeked(to: 0)
        let crossings = listen(&tracker, from: 0, to: 40)
        #expect(crossings == 1)
    }

    @Test func announcesOncePerPlay() {
        var tracker = ScrobbleTracker()
        tracker.begin(songID: "so-1", duration: 200, position: 0, at: start)
        let first = tracker.announce()
        let second = tracker.announce()
        #expect(first)
        #expect(!second)
        tracker.begin(songID: "so-1", duration: 200, position: 0, at: start)
        let afterNewPlay = tracker.announce()
        #expect(afterNewPlay)
    }
}

@MainActor
struct EngineScrobbleTests {
    private let songs = (1...2).map { Song(id: "so-\($0)", title: "Song \($0)", duration: 60) }
    private let player = FakeAudioPlayer()
    private let scrobbler = FakeScrobbler()
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEngine() -> PlaybackEngine {
        PlaybackEngine(
            player: player, session: FakeAudioSession(), nowPlaying: FakeNowPlaying(), urls: FakeStreamURLs(),
            store: InMemoryQueueStore(), scheduler: FakeScheduler(), network: FakeNetworkMonitor(),
            scrobbler: scrobbler, now: { [start] in start }
        )
    }

    private func tick(from: TimeInterval, to: TimeInterval) {
        var time = from
        while time < to {
            time += 0.5
            player.report(.timeChanged(time))
        }
    }

    @Test func startingPlaybackAnnouncesNowPlayingOnce() {
        let engine = makeEngine()
        engine.play(songs: songs)
        engine.pause()
        engine.play()
        #expect(scrobbler.nowPlayingSongIDs == ["so-1"])
    }

    @Test func listeningPastHalfwaySubmitsOnceWithTheStartTime() {
        let engine = makeEngine()
        engine.play(songs: songs)
        tick(from: 0, to: 29.5)
        #expect(scrobbler.submitted.isEmpty)
        tick(from: 29.5, to: 60)
        #expect(scrobbler.submitted == [PendingScrobble(songID: "so-1", playedAt: start)])
    }

    @Test func seekingToTheEndDoesNotScrobble() {
        let engine = makeEngine()
        engine.play(songs: songs)
        tick(from: 0, to: 5)
        engine.seek(to: 55)
        tick(from: 55, to: 60)
        #expect(scrobbler.submitted.isEmpty)
    }

    @Test func eachTrackGetsItsOwnPlay() {
        let engine = makeEngine()
        engine.play(songs: songs)
        tick(from: 0, to: 40)
        player.finishCurrentItem()
        tick(from: 0, to: 40)
        #expect(scrobbler.submitted.map(\.songID) == ["so-1", "so-2"])
        #expect(scrobbler.nowPlayingSongIDs == ["so-1", "so-2"])
    }

    @Test func restartingWithPreviousIsANewPlay() {
        let engine = makeEngine()
        engine.play(songs: songs)
        tick(from: 0, to: 40)
        engine.previous()  // more than 3 seconds in: restarts the track
        tick(from: 0, to: 40)
        #expect(scrobbler.submitted.map(\.songID) == ["so-1", "so-1"])
    }
}

@MainActor
struct ScrobblerTests {
    private let played = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func submittedScrobbleIsSentAndCleared() async {
        let sender = FakeScrobbleSender()
        let store = InMemoryScrobbleStore()
        let scrobbler = Scrobbler(sender: sender, store: store)

        scrobbler.submit(PendingScrobble(songID: "so-1", playedAt: played))
        #expect(store.load().count == 1)  // saved before sending
        await scrobbler.flush()

        #expect(sender.calls == [.init(songID: "so-1", playedAt: played, submission: true)])
        #expect(scrobbler.pending.isEmpty)
        #expect(store.load().isEmpty)
    }

    @Test func offlineScrobblesWaitAndAreSentInOrderLater() async {
        let sender = FakeScrobbleSender()
        sender.setOffline(true)
        let scrobbler = Scrobbler(sender: sender, store: InMemoryScrobbleStore())

        scrobbler.submit(PendingScrobble(songID: "so-1", playedAt: played))
        scrobbler.submit(PendingScrobble(songID: "so-2", playedAt: played.addingTimeInterval(60)))
        await scrobbler.flush()
        #expect(scrobbler.pending.count == 2)

        sender.setOffline(false)
        await scrobbler.flush()
        #expect(sender.calls.map(\.songID) == ["so-1", "so-2"])
        #expect(scrobbler.pending.isEmpty)
    }

    @Test func scrobblesSavedBeforeQuittingAreSentAfterRelaunch() async {
        let store = InMemoryScrobbleStore([PendingScrobble(songID: "so-9", playedAt: played)])
        let sender = FakeScrobbleSender()
        let scrobbler = Scrobbler(sender: sender, store: store)
        await scrobbler.flush()
        #expect(sender.calls.map(\.songID) == ["so-9"])
    }

    @Test func fileStoreRoundTrips() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "scrobbles-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = FileScrobbleStore(fileURL: file)
        #expect(store.load().isEmpty)
        let pending = [PendingScrobble(songID: "so-1", playedAt: played)]
        store.save(pending)
        #expect(store.load() == pending)
    }
}
