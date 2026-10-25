import Foundation

/// The Spectrum visualizer's columns and peak dots, like an old LED
/// equalizer's. Each column is the loudest of its group of bands; each dot
/// jumps up with its column, holds a moment, then falls with gravity
/// (faster and faster) until it lands on the column again.
public struct SpectrumPeaks: Sendable {
    /// Where each dot is, 0...1 like the levels.
    public private(set) var peaks: [Float]
    /// Seconds each dot still holds before falling.
    private var holds: [TimeInterval]
    /// How fast each dot is falling, in heights per second.
    private var speeds: [Float]

    static let hold: TimeInterval = 0.5
    /// Heights per second, per second.
    static let gravity: Float = 2.5

    public init(count: Int) {
        peaks = [Float](repeating: 0, count: count)
        holds = [TimeInterval](repeating: 0, count: count)
        speeds = [Float](repeating: 0, count: count)
    }

    /// Advances one frame lasting `elapsed` seconds, with this frame's
    /// column levels. A different number of columns (turning the phone)
    /// starts the dots again.
    public mutating func update(columns: [Float], elapsed: TimeInterval) {
        if columns.count != peaks.count { self = SpectrumPeaks(count: columns.count) }
        let step = min(max(elapsed, 0), 0.1)
        for index in peaks.indices {
            let level = min(max(columns[index], 0), 1)
            if level >= peaks[index] {
                peaks[index] = level
                holds[index] = Self.hold
                speeds[index] = 0
            } else if holds[index] > 0 {
                holds[index] -= step
            } else {
                speeds[index] += Self.gravity * Float(step)
                peaks[index] = max(level, peaks[index] - speeds[index] * Float(step))
            }
        }
    }

    /// `levels` in `count` groups, bass first, each the loudest of its group.
    /// Fewer levels than columns repeat across them.
    public static func columns(from levels: [Float], count: Int) -> [Float] {
        guard count > 0, !levels.isEmpty else { return [Float](repeating: 0, count: max(count, 0)) }
        return (0..<count).map { column in
            let start = column * levels.count / count
            let end = max((column + 1) * levels.count / count, start + 1)
            return levels[start..<min(end, levels.count)].max() ?? 0
        }
    }
}
