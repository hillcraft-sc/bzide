import Accelerate
import AVFoundation
import MediaToolbox
import Synchronization

/// Live loudness and recent samples of what's playing, from an audio processing
/// tap on each player item. Feeds the visualizer.
///
/// The tap's callbacks run on the real-time audio thread, so they never block,
/// allocate, or touch the main actor: levels go into atomics, and samples into
/// a buffer reserved up front, written only if its lock is free at that
/// instant (otherwise that buffer's samples are skipped). The UI reads both
/// whenever it draws. The audio passes through untouched.
public final class AudioLevelMeter: Sendable {
    private let leftBits = Atomic<UInt32>(0)
    private let rightBits = Atomic<UInt32>(0)
    private let callbacks = Atomic<Int>(0)
    /// Whether the tap's format is 32-bit float, which is what's measured. Set
    /// when the tap is prepared; other formats leave the levels at zero.
    private let isFloat = Atomic<Bool>(false)
    private let sampleRateBits = Atomic<UInt64>(44_100.0.bitPattern)
    /// Whether the taps measure. Off, they only pass the audio through.
    private let measuring = Atomic<Bool>(false)
    /// The most recent mono samples, oldest overwritten first.
    private let window = Mutex(SampleWindow(capacity: AudioLevelMeter.windowCapacity))

    /// Enough for the visualizer's 2048-point transform.
    public static let windowCapacity = 2048

    public init() {}

    /// Turning this on and off doesn't touch the player: the taps stay
    /// attached and just start or stop measuring, so playback doesn't hiccup.
    public var isMeasuring: Bool {
        get { measuring.load(ordering: .relaxed) }
        set { measuring.store(newValue, ordering: .relaxed) }
    }

    /// The tap's sample rate, once it has been prepared.
    public var sampleRate: Double {
        Double(bitPattern: sampleRateBits.load(ordering: .relaxed))
    }

    /// Copies the latest `samples.count` mono samples, oldest first. Off the
    /// audio thread only.
    public func copyLatestSamples(into samples: inout [Float]) {
        window.withLock { $0.copyLatest(into: &samples) }
    }

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
                meter.sampleRateBits.store(description.mSampleRate.bitPattern, ordering: .relaxed)
                meter.isFloat.store(
                    description.mFormatFlags & kAudioFormatFlagIsFloat != 0 && description.mBitsPerChannel == 32,
                    ordering: .relaxed
                )
            },
            unprepare: nil,
            process: { tap, frames, _, bufferList, framesOut, flagsOut in
                // Pass the audio through in place, then measure it if wanted.
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, nil, framesOut) == noErr else { return }
                let meter = AudioLevelMeter.meter(of: tap)
                guard meter.measuring.load(ordering: .relaxed) else { return }
                meter.measure(UnsafeMutableAudioBufferListPointer(bufferList))
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
        // Never wait for the UI: if it's reading right now, skip these samples.
        _ = window.withLockIfAvailable { $0.append(buffers) }
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

/// A fixed-size ring of mono samples. Its storage is allocated once, so
/// appending on the audio thread never allocates.
struct SampleWindow: Sendable {
    private var samples: [Float]
    private var next = 0

    init(capacity: Int) {
        samples = [Float](repeating: 0, count: capacity)
    }

    /// Mixes the buffers to mono: one buffer per channel (non-interleaved,
    /// the tap's usual format) is averaged across the first two; one
    /// interleaved buffer is averaged across its channels.
    mutating func append(_ buffers: UnsafeMutableAudioBufferListPointer) {
        guard let first = buffers.first, let left = first.mData?.assumingMemoryBound(to: Float.self) else { return }
        let channelsInFirst = max(Int(first.mNumberChannels), 1)
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channelsInFirst
        let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        for frame in 0..<frames {
            let value: Float
            if let right {
                value = (left[frame] + right[frame]) * 0.5
            } else if channelsInFirst > 1 {
                value = (left[frame * channelsInFirst] + left[frame * channelsInFirst + 1]) * 0.5
            } else {
                value = left[frame]
            }
            samples[next] = value
            next = (next + 1) % samples.count
        }
    }

    /// The latest `out.count` samples (at most the capacity), oldest first.
    func copyLatest(into out: inout [Float]) {
        let count = min(out.count, samples.count)
        var index = (next - count + samples.count) % samples.count
        for position in 0..<count {
            out[position] = samples[index]
            index = (index + 1) % samples.count
        }
    }
}
