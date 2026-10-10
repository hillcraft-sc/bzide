import Foundation

/// Decides when the current play has earned a scrobble.
///
/// Counts only time actually listened: a play earns its scrobble after 50% of
/// the track or 4 minutes, whichever comes first. Seeking forward adds nothing
/// and seeking back takes nothing away. Pure value type; the engine feeds it.
public struct ScrobbleTracker: Sendable, Equatable {
    public struct Play: Sendable, Equatable {
        public let songID: String
        public let startedAt: Date
        public var duration: TimeInterval?
        public var listened: TimeInterval = 0
        /// Last time reported by the player, to measure the next step from.
        var lastTime: TimeInterval
        public var isAnnounced = false
        public var isSubmitted = false
    }

    /// Never needs more than this much listening.
    public static let maximumThreshold: TimeInterval = 240
    /// Player ticks are about half a second apart; a bigger forward jump is a seek.
    static let largestListeningStep: TimeInterval = 2

    public private(set) var play: Play?

    public init() {}

    /// Seconds of listening this play needs.
    public var threshold: TimeInterval? {
        guard let play else { return nil }
        guard let duration = play.duration, duration > 0 else { return Self.maximumThreshold }
        return min(duration / 2, Self.maximumThreshold)
    }

    /// A new play of `songID`, starting at `position` (non-zero after a relaunch).
    public mutating func begin(songID: String, duration: TimeInterval?, position: TimeInterval, at date: Date) {
        play = Play(songID: songID, startedAt: date, duration: duration, lastTime: position)
    }

    public mutating func end() {
        play = nil
    }

    public mutating func updateDuration(_ duration: TimeInterval) {
        play?.duration = duration
    }

    /// The player reported a new time. Returns `true` exactly once per play: when
    /// listening crosses the threshold.
    public mutating func observe(time: TimeInterval) -> Bool {
        guard var current = play else { return false }
        let step = time - current.lastTime
        if step > 0, step <= Self.largestListeningStep {
            current.listened += step
        }
        current.lastTime = time
        play = current
        guard !current.isSubmitted, let threshold, current.listened >= threshold else { return false }
        play?.isSubmitted = true
        return true
    }

    /// The user moved the playhead. Listening resumes from here without credit.
    public mutating func seeked(to time: TimeInterval) {
        play?.lastTime = time
    }

    /// Returns `true` the first time it's called for a play, for the "now playing" update.
    public mutating func announce() -> Bool {
        guard let current = play, !current.isAnnounced else { return false }
        play?.isAnnounced = true
        return true
    }
}
