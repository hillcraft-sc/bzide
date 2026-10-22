import Foundation
import Observation

/// A 10-band graphic equalizer's settings: on or off, and a preset or the
/// user's own gains. Kept per iPhone, not per account: it's about the
/// listener's ears and speakers. Applied in each song's audio tap
/// (`EqualizerFilter`).
public struct EqualizerSettings: Codable, Equatable, Sendable {
    public var isOn: Bool
    public var preset: EqualizerPreset
    /// The user's own gains, in dB, one per band; used with `.custom`.
    public var customGains: [Double]

    public init(isOn: Bool = false, preset: EqualizerPreset = .flat, customGains: [Double] = EqualizerBands.flat) {
        self.isOn = isOn
        self.preset = preset
        self.customGains = EqualizerBands.clamped(customGains)
    }

    /// The gains in effect, in dB.
    public var gains: [Double] {
        preset == .custom ? customGains : preset.gains
    }

    /// The gains the audio gets: all 0 while off.
    public var appliedGains: [Double] {
        isOn ? gains : EqualizerBands.flat
    }

    private enum CodingKeys: String, CodingKey { case isOn, preset, customGains }

    /// Anything unreadable takes its default, so a bad value never stops playback.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isOn: (try? c.decodeIfPresent(Bool.self, forKey: .isOn)) ?? false,
            preset: (try? c.decodeIfPresent(EqualizerPreset.self, forKey: .preset)) ?? .flat,
            customGains: (try? c.decodeIfPresent([Double].self, forKey: .customGains)) ?? EqualizerBands.flat
        )
    }
}

/// The bands: one octave apart, from 32 Hz to 16 kHz.
public enum EqualizerBands {
    public static let frequencies: [Double] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    public static var count: Int { frequencies.count }
    /// How far each band can boost or cut, in dB.
    public static let range: ClosedRange<Double> = -12...12
    public static let flat = [Double](repeating: 0, count: 10)
    /// One octave wide, so neighboring bands meet.
    static let q = 1.414

    /// "32 Hz", "1 kHz", "16 kHz".
    public static func label(_ frequency: Double) -> String {
        frequency >= 1_000 ? "\((frequency / 1_000).formatted()) kHz" : "\(Int(frequency)) Hz"
    }

    /// Exactly one gain per band, each within `range`.
    static func clamped(_ gains: [Double]) -> [Double] {
        (0..<count).map { index in
            index < gains.count ? min(max(gains[index], range.lowerBound), range.upperBound) : 0
        }
    }

    /// How much quieter the audio is made so boosted bands don't clip: the
    /// largest boost, in dB (0 when nothing is boosted).
    public static func headroom(_ gains: [Double]) -> Double {
        max(gains.max() ?? 0, 0)
    }
}

public enum EqualizerPreset: String, Codable, CaseIterable, Sendable {
    case flat, bassBoost, bassReducer, trebleBoost, trebleReducer, vocal, loudness, lateNight
    case rock, pop, jazz, classical, electronic, hipHop, acoustic, smallSpeakers
    case custom

    public var title: String {
        switch self {
        case .flat: "Flat"
        case .bassBoost: "Bass Boost"
        case .bassReducer: "Bass Reducer"
        case .trebleBoost: "Treble Boost"
        case .trebleReducer: "Treble Reducer"
        case .vocal: "Vocal"
        case .loudness: "Loudness"
        case .lateNight: "Late Night"
        case .rock: "Rock"
        case .pop: "Pop"
        case .jazz: "Jazz"
        case .classical: "Classical"
        case .electronic: "Electronic"
        case .hipHop: "Hip-Hop"
        case .acoustic: "Acoustic"
        case .smallSpeakers: "Small Speakers"
        case .custom: "Custom"
        }
    }

    /// dB per band, 32 Hz to 16 kHz. Custom's are the user's (`EqualizerSettings.customGains`).
    public var gains: [Double] {
        switch self {
        case .flat, .custom: EqualizerBands.flat
        case .bassBoost: [6, 5, 4, 2.5, 1, 0, 0, 0, 0, 0]
        case .bassReducer: [-6, -5, -4, -2.5, -1, 0, 0, 0, 0, 0]
        case .trebleBoost: [0, 0, 0, 0, 0, 1, 2.5, 4, 5, 6]
        case .trebleReducer: [0, 0, 0, 0, 0, -1, -2.5, -4, -5, -6]
        case .vocal: [-2, -3, -2, 0, 2, 4, 4, 3, 1, 0]
        case .loudness: [5, 4, 2, 0, -1, 0, 0, 1, 3, 4]
        // Softer lows and highs for listening quietly (or near others), voices kept clear.
        case .lateNight: [-3, -2, -1, 0, 1, 2, 2, 1, 0, -1]
        case .rock: [5, 4, 3, 1, -1, -1, 1, 3, 4, 5]
        case .pop: [-1, 0, 1, 3, 4, 3, 1, 0, -1, -1]
        case .jazz: [4, 3, 1, 2, -1, -1, 0, 1, 2, 3]
        case .classical: [4, 3, 2, 1, -1, -1, 0, 2, 3, 4]
        case .electronic: [5, 4, 1, 0, -2, 2, 1, 1, 4, 5]
        case .hipHop: [5, 4, 1, 3, -1, -1, 1, -1, 2, 3]
        case .acoustic: [4, 4, 3, 1, 2, 1, 3, 3, 3, 2]
        // Small speakers can't play deep bass: leave it out, bring voices forward.
        case .smallSpeakers: [-4, -3, -2, 0, 2, 3, 3, 2, 1, 0]
        }
    }
}

/// One band's filter: a peaking EQ biquad (Robert Bristow-Johnson's Audio EQ
/// Cookbook), normalized so a0 is 1. At 0 dB, or for a band at or above
/// Nyquist, it passes the audio through unchanged.
struct BiquadCoefficients: Equatable, Sendable {
    var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double

    static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    static func peaking(frequency: Double, gain: Double, q: Double, sampleRate: Double) -> BiquadCoefficients {
        guard gain != 0, sampleRate > 0, frequency < sampleRate * 0.45 else { return .identity }
        let a = pow(10, gain / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosine = cos(w0)
        let a0 = 1 + alpha / a
        return BiquadCoefficients(
            b0: (1 + alpha * a) / a0,
            b1: -2 * cosine / a0,
            b2: (1 - alpha * a) / a0,
            a1: -2 * cosine / a0,
            a2: (1 - alpha / a) / a0
        )
    }

    /// The gain at `frequency`, in dB. For tests and drawing a curve.
    func response(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        // H(e^jw) = (b0 + b1 e^-jw + b2 e^-2jw) / (1 + a1 e^-jw + a2 e^-2jw)
        let numeratorReal = b0 + b1 * cos(w) + b2 * cos(2 * w)
        let numeratorImaginary = -(b1 * sin(w) + b2 * sin(2 * w))
        let denominatorReal = 1 + a1 * cos(w) + a2 * cos(2 * w)
        let denominatorImaginary = -(a1 * sin(w) + a2 * sin(2 * w))
        let numerator = numeratorReal * numeratorReal + numeratorImaginary * numeratorImaginary
        let denominator = denominatorReal * denominatorReal + denominatorImaginary * denominatorImaginary
        return 10 * log10(numerator / denominator)
    }
}

/// The equalizer's settings for the screens: saved on this iPhone (a device
/// setting, not swapped with the account's) and passed straight to the
/// audio (`EqualizerControl`) on every change.
@MainActor
@Observable
public final class EqualizerModel {
    public var settings: EqualizerSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            control.update(settings)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let control: EqualizerControl
    nonisolated public static let key = "equalizer"

    public init(defaults: UserDefaults = .standard, control: EqualizerControl) {
        self.defaults = defaults
        self.control = control
        settings = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(EqualizerSettings.self, from: $0) } ?? EqualizerSettings()
        control.update(settings)
    }

    /// Moving a band starts from what's in effect: a preset's gains become the
    /// user's own (Custom).
    public func setGain(_ gain: Double, band: Int) {
        guard (0..<EqualizerBands.count).contains(band) else { return }
        var gains = settings.gains
        gains[band] = min(max(gain, EqualizerBands.range.lowerBound), EqualizerBands.range.upperBound)
        settings.customGains = gains
        settings.preset = .custom
    }

    /// Custom back to flat.
    public func resetCustom() {
        settings.customGains = EqualizerBands.flat
    }

    /// Whether the equalizer reaches what's playing now: a song's tap is
    /// processing it. Never for radio stations, whose audio skips taps.
    /// (AirPlay is checked by the app, from the audio route.)
    public var isReachingPlayback: Bool {
        control.processedRecently()
    }

    /// "Off", or the preset's name.
    public var summary: String {
        settings.isOn ? settings.preset.title : "Off"
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
