import Foundation

/// The Storm visualizer's sky: the music sets the weather, and the weather
/// changes gradually, as real weather does. Calm passages clear the sky, busy
/// ones bring clouds; the bass sets the wind; the treble brings rain once it's
/// cloudy; drum hits in a storm strike lightning. Nothing flashes the whole
/// screen: a strike is a bolt that fades, with at most a slight lift of the sky.
public struct WeatherSky: Sendable {
    /// 0 (clear) ... 1 (overcast).
    public private(set) var cloudCover: Double = 0
    /// 0 (still) ... 1 (gale).
    public private(set) var wind: Double = 0
    /// How far the wind has blown the clouds so far. Only moves forward, so a
    /// change in wind never makes them jump.
    public private(set) var drift: Double = 0
    /// 0 (dry) ... 1 (downpour).
    public private(set) var rain: Double = 0
    /// Bolts still visible, oldest first.
    public private(set) var bolts: [LightningBolt] = []

    /// How quickly each follows the music, per second: clouds slowest, so the
    /// sky doesn't flicker between clear and overcast.
    static let cloudRate = 0.4
    static let windRate = 1.2
    static let rainRate = 0.8
    /// Below this much cloud there's no rain or lightning.
    static let stormThreshold = 0.5
    /// A beat at least this strong strikes lightning.
    static let strikeBeat: Float = 0.6
    /// The shortest gap between strikes, so a fast drum roll doesn't become a strobe.
    static let strikeGap: TimeInterval = 0.6
    /// How long a bolt takes to fade.
    public static let boltLife: TimeInterval = 0.5

    private var sinceStrike: TimeInterval = .infinity
    private var lastBeat: Float = 0
    private var strikeCount: UInt64 = 0

    public init() {}

    /// Advances one frame lasting `elapsed` seconds.
    public mutating func update(energy: SpectrumEnergy, beat: Float, elapsed: TimeInterval) {
        let step = min(max(elapsed, 0), 0.1)
        let busyness = Self.busyness(energy)
        cloudCover = Self.ease(cloudCover, toward: busyness, rate: Self.cloudRate, step: step)
        wind = Self.ease(wind, toward: Self.clamp(Double(energy.bass) * 1.6), rate: Self.windRate, step: step)
        // A breeze even on calm days, so the clouds never stop.
        drift += step * (0.02 + 0.25 * wind)
        let storminess = Self.clamp((cloudCover - Self.stormThreshold) / (1 - Self.stormThreshold))
        rain = Self.ease(rain, toward: Self.clamp(Double(energy.treble) * 2.2) * storminess, rate: Self.rainRate, step: step)

        sinceStrike += step
        bolts = bolts.compactMap { bolt in
            var bolt = bolt
            bolt.age += step
            return bolt.age < Self.boltLife ? bolt : nil
        }
        // A strike on the beat's rising edge, not for every frame it stays high.
        let isNewBeat = beat >= Self.strikeBeat && lastBeat < Self.strikeBeat
        lastBeat = beat
        if isNewBeat, cloudCover > Self.stormThreshold, sinceStrike >= Self.strikeGap {
            sinceStrike = 0
            strikeCount += 1
            bolts.append(LightningBolt(seed: strikeCount, age: 0))
        }
    }

    /// How much the sky lifts from lightning now: at most 10%, fading with the bolt.
    public var flash: Double {
        bolts.map { 0.1 * (1 - $0.age / Self.boltLife) }.max() ?? 0
    }

    /// 0...1: how much is going on in the music, mostly mid-range and treble.
    static func busyness(_ energy: SpectrumEnergy) -> Double {
        clamp(Double(energy.bass * 0.3 + energy.mid * 0.45 + energy.treble * 0.25) * 2)
    }

    private static func ease(_ value: Double, toward target: Double, rate: Double, step: TimeInterval) -> Double {
        value + (target - value) * min(rate * step, 1)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// One lightning strike. Its jagged shape comes from its seed, so it holds
/// still while it fades.
public struct LightningBolt: Sendable, Equatable {
    public let seed: UInt64
    /// Seconds since it struck.
    public var age: TimeInterval

    /// Where it strikes across the sky, 0 (left) ... 1 (right).
    public var x: Double { 0.15 + 0.7 * Double(Self.random(seed, 0)) }

    /// The bolt's zigzag from the cloud (y = 0) to the ground (y = 1), with x
    /// as an offset from `x` in fractions of the width. Forks are separate
    /// paths branching off the main one.
    public var paths: [[(x: Double, y: Double)]] {
        let steps = 9
        var main: [(x: Double, y: Double)] = [(0, 0)]
        var offset = 0.0
        for step in 1...steps {
            offset += (Double(Self.random(seed, UInt64(step))) - 0.5) * 0.08
            main.append((offset, Double(step) / Double(steps)))
        }
        // One fork from a third of the way down, a short way off to one side.
        let forkStart = main[3]
        let side = Self.random(seed, 99) < 0.5 ? -1.0 : 1.0
        var fork = [forkStart]
        for step in 1...3 {
            let last = fork[fork.count - 1]
            fork.append((last.x + side * 0.035 * Double(Self.random(seed, 100 + UInt64(step)) + 0.5), last.y + 0.08))
        }
        return [main, fork]
    }

    /// A repeatable number in 0..<1 for this seed and index (SplitMix64).
    public static func random(_ seed: UInt64, _ index: UInt64) -> Float {
        var z = seed &* 0x9E37_79B9_7F4A_7C15 &+ index &* 0xBF58_476D_1CE4_E5B9 &+ 0x94D0_49BB_1331_11EB
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Float(z >> 40) / Float(1 << 24)
    }
}
