import Accelerate
import AVFoundation
import MediaToolbox
import Synchronization

/// Live loudness of what's playing, measured by an audio processing tap on each
/// player item. The groundwork for a visualizer (phase 1: prove the tap works
/// without disturbing playback).
///
/// The tap's callbacks run on the real-time audio thread, so they never lock,
/// allocate, or touch the main actor: they measure with vDSP and store plain
/// numbers in atomics, which the UI reads whenever it draws. The audio passes
/// through untouched.
public final class AudioLevelMeter: Sendable {
    private let leftBits = Atomic<UInt32>(0)
    private let rightBits = Atomic<UInt32>(0)
    private let callbacks = Atomic<Int>(0)
    /// Whether the tap's format is 32-bit float, which is what's measured. Set
    /// when the tap is prepared; other formats leave the levels at zero.
    private let isFloat = Atomic<Bool>(false)

    public init() {}

    /// Root-mean-square level of the last buffer per channel, 0...1.
    public var levels: (left: Float, right: Float) {
        (Float(bitPattern: leftBits.load(ordering: .relaxed)), Float(bitPattern: rightBits.load(ordering: .relaxed)))
    }

    /// How many buffers the tap has seen, to tell whether it's running at all.
    public var bufferCount: Int {
        callbacks.load(ordering: .relaxed)
    }

    /// A new tap feeding this meter, for one player item. The meter must outlive
    /// it (the app keeps one for its lifetime): the tap holds it unretained.
    func makeTap() -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(self).toOpaque(),
            init: { _, clientInfo, storageOut in
                storageOut.pointee = clientInfo
            },
            finalize: nil,
            prepare: { tap, _, format in
                let meter = AudioLevelMeter.meter(of: tap)
                let description = format.pointee
                meter.isFloat.store(
                    description.mFormatFlags & kAudioFormatFlagIsFloat != 0 && description.mBitsPerChannel == 32,
                    ordering: .relaxed
                )
            },
            unprepare: nil,
            process: { tap, frames, _, bufferList, framesOut, flagsOut in
                // Pass the audio through in place, then measure it.
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, nil, framesOut) == noErr else { return }
                AudioLevelMeter.meter(of: tap).measure(UnsafeMutableAudioBufferListPointer(bufferList))
            }
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        return status == noErr ? tap : nil
    }

    private static func meter(of tap: MTAudioProcessingTap) -> AudioLevelMeter {
        Unmanaged<AudioLevelMeter>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    /// Real-time safe: no allocation, no locks. One buffer per channel
    /// (non-interleaved) gives left and right; one interleaved buffer gives
    /// both channels' combined level to each.
    func measure(_ buffers: UnsafeMutableAudioBufferListPointer) {
        callbacks.add(1, ordering: .relaxed)
        guard isFloat.load(ordering: .relaxed), let first = buffers.first else { return }
        let left = Self.rms(first)
        let right = buffers.count > 1 ? Self.rms(buffers[1]) : left
        leftBits.store(left.bitPattern, ordering: .relaxed)
        rightBits.store(right.bitPattern, ordering: .relaxed)
    }

    /// For tests: the format is float, as the tap usually reports.
    func assumeFloatSamples() {
        isFloat.store(true, ordering: .relaxed)
    }

    static func rms(_ buffer: AudioBuffer) -> Float {
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        guard count > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return 0 }
        var result: Float = 0
        vDSP_rmsqv(data, 1, &result, vDSP_Length(count))
        return result
    }
}
