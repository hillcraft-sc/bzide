import AVFoundation
import Foundation
import Testing
@testable import NavidromeCore

/// Gitea #17: the equalizer.
struct EqualizerMathTests {
    private let sampleRate = 48_000.0

    @Test func eachBandBoostsItsOwnFrequencyByItsGain() {
        for frequency in EqualizerBands.frequencies {
            let filter = BiquadCoefficients.peaking(frequency: frequency, gain: 6, q: EqualizerBands.q, sampleRate: sampleRate)
            #expect(abs(filter.response(at: frequency, sampleRate: sampleRate) - 6) < 0.01, "\(frequency) Hz")
            // Far from it, nearly untouched.
            let far = frequency < 1_000 ? frequency * 16 : frequency / 16
            #expect(abs(filter.response(at: far, sampleRate: sampleRate)) < 0.5, "\(frequency) Hz far")
        }
        let cut = BiquadCoefficients.peaking(frequency: 1_000, gain: -9, q: EqualizerBands.q, sampleRate: sampleRate)
        #expect(abs(cut.response(at: 1_000, sampleRate: sampleRate) + 9) < 0.01)
    }

    @Test func zeroGainAndBandsPastNyquistPassThrough() {
        #expect(BiquadCoefficients.peaking(frequency: 1_000, gain: 0, q: 1.4, sampleRate: sampleRate) == .identity)
        // 16 kHz at a 22.05 kHz sample rate is past Nyquist.
        #expect(BiquadCoefficients.peaking(frequency: 16_000, gain: 6, q: 1.4, sampleRate: 22_050) == .identity)
    }

    @Test func presetsHaveTenGainsInRange() {
        for preset in EqualizerPreset.allCases {
            #expect(preset.gains.count == EqualizerBands.count, "\(preset)")
            #expect(preset.gains.allSatisfy(EqualizerBands.range.contains), "\(preset)")
        }
        #expect(EqualizerPreset.flat.gains.allSatisfy { $0 == 0 })
        #expect(EqualizerBands.headroom(EqualizerPreset.bassBoost.gains) == 6)
        #expect(EqualizerBands.headroom(EqualizerPreset.bassReducer.gains) == 0)
    }

    @Test func labels() {
        #expect(EqualizerBands.label(32) == "32 Hz")
        #expect(EqualizerBands.label(1_000) == "1 kHz")
        #expect(EqualizerBands.label(16_000) == "16 kHz")
    }
}

struct EqualizerSettingsTests {
    @Test func offByDefaultAndForAnythingUnreadable() throws {
        #expect(!EqualizerSettings().isOn)
        let odd = try JSONDecoder().decode(EqualizerSettings.self, from: Data(#"{"preset":"nonsense","customGains":[30,1]}"#.utf8))
        #expect(odd.preset == .flat)
        // Clamped, and padded to ten bands.
        #expect(odd.customGains == [12, 1, 0, 0, 0, 0, 0, 0, 0, 0])
    }

    @Test func offAppliesNothing() {
        let settings = EqualizerSettings(isOn: false, preset: .rock)
        #expect(settings.gains == EqualizerPreset.rock.gains)
        #expect(settings.appliedGains == EqualizerBands.flat)
    }
}

@MainActor
struct EqualizerModelTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "Equalizer-\(UUID().uuidString)") ?? .standard
    }

    @Test func movingABandStartsCustomFromThePreset() {
        let model = EqualizerModel(defaults: defaults(), control: EqualizerControl())
        model.settings.isOn = true
        model.settings.preset = .bassBoost
        model.setGain(3, band: 9)
        #expect(model.settings.preset == .custom)
        #expect(model.settings.gains == [6, 5, 4, 2.5, 1, 0, 0, 0, 0, 3])
        model.setGain(40, band: 0)
        #expect(model.settings.gains[0] == 12)
        model.resetCustom()
        #expect(model.settings.gains == EqualizerBands.flat)
        #expect(model.summary == "Custom")
    }

    @Test func keptAcrossLaunches() {
        let store = defaults()
        let model = EqualizerModel(defaults: store, control: EqualizerControl())
        model.settings = EqualizerSettings(isOn: true, preset: .jazz)
        let again = EqualizerModel(defaults: store, control: EqualizerControl())
        #expect(again.settings == EqualizerSettings(isOn: true, preset: .jazz))
        #expect(again.summary == "Jazz")
    }

}

/// The filter that runs in each song's tap, fed sine waves.
struct EqualizerFilterTests {
    private let sampleRate = 48_000.0
    private let frames = 48_000

    private func sine(_ frequency: Double) -> [Float] {
        (0..<frames).map { Float(0.25 * sin(2 * Double.pi * frequency * Double($0) / sampleRate)) }
    }

    /// Runs `samples` (mono) through the filter in tap-sized buffers; the result.
    private func run(_ filter: EqualizerFilter, _ samples: [Float], buffer: Int = 512) -> [Float] {
        var output = samples
        output.withUnsafeMutableBufferPointer { all in
            var start = 0
            while start < frames {
                let count = min(buffer, frames - start)
                let list = AudioBufferList.allocate(maximumBuffers: 1)
                defer { free(list.unsafeMutablePointer) }
                list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(count * 4), mData: all.baseAddress.map { UnsafeMutableRawPointer($0 + start) })
                filter.process(list, frames: count)
                start += count
            }
        }
        return output
    }

    /// RMS of the second half (after the filter has settled).
    private func level(_ samples: [Float]) -> Double {
        let tail = samples[(frames / 2)...]
        return sqrt(tail.reduce(0) { $0 + Double($1) * Double($1) } / Double(tail.count))
    }

    private func decibels(_ output: [Float], over input: [Float]) -> Double {
        20 * log10(level(output) / level(input))
    }

    @Test func offIsUntouchedBitForBit() {
        let control = EqualizerControl()
        control.update(EqualizerSettings(isOn: false, preset: .rock))
        let filter = EqualizerFilter(control: control)
        filter.prepare(sampleRate: sampleRate, channels: 1)
        let input = sine(1_000)
        #expect(run(filter, input) == input)
        #expect(filter.isTransparent)
    }

    @Test func aBoostedBandIsLouderThanTheRestWithHeadroom() {
        let control = EqualizerControl()
        var gains = EqualizerBands.flat
        gains[5] = 6 // 1 kHz
        control.update(EqualizerSettings(isOn: true, preset: .custom, customGains: gains))
        let filter = EqualizerFilter(control: control)
        filter.prepare(sampleRate: sampleRate, channels: 1)
        // At 1 kHz: +6 dB from the band, −6 dB of headroom: about where it was.
        let atBand = sine(1_000)
        #expect(abs(decibels(run(filter, atBand), over: atBand)) < 0.5)
        // Far from it: just the headroom, about −6 dB.
        let filter2 = EqualizerFilter(control: control)
        filter2.prepare(sampleRate: sampleRate, channels: 1)
        let far = sine(100)
        #expect(abs(decibels(run(filter2, far), over: far) + 6) < 0.5)
    }

    @Test func aCutLowersItsBandOnly() {
        let control = EqualizerControl()
        control.update(EqualizerSettings(isOn: true, preset: .bassReducer))
        let filter = EqualizerFilter(control: control)
        filter.prepare(sampleRate: sampleRate, channels: 1)
        let bass = sine(64)
        #expect(decibels(run(filter, bass), over: bass) < -4)
        let filter2 = EqualizerFilter(control: control)
        filter2.prepare(sampleRate: sampleRate, channels: 1)
        let treble = sine(8_000)
        #expect(abs(decibels(run(filter2, treble), over: treble)) < 0.3)
    }

    @Test func aChangeWhilePlayingGlidesInAndStaysFinite() {
        let control = EqualizerControl()
        control.update(EqualizerSettings(isOn: false))
        let filter = EqualizerFilter(control: control)
        filter.prepare(sampleRate: sampleRate, channels: 1)
        var input = sine(1_000)
        // Turned on mid-song: no jump at the change, nothing blows up.
        let first = run(filter, Array(input[..<frames]))
        _ = first
        control.update(EqualizerSettings(isOn: true, preset: .trebleBoost))
        input = sine(8_000)
        let output = run(filter, input)
        let allFinite = output.allSatisfy { $0.isFinite }
        #expect(allFinite)
        #expect(!filter.isTransparent)
        // Settled: 8 kHz boosted (with its neighbors' overlap), less the 6 dB
        // of headroom: somewhere around unchanged, never far off.
        let change = decibels(output, over: input)
        #expect(change > -3 && change < 4)
        // Back off: passes through again once the ramp ends.
        control.update(EqualizerSettings(isOn: false))
        _ = run(filter, input)
        #expect(filter.isTransparent)
    }

    @Test func stereoInterleavedAndSplitChannelsBothFilter() {
        let control = EqualizerControl()
        control.update(EqualizerSettings(isOn: true, preset: .bassReducer))
        for interleaved in [true, false] {
            let filter = EqualizerFilter(control: control)
            filter.prepare(sampleRate: sampleRate, channels: 2)
            let mono = sine(64)
            var left = mono, right = mono
            var both = mono.flatMap { [$0, $0] }
            let count = 1024
            var start = 0
            while start < frames {
                let n = min(count, frames - start)
                let list = AudioBufferList.allocate(maximumBuffers: interleaved ? 1 : 2)
                if interleaved {
                    both.withUnsafeMutableBufferPointer { pointer in
                        list[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(n * 8), mData: UnsafeMutableRawPointer(pointer.baseAddress! + start * 2))
                        filter.process(list, frames: n)
                    }
                } else {
                    left.withUnsafeMutableBufferPointer { l in
                        right.withUnsafeMutableBufferPointer { r in
                            list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(n * 4), mData: UnsafeMutableRawPointer(l.baseAddress! + start))
                            list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(n * 4), mData: UnsafeMutableRawPointer(r.baseAddress! + start))
                            filter.process(list, frames: n)
                        }
                    }
                }
                free(list.unsafeMutablePointer)
                start += n
            }
            if interleaved {
                let leftOut = stride(from: 0, to: both.count, by: 2).map { both[$0] }
                let rightOut = stride(from: 1, to: both.count, by: 2).map { both[$0] }
                #expect(decibels(leftOut, over: mono) < -4)
                #expect(leftOut == rightOut)
            } else {
                #expect(decibels(left, over: mono) < -4)
                #expect(left == right)
            }
        }
    }
}

/// What the "EQ" indicator is based on: whether a tap is processing audio.
struct EqualizerReachTests {
    @Test func reachesPlaybackOnlyWhileATapIsProcessing() {
        let control = EqualizerControl()
        #expect(!control.processedRecently(now: 5_000_000_000))
        control.markProcessed(at: 5_000_000_000)
        #expect(control.processedRecently(within: 1.5, now: 6_000_000_000))
        // Nothing for two seconds (a radio station, AirPlay, paused): not reaching it.
        #expect(!control.processedRecently(within: 1.5, now: 7_000_000_000))
    }

    @Test func theFilterReportsEachBuffer() {
        let control = EqualizerControl()
        let filter = EqualizerFilter(control: control)
        filter.prepare(sampleRate: 48_000, channels: 1)
        var samples = [Float](repeating: 0.1, count: 256)
        samples.withUnsafeMutableBufferPointer { pointer in
            let list = AudioBufferList.allocate(maximumBuffers: 1)
            defer { free(list.unsafeMutablePointer) }
            list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 1024, mData: UnsafeMutableRawPointer(pointer.baseAddress!))
            filter.process(list, frames: 256)
        }
        #expect(control.processedRecently())
    }
}
