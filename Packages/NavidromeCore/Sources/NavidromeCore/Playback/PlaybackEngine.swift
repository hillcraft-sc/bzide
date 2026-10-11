import Foundation
import Observation
import os

public enum PlaybackStatus: Sendable, Equatable {
    /// Nothing queued.
    case idle
    case paused
    case buffering
    case playing
    /// The current track failed while playing; a retry is scheduled.
    case reconnecting
    /// The current track couldn't be played, and retries (if any) ran out.
    /// Play retries it.
    case failed(String)

    /// Playing or about to be: the user's intent is "music on".
    public var isActive: Bool {
        self == .playing || self == .buffering || self == .reconnecting
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
    @ObservationIgnored private let nowPlaying: any NowPlayingControlling
    /// Last info sent, so unchanged state isn't re-sent on every event.
    @ObservationIgnored private var lastNowPlaying: NowPlayingInfo?
    /// The first update is always sent, even when it's `nil`, so anything left
    /// over from a previous run is cleared.
    @ObservationIgnored private var hasPublishedNowPlaying = false
    @ObservationIgnored private let urls: any StreamURLProviding
    @ObservationIgnored private let store: any QueueStore
    /// Whether the player holds the current track. False after launch until play,
    /// so restoring a queue never touches the network or makes sound.
    @ObservationIgnored private var isPlayerLoaded = false
    @ObservationIgnored private var lastSavedPosition: TimeInterval = 0
    /// Set when an interruption stopped active playback; cleared by any user
    /// play/pause so the user's latest choice wins over the system's resume hint.
    @ObservationIgnored private var resumeAfterInterruption = false
    /// Between "media services lost" and "reset": the player is dead, and what
    /// it reports is noise.
    @ObservationIgnored private var isAwaitingMediaServicesReset = false
    /// Music was on when media services went down (or the user pressed play
    /// while they were down); resume once they're back.
    @ObservationIgnored private var resumeAfterMediaServicesReset = false

    @ObservationIgnored private let scheduler: any Scheduling
    @ObservationIgnored private let network: any NetworkMonitoring
    @ObservationIgnored private let recoveryPolicy: RecoveryPolicy
    /// Retries used for the current track since it last played successfully.
    @ObservationIgnored private var recoveryAttempts = 0
    @ObservationIgnored private var pendingRecovery: ScheduledAction?
    /// Where the last retry resumed from, to measure playback since.
    @ObservationIgnored private var lastRetryPosition: TimeInterval = 0
    @ObservationIgnored private var stallCheck: ScheduledAction?
    /// Retries used to rebuild the preloaded next track.
    @ObservationIgnored private var nextRebuildAttempts = 0
    @ObservationIgnored private var pendingNextRebuild: ScheduledAction?
    /// Retries ran out while the user was listening; retry when the network returns.
    @ObservationIgnored private var retryWhenNetworkReturns = false

    @ObservationIgnored private let scrobbler: any ScrobbleSubmitting
    @ObservationIgnored private var scrobbleTracker = ScrobbleTracker()
    @ObservationIgnored private let now: @MainActor () -> Date

    /// How often, in seconds of playback, the position is saved while playing.
    static let positionSaveInterval: TimeInterval = 10

    private static let logger = Logger(subsystem: "MusicApp", category: "PlaybackEngine")

    public init(
        player: any AudioPlayer,
        session: any AudioSessionControlling,
        nowPlaying: any NowPlayingControlling,
        urls: any StreamURLProviding,
        store: any QueueStore,
        scheduler: any Scheduling,
        network: any NetworkMonitoring,
        scrobbler: any ScrobbleSubmitting,
        recoveryPolicy: RecoveryPolicy = RecoveryPolicy(),
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.player = player
        self.session = session
        self.nowPlaying = nowPlaying
        self.urls = urls
        self.store = store
        self.scheduler = scheduler
        self.network = network
        self.recoveryPolicy = recoveryPolicy
        self.scrobbler = scrobbler
        self.now = now

        let snapshot = Self.restore(from: store)
        let restoredQueue = snapshot?.queue ?? PlaybackQueue()
        queue = restoredQueue
        position = snapshot?.position ?? 0
        lastSavedPosition = snapshot?.position ?? 0
        status = restoredQueue.isEmpty ? .idle : .paused
        duration = restoredQueue.current?.song.duration.map(TimeInterval.init)

        player.onEvent = { [weak self] event in self?.handle(event) }
        session.onEvent = { [weak self] event in self?.handle(event) }
        nowPlaying.onCommand = { [weak self] command in self?.handle(command) }
        network.onNetworkAvailable = { [weak self] in self?.networkBecameAvailable() }
        beginPlay()
        publishNowPlaying()
    }

    // MARK: - Commands

    /// Replaces the queue and starts playing at `startIndex`.
    public func play(songs: [Song], startIndex: Int = 0) {
        defer { publishNowPlaying() }
        cancelRecovery()
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

    /// Shuffles the songs once and plays them as an ordinary queue.
    public func playShuffled(_ songs: [Song]) {
        play(songs: songs.shuffled())
    }

    public func play() {
        defer { publishNowPlaying() }
        cancelRecovery()
        guard !queue.isEmpty else { return }
        resumeAfterInterruption = false
        if isAwaitingMediaServicesReset {
            // Nothing can play until the system's audio is back; start then.
            resumeAfterMediaServicesReset = true
            status = .reconnecting
            return
        }
        if !isPlayerLoaded {
            loadPlayer(startPosition: position)
        }
        startPlayback()
    }

    public func pause() {
        defer { publishNowPlaying() }
        cancelRecovery()
        guard !queue.isEmpty else { return }
        resumeAfterInterruption = false
        resumeAfterMediaServicesReset = false
        player.pause()
        status = .paused
        saveSnapshot()
    }

    public func togglePlayPause() {
        status.isActive ? pause() : play()
    }

    public func next() {
        defer { publishNowPlaying() }
        cancelRecovery()
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
        defer { publishNowPlaying() }
        cancelRecovery()
        guard !queue.isEmpty else { return }
        switch PreviousAction.decide(elapsed: position, hasPrevious: queue.hasPrevious) {
        case .restartCurrent:
            seek(to: 0)
            // Listening to it again is a new play, with its own scrobble.
            beginPlay()
        case .goToPrevious:
            queue.goBack()
            reloadCurrentTrack()
        }
    }

    public func jump(to entryID: QueueEntry.ID) {
        defer { publishNowPlaying() }
        cancelRecovery()
        guard entryID != queue.current?.id, queue.jump(to: entryID) else { return }
        reloadCurrentTrack()
    }

    /// Adds songs to the end of the queue without interrupting playback.
    public func append(_ songs: [Song]) {
        defer { publishNowPlaying() }
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
        defer { publishNowPlaying() }
        guard !queue.isEmpty else { return }
        var clamped = max(target, 0)
        if let duration { clamped = min(clamped, duration) }
        position = clamped
        scrobbleTracker.seeked(to: clamped)
        if isPlayerLoaded {
            player.seek(to: clamped)
        }
        saveSnapshot()
    }

    // MARK: - Remote commands

    private func handle(_ command: RemoteCommand) {
        switch command {
        case .play: play()
        case .pause: pause()
        case .togglePlayPause: togglePlayPause()
        case .next: next()
        case .previous: previous()
        case .seek(let position): seek(to: position)
        }
    }

    // MARK: - Audio session events

    private func handle(_ event: AudioSessionEvent) {
        defer { publishNowPlaying() }
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
        case .mediaServicesLost:
            mediaServicesLost()
        case .mediaServicesReset:
            mediaServicesReset()
        }
    }

    /// The system's audio services went down; the player and its tracks fail
    /// with them. Stop and wait for the reset, remembering if music was on.
    private func mediaServicesLost() {
        Self.logger.notice("Media services were lost")
        isAwaitingMediaServicesReset = true
        if status.isActive {
            resumeAfterMediaServicesReset = true
            status = .paused
        }
        cancelRecovery()
        saveSnapshot()
    }

    /// The system's audio services restarted and took the player with them.
    /// Rebuild it, and if music was on, carry on where it was: the user didn't
    /// stop it, and the output route is unchanged.
    private func mediaServicesReset() {
        Self.logger.notice("Media services were reset")
        let wasActive = status.isActive || resumeAfterMediaServicesReset
        isAwaitingMediaServicesReset = false
        resumeAfterMediaServicesReset = false
        cancelRecovery()
        player.rebuild()
        isPlayerLoaded = false
        if wasActive { status = .paused }
        // The system's copy of Now Playing went with the reset; send it all again.
        hasPublishedNowPlaying = false
        saveSnapshot()
        // `play()` reloads at the saved position and sets the session up again.
        // It's the same listen continuing, so the scrobble count carries on.
        if wasActive { play() }
    }

    /// Pauses because of something outside the user's control.
    private func stopForSystem() {
        cancelRecovery()
        player.pause()
        status = .paused
        saveSnapshot()
    }

    // MARK: - Player events

    private func handle(_ event: PlayerEvent) {
        guard !isAwaitingMediaServicesReset else { return }
        defer {
            // Time ticks are left to the system's own extrapolation.
            if case .timeChanged = event {} else { publishNowPlaying() }
        }
        switch event {
        case .currentItemChanged(let entryID):
            currentItemChanged(to: entryID)
        case .statusChanged(let playerStatus):
            // A failure stays visible until the user acts on it, and while
            // reconnecting the old player's reports are stale.
            if case .failed = status { return }
            if status == .reconnecting { return }
            switch playerStatus {
            case .paused: status = .paused
            case .buffering: status = .buffering
            case .playing:
                status = .playing
                playbackSucceeded()
                if scrobbleTracker.announce(), let songID = scrobbleTracker.play?.songID {
                    scrobbler.nowPlaying(songID: songID)
                }
            }
        case .timeChanged(let time):
            position = time
            if recoveryAttempts > 0, time - lastRetryPosition >= recoveryPolicy.playbackNeededToReset {
                recoveryAttempts = 0
            }
            // Announced here as well as on `.playing`: when one track flows into the
            // next, the player never stops playing, so no `.playing` event comes.
            if status == .playing, scrobbleTracker.announce(), let songID = scrobbleTracker.play?.songID {
                scrobbler.nowPlaying(songID: songID)
            }
            if scrobbleTracker.observe(time: time), let play = scrobbleTracker.play {
                scrobbler.submit(PendingScrobble(songID: play.songID, playedAt: play.startedAt))
            }
            if abs(time - lastSavedPosition) >= Self.positionSaveInterval {
                saveSnapshot()
            }
        case .durationKnown(let seconds):
            duration = seconds
            scrobbleTracker.updateDuration(seconds)
        case .reachedEnd:
            // Stay on the last track, rewound, so play starts it again.
            cancelRecovery()
            isPlayerLoaded = false
            status = .paused
            position = 0
            beginPlay()
            saveSnapshot()
        case .itemFailed(let entryID, let message):
            if entryID == queue.current?.id {
                Self.logger.error("Current item failed: \(message, privacy: .public)")
                currentTrackFailed(message: message)
            } else if entryID == queue.upNext.first?.id {
                Self.logger.error("Preloaded item failed: \(message, privacy: .public)")
                scheduleNextRebuild(entryID: entryID)
            }
        case .stalled(let entryID):
            guard entryID == queue.current?.id else { return }
            Self.logger.notice("Playback stalled")
            scheduleStallCheck()
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
        // A new track: its own recovery budget, and the old next-track rebuild is moot.
        cancelRecovery()
        if let next = queue.upNext.first, let item = makeItem(for: next) {
            player.append(item)
        }
        saveSnapshot()
    }

    // MARK: - Recovery

    private func currentTrackFailed(message: String) {
        stallCheck?.cancel()
        stallCheck = nil
        isPlayerLoaded = false
        guard status.isActive else {
            // Nobody is listening; show it and let play retry.
            status = .failed(message)
            saveSnapshot()
            return
        }
        guard recoveryAttempts < recoveryPolicy.retryDelays.count else {
            Self.logger.error("Giving up after \(self.recoveryAttempts) retries")
            status = .failed(message)
            retryWhenNetworkReturns = true
            saveSnapshot()
            return
        }
        status = .reconnecting
        let delay = recoveryPolicy.retryDelays[recoveryAttempts]
        recoveryAttempts += 1
        pendingRecovery?.cancel()
        pendingRecovery = scheduler.schedule(after: delay) { [weak self] in
            self?.retryCurrentTrack()
        }
        saveSnapshot()
    }

    /// Reloads the current track with a freshly signed URL at the last known position.
    private func retryCurrentTrack() {
        defer { publishNowPlaying() }
        pendingRecovery = nil
        lastRetryPosition = position
        loadPlayer(startPosition: position)
        startPlayback()
    }

    /// A stalled player usually recovers by itself; reload only if it doesn't.
    private func scheduleStallCheck() {
        guard status.isActive, stallCheck == nil else { return }
        stallCheck = scheduler.schedule(after: recoveryPolicy.stallGracePeriod) { [weak self] in
            guard let self else { return }
            self.stallCheck = nil
            guard self.status != .playing else { return }
            self.currentTrackFailed(message: "Playback stalled")
            self.publishNowPlaying()
        }
    }

    private func scheduleNextRebuild(entryID: QueueEntry.ID) {
        guard pendingNextRebuild == nil, nextRebuildAttempts < recoveryPolicy.retryDelays.count else { return }
        let delay = recoveryPolicy.retryDelays[nextRebuildAttempts]
        nextRebuildAttempts += 1
        pendingNextRebuild = scheduler.schedule(after: delay) { [weak self] in
            guard let self else { return }
            self.pendingNextRebuild = nil
            // Only if that entry is still next and the player is still running.
            guard self.isPlayerLoaded, let next = self.queue.upNext.first, next.id == entryID,
                  let item = self.makeItem(for: next) else { return }
            self.player.replaceUpcoming(with: item)
        }
    }

    private func networkBecameAvailable() {
        guard !isAwaitingMediaServicesReset else { return }
        defer { publishNowPlaying() }
        if status == .reconnecting {
            pendingRecovery?.cancel()
            retryCurrentTrack()
        } else if case .failed = status, retryWhenNetworkReturns {
            recoveryAttempts = 0
            retryWhenNetworkReturns = false
            retryCurrentTrack()
        }
    }

    /// The retry budget is not reset here; that waits for sustained playback
    /// (see `RecoveryPolicy.playbackNeededToReset`).
    private func playbackSucceeded() {
        retryWhenNetworkReturns = false
        stallCheck?.cancel()
        stallCheck = nil
    }

    /// Called whenever the user (or a track change) takes over from recovery.
    private func cancelRecovery() {
        pendingRecovery?.cancel()
        pendingRecovery = nil
        stallCheck?.cancel()
        stallCheck = nil
        pendingNextRebuild?.cancel()
        pendingNextRebuild = nil
        recoveryAttempts = 0
        nextRebuildAttempts = 0
        retryWhenNetworkReturns = false
    }

    // MARK: - Now Playing

    private func publishNowPlaying() {
        let info = queue.current.map { entry in
            NowPlayingInfo(
                title: entry.song.title,
                artist: entry.song.artist,
                album: entry.song.album,
                coverArtID: entry.song.coverArtID,
                duration: duration,
                elapsed: position,
                isPlaying: status == .playing,
                hasNext: queue.hasNext,
                hasPrevious: queue.hasPrevious
            )
        }
        guard !hasPublishedNowPlaying || info != lastNowPlaying else { return }
        hasPublishedNowPlaying = true
        lastNowPlaying = info
        nowPlaying.update(info)
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
        beginPlay()
    }

    /// Starts counting a new play of the current track from the current position.
    private func beginPlay() {
        guard let song = queue.current?.song else {
            scrobbleTracker.end()
            return
        }
        scrobbleTracker.begin(songID: song.id, duration: duration, position: position, at: now())
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
