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
    public private(set) var repeatMode: RepeatMode
    /// What each loaded entry plays as, recorded when its item is built: the
    /// preloaded next track keeps the quality it was loaded at.
    private var loadedQualities: [QueueEntry.ID: PlaybackQuality] = [:]

    /// What the current song is playing as; `nil` before it's loaded, for a
    /// radio station, or when unknown.
    public var currentQuality: PlaybackQuality? {
        queue.current.flatMap { loadedQualities[$0.id] }
    }

    /// The order before shuffling, while shuffle is on.
    private var shuffleOrigin: [QueueEntry.ID]?

    /// Shuffle is on: up next is in shuffled order, and turning it off puts
    /// what's left back in the original order.
    public var isShuffled: Bool { shuffleOrigin != nil }

    /// What a radio station says it's playing now, when it says. Always `nil`
    /// for songs.
    public private(set) var streamTitle: String?

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
    @ObservationIgnored private let history: (any PlayRecording)?
    @ObservationIgnored private var scrobbleTracker = ScrobbleTracker()
    @ObservationIgnored private let now: @MainActor () -> Date

    /// Bumped by every play request and anything that cancels one, so a slow
    /// activation can't start the player after the user moved on.
    @ObservationIgnored private var activationRequest = 0
    /// Waiting for the audio session before starting the player. The loaded
    /// player reports "paused" meanwhile; that's expected and not shown.
    @ObservationIgnored private var isActivationPending = false

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
        history: (any PlayRecording)? = nil,
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
        self.history = history
        self.now = now

        let snapshot = Self.restore(from: store)
        let restoredQueue = snapshot?.queue ?? PlaybackQueue()
        queue = restoredQueue
        // A station has no position to come back to; it rejoins live.
        let restoredPosition = restoredQueue.current?.song.isLive == true ? 0 : snapshot?.position ?? 0
        position = restoredPosition
        lastSavedPosition = restoredPosition
        status = restoredQueue.isEmpty ? .idle : .paused
        repeatMode = snapshot?.repeatMode ?? .off
        shuffleOrigin = snapshot?.shuffleOrigin
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
    /// Replaces the queue and starts playing at `startIndex`, in order:
    /// shuffle turns off.
    public func play(songs: [Song], startIndex: Int = 0) {
        start(PlaybackQueue(songs: songs, startIndex: startIndex), shuffleOrigin: nil)
    }

    /// Plays the songs in a random order with shuffle on, so turning shuffle
    /// off carries on with the rest in their original order.
    public func playShuffled(_ songs: [Song]) {
        let original = PlaybackQueue(songs: songs)
        start(PlaybackQueue(entries: original.entries.shuffled()), shuffleOrigin: original.entries.map(\.id))
    }

    /// Turns shuffle on (shuffling up next) or off (restoring its order). The
    /// current song plays on either way. Not for a radio station.
    public func toggleShuffle() {
        defer { publishNowPlaying() }
        guard !queue.isEmpty, !isLive else { return }
        let nextBefore = preloadEntry?.id
        if let origin = shuffleOrigin {
            queue.restoreUpcoming(order: origin)
            shuffleOrigin = nil
        } else {
            shuffleOrigin = queue.entries.map(\.id)
            queue.shuffleUpcoming()
        }
        refreshUpcomingIfChanged(from: nextBefore)
        saveSnapshot()
    }

    private func start(_ newQueue: PlaybackQueue, shuffleOrigin origin: [QueueEntry.ID]?) {
        defer { publishNowPlaying() }
        cancelRecovery()
        cancelPendingActivation()
        queue = newQueue
        shuffleOrigin = newQueue.isEmpty ? nil : origin
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
        // A paused station would resume minutes behind; reload it to rejoin live.
        if !isPlayerLoaded || (isLive && !status.isActive) {
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
        cancelPendingActivation()
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
        guard let target = nextEntry else { return }
        if isPlayerLoaded, preloadEntry?.id == target.id {
            // The player already holds the next track; the resulting
            // `currentItemChanged` event advances the queue (one code path for
            // manual and automatic advance).
            player.skipToNextItem()
        } else {
            // Not preloaded: nothing loaded yet, or repeat one (which preloads nothing).
            queue.jump(to: target.id)
            reloadCurrentTrack()
        }
    }

    /// Off, then repeat all, then repeat one.
    public func cycleRepeatMode() {
        setRepeatMode(repeatMode.next)
    }

    public func setRepeatMode(_ mode: RepeatMode) {
        defer { publishNowPlaying() }
        guard mode != repeatMode else { return }
        repeatMode = mode
        refreshUpcoming()
        saveSnapshot()
    }

    public func previous() {
        defer { publishNowPlaying() }
        // A station can't be restarted, and it's always the start of its queue.
        guard !queue.isEmpty, !isLive else { return }
        cancelRecovery()
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
        } else if !hadNext {
            // The player was on the last track; give it the new next one for gapless.
            refreshUpcoming()
        }
        saveSnapshot()
    }

    /// Puts songs right after the current track without interrupting it. The
    /// track the player had buffered as next is swapped for the first of these,
    /// so the handover stays gapless.
    public func playNext(_ songs: [Song]) {
        defer { publishNowPlaying() }
        guard !songs.isEmpty else { return }
        guard !queue.isEmpty else {
            append(songs)
            return
        }
        queue.insertNext(songs)
        refreshUpcoming()
        saveSnapshot()
    }

    /// Removes everything after the current track. The current track plays on;
    /// when it ends, playback stops as at the end of any queue.
    public func clearUpNext() {
        defer { publishNowPlaying() }
        guard queue.hasNext else { return }
        queue.removeUpcoming()
        refreshUpcoming()
        saveSnapshot()
    }

    /// Takes one upcoming song out of the queue (the current one plays on). If
    /// it was the buffered next track, the new next one takes its place.
    public func removeFromQueue(_ entryID: QueueEntry.ID) {
        defer { publishNowPlaying() }
        let nextBefore = preloadEntry?.id
        guard queue.removeUpcoming(entryID) else { return }
        refreshUpcomingIfChanged(from: nextBefore)
        saveSnapshot()
    }

    /// Reorders the upcoming songs; offsets count within `queue.upNext`. The
    /// buffered next track is only swapped if a different song now comes next.
    public func moveUpcoming(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        defer { publishNowPlaying() }
        let before = queue
        let nextBefore = preloadEntry?.id
        queue.moveUpcoming(fromOffsets: offsets, toOffset: destination)
        guard queue != before else { return }
        refreshUpcomingIfChanged(from: nextBefore)
        saveSnapshot()
    }

    /// The player's volume on top of the system's, 0...1. Only for fades
    /// (the sleep timer); 1 is normal.
    public var outputVolume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    public func seek(to target: TimeInterval) {
        defer { publishNowPlaying() }
        guard !queue.isEmpty, !isLive else { return }
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
            Self.logger.notice("Interruption began while \(String(describing: self.status), privacy: .public)")
            guard status.isActive else { return }
            resumeAfterInterruption = true
            stopForSystem()
        case .interruptionEnded(let shouldResume):
            let resume = resumeAfterInterruption && shouldResume
            Self.logger.notice("Interruption ended: shouldResume \(shouldResume), was playing \(self.resumeAfterInterruption), resuming \(resume)")
            resumeAfterInterruption = false
            if resume { play() }
        case .outputDeviceLost:
            Self.logger.notice("Output device lost while \(String(describing: self.status), privacy: .public), resume pending \(self.resumeAfterInterruption)")
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
        cancelPendingActivation()
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
        cancelPendingActivation()
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

    /// The last track finished: the queue is done and is emptied, which also
    /// clears Now Playing.
    private func endQueue() {
        cancelPendingActivation()
        queue = PlaybackQueue()
        shuffleOrigin = nil
        player.setItems([], startPosition: 0)
        status = .idle
        position = 0
        duration = nil
        beginPlay()
        saveSnapshot()
    }

    /// Pauses because of something outside the user's control.
    private func stopForSystem() {
        cancelRecovery()
        cancelPendingActivation()
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
            if isActivationPending, playerStatus == .paused { return }
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
                // Play history counts by the same rule as scrobbling.
                if let song = queue.current?.song, song.id == play.songID {
                    history?.record(song, playedAt: play.startedAt)
                }
            }
            if abs(time - lastSavedPosition) >= Self.positionSaveInterval {
                saveSnapshot()
            }
        case .durationKnown(let seconds):
            guard !isLive else { return }
            duration = seconds
            scrobbleTracker.updateDuration(seconds)
        case .reachedEnd:
            if isLive {
                // Live streams don't end; the station dropped. Retry like any failure.
                Self.logger.error("Live stream ended")
                currentTrackFailed(message: "The station stopped broadcasting.")
                return
            }
            cancelRecovery()
            isPlayerLoaded = false
            if repeatMode == .one || (repeatMode == .all && queue.entries.count == 1) {
                // Nothing was preloaded; play the same track again, as a new play.
                restartCurrentTrack()
            } else if let next = nextEntry {
                // The player ran out early (the next track couldn't be loaded in
                // time, or repeat all's first track wasn't preloaded); carry on.
                queue.jump(to: next.id)
                restartCurrentTrack()
            } else {
                endQueue()
            }
        case .itemFailed(let entryID, let message):
            if entryID == queue.current?.id {
                Self.logger.error("Current item failed: \(message, privacy: .public)")
                currentTrackFailed(message: message)
            } else if entryID == preloadEntry?.id {
                Self.logger.error("Preloaded item failed: \(message, privacy: .public)")
                scheduleNextRebuild(entryID: entryID)
            }
        case .stalled(let entryID):
            guard entryID == queue.current?.id else { return }
            Self.logger.notice("Playback stalled")
            scheduleStallCheck()
        case .streamTitle(let entryID, let title):
            guard entryID == queue.current?.id, isLive else { return }
            let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            streamTitle = trimmed?.isEmpty == false ? trimmed : nil
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
        if let next = preloadEntry, let item = makeItem(for: next) {
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
        if isLive { position = 0 }
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
            guard self.isPlayerLoaded, let next = self.preloadEntry, next.id == entryID,
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
            let song = entry.song
            let live = song.isLive
            return NowPlayingInfo(
                title: currentTitle ?? song.title,
                artist: currentSubtitle,
                album: song.album,
                coverArtID: song.coverArtID,
                duration: live ? nil : duration,
                elapsed: live ? 0 : position,
                isPlaying: status == .playing,
                hasNext: nextEntry != nil,
                hasPrevious: !live && queue.hasPrevious,
                isLiveStream: live
            )
        }
        guard !hasPublishedNowPlaying || info != lastNowPlaying else { return }
        hasPublishedNowPlaying = true
        lastNowPlaying = info
        nowPlaying.update(info)
    }

    // MARK: - Helpers

    /// Activates the audio session, then starts the player once it's active.
    /// Starting the player first would make AVFoundation activate the session
    /// itself, synchronously, on the main thread.
    private func startPlayback() {
        guard isPlayerLoaded else { return }
        status = .buffering
        activationRequest += 1
        isActivationPending = true
        let request = activationRequest
        session.activate { [weak self] error in
            guard let self else { return }
            // Paused, interrupted or replaced meanwhile: this one no longer counts.
            guard request == self.activationRequest, self.isPlayerLoaded else { return }
            self.isActivationPending = false
            if let error {
                self.player.pause()
                self.status = .failed("Can't play right now: \(error.message)")
            } else {
                // The player's own status report (which may arrive at once) has the last word.
                self.player.play()
            }
            self.publishNowPlaying()
        }
    }

    private func cancelPendingActivation() {
        activationRequest += 1
        isActivationPending = false
    }

    /// Where next goes: the following entry, or with repeat all the first one
    /// after the last. Repeat one doesn't change this; next still moves on.
    private var nextEntry: QueueEntry? {
        if let following = queue.upNext.first { return following }
        guard repeatMode == .all, queue.entries.count > 1 else { return nil }
        return queue.entries.first
    }

    /// The entry the player holds after the current one, for a gapless handover.
    /// Repeat one holds nothing: the track is restarted when it ends. Neither
    /// does a station, which never ends.
    private var preloadEntry: QueueEntry? {
        repeatMode == .one || isLive ? nil : nextEntry
    }

    /// The current entry is a radio station.
    public var isLive: Bool {
        queue.current?.song.isLive == true
    }

    /// Whether next has somewhere to go (including repeat all's wrap-around).
    public var canGoNext: Bool {
        nextEntry != nil
    }

    /// What to show as the title: for a station, the song it announced, if any.
    public var currentTitle: String? {
        guard let song = queue.current?.song else { return nil }
        return song.isLive ? streamTitle ?? song.title : song.title
    }

    /// Beneath the title: the artist, or for a station its name when the title
    /// is the announced song.
    public var currentSubtitle: String? {
        guard let song = queue.current?.song else { return nil }
        guard song.isLive else { return song.artist }
        return streamTitle == nil ? nil : song.title
    }

    /// Makes the player's preloaded next track match `preloadEntry`, after
    /// anything that may have changed it.
    private func refreshUpcoming() {
        pendingNextRebuild?.cancel()
        pendingNextRebuild = nil
        nextRebuildAttempts = 0
        guard isPlayerLoaded else { return }
        if let next = preloadEntry, let item = makeItem(for: next) {
            player.replaceUpcoming(with: item)
        } else {
            player.removeUpcoming()
        }
    }

    /// Like `refreshUpcoming`, but leaves the player alone when the same entry
    /// still comes next, so a reorder further down never touches the buffer.
    private func refreshUpcomingIfChanged(from previousNext: QueueEntry.ID?) {
        guard preloadEntry?.id != previousNext else { return }
        refreshUpcoming()
    }

    /// Plays the current entry from the start: a new play.
    private func restartCurrentTrack() {
        resetForNewTrack()
        loadPlayer(startPosition: 0)
        startPlayback()
        saveSnapshot()
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
        // A station always starts at "now".
        let startPosition = current.song.isLive ? 0 : startPosition
        guard let currentItem = makeItem(for: current) else {
            isPlayerLoaded = false
            status = .failed("Couldn't build a stream URL for this track.")
            return
        }
        var items = [currentItem]
        if let next = preloadEntry, let nextItem = makeItem(for: next) {
            items.append(nextItem)
        }
        player.setItems(items, startPosition: startPosition)
        isPlayerLoaded = true
        if case .failed = status { status = .paused }
    }

    private func makeItem(for entry: QueueEntry) -> PlayerItem? {
        do {
            if let live = entry.song.liveStreamURL {
                return PlayerItem(entryID: entry.id, url: live, isLive: true)
            }
            let item = PlayerItem(entryID: entry.id, url: try urls.streamURL(for: entry.song))
            recordQuality(of: entry)
            return item
        } catch {
            Self.logger.error("No stream URL for a queue entry: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Keeps the quality of what the player holds: the current entry and the
    /// one preloaded after it.
    private func recordQuality(of entry: QueueEntry) {
        let kept: Set<QueueEntry.ID> = [queue.current?.id, preloadEntry?.id, entry.id].reduce(into: []) { set, id in
            if let id { set.insert(id) }
        }
        loadedQualities = loadedQualities.filter { kept.contains($0.key) }
        loadedQualities[entry.id] = urls.quality(for: entry.song)
    }

    private func resetForNewTrack() {
        position = 0
        lastSavedPosition = 0
        streamTitle = nil
        duration = metadataDuration
        beginPlay()
    }

    /// Starts counting a new play of the current track from the current position.
    private func beginPlay() {
        // Radio is never scrobbled or added to history.
        guard let song = queue.current?.song, !song.isLive else {
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
            try store.save(QueueSnapshot(queue: queue, position: position, repeatMode: repeatMode, shuffleOrigin: shuffleOrigin))
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
