import Foundation
import Testing
@testable import NavidromeCore

struct WeatherSkyTests {
    private let frame: TimeInterval = 1.0 / 60
    private let calm = SpectrumEnergy(bass: 0.05, mid: 0.05, treble: 0.05)
    private let loud = SpectrumEnergy(bass: 0.8, mid: 0.8, treble: 0.8)

    /// Runs `seconds` of frames with the same music.
    private func play(_ sky: inout WeatherSky, _ energy: SpectrumEnergy, seconds: Double, beat: Float = 0) {
        for _ in 0..<Int(seconds * 60) {
            sky.update(energy: energy, beat: beat, elapsed: frame)
        }
    }

    @Test func calmMusicKeepsTheSkyClearAndDry() {
        var sky = WeatherSky()
        play(&sky, calm, seconds: 20)
        #expect(sky.cloudCover < 0.3)
        #expect(sky.rain == 0)
    }

    @Test func busyMusicBringsCloudsGradually() {
        var sky = WeatherSky()
        play(&sky, loud, seconds: 0.5)
        // Not overcast in an instant.
        #expect(sky.cloudCover < 0.4)
        play(&sky, loud, seconds: 15)
        #expect(sky.cloudCover > 0.9)
    }

    @Test func trebleRainsOnlyWhenItsCloudy() {
        var clear = WeatherSky()
        play(&clear, SpectrumEnergy(bass: 0, mid: 0, treble: 0.6), seconds: 20)
        #expect(clear.rain == 0)

        var stormy = WeatherSky()
        play(&stormy, loud, seconds: 20)
        #expect(stormy.rain > 0.5)
    }

    @Test func bassSetsTheWindAndTheCloudsKeepMoving() {
        var sky = WeatherSky()
        play(&sky, calm, seconds: 5)
        let calmDrift = sky.drift
        #expect(calmDrift > 0)
        play(&sky, SpectrumEnergy(bass: 0.8, mid: 0, treble: 0), seconds: 5)
        #expect(sky.wind > 0.8)
        #expect(sky.drift - calmDrift > calmDrift * 3)
    }

    @Test func aBeatInAStormStrikesOnce() {
        var sky = WeatherSky()
        play(&sky, loud, seconds: 15)
        // A beat that stays high for several frames is one strike.
        play(&sky, loud, seconds: 0.2, beat: 1)
        #expect(sky.bolts.count == 1)
        #expect(sky.flash > 0 && sky.flash <= 0.1)
        // The bolt fades away.
        play(&sky, loud, seconds: 1)
        #expect(sky.bolts.isEmpty)
        #expect(sky.flash == 0)
    }

    @Test func noLightningUnderAClearSky() {
        var sky = WeatherSky()
        play(&sky, calm, seconds: 5)
        sky.update(energy: calm, beat: 1, elapsed: frame)
        #expect(sky.bolts.isEmpty)
    }

    @Test func fastDrumsDontStrobe() {
        var sky = WeatherSky()
        play(&sky, loud, seconds: 15)
        var strikes = 0
        // A beat every 0.2 s for two seconds.
        for index in 0..<120 {
            let before = sky.bolts.filter { $0.age == 0 }.count
            sky.update(energy: loud, beat: index % 12 < 2 ? 1 : 0, elapsed: frame)
            strikes += sky.bolts.filter { $0.age == 0 }.count - before
        }
        #expect(strikes <= 4)
    }

    @Test func aBoltKeepsItsShape() {
        let bolt = LightningBolt(seed: 7, age: 0)
        let older = LightningBolt(seed: 7, age: 0.3)
        #expect(bolt.paths.map { $0.map(\.x) } == older.paths.map { $0.map(\.x) })
        #expect(bolt.paths[0].first?.y == 0)
        #expect(bolt.paths[0].last?.y == 1)
        #expect((0.15...0.85).contains(bolt.x))
        #expect(LightningBolt(seed: 8, age: 0).paths[0].map(\.x) != bolt.paths[0].map(\.x))
    }
}
