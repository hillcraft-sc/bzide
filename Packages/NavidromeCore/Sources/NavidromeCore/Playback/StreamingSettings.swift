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
    /// Off by default: searching Radio Browser for stations, which sends the
    /// search there and counts plays of stations found there.
    public var findStationsOnline: Bool
    /// Off by default: looking up the song a station is playing on
    /// MusicBrainz (Song Info and the album cover), which sends its artist and title there.
    public var lookUpSongsOnline: Bool
    /// Off by default: an artist's page adds a Wikipedia biography and the
    /// releases the user doesn't have, from MusicBrainz, which sends the
    /// artist's name or MusicBrainz id there.
    public var lookUpArtistsOnline: Bool
    /// Off by default: Weather (Live) asks MET Norway for the weather where
    /// the user is, which sends rounded coordinates there.
    public var liveWeather: Bool
    /// Where the weather is for: the phone's location (asked for once), and
    /// failing that, or with this off, the city typed in Settings.
    public var liveWeatherUsesLocation: Bool
    /// What's typed in the Place field: a city and state, or a postal code.
    public var liveWeatherCity: String
    /// What Apple's geocoder matched it to, once looked up.
    public var liveWeatherPlace: LiveWeatherPlace?
    /// How Spin the Dial picks stations.
    public var spinTheDial: DialSettings
    /// Off by default: evening out loudness with the songs' ReplayGain.
    public var volumeNormalization: VolumeNormalization
    /// Off by default: when a queue reaches its last song, spin off from it
    /// so the music keeps going (see `SpinOffModel`).
    public var keepSpinning: Bool
    /// Off by default: Random Mix, Spin Off and Keep Spinning leave out songs
    /// rated Meh.
    public var includeMehInMixes: Bool
    /// On by default: favorites (hearts) are in My Cuts, as well as songs
    /// rated Love or Like.
    public var myCutsIncludeFavorites: Bool

    public init(
        wifiQuality: StreamQuality = .original, cellularQuality: StreamQuality = .kbps192,
        downloadOverCellular: Bool = false, downloadQuality: StreamQuality = .original,
        findLyricsOnline: Bool = false, findStationsOnline: Bool = false, lookUpSongsOnline: Bool = false, lookUpArtistsOnline: Bool = false,
        liveWeather: Bool = false, liveWeatherUsesLocation: Bool = true, liveWeatherCity: String = "", liveWeatherPlace: LiveWeatherPlace? = nil, spinTheDial: DialSettings = DialSettings(), volumeNormalization: VolumeNormalization = .off, keepSpinning: Bool = false,
        includeMehInMixes: Bool = false, myCutsIncludeFavorites: Bool = true
    ) {
        self.wifiQuality = wifiQuality
        self.cellularQuality = cellularQuality
        self.downloadOverCellular = downloadOverCellular
        self.downloadQuality = downloadQuality
        self.findLyricsOnline = findLyricsOnline
        self.findStationsOnline = findStationsOnline
        self.lookUpSongsOnline = lookUpSongsOnline
        self.lookUpArtistsOnline = lookUpArtistsOnline
        self.liveWeather = liveWeather
        self.liveWeatherUsesLocation = liveWeatherUsesLocation
        self.liveWeatherCity = liveWeatherCity
        self.liveWeatherPlace = liveWeatherPlace
        self.spinTheDial = spinTheDial
        self.volumeNormalization = volumeNormalization
        self.keepSpinning = keepSpinning
        self.includeMehInMixes = includeMehInMixes
        self.myCutsIncludeFavorites = myCutsIncludeFavorites
    }

    private enum CodingKeys: String, CodingKey {
        case wifiQuality, cellularQuality, downloadOverCellular, downloadQuality, findLyricsOnline, findStationsOnline, lookUpSongsOnline, lookUpArtistsOnline, liveWeather, liveWeatherUsesLocation, liveWeatherCity, liveWeatherPlace, spinTheDial, volumeNormalization, keepSpinning, includeMehInMixes, myCutsIncludeFavorites
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
        findStationsOnline = (try? c.decodeIfPresent(Bool.self, forKey: .findStationsOnline)) ?? defaults.findStationsOnline
        lookUpSongsOnline = (try? c.decodeIfPresent(Bool.self, forKey: .lookUpSongsOnline)) ?? defaults.lookUpSongsOnline
        lookUpArtistsOnline = (try? c.decodeIfPresent(Bool.self, forKey: .lookUpArtistsOnline)) ?? defaults.lookUpArtistsOnline
        liveWeather = (try? c.decodeIfPresent(Bool.self, forKey: .liveWeather)) ?? defaults.liveWeather
        liveWeatherUsesLocation = (try? c.decodeIfPresent(Bool.self, forKey: .liveWeatherUsesLocation)) ?? defaults.liveWeatherUsesLocation
        liveWeatherCity = (try? c.decodeIfPresent(String.self, forKey: .liveWeatherCity)) ?? defaults.liveWeatherCity
        liveWeatherPlace = (try? c.decodeIfPresent(LiveWeatherPlace.self, forKey: .liveWeatherPlace)) ?? nil
        spinTheDial = (try? c.decodeIfPresent(DialSettings.self, forKey: .spinTheDial)) ?? defaults.spinTheDial
        volumeNormalization = (try? c.decodeIfPresent(VolumeNormalization.self, forKey: .volumeNormalization)) ?? defaults.volumeNormalization
        keepSpinning = (try? c.decodeIfPresent(Bool.self, forKey: .keepSpinning)) ?? defaults.keepSpinning
        includeMehInMixes = (try? c.decodeIfPresent(Bool.self, forKey: .includeMehInMixes)) ?? defaults.includeMehInMixes
        myCutsIncludeFavorites = (try? c.decodeIfPresent(Bool.self, forKey: .myCutsIncludeFavorites)) ?? defaults.myCutsIncludeFavorites
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
        settings = Self.load(defaults)
    }

    /// Reads them again, after another account's settings were put in place.
    public func reload() {
        settings = Self.load(defaults)
    }

    private static func load(_ defaults: UserDefaults) -> StreamingSettings {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(StreamingSettings.self, from: $0) } ?? StreamingSettings()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
