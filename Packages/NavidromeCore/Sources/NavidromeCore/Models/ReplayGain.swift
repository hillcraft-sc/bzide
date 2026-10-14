import Foundation

/// A song's ReplayGain (OpenSubsonic `replayGain`): how many decibels to turn
/// it up or down to reach a common loudness, for the track alone and for its
/// whole album, and the loudest point of each (1 is full scale). Navidrome
/// has these when the music files are tagged with them.
public struct ReplayGain: Sendable, Equatable, Codable {
    public var trackGain: Double?
    public var albumGain: Double?
    public var trackPeak: Double?
    public var albumPeak: Double?

    public init(trackGain: Double? = nil, albumGain: Double? = nil, trackPeak: Double? = nil, albumPeak: Double? = nil) {
        self.trackGain = trackGain
        self.albumGain = albumGain
        self.trackPeak = trackPeak
        self.albumPeak = albumPeak
    }

    private enum CodingKeys: String, CodingKey { case trackGain, albumGain, trackPeak, albumPeak }

    /// Lenient: a value that isn't a number (or a numeric string) is left out.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys) -> Double? {
            if let value = try? c.decodeIfPresent(Double.self, forKey: key) { return value.isFinite ? value : nil }
            if let text = try? c.decodeIfPresent(String.self, forKey: key) { return Double(text) }
            return nil
        }
        trackGain = number(.trackGain)
        albumGain = number(.albumGain)
        trackPeak = number(.trackPeak)
        albumPeak = number(.albumPeak)
    }

    /// Whether there's a gain to apply at all.
    public var hasGain: Bool { trackGain != nil || albumGain != nil }
}

/// Evening out loudness between songs with their ReplayGain: off, by track
/// (every song to the same loudness) or by album (whole albums to the same
/// loudness, keeping the differences within each album).
public enum VolumeNormalization: String, CaseIterable, Codable, Sendable {
    case off, track, album

    public var title: String {
        switch self {
        case .off: "Off"
        case .track: "By Track"
        case .album: "By Album"
        }
    }

    /// The change to apply, in decibels, or `nil` for none (off, or the song
    /// has no ReplayGain). By album falls back to the track's gain, and the
    /// other way round, when only one is known. A boost is capped so the
    /// song's peak stays at full scale, never clipping.
    public func decibels(for replayGain: ReplayGain?) -> Double? {
        guard self != .off, let replayGain else { return nil }
        let (gain, peak): (Double?, Double?) = self == .album
            ? (replayGain.albumGain ?? replayGain.trackGain, replayGain.albumGain != nil ? replayGain.albumPeak : replayGain.trackPeak)
            : (replayGain.trackGain ?? replayGain.albumGain, replayGain.trackGain != nil ? replayGain.trackPeak : replayGain.albumPeak)
        guard let gain else { return nil }
        guard let peak, peak > 0 else { return gain }
        // At most what brings the peak to 1.0 (0 dB).
        return min(gain, -20 * log10(peak))
    }

    /// The same as a factor to multiply the audio by; 1 for none.
    public func gain(for replayGain: ReplayGain?) -> Float {
        guard let decibels = decibels(for: replayGain) else { return 1 }
        return Float(pow(10, decibels / 20))
    }
}
