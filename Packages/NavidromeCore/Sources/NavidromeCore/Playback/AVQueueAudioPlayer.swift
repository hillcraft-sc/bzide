import AVFoundation

/// `AudioPlayer` backed by `AVQueuePlayer`, which plays its items back to back
/// without gaps once the next one is buffered.
///
/// Only verifiable on a device or the iOS Simulator with real audio; the engine's
/// logic is tested against a fake instead. Lives for the app's lifetime.
@MainActor
public final class AVQueueAudioPlayer: AudioPlayer {
    public var onEvent: (@MainActor (PlayerEvent) -> Void)?

    private let player = AVQueuePlayer()
    private var entryIDs: [ObjectIdentifier: QueueEntry.ID] = [:]
    private var itemObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var playerObservations: [NSKeyValueObservation] = []
    private var notificationTokens: [any NSObjectProtocol] = []
    private var timeObserver: Any?
    /// A start position for an item that wasn't ready to seek yet.
    private var pendingSeek: (item: ObjectIdentifier, position: TimeInterval)?

    public init() {
        observePlayer()
        observeItemNotifications()
    }

    // MARK: - AudioPlayer

    public func setItems(_ items: [PlayerItem], startPosition: TimeInterval) {
        player.removeAllItems()
        forgetItems(except: [])
        pendingSeek = nil
        for item in items {
            enqueue(item)
        }
        if startPosition > 0, let first = player.items().first {
            seek(first, to: startPosition)
        }
    }

    public func append(_ item: PlayerItem) {
        enqueue(item)
    }

    public func replaceUpcoming(with item: PlayerItem) {
        for upcoming in player.items().dropFirst() {
            player.remove(upcoming)
        }
        forgetItems(except: player.items())
        enqueue(item)
    }

    public func skipToNextItem() {
        player.advanceToNextItem()
    }

    public func play() {
        player.play()
    }

    public func pause() {
        player.pause()
    }

    public func seek(to position: TimeInterval) {
        guard let current = player.currentItem else { return }
        seek(current, to: position)
    }

    // MARK: - Items

    private func enqueue(_ item: PlayerItem) {
        let avItem = AVPlayerItem(url: item.url)
        let key = ObjectIdentifier(avItem)
        entryIDs[key] = item.entryID
        itemObservations[key] = avItem.observe(\.status, options: [.new]) { [weak self] avItem, _ in
            Task { @MainActor in self?.itemStatusChanged(avItem) }
        }
        player.insert(avItem, after: nil)
    }

    /// Seeks now if the item is ready, otherwise once it becomes ready.
    private func seek(_ item: AVPlayerItem, to position: TimeInterval) {
        guard item.status == .readyToPlay else {
            pendingSeek = (ObjectIdentifier(item), position)
            return
        }
        item.seek(to: CMTime(seconds: position, preferredTimescale: 600), completionHandler: nil)
    }

    private func itemStatusChanged(_ item: AVPlayerItem) {
        let key = ObjectIdentifier(item)
        guard let entryID = entryIDs[key] else { return }
        switch item.status {
        case .readyToPlay:
            if let pending = pendingSeek, pending.item == key {
                pendingSeek = nil
                seek(item, to: pending.position)
            }
            if item === player.currentItem {
                reportDuration(of: item)
            }
        case .failed:
            let message = item.error?.localizedDescription ?? "Unknown playback error"
            onEvent?(.itemFailed(entryID, message: message))
        default:
            break
        }
    }

    private func reportDuration(of item: AVPlayerItem) {
        let seconds = item.duration.seconds
        if seconds.isFinite, seconds > 0 {
            onEvent?(.durationKnown(seconds))
        }
    }

    /// Drops bookkeeping for items the player no longer holds.
    private func forgetItems(except kept: [AVPlayerItem]) {
        let keep = Set(kept.map(ObjectIdentifier.init))
        for key in entryIDs.keys where !keep.contains(key) {
            entryIDs[key] = nil
            itemObservations[key]?.invalidate()
            itemObservations[key] = nil
        }
    }

    // MARK: - Player observation

    private func observePlayer() {
        playerObservations.append(player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.currentItemChanged() }
        })
        playerObservations.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.timeControlStatusChanged() }
        })
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.player.currentItem != nil, time.seconds.isFinite else { return }
                self.onEvent?(.timeChanged(time.seconds))
            }
        }
    }

    private func currentItemChanged() {
        let current = player.currentItem
        forgetItems(except: player.items())
        onEvent?(.currentItemChanged(current.flatMap { entryIDs[ObjectIdentifier($0)] }))
        if let current, current.status == .readyToPlay {
            reportDuration(of: current)
        }
    }

    private func timeControlStatusChanged() {
        switch player.timeControlStatus {
        case .paused: onEvent?(.statusChanged(.paused))
        case .waitingToPlayAtSpecifiedRate: onEvent?(.statusChanged(.buffering))
        case .playing: onEvent?(.statusChanged(.playing))
        @unknown default: break
        }
    }

    private func observeItemNotifications() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            MainActor.assumeIsolated { self?.itemDidPlayToEnd(item) }
        })
        notificationTokens.append(center.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            let message = error?.localizedDescription ?? "Playback stopped unexpectedly"
            MainActor.assumeIsolated { self?.itemFailed(item, message: message) }
        })
        notificationTokens.append(center.addObserver(
            forName: AVPlayerItem.playbackStalledNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            MainActor.assumeIsolated { self?.itemStalled(item) }
        })
    }

    private func itemDidPlayToEnd(_ item: AVPlayerItem?) {
        // Only the last loaded item ending means the queue ran out; earlier ones
        // just hand over to the next item.
        guard let item, entryIDs[ObjectIdentifier(item)] != nil, player.items().last === item else { return }
        onEvent?(.reachedEnd)
    }

    private func itemFailed(_ item: AVPlayerItem?, message: String) {
        guard let item, let entryID = entryIDs[ObjectIdentifier(item)] else { return }
        onEvent?(.itemFailed(entryID, message: message))
    }

    private func itemStalled(_ item: AVPlayerItem?) {
        guard let item, let entryID = entryIDs[ObjectIdentifier(item)] else { return }
        onEvent?(.stalled(entryID))
    }
}
