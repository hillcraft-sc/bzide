import AVFoundation

/// `AudioPlayer` backed by `AVQueuePlayer`, which plays its items back to back
/// without gaps once the next one is buffered.
///
/// Only verifiable on a device or the iOS Simulator with real audio; the engine's
/// logic is tested against a fake instead. Lives for the app's lifetime.
@MainActor
public final class AVQueueAudioPlayer: AudioPlayer {
    public var onEvent: (@MainActor (PlayerEvent) -> Void)?

    /// Replaced by `rebuild()` after the system's audio services reset.
    private var player = AVQueuePlayer()
    private var entryIDs: [ObjectIdentifier: QueueEntry.ID] = [:]
    private var itemObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var playerObservations: [NSKeyValueObservation] = []
    private var notificationTokens: [any NSObjectProtocol] = []
    private var timeObserver: Any?
    /// A start position for an item that wasn't ready to seek yet.
    private var pendingSeek: (item: ObjectIdentifier, position: TimeInterval)?
    /// Live items' metadata outputs, to tell whose stream announced a title.
    private var metadataOutputs: [ObjectIdentifier: (output: AVPlayerItemMetadataOutput, entryID: QueueEntry.ID)] = [:]
    private var titleReader: StreamTitleReader?

    /// Live levels of what's playing, while `isMetering` is on.
    public let levelMeter = AudioLevelMeter()

    /// Whether `levelMeter` measures. Every item is tapped when it's loaded,
    /// before it plays, and the tap stays: adding or removing a tap on a playing
    /// item makes AVFoundation rebuild its audio chain, which is heard as a
    /// skip. So this only switches measuring on and off.
    public var isMetering: Bool {
        get { levelMeter.isMeasuring }
        set { levelMeter.isMeasuring = newValue }
    }

    public init() {
        observePlayer()
        observeItemNotifications()
        titleReader = StreamTitleReader { [weak self] outputKey, title in
            Task { @MainActor in self?.streamAnnounced(title, by: outputKey) }
        }
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
        removeUpcoming()
        enqueue(item)
    }

    public func removeUpcoming() {
        for upcoming in player.items().dropFirst() {
            player.remove(upcoming)
        }
        forgetItems(except: player.items())
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

    public func rebuild() {
        // Stop listening first, so tearing down the old player reports nothing.
        stopObservingPlayer()
        player.pause()
        player.removeAllItems()
        forgetItems(except: [])
        pendingSeek = nil
        player = AVQueuePlayer()
        observePlayer()
    }

    // MARK: - Items

    private func enqueue(_ item: PlayerItem) {
        let avItem = AVPlayerItem(url: item.url)
        let key = ObjectIdentifier(avItem)
        entryIDs[key] = item.entryID
        // KVO may call back on any thread, so the handler is @Sendable (not
        // main-actor isolated) and hops to the main actor itself.
        itemObservations[key] = avItem.observe(\.status, options: [.new]) { @Sendable [weak self] avItem, _ in
            Task { @MainActor in self?.itemStatusChanged(avItem) }
        }
        attachLevelTap(to: avItem)
        if item.isLive, let titleReader {
            // Radio streams announce what they're playing as timed metadata.
            let output = AVPlayerItemMetadataOutput(identifiers: nil)
            output.setDelegate(titleReader, queue: .main)
            avItem.add(output)
            metadataOutputs[key] = (output, item.entryID)
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
            metadataOutputs[key]?.output.setDelegate(nil, queue: nil)
            metadataOutputs[key] = nil
        }
    }

    // MARK: - Player observation

    private func observePlayer() {
        // KVO handlers are @Sendable for the same reason as in `enqueue`.
        // Each report carries which player it came from: one queued just before
        // a rebuild must not be read as news about the new player.
        playerObservations.append(player.observe(\.currentItem, options: [.new]) { @Sendable [weak self] observed, _ in
            let source = ObjectIdentifier(observed)
            Task { @MainActor in
                guard let self, source == ObjectIdentifier(self.player) else { return }
                self.currentItemChanged()
            }
        })
        playerObservations.append(player.observe(\.timeControlStatus, options: [.new]) { @Sendable [weak self] observed, _ in
            let source = ObjectIdentifier(observed)
            Task { @MainActor in
                guard let self, source == ObjectIdentifier(self.player) else { return }
                self.timeControlStatusChanged()
            }
        })
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.player.currentItem != nil, time.seconds.isFinite else { return }
                self.onEvent?(.timeChanged(time.seconds))
            }
        }
    }

    private func stopObservingPlayer() {
        playerObservations.forEach { $0.invalidate() }
        playerObservations = []
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
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

    /// Taps a newly loaded item for `levelMeter` (measuring only while
    /// `isMetering`). The tap goes on the item's audio track, which a streamed
    /// item only knows once it has loaded; that's normally done while it
    /// buffers, before it's heard. The audio passes through unchanged.
    private func attachLevelTap(to item: AVPlayerItem) {
        Task { [weak self] in
            guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first,
                  let self, let tap = self.levelMeter.makeTap() else { return }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            item.audioMix = mix
        }
    }

    private func streamAnnounced(_ title: String?, by outputKey: ObjectIdentifier) {
        guard let entry = metadataOutputs.values.first(where: { ObjectIdentifier($0.output) == outputKey }) else { return }
        onEvent?(.streamTitle(entry.entryID, title))
    }
}

/// Reads "now playing" titles out of a live stream's timed metadata (Shoutcast
/// and Icecast `StreamTitle`, or a common title). AVFoundation calls it on the
/// queue it was given, but it's kept nonisolated and hands each title to a
/// `@Sendable` closure, which hops to the main actor itself.
private final class StreamTitleReader: NSObject, AVPlayerItemMetadataOutputPushDelegate, Sendable {
    private let onTitle: @Sendable (ObjectIdentifier, String?) -> Void

    init(onTitle: @escaping @Sendable (ObjectIdentifier, String?) -> Void) {
        self.onTitle = onTitle
    }

    nonisolated func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        let items = groups.flatMap(\.items)
        let titleItem = items.first { $0.identifier == .icyMetadataStreamTitle }
            ?? items.first { $0.commonKey == .commonKeyTitle }
        guard let titleItem else { return }
        // AVMetadataItem is immutable (changes need the separate
        // AVMutableMetadataItem), so the task can read it safely even though
        // the SDK doesn't mark it Sendable.
        nonisolated(unsafe) let item = titleItem
        let key = ObjectIdentifier(output)
        let onTitle = onTitle
        Task {
            let title = try? await item.load(.stringValue)
            onTitle(key, title ?? nil)
        }
    }
}
