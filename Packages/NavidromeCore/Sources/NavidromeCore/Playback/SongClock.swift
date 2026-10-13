import Foundation

/// Seconds into the current song for visualizers that record the song as it
/// plays (Groove, Tapestry). The engine's position updates only a few times a
/// second; this runs smoothly between updates, follows seeks, and starts over
/// when the song changes.
public struct SongClock: Sendable {
    /// Further apart than this, the engine's position is a seek, not drift.
    static let resyncThreshold: TimeInterval = 1.0

    public private(set) var songTime: TimeInterval = 0
    private var entryID: QueueEntry.ID?

    public init() {}

    /// Advances one frame. Returns true when the song changed, so the caller
    /// can drop what it recorded for the old one.
    public mutating func update(
        entryID: QueueEntry.ID?, position: TimeInterval, isPlaying: Bool, elapsed: TimeInterval
    ) -> Bool {
        let isNewSong = entryID != self.entryID
        if isNewSong {
            self.entryID = entryID
            songTime = position
        }
        if isPlaying {
            songTime += max(elapsed, 0)
        }
        // Follow the engine when it moves somewhere else (a seek), but not for
        // the small lag between its updates.
        if abs(songTime - position) > Self.resyncThreshold {
            songTime = position
        }
        return isNewSong
    }
}
