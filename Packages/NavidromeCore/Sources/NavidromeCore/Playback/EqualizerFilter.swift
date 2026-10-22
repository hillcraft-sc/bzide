import AVFoundation
import Foundation
import Synchronization

/// The equalizer's current gains, shared by every song's tap. Written from the
/// main actor (`EqualizerModel`); read on the audio thread, which never waits
/// for it: a tap that finds it busy picks the change up on its next buffer.
public final class EqualizerControl: Sendable {
    private let gains = Mutex<[Float]>([Float](repeating: 0, count: EqualizerBands.count))
    private let version = Atomic<Int>(0)
    /// When a tap last processed audio (uptime nanoseconds), so the screens
    /// can tell whether the equalizer reaches what's playing: radio stations
    /// and AirPlay bypass taps entirely.
    private let lastProcessed = Atomic<UInt64>(0)

    public init() {}

    public func update(_ settings: EqualizerSettings) {
        let applied = settings.appliedGains.map(Float.init)
        gains.withLock { stored in
            for index in stored.indices { stored[index] = applied[index] }
        }
        version.add(1, ordering: .releasing)
    }

    var currentVersion: Int { version.load(ordering: .acquiring) }

    /// Real-time safe: a clock read and an atomic store.
    func markProcessed(at now: UInt64 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) {
        lastProcessed.store(now, ordering: .relaxed)
    }

    /// Whether a tap processed audio within `seconds`.
    public func processedRecently(within seconds: Double = 1.5, now: UInt64 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) -> Bool {
        let last = lastProcessed.load(ordering: .relaxed)
        return last != 0 && now >= last && Double(now - last) / 1_000_000_000 <= seconds
    }

    /// Copies the gains into `target` without allocating; `false` if the
    /// lock was busy (try again next buffer).
    func copyGains(into target: inout [Float]) -> Bool {
        gains.withLockIfAvailable { stored in
            for index in stored.indices where index < target.count { target[index] = stored[index] }
            return true
        } ?? false
    }
}

/// One song's equalizer, run in its audio tap on the real-time thread: a
/// peaking biquad per band per channel, after lowering the level by the
/// largest boost so boosted bands don't clip. All storage is reserved in
/// `prepare` (when the format is known), so `process` never allocates or
/// waits. Changes glide over `rampFrames` frames, so moving a slider doesn't
/// click. While everything is flat (the equalizer off, or all at 0 dB), the
/// audio passes through untouched.
///
/// Only touched from the tap's own callbacks, one at a time.
final class EqualizerFilter: @unchecked Sendable {
    /// How long a change takes to settle: about 20 ms at 48 kHz.
    static let rampFrames = 1024
    /// Coefficients move toward their targets once per block of this many frames.
    static let blockFrames = 64

    private let control: EqualizerControl
    private var seenVersion = -1
    private var sampleRate: Double = 0
    private var gains: [Float]
    /// Per band: b0, b1, b2, a1, a2. Current and where they're heading.
    private var current: [Double]
    private var target: [Double]
    private var preamp: Double = 1
    private var targetPreamp: Double = 1
    private var rampLeft = 0
    /// Per channel, per band: the two state values of a transposed direct-form II biquad.
    private var state: [Double] = []
    private var channels = 0

    init(control: EqualizerControl) {
        _ = Self.identity
        self.control = control
        let bands = EqualizerBands.count
        gains = [Float](repeating: 0, count: bands)
        // Each its own storage, built here: arrays sharing storage would be
        // copied (allocating) on their first write, on the audio thread.
        current = Self.makeIdentity()
        target = Self.makeIdentity()
    }

    /// Called when the tap learns the format. May allocate.
    func prepare(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = max(channels, 1)
        state = [Double](repeating: 0, count: self.channels * EqualizerBands.count * 2)
        seenVersion = -1
        // Start at the settings as they are, without a ramp.
        refreshTarget()
        arrive()
    }

    /// Whether the filter changes nothing now (and isn't about to).
    var isTransparent: Bool {
        rampLeft == 0 && preamp == 1 && current == Self.identity
    }

    /// Equalizes 32-bit float samples in place: one buffer per channel, or
    /// interleaved channels in one buffer.
    func process(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        guard sampleRate > 0 else { return }
        if frames > 0 { control.markProcessed() }
        if control.currentVersion != seenVersion { refreshTarget(ramping: true) }
        guard !isTransparent, frames > 0 else { return }

        var start = 0
        while start < frames {
            let count = min(Self.blockFrames, frames - start)
            stepRamp(count)
            var channel = 0
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let stride = max(Int(buffer.mNumberChannels), 1)
                for offset in 0..<stride where channel < channels {
                    filter(data + start * stride + offset, count: count, stride: stride, channel: channel)
                    channel += 1
                }
            }
            start += count
        }
    }

    // MARK: - Steps

    /// Picks up new gains (if the control isn't busy) and works out where the
    /// coefficients should head.
    private func refreshTarget(ramping: Bool = false) {
        let version = control.currentVersion
        guard control.copyGains(into: &gains) else { return }
        seenVersion = version
        var largestBoost: Float = 0
        for band in 0..<EqualizerBands.count {
            let coefficients = BiquadCoefficients.peaking(
                frequency: EqualizerBands.frequencies[band], gain: Double(gains[band]), q: EqualizerBands.q, sampleRate: sampleRate
            )
            let base = band * 5
            target[base] = coefficients.b0
            target[base + 1] = coefficients.b1
            target[base + 2] = coefficients.b2
            target[base + 3] = coefficients.a1
            target[base + 4] = coefficients.a2
            largestBoost = max(largestBoost, gains[band])
        }
        targetPreamp = pow(10, -Double(largestBoost) / 20)
        if ramping { rampLeft = Self.rampFrames }
    }

    /// Moves the coefficients and preamp toward their targets, arriving exactly.
    private func stepRamp(_ count: Int) {
        guard rampLeft > 0 else { return }
        let fraction = min(Double(count) / Double(rampLeft), 1)
        for index in current.indices {
            current[index] += (target[index] - current[index]) * fraction
        }
        preamp += (targetPreamp - preamp) * fraction
        rampLeft = max(rampLeft - count, 0)
        if rampLeft == 0 { arrive() }
    }

    /// At the targets exactly, copied element by element (no allocation).
    private func arrive() {
        for index in current.indices { current[index] = target[index] }
        preamp = targetPreamp
        rampLeft = 0
    }

    private func filter(_ samples: UnsafeMutablePointer<Float>, count: Int, stride: Int, channel: Int) {
        let bands = EqualizerBands.count
        let stateBase = channel * bands * 2
        for frame in 0..<count {
            let index = frame * stride
            var sample = Double(samples[index]) * preamp
            for band in 0..<bands {
                let c = band * 5
                let s = stateBase + band * 2
                let output = current[c] * sample + state[s]
                state[s] = current[c + 1] * sample - current[c + 3] * output + state[s + 1]
                state[s + 1] = current[c + 2] * sample - current[c + 4] * output
                sample = output
            }
            samples[index] = Float(sample)
        }
    }

    /// Every band passing the audio through: b0 1, the rest 0. Read-only
    /// (compared against), built once, before any audio runs.
    private static let identity = makeIdentity()

    private static func makeIdentity() -> [Double] {
        var coefficients = [Double](repeating: 0, count: EqualizerBands.count * 5)
        for band in 0..<EqualizerBands.count { coefficients[band * 5] = 1 }
        return coefficients
    }
}
