import Foundation
import Observation

/// Keeps the widgets' snapshot (`WidgetSnapshot`) in step with the engine:
/// whenever the song, its title, playing or paused, next, the favorite or the
/// cover changes, the snapshot is rewritten and the widgets are asked to
/// reload, at most once every `reloadGap` (a skip through several songs
/// reloads once at the end). A new cover is saved as a small JPEG first, and
/// the snapshot names it only once it's there, so a widget never shows the
/// last song's cover with this one's title.
@MainActor
public final class WidgetFeed {
    /// The artwork, as a JPEG small enough for a widget; `nil` if it can't be had.
    public typealias Artwork = @MainActor (String) async -> Data?

    static let reloadGap: TimeInterval = 1

    private let engine: PlaybackEngine
    private let stars: StarModel
    private let store: WidgetSnapshotStore
    private let artwork: Artwork
    private let reload: @MainActor () -> Void
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void

    private var lastWritten: WidgetSnapshot??
    /// The cover whose artwork is saved, and the one being fetched.
    private var savedCover: String?
    private var fetchingCover: String?
    private var artworkTask: Task<Void, Never>?
    private var lastReload: Date?
    private var pendingReload: Task<Void, Never>?

    public init(
        engine: PlaybackEngine, stars: StarModel, store: WidgetSnapshotStore,
        artwork: @escaping Artwork, reload: @escaping @MainActor () -> Void,
        now: @escaping @Sendable () -> Date = { .now },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.engine = engine
        self.stars = stars
        self.store = store
        self.artwork = artwork
        self.reload = reload
        self.now = now
        self.sleep = sleep
    }

    /// Starts following, and writes what's there now. Artwork left from
    /// before is dropped; the current cover is saved again.
    public func start() {
        store.writeArtwork(nil)
        observe()
        changed()
    }

    private func observe() {
        withObservationTracking {
            _ = snapshot()
        } onChange: { [weak self] in
            // Called before the change lands: act once it has.
            Task { @MainActor in
                self?.observe()
                self?.changed()
            }
        }
    }

    /// The app is quitting, and the music with it: the widgets show it paused
    /// (the queue is restored paused at the next launch).
    public func appWillTerminate() {
        guard var snapshot = snapshot() else { return }
        snapshot.isPlaying = false
        store.write(snapshot)
        reloadNow()
    }

    /// What the widgets should show now, with the saved artwork if it's this cover's.
    func snapshot() -> WidgetSnapshot? {
        guard let song = engine.queue.current?.song else { return nil }
        let cover = engine.currentCoverArtID
        return WidgetSnapshot(
            title: engine.currentTitle ?? song.title,
            subtitle: engine.currentSubtitle,
            isPlaying: engine.status.isActive,
            isLive: song.isLive,
            hasNext: engine.canGoNext,
            isFavorite: song.isLive ? nil : stars.isStarred(.song(id: song.id), fromServer: song.isStarred),
            coverArtID: cover != nil && cover == savedCover ? cover : nil
        )
    }

    private func changed() {
        let cover = engine.currentCoverArtID
        if cover != savedCover, cover != fetchingCover { fetchArtwork(cover) }
        write()
    }

    private func fetchArtwork(_ cover: String?) {
        artworkTask?.cancel()
        artworkTask = nil
        fetchingCover = cover
        guard let cover else {
            savedCover = nil
            store.writeArtwork(nil)
            return
        }
        artworkTask = Task { [weak self, artwork] in
            let jpeg = await artwork(cover)
            guard let self, !Task.isCancelled else { return }
            self.artworkTask = nil
            self.fetchingCover = nil
            // Not had: no artwork, and it's tried again on the next change.
            guard let jpeg else { return }
            self.store.writeArtwork(jpeg)
            self.savedCover = cover
            self.write()
        }
    }

    private func write() {
        let snapshot = snapshot()
        guard lastWritten != .some(snapshot) else { return }
        lastWritten = .some(snapshot)
        store.write(snapshot)
        scheduleReload()
    }

    private func scheduleReload() {
        guard pendingReload == nil else { return }
        let wait = lastReload.map { Self.reloadGap - now().timeIntervalSince($0) } ?? 0
        guard wait > 0 else {
            reloadNow()
            return
        }
        pendingReload = Task { [weak self, sleep] in
            await sleep(wait)
            self?.pendingReload = nil
            self?.reloadNow()
        }
    }

    private func reloadNow() {
        lastReload = now()
        reload()
    }

    /// Waits for the artwork and any reload in flight. For tests.
    func settle() async {
        await artworkTask?.value
        await pendingReload?.value
    }
}
