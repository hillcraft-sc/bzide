import AVFoundation
import Testing
@testable import NavidromeCore

struct AudioLevelMeterTests {
    /// Measures a two-channel, non-interleaved float buffer list, as the tap gets.
    private func measure(left: [Float], right: [Float], meter: AudioLevelMeter) {
        var left = left
        var right = right
        left.withUnsafeMutableBytes { leftBytes in
            right.withUnsafeMutableBytes { rightBytes in
                let list = AudioBufferList.allocate(maximumBuffers: 2)
                defer { free(list.unsafeMutablePointer) }
                list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(leftBytes.count), mData: leftBytes.baseAddress)
                list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(rightBytes.count), mData: rightBytes.baseAddress)
                meter.measure(list)
            }
        }
    }

    @Test func measuresEachChannelsLoudness() {
        let meter = AudioLevelMeter()
        meter.assumeFloatSamples()
        // A full-scale sine has an RMS of 1/√2; silence has 0.
        let sine = (0..<512).map { Float(sin(Double($0) * 2 * .pi / 64)) }
        measure(left: sine, right: [Float](repeating: 0, count: 512), meter: meter)
        #expect(abs(meter.levels.left - 0.7071) < 0.001)
        #expect(meter.levels.right == 0)
        #expect(meter.bufferCount == 1)
    }

    @Test func aFormatItCantReadLeavesTheLevelsAlone() {
        let meter = AudioLevelMeter()
        measure(left: [1, -1, 1, -1], right: [1, -1, 1, -1], meter: meter)
        #expect(meter.levels.left == 0)
        // Still counted, so a running tap is visible even then.
        #expect(meter.bufferCount == 1)
    }

    @Test func aTapCanBeMade() {
        #expect(AudioLevelMeter().makeTap() != nil)
    }
}
