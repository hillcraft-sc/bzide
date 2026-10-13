import Foundation

/// What the Tapestry visualizer weaves: one row of threads for every half
/// second of the current song, each thread a frequency band (bass first) and
/// its value how loud that band got during the row. The finished cloth shows
/// the whole song's shape. Rows played while the visualizer was closed weren't
/// heard and are `nil`.
public struct TapestryRecorder: Sendable {
    /// Rows per second of song time.
    public static let rowsPerSecond = 2
    public static let threadCount = 20

    /// One row per 1/`rowsPerSecond` of the song so far, `threadCount` levels
    /// of 0...1 each, or `nil` where it wasn't heard.
    public private(set) var rows: [[Float]?] = []
    /// Seconds into the song, kept smooth between the engine's position updates.
    public var songTime: TimeInterval { clock.songTime }
    private var clock = SongClock()

    public init() {}

    /// Advances one frame. `position` is the engine's; `levels` are the
    /// spectrum's bands right now, bass first, any number of them.
    public mutating func update(
        entryID: QueueEntry.ID?, position: TimeInterval, isPlaying: Bool, levels: [Float], elapsed: TimeInterval
    ) {
        if clock.update(entryID: entryID, position: position, isPlaying: isPlaying, elapsed: elapsed) {
            rows = []
        }
        guard isPlaying, entryID != nil else { return }
        let index = Int(songTime * Double(Self.rowsPerSecond))
        guard index >= 0 else { return }
        if rows.count <= index {
            rows.append(contentsOf: [[Float]?](repeating: nil, count: index - rows.count + 1))
        }
        // Each thread keeps the loudest its band got during the row.
        let threads = Self.threads(from: levels)
        let previous = rows[index] ?? [Float](repeating: 0, count: Self.threadCount)
        rows[index] = zip(previous, threads).map { max($0, $1) }
    }

    /// The bands grouped into `threadCount` threads, each the average of its
    /// group, clamped to 0...1. Missing bands count as silence.
    static func threads(from levels: [Float]) -> [Float] {
        guard !levels.isEmpty else { return [Float](repeating: 0, count: threadCount) }
        return (0..<threadCount).map { thread in
            let start = thread * levels.count / threadCount
            let end = max((thread + 1) * levels.count / threadCount, start + 1)
            let group = levels[start..<min(end, levels.count)]
            let average = group.reduce(0, +) / Float(group.count)
            return min(max(average, 0), 1)
        }
    }
}
