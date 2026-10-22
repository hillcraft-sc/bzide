import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct WidgetFeedTests {
    private let player = FakeAudioPlayer()
    private static let first = Song(id: "so-1", title: "Karma Police", artist: "Radiohead", coverArtID: "al-ok")
    private static let second = Song(id: "so-2", title: "Idioteque", artist: "Radiohead", coverArtID: "al-kida", isStarred: true)

    private final class Calls: @unchecked Sendable {
        var reloads = 0
        var artwork: [String] = []
        var now = Date(timeIntervalSince1970: 1_000)
        var waits: [TimeInterval] = []
    }

    private func makeEngine() -> PlaybackEngine {
        PlaybackEngine(player: player, session: FakeAudioSession(), nowPlaying: FakeNowPlaying(), urls: FakeStreamURLs(), store: InMemoryQueueStore(), scheduler: FakeScheduler(), network: FakeNetworkMonitor(), scrobbler: FakeScrobbler())
    }

    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "Widget-\(UUID().uuidString)")
    }

    private func feed(
        _ engine: PlaybackEngine, stars: StarModel = StarModel { _, _ in }, store: WidgetSnapshotStore, calls: Calls,
        artwork: @escaping @MainActor (String) -> Data? = { Data("jpeg \($0)".utf8) }
    ) -> WidgetFeed {
        WidgetFeed(
            engine: engine, stars: stars, store: store,
            artwork: { cover in
                calls.artwork.append(cover)
                return artwork(cover)
            },
            reload: { calls.reloads += 1 },
            now: { calls.now },
            sleep: { seconds in await MainActor.run { calls.waits.append(seconds); calls.now = calls.now.addingTimeInterval(seconds) } }
        )
    }

    /// Lets the feed's observation tasks run.
    private func settle(_ feed: WidgetFeed) async {
        for _ in 0..<20 { await Task.yield() }
        await feed.settle()
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func writesWhatsPlayingThenItsCover() async {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        let calls = Calls()
        let engine = makeEngine()
        engine.play(songs: [Self.first, Self.second])
        let widgets = feed(engine, store: store, calls: calls)
        widgets.start()
        // At once, without a cover: it isn't saved yet.
        #expect(store.read() == WidgetSnapshot(title: "Karma Police", subtitle: "Radiohead", isPlaying: true, hasNext: true, isFavorite: false))
        await settle(widgets)
        #expect(calls.artwork == ["al-ok"])
        #expect(store.read()?.coverArtID == "al-ok")
        #expect(store.readArtwork() == Data("jpeg al-ok".utf8))

        engine.next()
        await settle(widgets)
        let snapshot = store.read()
        #expect(snapshot?.title == "Idioteque")
        #expect(snapshot?.isFavorite == true)
        #expect(snapshot?.hasNext == false)
        #expect(snapshot?.coverArtID == "al-kida")
        #expect(store.readArtwork() == Data("jpeg al-kida".utf8))

        engine.pause()
        await settle(widgets)
        #expect(store.read()?.isPlaying == false)
        // The cover isn't fetched again for a pause.
        #expect(calls.artwork == ["al-ok", "al-kida"])
    }

    @Test func aFavoriteChangeIsShown() async {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        let stars = StarModel { _, _ in }
        let engine = makeEngine()
        engine.play(songs: [Self.first])
        let widgets = feed(engine, stars: stars, store: store, calls: Calls())
        widgets.start()
        await settle(widgets)
        #expect(store.read()?.isFavorite == false)
        _ = await stars.set(.song(id: "so-1"), starred: true, fromServer: false)
        await settle(widgets)
        #expect(store.read()?.isFavorite == true)
    }

    @Test func aStationHasNoFavoriteAndNoCoverWithoutArtwork() async {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        let station = RadioStation(id: "rs-1", name: "Night Waves", streamURL: URL(string: "https://stream.example.com/waves")!)
        let engine = makeEngine()
        engine.play(songs: [Song(station: station, stream: station.streamURL)])
        let widgets = feed(engine, store: store, calls: Calls(), artwork: { _ in nil })
        widgets.start()
        await settle(widgets)
        let snapshot = store.read()
        #expect(snapshot?.title == "Night Waves")
        #expect(snapshot?.isLive == true)
        #expect(snapshot?.isFavorite == nil)
        #expect(snapshot?.coverArtID == nil)
    }

    @Test func nothingQueuedIsNoSnapshot() async {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        store.write(WidgetSnapshot(title: "Old", isPlaying: true))
        store.writeArtwork(Data("old".utf8))
        let calls = Calls()
        let widgets = feed(makeEngine(), store: store, calls: calls)
        widgets.start()
        await settle(widgets)
        #expect(store.read() == nil)
        #expect(store.readArtwork() == nil)
        #expect(calls.reloads == 1)
    }

    @Test func reloadsAreSpacedOut() async {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        let calls = Calls()
        let engine = makeEngine()
        engine.play(songs: [Self.first, Self.second])
        let widgets = feed(engine, store: store, calls: calls, artwork: { _ in nil })
        widgets.start()
        #expect(calls.reloads == 1)
        // Several changes within the second: one more reload, once it's up.
        engine.next()
        engine.pause()
        await settle(widgets)
        #expect(calls.reloads == 2)
        #expect(calls.waits == [WidgetFeed.reloadGap])
        #expect(store.read()?.title == "Idioteque")
        #expect(store.read()?.isPlaying == false)
    }

    @Test func noFolderKeepsNothing() {
        let store = WidgetSnapshotStore(directory: nil)
        store.write(WidgetSnapshot(title: "A", isPlaying: false))
        store.writeArtwork(Data("x".utf8))
        #expect(store.read() == nil)
        #expect(store.readArtwork() == nil)
    }
}
