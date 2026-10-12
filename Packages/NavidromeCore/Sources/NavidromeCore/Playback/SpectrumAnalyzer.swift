import Accelerate
import Foundation

/// Turns the latest samples into bar heights for the visualizer: a windowed
/// Fourier transform, grouped into bands spaced like musical pitch (each about
/// the same number of semitones), on a decibel scale so quiet passages still
/// move. Runs off the audio thread, once per frame.
public final class SpectrumAnalyzer {
    public let bandCount: Int
    public let size: Int

    private let fft: vDSP.FFT<DSPSplitComplex>?
    private let hann: [Float]
    private let minFrequency: Double
    private let maxFrequency: Double

    // Scratch space, allocated once.
    private var windowed: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var power: [Float]

    /// Below this a band shows as empty; at `ceilingDB` it's full height.
    static let floorDB: Float = -75
    static let ceilingDB: Float = -15

    public init(bandCount: Int = 40, size: Int = AudioLevelMeter.windowCapacity, minFrequency: Double = 60, maxFrequency: Double = 16_000) {
        self.bandCount = bandCount
        self.size = size
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
        fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(size)).rounded()), radix: .radix2, ofType: DSPSplitComplex.self)
        hann = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        windowed = [Float](repeating: 0, count: size)
        real = [Float](repeating: 0, count: size / 2)
        imaginary = [Float](repeating: 0, count: size / 2)
        power = [Float](repeating: 0, count: size / 2)
    }

    /// Band levels 0...1, bass first. `samples` must hold `size` samples.
    public func bands(of samples: [Float], sampleRate: Double) -> [Float] {
        guard let fft, samples.count == size, sampleRate > 0 else {
            return [Float](repeating: 0, count: bandCount)
        }
        vDSP.multiply(samples, hann, result: &windowed)
        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                guard let realBase = realBuffer.baseAddress, let imaginaryBase = imaginaryBuffer.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imaginaryBase)
                windowed.withUnsafeBytes { bytes in
                    guard let complex = bytes.bindMemory(to: DSPComplex.self).baseAddress else { return }
                    vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(size / 2))
                }
                fft.forward(input: split, output: &split)
                vDSP.squareMagnitudes(split, result: &power)
            }
        }
        // vDSP's real transform comes out scaled by 2·n relative to amplitude.
        let scale = 1 / Float(size * size)
        let binWidth = sampleRate / Double(size)
        var levels = [Float](repeating: 0, count: bandCount)
        for band in 0..<bandCount {
            let (low, high) = bins(for: band, binWidth: binWidth)
            var peak: Float = 0
            for bin in low...high {
                peak = max(peak, power[bin])
            }
            let decibels = 10 * log10(peak * scale + 1e-12)
            levels[band] = min(max((decibels - Self.floorDB) / (Self.ceilingDB - Self.floorDB), 0), 1)
        }
        return levels
    }

    /// The FFT bins a band covers. Bands are spaced evenly in log frequency; a
    /// low band narrower than one bin uses the bin it falls in.
    func bins(for band: Int, binWidth: Double) -> (low: Int, high: Int) {
        let ratio = maxFrequency / minFrequency
        let lowFrequency = minFrequency * pow(ratio, Double(band) / Double(bandCount))
        let highFrequency = minFrequency * pow(ratio, Double(band + 1) / Double(bandCount))
        let last = size / 2 - 1
        let low = min(max(Int((lowFrequency / binWidth).rounded(.down)), 1), last)
        let high = min(max(Int((highFrequency / binWidth).rounded(.down)), low), last)
        return (low, high)
    }

    /// The band a frequency falls in, for tests.
    func band(containing frequency: Double) -> Int {
        let position = log(frequency / minFrequency) / log(maxFrequency / minFrequency)
        return min(max(Int(position * Double(bandCount)), 0), bandCount - 1)
    }
}

/// Makes bars move like a meter: they jump up quickly and fall back slowly.
public struct SpectrumSmoother: Sendable {
    public private(set) var levels: [Float]
    /// How much of the way up to a higher level each frame goes.
    let rise: Float
    /// Full height per second that a bar can fall.
    let fallPerSecond: Float

    public init(bandCount: Int, rise: Float = 0.6, fallPerSecond: Float = 1.6) {
        levels = [Float](repeating: 0, count: bandCount)
        self.rise = rise
        self.fallPerSecond = fallPerSecond
    }

    /// Moves toward `target` for a frame lasting `elapsed` seconds.
    public mutating func update(toward target: [Float], elapsed: TimeInterval) {
        let fall = fallPerSecond * Float(max(elapsed, 0))
        for index in levels.indices {
            let goal = index < target.count ? target[index] : 0
            if goal > levels[index] {
                levels[index] += (goal - levels[index]) * rise
            } else {
                levels[index] = max(goal, levels[index] - fall)
            }
        }
    }
}

/// What the visualizer draws each frame: the meter's latest samples, analysed
/// and smoothed. When no new audio has arrived for a moment (paused, between
/// items, or the tap isn't running), the bars fall to nothing instead of
/// freezing on the last frame.
@MainActor
public final class SpectrumFeed {
    public var levels: [Float] { smoother.levels }
    /// The sound wave for the waveform style: `wavePointCount` points, -1...1.
    public private(set) var wave: [Float]

    private let meter: AudioLevelMeter
    private let analyzer: SpectrumAnalyzer
    private var smoother: SpectrumSmoother
    private var samples: [Float]
    private var lastBufferCount = -1
    private var lastNewAudio: Date = .distantPast
    private var lastFrame: Date?

    /// No new buffers for this long means the audio has stopped.
    static let staleAfter: TimeInterval = 0.25
    public static let wavePointCount = 128
    /// Samples the waveform shows, starting at a rising zero crossing so the
    /// picture holds still from frame to frame like an oscilloscope's.
    static let waveSpan = 512
    /// Music rarely nears full scale; this makes a typical song fill the height.
    static let waveGain: Float = 2.5

    public init(meter: AudioLevelMeter, bandCount: Int = 40) {
        self.meter = meter
        analyzer = SpectrumAnalyzer(bandCount: bandCount)
        smoother = SpectrumSmoother(bandCount: bandCount)
        samples = [Float](repeating: 0, count: analyzer.size)
        wave = [Float](repeating: 0, count: Self.wavePointCount)
    }

    /// Advances to `time` (one call per drawn frame) and returns the bar heights.
    @discardableResult
    public func update(at time: Date) -> [Float] {
        let count = meter.bufferCount
        if count != lastBufferCount {
            lastBufferCount = count
            lastNewAudio = time
        }
        let target: [Float]
        let isFresh = time.timeIntervalSince(lastNewAudio) < Self.staleAfter
        if isFresh {
            meter.copyLatestSamples(into: &samples)
            target = analyzer.bands(of: samples, sampleRate: meter.sampleRate)
        } else {
            target = []
        }
        updateWave(isFresh: isFresh)
        let elapsed = lastFrame.map { time.timeIntervalSince($0) } ?? 0
        lastFrame = time
        smoother.update(toward: target, elapsed: min(elapsed, 0.1))
        return smoother.levels
    }

    /// Eases the wave toward the latest samples, or toward flat when the audio
    /// has stopped, so it neither jitters nor freezes.
    private func updateWave(isFresh: Bool) {
        let target = isFresh ? Self.wavePoints(from: samples) : [Float](repeating: 0, count: Self.wavePointCount)
        for index in wave.indices {
            wave[index] += (target[index] - wave[index]) * 0.5
            if abs(wave[index]) < 0.001 { wave[index] = 0 }
        }
    }

    /// `waveSpan` samples from the first rising zero crossing, averaged down to
    /// `wavePointCount` points and scaled to -1...1.
    static func wavePoints(from samples: [Float]) -> [Float] {
        let span = min(waveSpan, samples.count)
        let searchEnd = max(samples.count - span, 1)
        var start = 0
        for index in 1..<searchEnd where samples[index - 1] < 0 && samples[index] >= 0 {
            start = index
            break
        }
        let perPoint = max(span / wavePointCount, 1)
        return (0..<wavePointCount).map { point in
            let from = start + point * perPoint
            let to = min(from + perPoint, samples.count)
            guard from < to else { return 0 }
            let average = samples[from..<to].reduce(0, +) / Float(to - from)
            return min(max(average * waveGain, -1), 1)
        }
    }
}
