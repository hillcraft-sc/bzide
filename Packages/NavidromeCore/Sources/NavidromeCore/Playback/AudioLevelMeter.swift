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
/// whenever it draws. Each tap can also equalize (`EqualizerFilter`, from the
/// shared `EqualizerControl`) and apply a gain (volume normalization), both
/// changeable while it plays; flat and at 1, the audio passes through untouched.
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

    /// A new tap for one player item: it equalizes, applies `gain` and feeds
    /// this meter. Its context (meter, equalizer and gain) is retained by the
    /// tap and released when the tap is finalized.
    func makeTap(gain: TapGain = TapGain(), equalizer: EqualizerControl = EqualizerControl()) -> MTAudioProcessingTap? {
        let context = Unmanaged.passRetained(TapContext(meter: self, gain: gain, equalizer: EqualizerFilter(control: equalizer)))
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: context.toOpaque(),
            init: { _, clientInfo, storageOut in
                storageOut.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                let context = AudioLevelMeter.context(of: tap)
                let description = format.pointee
                let isFloat = description.mFormatFlags & kAudioFormatFlagIsFloat != 0 && description.mBitsPerChannel == 32
                context.isFloat.store(isFloat, ordering: .relaxed)
                context.meter.sampleRateBits.store(description.mSampleRate.bitPattern, ordering: .relaxed)
                context.meter.isFloat.store(isFloat, ordering: .relaxed)
                // Not yet rendering: the filter may reserve its storage here.
                context.equalizer.prepare(sampleRate: description.mSampleRate, channels: Int(description.mChannelsPerFrame))
            },
            unprepare: nil,
            process: { tap, frames, _, bufferList, framesOut, flagsOut in
                // Pass the audio through in place, equalize it, apply the gain,
                // then measure it if wanted (so the visualizer sees what's heard).
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, nil, framesOut) == noErr else { return }
                let context = AudioLevelMeter.context(of: tap)
                let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
                if context.isFloat.load(ordering: .relaxed) {
                    context.equalizer.process(buffers, frames: Int(framesOut.pointee))
                    AudioLevelMeter.apply(context.gain.value, to: buffers)
                }
                guard context.meter.measuring.load(ordering: .relaxed) else { return }
                context.meter.measure(buffers)
            }
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr else {
            context.release()
            return nil
        }
        return tap
    }

    private static func context(of tap: MTAudioProcessingTap) -> TapContext {
        Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    /// Multiplies 32-bit float samples by `gain`, in place. Real-time safe.
    static func apply(_ gain: Float, to buffers: UnsafeMutableAudioBufferListPointer) {
        guard gain != 1 else { return }
        var factor = gain
        for buffer in buffers {
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            vDSP_vsmul(data, 1, &factor, data, 1, vDSP_Length(count))
        }
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

/// The gain one item's tap applies (volume normalization), changeable from
/// the main actor while the audio thread reads it.
public final class TapGain: Sendable {
    private let bits: Atomic<UInt32>

    public init(_ value: Float = 1) {
        bits = Atomic(value.bitPattern)
    }

    public var value: Float {
        get { Float(bitPattern: bits.load(ordering: .relaxed)) }
        set { bits.store(newValue.bitPattern, ordering: .relaxed) }
    }
}

/// What one tap needs on the audio thread: the shared meter, its own
/// equalizer and gain, and whether its format is one they can be applied to.
private final class TapContext: Sendable {
    let meter: AudioLevelMeter
    let gain: TapGain
    let equalizer: EqualizerFilter
    let isFloat = Atomic<Bool>(false)

    init(meter: AudioLevelMeter, gain: TapGain, equalizer: EqualizerFilter) {
        self.meter = meter
        self.gain = gain
        self.equalizer = equalizer
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
