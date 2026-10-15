import Foundation
import Observation

/// How good streamed audio is. Anything but `.original` asks the server to
/// transcode to MP3 at that bitrate.
public enum StreamQuality: Int, CaseIterable, Codable, Sendable {
    case original = 0
    case kbps320 = 320
    case kbps256 = 256
    case kbps192 = 192
    case kbps128 = 128
    case kbps96 = 96

    public var title: String {
        self == .original ? "Original" : "\(rawValue) kbps"
    }

    /// `nil` means no transcoding.
    public var maxBitRate: Int? {
        self == .original ? nil : rawValue
    }
}

public struct StreamingSettings: Codable, Sendable, Equatable {
    public var wifiQuality: StreamQuality
    public var cellularQuality: StreamQuality
    /// Off by default: downloads wait for Wi-Fi.
    public var downloadOverCellular: Bool
    /// Original by default. Applies to songs downloaded after it changes.
    public var downloadQuality: StreamQuality
    /// Off by default: when the server has no lyrics for a song, look them up
    /// on LRCLIB. That sends the song's title, artist, album and length there.
    public var findLyricsOnline: Bool
    /// Off by default: evening out loudness with the songs' ReplayGain.
    public var volumeNormalization: VolumeNormalization
    /// Off by default: when a queue reaches its last song, spin off from it
    /// so the music keeps going (see `SpinOffModel`).
    public var keepSpinning: Bool

    public init(
        wifiQuality: StreamQuality = .original, cellularQuality: StreamQuality = .kbps192,
        downloadOverCellular: Bool = false, downloadQuality: StreamQuality = .original,
        findLyricsOnline: Bool = false, volumeNormalization: VolumeNormalization = .off, keepSpinning: Bool = false
    ) {
        self.wifiQuality = wifiQuality
        self.cellularQuality = cellularQuality
        self.downloadOverCellular = downloadOverCellular
        self.downloadQuality = downloadQuality
        self.findLyricsOnline = findLyricsOnline
        self.volumeNormalization = volumeNormalization
        self.keepSpinning = keepSpinning
    }

    private enum CodingKeys: String, CodingKey {
        case wifiQuality, cellularQuality, downloadOverCellular, downloadQuality, findLyricsOnline, volumeNormalization, keepSpinning
    }

    /// A setting missing from what was saved (added in a later version) takes its
    /// default; the others are kept.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = StreamingSettings()
        wifiQuality = try c.decodeIfPresent(StreamQuality.self, forKey: .wifiQuality) ?? defaults.wifiQuality
        cellularQuality = try c.decodeIfPresent(StreamQuality.self, forKey: .cellularQuality) ?? defaults.cellularQuality
        downloadOverCellular = try c.decodeIfPresent(Bool.self, forKey: .downloadOverCellular) ?? defaults.downloadOverCellular
        downloadQuality = try c.decodeIfPresent(StreamQuality.self, forKey: .downloadQuality) ?? defaults.downloadQuality
        findLyricsOnline = try c.decodeIfPresent(Bool.self, forKey: .findLyricsOnline) ?? defaults.findLyricsOnline
        volumeNormalization = (try? c.decodeIfPresent(VolumeNormalization.self, forKey: .volumeNormalization)) ?? defaults.volumeNormalization
        keepSpinning = (try? c.decodeIfPresent(Bool.self, forKey: .keepSpinning)) ?? defaults.keepSpinning
    }
}

/// The user's streaming settings, saved to `UserDefaults` on every change.
/// Nothing secret lives here.
@MainActor
@Observable
public final class StreamingSettingsModel {
    public var settings: StreamingSettings {
        didSet { save() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    static let key = "streamingSettings"

    /// Saved settings that can't be read (say, from a newer app version) are
    /// replaced by the defaults rather than blocking playback.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(StreamingSettings.self, from: $0) }
            ?? StreamingSettings()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
