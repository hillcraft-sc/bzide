import Foundation

/// What the Groove visualizer engraves: how loud the music was at each moment
/// of the current song, so the record can show the whole song's shape as it's
/// "cut". Only moments heard while the visualizer was open have a level; the
/// rest are unknown and drawn as a plain groove.
public struct GrooveRecorder: Sendable {
    /// Levels per second of song time.
    public static let samplesPerSecond = 20
    /// One entry per 1/`samplesPerSecond` of the song so far, 0...1, or `nil`
    /// where it wasn't heard.
    public private(set) var levels: [Float?] = []
    /// Seconds into the song, kept smooth between the engine's position updates.
    public var songTime: TimeInterval { clock.songTime }
    private var clock = SongClock()

    public init() {}

    /// Advances one frame. `position` is the engine's (it updates only a few
    /// times a second); `level` is how loud the music is right now.
    public mutating func update(
        entryID: QueueEntry.ID?, position: TimeInterval, isPlaying: Bool, level: Float, elapsed: TimeInterval
    ) {
        if clock.update(entryID: entryID, position: position, isPlaying: isPlaying, elapsed: elapsed) {
            levels = []
        }
        guard isPlaying, entryID != nil else { return }
        let index = Int(songTime * Double(Self.samplesPerSecond))
        guard index >= 0 else { return }
        if levels.count <= index {
            levels.append(contentsOf: [Float?](repeating: nil, count: index - levels.count + 1))
        }
        levels[index] = max(levels[index] ?? 0, min(max(level, 0), 1))
    }
}
