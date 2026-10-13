import Foundation

/// How the Typeset visualizer's letters move, following the feel of the track.
///
/// - Each letter plays its part of the spectrum, picked by its place in the
///   words (`positions`, 0 for the first letter, bass, to 1 for the last,
///   treble). It jumps when its part gets louder than it has been lately and
///   settles home as that becomes the new normal, so a loud song keeps the
///   words in place and only the changes move them; it brightens with how
///   loud its part is.
/// - A bass hit also thumps the whole title up together; treble leans the
///   letters; loudness swells the words.
/// - Drum hits make the letters jump out: each pops bigger and is knocked
///   loose in its own direction, then springs back.
/// - Soft, slow passages float the letters on a gentle wave. The springs
///   follow the mood too: loose and drifting when it's calm, tight and
///   punchy when it's loud.
///
/// Letters ride springs toward where the music puts them, so they leap and
/// settle rather than tremble. Offsets are in font sizes.
public struct TypesetMotion: Sendable {
    public struct Letter: Sendable, Equatable {
        public var dx: Double
        public var dy: Double
        /// Radians.
        public var rotation: Double
        /// Vertical stretch from the baseline, 1 at rest.
        public var stretch: Double
        /// Overall size, 1 at rest: pops on drum hits, swells with loudness.
        public var scale: Double
        /// 0...1.
        public var brightness: Double

        public static let still = Letter(dx: 0, dy: 0, rotation: 0, stretch: 1, scale: 1, brightness: 0)
    }

    public private(set) var letters: [Letter] = []
    /// 0 (loud and busy) ... 1 (soft and calm), over the last few seconds.
    public private(set) var calm: Double = 1

    /// A beat at least this strong makes the letters jump, at most this often.
    static let jumpBeat: Float = 0.6
    static let jumpGap: TimeInterval = 0.3
    /// How hard a full beat throws a letter (font sizes per second), turns it, and pops it bigger.
    static let throwSpeed = 5.5
    static let spinSpeed = 4.0
    static let popSpeed = 4.0
    /// How high a jump in a letter's own band lifts it (and how far a drop
    /// lowers it), and how much taller it stretches.
    static let lift = 0.6
    static let dip = 0.15
    static let stretch = 0.3
    /// How much a band must rise above its recent level for a full jump.
    static let jumpRange = 0.4
    /// How quickly "recently" follows the music, per second: about a second.
    static let averageRate = 1.2
    /// How high the bass thumps the whole title.
    static let thump = 0.35
    /// How far treble leans the letters (radians), the treble end most.
    static let flick = 0.18
    /// How much loudness swells the words.
    static let swell = 0.12
    /// How high soft passages float the letters, and how far they sway (radians).
    static let floatHeight = 0.14
    static let floatSway = 0.08
    /// Bands either side that each letter also listens to, smoothing out flicker.
    static let bandSpread = 2
    /// How quickly the mood follows the music, per second.
    static let calmRate = 0.5
    /// Spring stiffness from calm (floaty) to loud (punchy); damping keeps a
    /// little overshoot at either end.
    static let stiffness = (calm: 28.0, loud: 130.0)
    static let dampingRatio = 0.45
    /// The spring pulling thrown letters home, the same whatever the mood, so
    /// a drum hit in a soft song doesn't fling them across the screen.
    static let throwStiffness = 60.0

    private var springs: [Springs] = []
    private var lastBeat: Float = 0
    private var sinceJump: TimeInterval = .infinity
    private var jumpCount: UInt64 = 0
    private var clock: TimeInterval = 0
    private var bassAverage = 0.0

    /// One letter's springs: knocked offset and turn, bounce height, tilt and pop.
    private struct Springs: Sendable {
        var x = Spring(), y = Spring(), turn = Spring()
        var bounce = Spring(), tilt = Spring(), pop = Spring()
        /// The letter's band, recently.
        var average = 0.0
    }

    private struct Spring: Sendable {
        var value = 0.0
        var velocity = 0.0

        mutating func step(toward target: Double, stiffness: Double, damping: Double, elapsed: TimeInterval) {
            velocity += (stiffness * (target - value) - damping * velocity) * elapsed
            value += velocity * elapsed
        }
    }

    public init() {}

    /// Advances one frame. `positions` gives each letter's place in the words,
    /// 0...1; when the number of letters changes (a new song), they start at rest.
    public mutating func update(
        positions: [Double], levels: [Float], energy: SpectrumEnergy, beat: Float, elapsed: TimeInterval
    ) {
        let step = min(max(elapsed, 0), 0.1)
        clock += step
        if springs.count != positions.count {
            springs = Array(repeating: Springs(), count: positions.count)
        }

        let loudness = levels.isEmpty ? 0 : Double(levels.reduce(0, +)) / Double(levels.count)
        let busy = Self.clamp((loudness - 0.08) / 0.3)
        calm += ((1 - busy) - calm) * min(Self.calmRate * step, 1)
        let stiffness = Self.stiffness.calm + (Self.stiffness.loud - Self.stiffness.calm) * (1 - calm)
        let damping = 2 * Self.dampingRatio * stiffness.squareRoot()

        let isNewBeat = beat >= Self.jumpBeat && lastBeat < Self.jumpBeat
        lastBeat = beat
        if isNewBeat, sinceJump >= Self.jumpGap {
            sinceJump = 0
            jump(strength: Double(beat))
        }
        sinceJump += step

        // Only a rise in the bass thumps; a steady bass line leaves the words be.
        let bass = Double(energy.bass)
        let thump = Self.thump * Self.clamp((bass - bassAverage) / 0.3)
        bassAverage += (bass - bassAverage) * min(Self.averageRate * step, 1)
        let treble = Self.clamp(Double(energy.treble) * 2.5 - 0.1)
        let swell = 1 + Self.swell * busy

        letters = positions.enumerated().map { index, position in
            let raw = Self.level(at: position, in: levels)
            let level = Self.emphasized(raw)
            var letter = springs[index]
            let change = min(max((raw - letter.average) / Self.jumpRange, -1), 1)
            letter.average += (raw - letter.average) * min(Self.averageRate * step, 1)
            let rise = change > 0 ? Self.lift * change : Self.dip * change
            // Thrown letters always spring home; the rest follow the music.
            let throwDamping = 2 * 0.5 * Self.throwStiffness.squareRoot()
            letter.x.step(toward: 0, stiffness: Self.throwStiffness, damping: throwDamping, elapsed: step)
            letter.y.step(toward: 0, stiffness: Self.throwStiffness, damping: throwDamping, elapsed: step)
            letter.turn.step(toward: 0, stiffness: Self.throwStiffness, damping: throwDamping, elapsed: step)
            letter.pop.step(toward: 0, stiffness: stiffness, damping: damping, elapsed: step)
            letter.bounce.step(toward: rise + thump, stiffness: stiffness, damping: damping, elapsed: step)
            // All lean the same way, so neighbors don't collide.
            letter.tilt.step(toward: Self.flick * treble * position, stiffness: stiffness, damping: damping, elapsed: step)
            springs[index] = letter

            let wave = clock * 1.4 + position * 5
            let height = letter.bounce.value
            return Letter(
                dx: letter.x.value + calm * Self.floatHeight * 0.3 * sin(clock * 0.8 + position * 3),
                dy: letter.y.value - height + calm * Self.floatHeight * sin(wave),
                rotation: letter.turn.value + letter.tilt.value + calm * Self.floatSway * sin(wave + 1.2),
                // Only its own band stretches a letter; the thump just lifts.
                stretch: 1 + Self.stretch * min(max(height - thump, 0) / Self.lift, 1),
                scale: swell * max(1 + letter.pop.value, 0.5),
                brightness: max(level, Double(beat) * 0.5)
            )
        }
    }

    /// Every letter pops bigger and is thrown in its own direction, mostly
    /// upward, with a spin.
    private mutating func jump(strength: Double) {
        jumpCount += 1
        for index in springs.indices {
            let seed = UInt64(index) * 4
            let angle = -Double.pi / 2 + (Self.random(jumpCount, seed) - 0.5) * 2.6
            let speed = Self.throwSpeed * strength * (0.5 + Self.random(jumpCount, seed + 1))
            springs[index].x.velocity += cos(angle) * speed
            springs[index].y.velocity += sin(angle) * speed
            springs[index].turn.velocity += (Self.random(jumpCount, seed + 2) - 0.5) * 2 * Self.spinSpeed * strength
            springs[index].pop.velocity += Self.popSpeed * strength * (0.7 + 0.6 * Self.random(jumpCount, seed + 3))
        }
    }

    /// The average of the bands around `position` (0 bass ... 1 treble), each clamped to 0...1.
    static func level(at position: Double, in levels: [Float]) -> Double {
        guard !levels.isEmpty else { return 0 }
        let band = min(max(Int(position * Double(levels.count)), 0), levels.count - 1)
        let nearby = levels[max(band - bandSpread, 0)...min(band + bandSpread, levels.count - 1)]
        return nearby.reduce(0) { $0 + Double(min(max($1, 0), 1)) } / Double(nearby.count)
    }

    /// Very quiet bands leave their letters down, so the loud ones stand out.
    static func emphasized(_ level: Double) -> Double {
        clamp((level - 0.08) / 0.45)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    /// A repeatable number in 0..<1 for this seed and index (SplitMix64).
    static func random(_ seed: UInt64, _ index: UInt64) -> Double {
        var z = seed &* 0x9E37_79B9_7F4A_7C15 &+ index &* 0xBF58_476D_1CE4_E5B9 &+ 0x94D0_49BB_1331_11EB
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }
}
