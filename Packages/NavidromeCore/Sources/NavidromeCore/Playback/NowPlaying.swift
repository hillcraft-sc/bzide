import Foundation

/// What the lock screen and Control Center show.
public struct NowPlayingInfo: Sendable, Equatable {
    public var title: String
    public var artist: String?
    public var album: String?
    /// Server cover art id; the app layer turns it into an image.
    public var coverArtID: String?
    /// Seconds.
    public var duration: TimeInterval?
    /// Seconds into the track at the moment of this update. The system
    /// extrapolates from here using `isPlaying`.
    public var elapsed: TimeInterval
    public var isPlaying: Bool
    public var hasNext: Bool
    public var hasPrevious: Bool
    /// A radio station: no duration and no seeking.
    public var isLiveStream: Bool
    /// For CarPlay's shuffle and repeat buttons, which show these.
    public var isShuffled: Bool
    public var repeatMode: RepeatMode

    public init(
        title: String, artist: String? = nil, album: String? = nil, coverArtID: String? = nil,
        duration: TimeInterval? = nil, elapsed: TimeInterval, isPlaying: Bool, hasNext: Bool, hasPrevious: Bool,
        isLiveStream: Bool = false, isShuffled: Bool = false, repeatMode: RepeatMode = .off
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.coverArtID = coverArtID
        self.duration = duration
        self.elapsed = elapsed
        self.isPlaying = isPlaying
        self.hasNext = hasNext
        self.hasPrevious = hasPrevious
        self.isLiveStream = isLiveStream
        self.isShuffled = isShuffled
        self.repeatMode = repeatMode
    }
}

/// Buttons and gestures from the lock screen, Control Center, headphones and CarPlay.
public enum RemoteCommand: Sendable, Equatable {
    case play
    case pause
    case togglePlayPause
    case next
    case previous
    case seek(to: TimeInterval)
    /// CarPlay's shuffle button (on or off).
    case setShuffle(Bool)
    /// CarPlay's repeat button.
    case setRepeat(RepeatMode)
}

/// The Now Playing boundary. The real implementation lives in the app target
/// because artwork needs UIKit; tests use a fake.
@MainActor
public protocol NowPlayingControlling: AnyObject {
    var onCommand: (@MainActor (RemoteCommand) -> Void)? { get set }
    /// `nil` clears Now Playing (empty queue).
    func update(_ info: NowPlayingInfo?)
}
