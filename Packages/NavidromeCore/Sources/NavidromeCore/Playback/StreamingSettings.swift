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
    var maxBitRate: Int? {
        self == .original ? nil : rawValue
    }
}

public struct StreamingSettings: Codable, Sendable, Equatable {
    public var wifiQuality: StreamQuality
    public var cellularQuality: StreamQuality

    public init(wifiQuality: StreamQuality = .original, cellularQuality: StreamQuality = .kbps192) {
        self.wifiQuality = wifiQuality
        self.cellularQuality = cellularQuality
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
