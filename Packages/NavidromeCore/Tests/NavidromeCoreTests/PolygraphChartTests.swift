import Foundation
import Testing
@testable import NavidromeCore

struct PolygraphChartTests {
    private let frame: TimeInterval = 1.0 / 60
    private let quiet = SpectrumEnergy(bass: 0, mid: 0, treble: 0)

    private func run(
        _ chart: inout PolygraphChart, seconds: Double, energy: SpectrumEnergy? = nil,
        loudness: Float = 0, beat: Float = 0, isPlaying: Bool = true
    ) {
        for _ in 0..<Int((seconds * 60).rounded()) {
            chart.update(energy: energy ?? quiet, loudness: loudness, beat: beat, isPlaying: isPlaying, elapsed: frame)
        }
    }

    @Test func thePaperRunsWhilePlaying() {
        var chart = PolygraphChart()
        run(&chart, seconds: 2)
        #expect(abs(chart.travel - 2) < 0.01)
        #expect(abs(chart.samples.count - 2 * PolygraphChart.samplesPerSecond) <= 1)
        #expect(chart.samples.allSatisfy { $0.count == PolygraphChart.penCount })
    }

    @Test func pausedThePaperRunsOnWithFlatLines() {
        var chart = PolygraphChart()
        let music = SpectrumEnergy(bass: 0.4, mid: 0.3, treble: 0.2)
        run(&chart, seconds: 0.3, energy: music, loudness: 0.5)
        let before = chart.samples.count
        run(&chart, seconds: 3, energy: music, loudness: 0.5, isPlaying: false)
        #expect(abs(chart.samples.count - before - 3 * PolygraphChart.samplesPerSecond) <= 1)
        #expect(abs(chart.travel - 3.3) < 0.01)
        // Once the pens have come to rest: straight lines down the middle.
        let settled = chart.samples.suffix(PolygraphChart.samplesPerSecond)
        #expect(settled.allSatisfy { $0.allSatisfy { abs($0) < 0.01 } })
    }

    @Test func playingAgainPicksUpSmoothly() {
        var chart = PolygraphChart()
        let steady = SpectrumEnergy(bass: 0, mid: 0.2, treble: 0)
        run(&chart, seconds: 8, energy: steady)
        // Paused, the music's level drops to nothing; that mustn't count as a change.
        run(&chart, seconds: 3, isPlaying: false)
        run(&chart, seconds: 0.2, energy: steady)
        #expect(abs(chart.pens[1]) < 0.1)
    }

    @Test func silenceDrawsStraightLines() {
        var chart = PolygraphChart()
        run(&chart, seconds: 2)
        #expect(chart.samples.allSatisfy { $0.allSatisfy { $0 == 0 } })
    }

    @Test func aRiseSwingsThePenThenItWandersBack() {
        var chart = PolygraphChart()
        run(&chart, seconds: 1)
        run(&chart, seconds: 0.15, energy: SpectrumEnergy(bass: 0, mid: 0.2, treble: 0))
        #expect(chart.pens[1] > 0.5)
        // Held steady, it becomes the new normal and the pen comes back.
        run(&chart, seconds: 8, energy: SpectrumEnergy(bass: 0, mid: 0.2, treble: 0))
        #expect(abs(chart.pens[1]) < 0.05)
        // A drop swings it the other way.
        run(&chart, seconds: 0.15)
        #expect(chart.pens[1] < -0.5)
    }

    @Test func eachPenFollowsItsOwnPart() {
        var chart = PolygraphChart()
        run(&chart, seconds: 0.15, energy: SpectrumEnergy(bass: 0, mid: 0, treble: 0.3))
        #expect(chart.pens[2] > 0.5)
        #expect(chart.pens[0] == 0)
        #expect(chart.pens[1] == 0)
    }

    @Test func aDrumHitKicksTheBassPen() {
        var chart = PolygraphChart()
        run(&chart, seconds: 0.1, beat: 1)
        #expect(chart.pens[0] > 0.4)
    }

    @Test func loudnessSetsTheHatchingAcrossItsRange() {
        var chart = PolygraphChart()
        // Quieter than a quiet verse: nothing.
        run(&chart, seconds: 1, loudness: 0.1)
        #expect(chart.pens[3] == 0)
        // Halfway between a quiet verse and a loud chorus: half width.
        run(&chart, seconds: 1, loudness: 0.375)
        #expect(abs(chart.pens[3] - 0.5) < 0.02)
        // Louder than the range: full width, no further.
        run(&chart, seconds: 1, loudness: 2)
        #expect(abs(chart.pens[3] - 1) < 0.01)
        #expect(chart.pens[3] <= 1)
    }

    @Test func pensStayInTheirLanes() {
        var chart = PolygraphChart()
        for index in 0..<600 {
            let wild = Float(index % 20 < 10 ? 1 : 0)
            chart.update(energy: SpectrumEnergy(bass: wild, mid: 1 - wild, treble: wild), loudness: wild, beat: wild, isPlaying: true, elapsed: frame)
            #expect(chart.pens.prefix(3).allSatisfy { (-1...1).contains($0) })
            #expect((0...1).contains(chart.pens[3]))
        }
    }

    @Test func oldPaperIsDropped() {
        var chart = PolygraphChart()
        run(&chart, seconds: PolygraphChart.keptSeconds + 5)
        #expect(chart.samples.count == Int(PolygraphChart.keptSeconds) * PolygraphChart.samplesPerSecond)
    }
}
