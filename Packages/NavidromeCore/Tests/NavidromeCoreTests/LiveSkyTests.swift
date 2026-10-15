import Foundation
import Testing
@testable import NavidromeCore

struct LiveSkyTests {
    private static let night = SkyClock.Sun(altitude: -30, hourAngle: 160)
    private static let day = SkyClock.Sun(altitude: 40, hourAngle: -20)
    private static let quiet = SpectrumEnergy(bass: 0.05, mid: 0.05, treble: 0.05)
    private static let loud = SpectrumEnergy(bass: 0.6, mid: 0.6, treble: 0.6)

    /// A sky with its own clock, played in 0.05 s frames with a strong beat
    /// every half second. Counts every shooting star, comet and flock that
    /// sets off.
    private struct Session {
        var sky = LiveSky()
        var frame = 0
        var shootingStars = Set<UInt64>()
        var comets = Set<UInt64>()
        var flocks = Set<UInt64>()
        var bolts = Set<UInt64>()

        static let step = 0.05
        /// A beat on every tenth frame.
        static let beatFrames = 10

        mutating func play(_ seconds: Double, energy: SpectrumEnergy, sun: SkyClock.Sun, weather: LiveWeather = .fair, beats: Bool = true) {
            for _ in 0..<Int((seconds / Self.step).rounded()) {
                frame += 1
                let beat: Float = beats && frame % Self.beatFrames == 0 ? 1 : 0
                sky.update(energy: energy, beat: beat, sun: sun, weather: weather, elapsed: Self.step)
                for star in sky.shootingStars {
                    shootingStars.insert(star.seed)
                    if star.isComet { comets.insert(star.seed) }
                }
                for flock in sky.flocks { flocks.insert(flock.seed) }
                for bolt in sky.bolts { bolts.insert(bolt.seed) }
            }
        }
    }

    @Test func darknessFollowsTheSun() {
        #expect(LiveSky.darkness(sunAltitude: 30) == 0)
        #expect(LiveSky.darkness(sunAltitude: -30) == 1)
        #expect(abs(LiveSky.darkness(sunAltitude: -3) - 0.5) < 0.0001)
    }

    @Test func theMoodFollowsTheMusicOverAFewSeconds() {
        var session = Session()
        session.play(0.5, energy: Self.loud, sun: Self.day, beats: false)
        // Half a second in: still mostly calm.
        #expect(session.sky.intensity < 0.3)
        session.play(15, energy: Self.loud, sun: Self.day, beats: false)
        #expect(session.sky.intensity > 0.9)
        session.play(15, energy: SpectrumEnergy(bass: 0.05, mid: 0.1, treble: 0.5), sun: Self.day, beats: false)
        #expect(session.sky.brightness > 0.8)
    }

    @Test func beatsAtNightSendShootingStarsSpacedByTheMood() {
        var calm = Session()
        calm.play(30, energy: Self.quiet, sun: Self.night)
        var energetic = Session()
        energetic.play(30, energy: Self.loud, sun: Self.night)
        // Calm music: about one every 4 seconds. Energetic: about one a second.
        #expect((7...9).contains(calm.shootingStars.count))
        #expect(energetic.shootingStars.count >= 20)
    }

    @Test func noShootingStarsByDayAndNoBirdsAtNight() {
        var night = Session()
        night.play(5, energy: Self.quiet, sun: Self.night)
        night.play(10, energy: Self.loud, sun: Self.night)
        #expect(night.flocks.isEmpty)
        var day = Session()
        day.play(20, energy: Self.loud, sun: Self.day)
        #expect(day.shootingStars.isEmpty)
    }

    @Test func cometsOnlyInAnEnergeticStretchAndRarely() {
        var calm = Session()
        calm.play(120, energy: Self.quiet, sun: Self.night)
        #expect(calm.comets.isEmpty)

        // Two minutes of energetic music: a comet every 30 seconds at most.
        var energetic = Session()
        energetic.play(120, energy: Self.loud, sun: Self.night)
        #expect((3...4).contains(energetic.comets.count))
    }

    @Test func birdsFlyByDayWhenTheMusicBuildsOrIsEnergetic() {
        // Steady, calm music: no birds.
        var calm = Session()
        calm.play(50, energy: Self.quiet, sun: Self.day)
        #expect(calm.flocks.isEmpty)

        // Energetic music: flocks keep coming, about every 6 seconds.
        var energetic = Session()
        energetic.play(50, energy: Self.loud, sun: Self.day)
        #expect(energetic.flocks.count >= 6)

        // Quiet, then loud: the music builds, and a flock sets off at once.
        var building = Session()
        building.play(10, energy: Self.quiet, sun: Self.day)
        #expect(building.flocks.isEmpty)
        building.play(4, energy: Self.loud, sun: Self.day)
        #expect(building.flocks.count == 1)
        #expect((building.sky.flocks.first?.size ?? 0) >= 3)
    }

    @Test func twilightHasBothShootingStarsAndBirds() {
        var twilight = Session()
        twilight.play(30, energy: Self.loud, sun: SkyClock.Sun(altitude: -4, hourAngle: 100))
        #expect(twilight.shootingStars.count >= 20)
        #expect(twilight.flocks.count >= 3)
    }

    @Test func everyBeatFlashesAndFadesQuickly() {
        var session = Session()
        session.sky.update(energy: Self.loud, beat: 1, sun: Self.night, elapsed: 0.05)
        #expect(session.sky.flash == 1)
        session.play(0.3, energy: Self.loud, sun: Self.night, beats: false)
        #expect(session.sky.flash < 0.01)
        session.play(3, energy: SpectrumEnergy(bass: 0.1, mid: 0.5, treble: 0.1), sun: Self.night, beats: false)
        #expect(session.sky.glow > 0.9)
    }

    @Test func theWindGustsWithTheBassAndTheCloudsKeepMoving() {
        var session = Session()
        session.play(5, energy: Self.quiet, sun: Self.day, beats: false)
        let calmWind = session.sky.wind
        let drift = session.sky.drift
        session.play(5, energy: SpectrumEnergy(bass: 0.7, mid: 0.2, treble: 0.1), sun: Self.day, beats: false)
        #expect(session.sky.wind > calmWind + 0.5)
        #expect(session.sky.drift > drift)
    }

    // MARK: Real weather, amplified

    private static let rain = LiveWeather(cloudCover: 0.9, precipitation: .rain, intensity: 0.65)
    private static let storm = LiveWeather(cloudCover: 0.95, precipitation: .rain, intensity: 1, isThunder: true, windSpeed: 9)
    private static let fog = LiveWeather(cloudCover: 0.7, isFog: true)

    @Test func theMusicAmplifiesTheRealRain() {
        var quiet = Session()
        quiet.play(10, energy: Self.quiet, sun: Self.day, weather: Self.rain)
        var loud = Session()
        loud.play(10, energy: Self.loud, sun: Self.day, weather: Self.rain)
        // Quiet: a bit over half the real strength. Loud: a downpour.
        #expect((0.3...0.5).contains(quiet.sky.precipitation))
        #expect(loud.sky.precipitation > 0.95)
        // No weather, no rain, however loud.
        var dry = Session()
        dry.play(10, energy: Self.loud, sun: Self.day)
        #expect(dry.sky.precipitation == 0)
    }

    @Test func busyMusicThickensTheRealClouds() {
        let partly = LiveWeather(cloudCover: 0.5)
        var quiet = Session()
        quiet.play(10, energy: Self.quiet, sun: Self.day, weather: partly)
        var loud = Session()
        loud.play(10, energy: Self.loud, sun: Self.day, weather: partly)
        #expect(abs(quiet.sky.cloudCover - 0.5) < 0.08)
        #expect(loud.sky.cloudCover > 0.68)
    }

    @Test func lightningOnlyInARealThunderstorm() {
        var storm = Session()
        storm.play(10, energy: Self.loud, sun: Self.day, weather: Self.storm)
        // A beat every half second, and strikes at most every 0.6 s: every other beat.
        #expect(storm.bolts.count >= 9)
        var rain = Session()
        rain.play(10, energy: Self.loud, sun: Self.day, weather: Self.rain)
        #expect(rain.bolts.isEmpty)
    }

    @Test func fogSettlesInCalmMusicAndThinsInBusy() {
        var calm = Session()
        calm.play(15, energy: Self.quiet, sun: Self.day, weather: Self.fog)
        var busy = Session()
        busy.play(15, energy: Self.loud, sun: Self.day, weather: Self.fog)
        #expect(calm.sky.fog > 0.7)
        #expect(busy.sky.fog < 0.5)
    }

    @Test func noBirdsInBadWeatherAndNoShootingStarsUnderCloud() {
        var rain = Session()
        rain.play(30, energy: Self.loud, sun: Self.day, weather: Self.rain)
        #expect(rain.flocks.isEmpty)
        var overcast = Session()
        overcast.play(30, energy: Self.loud, sun: Self.night, weather: LiveWeather(cloudCover: 0.95))
        #expect(overcast.shootingStars.isEmpty)
    }

    @Test func theRealWindBlowsAndTheBassGustsIt() {
        var calm = Session()
        calm.play(5, energy: Self.quiet, sun: Self.day, weather: LiveWeather(cloudCover: 0.3, windSpeed: 1))
        var windy = Session()
        windy.play(5, energy: Self.quiet, sun: Self.day, weather: LiveWeather(cloudCover: 0.3, windSpeed: 14))
        #expect(windy.sky.wind > calm.sky.wind + 0.5)
    }
}
