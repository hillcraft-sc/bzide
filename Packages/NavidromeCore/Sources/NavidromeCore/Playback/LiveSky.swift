import Foundation

/// The Weather (Live) sky: the real time of day (from `SkyClock`) and the
/// real weather (`LiveWeather`) set the scene, and the music amplifies it:
/// quiet passages show the weather gently, loud ones dramatically. Advanced
/// once a frame.
///
/// - **Weather, amplified** (by `drive`, the music's loudness followed
///   quickly): clouds start at the real cover and billow thicker in busy
///   music; rain, sleet or snow fall at the real strength, from about half
///   of it in quiet passages to twice it when loud; the real wind blows,
///   gusting with the bass; a real thunderstorm strikes lightning on the
///   beats; fog lies thicker in calm passages and thins in busy ones.
/// - **Mood:** how energetic the music is (`intensity`, loudness and
///   busyness) and how bright (`brightness`, treble against bass), both
///   followed over a few seconds, so the scene breathes with the song rather
///   than flickering with each note. Calm music makes everything slower and
///   rarer; energetic music, busier.
/// - **Every beat** (`flash`): the stars flare and the sun's and moon's glow
///   swell on each drum hit.
/// - **Night and twilight:** stars twinkle with the treble (`sparkle`);
///   beats send shooting stars, and in an energetic stretch, comets;
///   fireflies glow over the hills with the mid-range (`glow`), more of them
///   the more energetic the music.
/// - **Day and twilight:** flocks of birds cross when the music builds or
///   is energetic; the sun's rays pulse with the bass (`pulse`).
/// - **Always:** a breeze that gusts with the bass (`wind`), moving the
///   clouds (`drift`) and bending the trees.
///
/// Events are spaced by the mood: the calmer the music, the longer the gap.
/// Their look comes from a seed, so each holds steady.
public struct LiveSky: Sendable {
    // MARK: Mood

    /// 0 (calm) ... 1 (energetic), over the last few seconds.
    public private(set) var intensity: Double = 0
    /// 0 (dark, bass-heavy) ... 1 (bright, treble-heavy), over the last few seconds.
    public private(set) var brightness: Double = 0.5
    /// 0 ... 1: the treble now, lightly smoothed, for twinkling stars.
    public private(set) var sparkle: Double = 0
    /// 0 ... 1: the bass now, lightly smoothed, for the sun's rays.
    public private(set) var pulse: Double = 0
    /// 0 ... 1: the latest beat, fading quickly, for flashes on each drum hit.
    public private(set) var flash: Double = 0
    /// 0 ... 1: the mid-range now, lightly smoothed, for the fireflies.
    public private(set) var glow: Double = 0
    /// 0 ... 1: the music's loudness, followed within a second or so: how
    /// much it amplifies the weather.
    public private(set) var drive: Double = 0

    // MARK: Weather

    /// The real weather, as last given.
    public private(set) var weather = LiveWeather.fair
    /// 0 ... 1: how hard it's raining, sleeting or snowing now.
    public private(set) var precipitation: Double = 0
    /// 0 ... 1: how thick the fog is now.
    public private(set) var fog: Double = 0
    /// Lightning bolts still visible, oldest first (thunderstorms only).
    public private(set) var bolts: [LightningBolt] = []

    // MARK: Wind and clouds

    /// 0 (still) ... 1 (gale): a breeze plus gusts from the bass.
    public private(set) var wind: Double = 0
    /// How far the wind has moved the clouds. Only moves forward.
    public private(set) var drift: Double = 0
    /// 0 (clear) ... 1 (overcast): the real cover, thickened by busy music.
    public private(set) var cloudCover: Double = 0.2

    // MARK: Events

    public private(set) var shootingStars: [ShootingStar] = []
    public private(set) var flocks: [BirdFlock] = []

    // MARK: Tuning

    /// How fast the mood follows the music, per second.
    static let moodRate = 0.35
    static let sparkleRate = 6.0
    static let pulseRate = 8.0
    static let glowRate = 4.0
    /// How fast a beat's flash fades, per second.
    static let flashFade = 4.0
    static let windRate = 1.2
    static let cloudRate = 0.5
    static let driveRate = 1.5
    static let precipitationRate = 1.2
    static let fogRate = 0.4
    /// How much busy music can add to the real cloud cover.
    static let cloudBoost = 0.3
    /// Precipitation from this share of the real strength (quiet) to `precipitationLoud` (loud).
    static let precipitationQuiet = 0.5
    static let precipitationLoud = 2.0
    /// Real wind at this speed (m/s) or more counts as a full gale.
    static let galeSpeed = 15.0
    /// Lightning: the shortest gap between strikes, and how long a bolt lasts.
    static let strikeGap: TimeInterval = 0.6
    /// A beat at least this strong can set off an event.
    static let eventBeat: Float = 0.6
    /// The shortest gap between shooting stars: long when calm, short when energetic.
    static let shootingStarGap = (calm: 4.0, energetic: 0.8)
    /// Comets: only in an energetic stretch, and at most this often.
    static let cometIntensity = 0.4
    static let cometGap: TimeInterval = 30
    /// Every this-many shooting stars in an energetic stretch, a comet instead.
    static let cometEvery = 5
    /// Bird flocks: when the music builds or is energetic, at most this often.
    static let flockGap = (calm: 20.0, energetic: 6.0)
    /// Energetic enough for birds without a build.
    static let flockIntensity = 0.5
    /// Shooting stars once the sky is this dark (from twilight on); birds
    /// while it's lighter than `birdDarkness`.
    static let starDarkness = 0.35
    static let birdDarkness = 0.7
    /// How much the intensity must have risen over `buildWindow` to count as a build.
    static let buildRise = 0.08
    static let buildWindow: TimeInterval = 3

    private var hasStarted = false
    private var sinceShootingStar: TimeInterval = .infinity
    private var sinceComet: TimeInterval = .infinity
    private var sinceFlock: TimeInterval = .infinity
    private var shootingStarCount = 0
    private var seedCount: UInt64 = 0
    private var lastBeat: Float = 0
    /// The intensity a few seconds ago, to spot the music building.
    private var recentIntensity: [(age: TimeInterval, value: Double)] = []

    public init() {}

    /// How dark the sky is, 0 (full day) ... 1 (full night), from the sun's
    /// height: day above 6°, night below −12°, blending between.
    public static func darkness(sunAltitude: Double) -> Double {
        let value = (6 - sunAltitude) / 18
        return min(max(value, 0), 1)
    }

    /// Advances one frame lasting `elapsed` seconds.
    public mutating func update(energy: SpectrumEnergy, beat: Float, sun: SkyClock.Sun, weather: LiveWeather = .fair, elapsed: TimeInterval) {
        self.weather = weather
        // The first frame starts as the weather is, rather than clearing for
        // a moment; later changes (the forecast arriving) blend in.
        if !hasStarted {
            hasStarted = true
            cloudCover = weather.cloudCover
            fog = weather.isFog ? 0.85 : 0
            precipitation = weather.intensity * Self.precipitationQuiet
        }
        let step = min(max(elapsed, 0), 0.1)
        let bass = Double(energy.bass), mid = Double(energy.mid), treble = Double(energy.treble)

        let loudness = Self.clamp((bass * 0.35 + mid * 0.45 + treble * 0.2) * 2)
        intensity = Self.ease(intensity, toward: loudness, rate: Self.moodRate, step: step)
        let total = bass + treble
        if total > 0.05 {
            brightness = Self.ease(brightness, toward: treble / total, rate: Self.moodRate, step: step)
        }
        sparkle = Self.ease(sparkle, toward: Self.clamp(treble * 2.5), rate: Self.sparkleRate, step: step)
        pulse = Self.ease(pulse, toward: Self.clamp(bass * 1.8), rate: Self.pulseRate, step: step)
        glow = Self.ease(glow, toward: Self.clamp(mid * 2.2), rate: Self.glowRate, step: step)
        flash = max(Double(beat), flash - Self.flashFade * step, 0)

        drive = Self.ease(drive, toward: loudness, rate: Self.driveRate, step: step)

        // The real wind, plus gusts from the bass.
        let realWind = Self.clamp(weather.windSpeed / Self.galeSpeed)
        wind = Self.ease(wind, toward: Self.clamp(0.05 + realWind * 0.7 + bass * 1.1), rate: Self.windRate, step: step)
        drift += step * (0.02 + 0.25 * wind)
        cloudCover = Self.ease(cloudCover, toward: Self.clamp(weather.cloudCover + Self.cloudBoost * drive * (1 - weather.cloudCover * 0.5)), rate: Self.cloudRate, step: step)
        let amplified = weather.intensity * (Self.precipitationQuiet + (Self.precipitationLoud - Self.precipitationQuiet) * drive)
        precipitation = Self.ease(precipitation, toward: Self.clamp(amplified), rate: Self.precipitationRate, step: step)
        // Calm passages let the fog settle; busy ones stir it thinner.
        fog = Self.ease(fog, toward: weather.isFog ? 0.85 - 0.45 * drive : 0, rate: Self.fogRate, step: step)

        age(by: step)
        let isNewBeat = beat >= Self.eventBeat && lastBeat < Self.eventBeat
        lastBeat = beat
        let darkness = Self.darkness(sunAltitude: sun.altitude)
        if isNewBeat, weather.isThunder { strike() }
        if isNewBeat, darkness > Self.starDarkness, isSkyOpen { launchShootingStar() }
        if isNewBeat, darkness < Self.birdDarkness, isFlyingWeather, isBuilding || intensity >= Self.flockIntensity { launchFlock() }
        remember(intensity, step: step)
    }

    // MARK: - Events

    /// Enough clear sky to see shooting stars.
    public var isSkyOpen: Bool { cloudCover < 0.75 && fog < 0.4 }

    /// Birds don't fly in rain, snow, storms or fog.
    var isFlyingWeather: Bool { weather.precipitation == .none && !weather.isThunder && !weather.isFog }

    private var sinceStrike: TimeInterval = .infinity

    private mutating func strike() {
        guard sinceStrike >= Self.strikeGap else { return }
        sinceStrike = 0
        seedCount += 1
        bolts.append(LightningBolt(seed: seedCount, age: 0))
    }

    private mutating func age(by step: TimeInterval) {
        sinceStrike += step
        bolts = bolts.compactMap { bolt in
            var bolt = bolt
            bolt.age += step
            return bolt.age < WeatherSky.boltLife ? bolt : nil
        }
        sinceShootingStar += step
        sinceComet += step
        sinceFlock += step
        shootingStars = shootingStars.compactMap { star in
            var star = star
            star.age += step
            return star.age < star.life ? star : nil
        }
        flocks = flocks.compactMap { flock in
            var flock = flock
            flock.age += step
            return flock.age < BirdFlock.life ? flock : nil
        }
    }

    private var gapForMood: (shootingStar: TimeInterval, flock: TimeInterval) {
        (
            Self.shootingStarGap.calm + (Self.shootingStarGap.energetic - Self.shootingStarGap.calm) * intensity,
            Self.flockGap.calm + (Self.flockGap.energetic - Self.flockGap.calm) * intensity
        )
    }

    private mutating func launchShootingStar() {
        guard sinceShootingStar >= gapForMood.shootingStar else { return }
        sinceShootingStar = 0
        shootingStarCount += 1
        seedCount += 1
        let isComet = intensity >= Self.cometIntensity && sinceComet >= Self.cometGap
            && shootingStarCount % Self.cometEvery == 0
        if isComet { sinceComet = 0 }
        shootingStars.append(ShootingStar(seed: seedCount, isComet: isComet, age: 0))
    }

    /// Whether the music has been building: louder now than a few seconds ago.
    private var isBuilding: Bool {
        guard let past = recentIntensity.first, past.age >= Self.buildWindow - 0.5 else { return false }
        return intensity - past.value >= Self.buildRise
    }

    private mutating func launchFlock() {
        guard sinceFlock >= gapForMood.flock else { return }
        sinceFlock = 0
        seedCount += 1
        flocks.append(BirdFlock(seed: seedCount, size: 3 + Int(intensity * 6), age: 0))
    }

    /// Keeps a few seconds of intensity readings, oldest first.
    private mutating func remember(_ value: Double, step: TimeInterval) {
        recentIntensity = recentIntensity.map { ($0.age + step, $0.value) }.filter { $0.age <= Self.buildWindow }
        recentIntensity.append((0, value))
    }

    // MARK: - Helpers

    private static func ease(_ value: Double, toward target: Double, rate: Double, step: TimeInterval) -> Double {
        value + (target - value) * min(rate * step, 1)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// A shooting star, or a comet: a long-tailed, slower one.
public struct ShootingStar: Sendable, Equatable {
    public let seed: UInt64
    public let isComet: Bool
    /// Seconds since it appeared.
    public var age: TimeInterval

    /// How long it's visible.
    public var life: TimeInterval { isComet ? 7 : 1.1 }
    /// 0 ... 1 through its life.
    public var progress: Double { min(age / life, 1) }

    /// Where it starts, as fractions of the sky (x across, y down), and the
    /// direction it travels (radians; down and to one side).
    public var start: (x: Double, y: Double) {
        (0.1 + 0.8 * Double(LightningBolt.random(seed, 1)), 0.05 + 0.35 * Double(LightningBolt.random(seed, 2)))
    }

    public var angle: Double {
        let side = LightningBolt.random(seed, 3) < 0.5 ? -1.0 : 1.0
        return .pi / 2 + side * (0.6 + 0.4 * Double(LightningBolt.random(seed, 4)))
    }
}

/// A small flock of birds crossing the sky in a loose V.
public struct BirdFlock: Sendable, Equatable {
    public let seed: UInt64
    public let size: Int
    /// Seconds since it set off.
    public var age: TimeInterval

    /// How long it takes to cross.
    public static let life: TimeInterval = 14
    public var progress: Double { min(age / Self.life, 1) }
    /// Left to right, or right to left.
    public var isHeadingRight: Bool { LightningBolt.random(seed, 1) < 0.5 }
    /// How high it flies, 0 (top of the sky) ... 1 (horizon).
    public var height: Double { 0.15 + 0.4 * Double(LightningBolt.random(seed, 2)) }
}
