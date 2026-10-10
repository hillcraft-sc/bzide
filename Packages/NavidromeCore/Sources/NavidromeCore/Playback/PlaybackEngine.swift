import Foundation
import Observation
import os

public enum PlaybackStatus: Sendable, Equatable {
    /// Nothing queued.
    case idle
    case paused
    case buffering
    case playing
    /// The current track couldn't be played. Play retries it.
    case failed(String)

    /// Playing or about to be: the user's intent is "music on".
    public var isActive: Bool {
        self == .playing || self == .buffering
    }
}

/// The single owner of queue and playback state. The UI observes it and calls its
/// methods; nothing else changes playback. Rules are in docs/BEHAVIOR.md.
///
/// The player always holds the current track and the one after it, so the next
/// track is buffered before the current one ends (gapless).
@MainActor
@Observable
public final class PlaybackEngine {
    public private(set) var queue: PlaybackQueue
    public private(set) var status: PlaybackStatus
    /// Seconds into the current track.
    public private(set) var position: TimeInterval
    /// Seconds. From the server's metadata until the player knows better.
    public private(set) var duration: TimeInterval?

    @ObservationIgnored private let player: any AudioPlayer
    @ObservationIgnored private let session: any AudioSessionControlling
    @ObservationIgnored private let urls: any StreamURLProviding
    @ObservationIgnored private let store: any QueueStore
    /// Whether the player holds the current track. False after launch until play,
    /// so restoring a queue never touches the network or makes sound.
    @ObservationIgnored private var isPlayerLoaded = false
    @ObservationIgnored private var lastSavedPosition: TimeInterval = 0
    /// Set when an interruption stopped active playback; cleared by any user
    /// play/pause so the user's latest choice wins over the system's resume hint.
    @ObservationIgnored private var resumeAfterInterruption = false

    /// How often, in seconds of playback, the position is saved while playing.
    static let positionSaveInterval: TimeInterval = 10

    private static let logger = Logger(subsystem: "MusicApp", category: "PlaybackEngine")

    public init(
        player: any AudioPlayer,
        session: any AudioSessionControlling,
        urls: any StreamURLProviding,
        store: any QueueStore
    ) {
        self.player = player
        self.session = session
        self.urls = urls
        self.store = store

        let snapshot = Self.restore(from: store)
        let restoredQueue = snapshot?.queue ?? PlaybackQueue()
        queue = restoredQueue
        position = snapshot?.position ?? 0
        lastSavedPosition = snapshot?.position ?? 0
        status = restoredQueue.isEmpty ? .idle : .paused
        duration = restoredQueue.current?.song.duration.map(TimeInterval.init)

        player.onEvent = { [weak self] event in self?.handle(event) }
        session.onEvent = { [weak self] event in self?.handle(event) }
    }

    // MARK: - Commands

    /// Replaces the queue and starts playing at `startIndex`.
    public func play(songs: [Song], startIndex: Int = 0) {
        queue = PlaybackQueue(songs: songs, startIndex: startIndex)
        resetForNewTrack()
        saveSnapshot()
        guard !queue.isEmpty else {
            isPlayerLoaded = false
            player.setItems([], startPosition: 0)
            status = .idle
            return
        }
        loadPlayer(startPosition: 0)
        startPlayback()
    }

    public func play() {
        guard !queue.isEmpty else { return }
        resumeAfterInterruption = false
        if !isPlayerLoaded {
            loadPlayer(startPosition: position)
        }
        startPlayback()
    }

    public func pause() {
        guard !queue.isEmpty else { return }
        resumeAfterInterruption = false
        player.pause()
        status = .paused
        saveSnapshot()
    }

    public func togglePlayPause() {
        status.isActive ? pause() : play()
    }

    public func next() {
        guard queue.hasNext else { return }
        if isPlayerLoaded {
            // The player already holds the next track; the resulting
            // `currentItemChanged` event advances the queue (one code path for
            // manual and automatic advance).
            player.skipToNextItem()
        } else {
            queue.advance()
            resetForNewTrack()
            saveSnapshot()
        }
    }

    public func previous() {
        guard !queue.isEmpty else { return }
        switch PreviousAction.decide(elapsed: position, hasPrevious: queue.hasPrevious) {
        case .restartCurrent:
            seek(to: 0)
        case .goToPrevious:
            queue.goBack()
            reloadCurrentTrack()
        }
    }

    public func jump(to entryID: QueueEntry.ID) {
        guard entryID != queue.current?.id, queue.jump(to: entryID) else { return }
        reloadCurrentTrack()
    }

    /// Adds songs to the end of the queue without interrupting playback.
    public func append(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        let wasEmpty = queue.isEmpty
        let hadNext = queue.hasNext
        queue.append(songs)
        if wasEmpty {
            resetForNewTrack()
            status = .paused
        } else if isPlayerLoaded, !hadNext, let next = queue.upNext.first, let item = makeItem(for: next) {
            // The player was on the last track; give it the new next one for gapless.
            player.append(item)
        }
        saveSnapshot()
    }

    public func seek(to target: TimeInterval) {
        guard !queue.isEmpty else { return }
        var clamped = max(target, 0)
        if let duration { clamped = min(clamped, duration) }
        position = clamped
        if isPlayerLoaded {
            player.seek(to: clamped)
        }
        saveSnapshot()
    }

    // MARK: - Audio session events

    private func handle(_ event: AudioSessionEvent) {
        switch event {
        case .interruptionBegan:
            guard status.isActive else { return }
            resumeAfterInterruption = true
            stopForSystem()
        case .interruptionEnded(let shouldResume):
            let resume = resumeAfterInterruption && shouldResume
            resumeAfterInterruption = false
            if resume { play() }
        case .outputDeviceLost:
            // Never fall back to the speaker on our own; the user presses play.
            guard status.isActive else { return }
            resumeAfterInterruption = false
            stopForSystem()
        }
    }

    /// Pauses because of something outside the user's control.
    private func stopForSystem() {
        player.pause()
        status = .paused
        saveSnapshot()
    }

    // MARK: - Player events

    private func handle(_ event: PlayerEvent) {
        switch event {
        case .currentItemChanged(let entryID):
            currentItemChanged(to: entryID)
        case .statusChanged(let playerStatus):
            // A failure stays visible until the user acts on it.
            if case .failed = status { return }
            switch playerStatus {
            case .paused: status = .paused
            case .buffering: status = .buffering
            case .playing: status = .playing
            }
        case .timeChanged(let time):
            position = time
            if abs(time - lastSavedPosition) >= Self.positionSaveInterval {
                saveSnapshot()
            }
        case .durationKnown(let seconds):
            duration = seconds
        case .reachedEnd:
            // Stay on the last track, rewound, so play starts it again.
            isPlayerLoaded = false
            status = .paused
            position = 0
            saveSnapshot()
        case .itemFailed(let entryID, let message):
            guard entryID == queue.current?.id else {
                Self.logger.error("Preloaded item failed: \(message, privacy: .public)")
                return
            }
            Self.logger.error("Current item failed: \(message, privacy: .public)")
            isPlayerLoaded = false
            status = .failed(message)
            saveSnapshot()
        case .stalled:
            // Recovery is handled in a later step; for now the player's own
            // buffering status is what the UI shows.
            Self.logger.notice("Playback stalled")
        }
    }

    private func currentItemChanged(to entryID: QueueEntry.ID?) {
        guard let entryID, entryID != queue.current?.id else { return }
        if queue.upNext.first?.id == entryID {
            queue.advance()
        } else if !queue.jump(to: entryID) {
            Self.logger.error("Player moved to an item that isn't in the queue")
            return
        }
        resetForNewTrack()
        if let next = queue.upNext.first, let item = makeItem(for: next) {
            player.append(item)
        }
        saveSnapshot()
    }

    // MARK: - Helpers

    private func startPlayback() {
        guard isPlayerLoaded else { return }
        do {
            try session.activate()
        } catch {
            player.pause()
            status = .failed("Can't play right now: \(error.message)")
            return
        }
        // Set before calling the player, so its own status report (which may arrive
        // immediately) has the last word.
        status = .buffering
        player.play()
    }

    /// After the current entry changed by user action: load it from the start,
    /// keeping playing or paused as it was.
    private func reloadCurrentTrack() {
        let wasActive = status.isActive
        resetForNewTrack()
        if isPlayerLoaded || wasActive {
            loadPlayer(startPosition: 0)
            if wasActive { startPlayback() }
        }
        saveSnapshot()
    }

    /// Loads the current track and the one after it.
    private func loadPlayer(startPosition: TimeInterval) {
        guard let current = queue.current else { return }
        guard let currentItem = makeItem(for: current) else {
            isPlayerLoaded = false
            status = .failed("Couldn't build a stream URL for this track.")
            return
        }
        var items = [currentItem]
        if let next = queue.upNext.first, let nextItem = makeItem(for: next) {
            items.append(nextItem)
        }
        player.setItems(items, startPosition: startPosition)
        isPlayerLoaded = true
        if case .failed = status { status = .paused }
    }

    private func makeItem(for entry: QueueEntry) -> PlayerItem? {
        do {
            return PlayerItem(entryID: entry.id, url: try urls.streamURL(for: entry.song))
        } catch {
            Self.logger.error("No stream URL for a queue entry: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func resetForNewTrack() {
        position = 0
        lastSavedPosition = 0
        duration = metadataDuration
    }

    private var metadataDuration: TimeInterval? {
        queue.current?.song.duration.map(TimeInterval.init)
    }

    private func saveSnapshot() {
        do {
            try store.save(QueueSnapshot(queue: queue, position: position))
            lastSavedPosition = position
        } catch {
            // Losing a save is better than interrupting playback; the next save retries.
            Self.logger.error("Couldn't save the queue: \(String(describing: error), privacy: .public)")
        }
    }

    private static func restore(from store: any QueueStore) -> QueueSnapshot? {
        do {
            return try store.load()
        } catch {
            logger.error("Couldn't restore the saved queue, starting empty: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
