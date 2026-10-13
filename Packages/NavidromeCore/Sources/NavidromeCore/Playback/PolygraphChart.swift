import Foundation

/// The Lie Detector visualizer's chart: four pens on springy arms drawing on
/// paper that runs past them while the music plays.
///
/// - Pens 0–2 follow the bass, mid-range and treble. Each swings either way
///   around its center by how much its part is louder or quieter than it has
///   been lately, so the lines wander rather than pinning to one side; drum
///   hits kick the bass pen.
/// - Pen 3 follows overall loudness, drawn as dense back-and-forth hatching
///   (its value is the hatching's height, 0...1).
/// - The pens have a little weight: they overshoot and wiggle like real
///   needles.
/// - Paused, the paper keeps running and the pens rest at center, drawing
///   flat lines, as if nothing is being recorded. What "lately" means for each
///   pen holds still meanwhile, so playing again picks up smoothly.
public struct PolygraphChart: Sendable {
    public static let penCount = 4
    /// Points on the paper per second of paper travel.
    public static let samplesPerSecond = 60
    /// How much paper is kept, in seconds; more than fits on screen.
    public static let keptSeconds = 20.0

    /// What each pen has drawn, oldest first, `samplesPerSecond` apart:
    /// pens 0–2 from -1 to 1, pen 3 from 0 to 1.
    public private(set) var samples: [[Double]] = []
    /// Where each pen is now.
    public private(set) var pens: [Double] = Array(repeating: 0, count: penCount)
    /// Seconds of paper that have run past, for scrolling the grid with the ink.
    /// It runs whether or not the music plays.
    public private(set) var travel: TimeInterval = 0

    /// How far a pen swings for a change in its part (full swing at this much).
    static let swingRange: [Double] = [0.25, 0.2, 0.15]
    /// How quickly "lately" follows the music, per second.
    static let averageRate = 0.8
    /// The loudness (average band level) the hatching spans, from nothing to
    /// full width: about a quiet verse to a loud, dense chorus, so quiet songs
    /// draw a thin band, loud ones a wide one, and a swell into a chorus shows.
    static let loudnessRange = 0.15...0.6
    /// How hard a full beat kicks the bass pen.
    static let beatKick = 0.8
    /// The pens' springs: stiff and lightly damped, so they wiggle.
    static let stiffness = 260.0
    static let dampingRatio = 0.3

    private var velocities: [Double] = Array(repeating: 0, count: penCount)
    private var averages: [Double] = [0, 0, 0]
    private var sinceSample: TimeInterval = 0

    public init() {}

    /// Advances one frame lasting `elapsed` seconds.
    public mutating func update(energy: SpectrumEnergy, loudness: Float, beat: Float, isPlaying: Bool, elapsed: TimeInterval) {
        let step = min(max(elapsed, 0), 0.1)
        let parts = [Double(energy.bass), Double(energy.mid), Double(energy.treble)]
        // Paused, every pen rests at center: flat lines.
        var targets = [Double](repeating: 0, count: Self.penCount)
        if isPlaying {
            for pen in 0..<3 {
                let change = (parts[pen] - averages[pen]) / Self.swingRange[pen]
                averages[pen] += (parts[pen] - averages[pen]) * min(Self.averageRate * step, 1)
                targets[pen] = change + (pen == 0 ? Self.beatKick * Double(beat) : 0)
            }
            let range = Self.loudnessRange
            targets[3] = Self.clamp((Double(loudness) - range.lowerBound) / (range.upperBound - range.lowerBound), 0, 1)
        }

        let damping = 2 * Self.dampingRatio * Self.stiffness.squareRoot()
        for pen in 0..<Self.penCount {
            let low: Double = pen == 3 ? 0 : -1
            velocities[pen] += (Self.stiffness * (Self.clamp(targets[pen], low, 1) - pens[pen]) - damping * velocities[pen]) * step
            pens[pen] += velocities[pen] * step
            // The arm stops at the edge of its lane.
            if pens[pen] > 1 || pens[pen] < low {
                pens[pen] = Self.clamp(pens[pen], low, 1)
                velocities[pen] = 0
            }
        }

        travel += step
        sinceSample += step
        let interval = 1 / Double(Self.samplesPerSecond)
        while sinceSample >= interval {
            sinceSample -= interval
            samples.append(pens)
        }
        let kept = Int(Self.keptSeconds * Double(Self.samplesPerSecond))
        if samples.count > kept {
            samples.removeFirst(samples.count - kept)
        }
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), high)
    }
}
