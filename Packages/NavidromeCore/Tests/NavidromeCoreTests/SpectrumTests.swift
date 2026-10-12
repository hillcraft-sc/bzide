import AVFoundation
import Foundation
import Testing
@testable import NavidromeCore

struct SpectrumAnalyzerTests {
    private func sine(_ frequency: Double, sampleRate: Double = 44_100, count: Int = AudioLevelMeter.windowCapacity, amplitude: Float = 0.5) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    @Test func aToneLightsItsOwnBand() throws {
        let analyzer = SpectrumAnalyzer()
        for frequency in [100.0, 1_000, 5_000] {
            let levels = analyzer.bands(of: sine(frequency), sampleRate: 44_100)
            let loudest = try #require(levels.indices.max { levels[$0] < levels[$1] })
            #expect(abs(loudest - analyzer.band(containing: frequency)) <= 1, "\(frequency) Hz")
            #expect(levels[loudest] > 0.5)
        }
    }

    @Test func silenceIsFlat() {
        let analyzer = SpectrumAnalyzer()
        let levels = analyzer.bands(of: [Float](repeating: 0, count: analyzer.size), sampleRate: 44_100)
        #expect(levels.count == 40)
        #expect(levels.allSatisfy { $0 == 0 })
    }

    @Test func theWrongNumberOfSamplesGivesNothing() {
        let analyzer = SpectrumAnalyzer()
        #expect(analyzer.bands(of: [0.5, -0.5], sampleRate: 44_100).allSatisfy { $0 == 0 })
    }

    @Test func everyBandCoversAtLeastOneBin() {
        let analyzer = SpectrumAnalyzer()
        for band in 0..<analyzer.bandCount {
            let (low, high) = analyzer.bins(for: band, binWidth: 44_100 / Double(analyzer.size))
            #expect(low >= 1 && low <= high && high < analyzer.size / 2)
        }
    }
}

struct SpectrumSmootherTests {
    @Test func risesQuicklyAndFallsSmoothly() {
        var smoother = SpectrumSmoother(bandCount: 1, rise: 0.5, fallPerSecond: 1)
        smoother.update(toward: [1], elapsed: 1 / 60)
        #expect(smoother.levels[0] == 0.5)
        smoother.update(toward: [1], elapsed: 1 / 60)
        #expect(smoother.levels[0] == 0.75)
        // Falling: at most 1 per second.
        smoother.update(toward: [0], elapsed: 0.25)
        #expect(abs(smoother.levels[0] - 0.5) < 0.0001)
        smoother.update(toward: [0], elapsed: 1)
        #expect(smoother.levels[0] == 0)
    }
}

@MainActor
struct SpectrumFeedTests {
    /// Sends a stereo buffer of a tone through the meter, as the tap would.
    private func play(_ meter: AudioLevelMeter, frequency: Double) {
        var samples = (0..<1024).map { 0.5 * Float(sin(2 * .pi * frequency * Double($0) / 44_100)) }
        var copy = samples
        samples.withUnsafeMutableBytes { left in
            copy.withUnsafeMutableBytes { right in
                let list = AudioBufferList.allocate(maximumBuffers: 2)
                defer { free(list.unsafeMutablePointer) }
                list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(left.count), mData: left.baseAddress)
                list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(right.count), mData: right.baseAddress)
                meter.measure(list)
            }
        }
    }

    @Test func barsFollowTheAudioAndFallWhenItStops() {
        let meter = AudioLevelMeter()
        meter.assumeFloatSamples()
        let feed = SpectrumFeed(meter: meter)
        let start = Date(timeIntervalSince1970: 0)

        play(meter, frequency: 1_000)
        play(meter, frequency: 1_000)
        var levels = feed.update(at: start)
        #expect((levels.max() ?? 0) > 0.2)

        // No new audio for longer than the stale limit: the bars head to zero.
        for frame in 1...120 {
            levels = feed.update(at: start.addingTimeInterval(Double(frame) / 60))
        }
        #expect(levels.allSatisfy { $0 == 0 })
    }

    @Test func theWaveFollowsTheAudioAndFlattensWhenItStops() {
        let meter = AudioLevelMeter()
        meter.assumeFloatSamples()
        let feed = SpectrumFeed(meter: meter)
        let start = Date(timeIntervalSince1970: 0)
        play(meter, frequency: 440)
        play(meter, frequency: 440)
        for frame in 0..<6 {
            feed.update(at: start.addingTimeInterval(Double(frame) / 60))
        }
        #expect(feed.wave.count == SpectrumFeed.wavePointCount)
        #expect((feed.wave.map(abs).max() ?? 0) > 0.3)
        #expect(feed.wave.allSatisfy { (-1...1).contains($0) })

        for frame in 6...200 {
            feed.update(at: start.addingTimeInterval(Double(frame) / 60))
        }
        #expect(feed.wave.allSatisfy { $0 == 0 })
    }

    @Test func theWaveStartsAtARisingZeroCrossing() {
        // A sine that starts falling: the picture should begin where it next rises through zero.
        let samples = (0..<2048).map { -Float(sin(2 * .pi * Double($0) / 100)) }
        let points = SpectrumFeed.wavePoints(from: samples)
        #expect(points.count == SpectrumFeed.wavePointCount)
        // Just past the crossing: at or above zero, well below the peaks, and rising.
        #expect(points[0] >= 0 && points[0] < 0.5)
        #expect(points[1] > points[0])
        #expect(points.max() == 1)
    }

    @Test func flowOnlyMovesForwardAndFasterWhenBusy() {
        let meter = AudioLevelMeter()
        meter.assumeFloatSamples()
        let start = Date(timeIntervalSince1970: 0)

        let quiet = SpectrumFeed(meter: AudioLevelMeter())
        for frame in 0...60 { quiet.update(at: start.addingTimeInterval(Double(frame) / 60)) }
        // A second of silence moves it at the quiet speed.
        #expect(abs(quiet.flow - SpectrumFeed.flowSpeed.quiet) < 0.01)

        let busy = SpectrumFeed(meter: meter)
        var previous = busy.flow
        for frame in 0...60 {
            play(meter, frequency: 1_000)
            busy.update(at: start.addingTimeInterval(Double(frame) / 60))
            #expect(busy.flow >= previous)
            previous = busy.flow
        }
        #expect(busy.flow > quiet.flow)
    }

    @Test func aSuddenBassHitIsABeatThatFades() {
        let meter = AudioLevelMeter()
        meter.assumeFloatSamples()
        let feed = SpectrumFeed(meter: meter)
        let start = Date(timeIntervalSince1970: 0)
        #expect(feed.beat == 0)

        // Silence, then a loud low tone arrives: a beat.
        for frame in 0..<30 { feed.update(at: start.addingTimeInterval(Double(frame) / 60)) }
        var peak: Float = 0
        for frame in 30..<40 {
            play(meter, frequency: 80)
            feed.update(at: start.addingTimeInterval(Double(frame) / 60))
            peak = max(peak, feed.beat)
        }
        #expect(peak > 0.5)

        // The same tone held steady stops counting as a beat; it fades.
        for frame in 40..<160 {
            play(meter, frequency: 80)
            feed.update(at: start.addingTimeInterval(Double(frame) / 60))
        }
        #expect(feed.beat < 0.1)
    }

    @Test func nothingPlayedMeansNoBars() {
        let feed = SpectrumFeed(meter: AudioLevelMeter())
        #expect(feed.update(at: Date()).allSatisfy { $0 == 0 })
    }
}

struct SpectrumEnergyTests {
    @Test func averagesBassMidAndTreble() {
        // 10 bars: 2 bass, 4 mid, 4 treble.
        let energy = SpectrumEnergy(levels: [1, 1, 0.5, 0.5, 0.5, 0.5, 0, 0, 0, 0.4])
        #expect(energy == SpectrumEnergy(bass: 1, mid: 0.5, treble: 0.1))
    }

    @Test func tooFewBarsIsSilence() {
        #expect(SpectrumEnergy(levels: [1, 1]) == SpectrumEnergy(bass: 0, mid: 0, treble: 0))
    }
}
