import Foundation

/// One loaded track, tagged with the queue entry it belongs to.
public struct PlayerItem: Sendable, Equatable {
    public let entryID: QueueEntry.ID
    public let url: URL
    /// A radio stream: the player reports the titles it announces.
    public let isLive: Bool

    public init(entryID: QueueEntry.ID, url: URL, isLive: Bool = false) {
        self.entryID = entryID
        self.url = url
        self.isLive = isLive
    }
}

/// What the player reports back to the engine.
public enum PlayerEvent: Sendable, Equatable {
    /// The player moved on to another item, on its own (track ended) or because
    /// it was told to skip. `nil` means it ran out of items.
    case currentItemChanged(QueueEntry.ID?)
    case statusChanged(PlayerStatus)
    /// Seconds into the current item.
    case timeChanged(TimeInterval)
    /// The current item's real duration, once the player knows it.
    case durationKnown(TimeInterval)
    /// The last loaded item finished.
    case reachedEnd
    case itemFailed(QueueEntry.ID, message: String)
    /// Playback paused itself waiting for data.
    case stalled(QueueEntry.ID)
    /// A live stream announced what it's playing now (`nil`: it cleared it).
    case streamTitle(QueueEntry.ID, String?)
}

public enum PlayerStatus: Sendable, Equatable {
    case paused
    case buffering
    case playing
}

/// The audio boundary. Production wraps `AVQueuePlayer`; tests use a fake.
///
/// The player holds a short list of items and plays them in order without gaps.
/// It knows nothing about the queue; the engine decides what to load.
@MainActor
public protocol AudioPlayer: AnyObject {
    var onEvent: (@MainActor (PlayerEvent) -> Void)? { get set }

    /// Replaces everything loaded. The first item becomes current, starting at `startPosition`.
    func setItems(_ items: [PlayerItem], startPosition: TimeInterval)
    /// Adds an item after the last loaded one.
    func append(_ item: PlayerItem)
    /// Replaces every loaded item after the current one, leaving the current one
    /// playing undisturbed.
    func replaceUpcoming(with item: PlayerItem)
    /// Drops every loaded item after the current one; the current one plays on.
    func removeUpcoming()
    /// Drops the current item and starts the next loaded one.
    func skipToNextItem()
    func play()
    func pause()
    func seek(to position: TimeInterval)
    /// Throws away the underlying player and everything loaded, and starts a
    /// fresh one. For after the system's audio services reset. Reports nothing
    /// about the old player.
    func rebuild()
}

/// Turns a song into a URL the player can load. URLs contain auth tokens, so they
/// are built when needed and never stored. Main-actor bound because the engine is
/// its only caller and the choice can depend on main-actor state (settings,
/// network type, downloads).
@MainActor
public protocol StreamURLProviding {
    func streamURL(for song: Song) throws -> URL
    /// What `streamURL(for:)` chose, to show the listener; `nil` if unknown.
    func quality(for song: Song) -> PlaybackQuality?
}

extension StreamURLProviding {
    public func quality(for song: Song) -> PlaybackQuality? { nil }
}

extension SubsonicClient: StreamURLProviding {
    public func streamURL(for song: Song) throws -> URL {
        try streamURL(songID: song.id)
    }
}
