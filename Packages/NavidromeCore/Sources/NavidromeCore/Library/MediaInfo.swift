import Foundation

/// One line of an Info screen: what it is, and its value.
public struct InfoRow: Sendable, Equatable {
    public var label: String
    public var value: String
}

/// A group of Info rows under a heading.
public struct InfoSection: Sendable, Equatable {
    public var title: String
    public var rows: [InfoRow]
}

/// What a song's or album's Info screen shows, and an album page's details
/// line. Only what the server said appears: a row without a value is left
/// out, and so is a section with no rows.
public enum MediaInfo {
    public static func sections(for song: Song, simplifiedRating: Bool = true, locale: Locale = .current) -> [InfoSection] {
        let details = song.details
        let genres = details.genres.isEmpty ? [song.genre].compactMap { $0 } : details.genres
        let general = rows([
            ("Title", song.title),
            ("Artist", song.artist),
            ("Album", song.album),
            ("Album Artist", details.albumArtist == song.artist ? nil : details.albumArtist),
            ("Track", trackPosition(track: song.track, disc: song.discNumber)),
            ("Year", song.year.map(String.init)),
            (genres.count > 1 ? "Genres" : "Genre", genres.isEmpty ? nil : genres.joined(separator: ", ")),
            ("Composer", details.composer),
            ("Length", song.duration.map(clock)),
            ("BPM", details.bpm.map(String.init)),
            ("Mood", details.moods.isEmpty ? nil : details.moods.joined(separator: ", ")),
            ("Comment", details.comment),
        ])
        let audio = rows([
            ("Format", song.suffix?.uppercased()),
            ("Resolution", resolution(bitDepth: details.bitDepth, sampleRate: details.sampleRate, locale: locale)),
            ("Channels", details.channels.map(channels)),
            ("Bitrate", song.bitRate.map { "\($0.formatted(.number.locale(locale))) kbps" }),
            ("Size", details.size.map { $0.formatted(.byteCount(style: .file).locale(locale)) }),
            ("ReplayGain", replayGain(song.replayGain, locale: locale)),
        ])
        let library = rows([
            ("Plays", details.playCount.map { $0.formatted(.number.locale(locale)) }),
            ("Last Played", details.lastPlayed.map { day($0, locale: locale) }),
            ("Added", details.added.map { day($0, locale: locale) }),
            ("Rating", Rating.title(serverValue: song.userRating, simplified: simplifiedRating)),
            ("Favorite", song.isStarred ? "Yes" : nil),
        ])
        return [
            InfoSection(title: "General", rows: general),
            InfoSection(title: "Audio", rows: audio),
            InfoSection(title: "Library", rows: library),
        ].filter { !$0.rows.isEmpty }
    }

    public static func sections(for album: Album, simplifiedRating: Bool = true, locale: Locale = .current) -> [InfoSection] {
        let details = album.details
        let genres = details.genres.isEmpty ? [album.genre].compactMap { $0 } : details.genres
        let year: String? = album.year.map { year in
            guard let original = details.originalYear, original != year else { return String(year) }
            return "\(year) (originally \(original))"
        }
        let general = rows([
            ("Title", album.name),
            ("Artist", album.artist),
            ("Year", year),
            (genres.count > 1 ? "Genres" : "Genre", genres.isEmpty ? nil : genres.joined(separator: ", ")),
            ("Release Type", releaseTypes(details).isEmpty ? nil : releaseTypes(details).joined(separator: ", ")),
            (details.labels.count > 1 ? "Labels" : "Label", details.labels.isEmpty ? nil : details.labels.joined(separator: ", ")),
            ("Songs", album.songCount.map(String.init)),
            ("Length", album.duration.map { length($0, locale: locale) }),
        ])
        let library = rows([
            ("Plays", details.playCount.map { $0.formatted(.number.locale(locale)) }),
            ("Added", details.added.map { day($0, locale: locale) }),
            ("Rating", Rating.title(serverValue: album.userRating, simplified: simplifiedRating)),
            ("Favorite", album.isStarred ? "Yes" : nil),
        ])
        return [
            InfoSection(title: "General", rows: general),
            InfoSection(title: "Library", rows: library),
        ].filter { !$0.rows.isEmpty }
    }

    /// The line under an album page's artist and year: genre, songs and
    /// length, e.g. "Rock · 12 songs · 41 min". `nil` if there's nothing. The
    /// label is in Album Info, keeping this line short.
    public static func albumDetailsLine(_ album: Album, locale: Locale = .current) -> String? {
        let genre = album.details.genres.first ?? album.genre
        let songs = album.songCount.map { $0 == 1 ? "1 song" : "\($0) songs" }
        let parts = [genre, songs, album.duration.map { length($0, locale: locale) }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Pieces

    private static func rows(_ pairs: [(String, String?)]) -> [InfoRow] {
        pairs.compactMap { label, value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return InfoRow(label: label, value: value)
        }
    }

    static func trackPosition(track: Int?, disc: Int?) -> String? {
        guard let track, track > 0 else { return nil }
        guard let disc, disc > 1 else { return "\(track)" }
        return "\(track) (disc \(disc))"
    }

    /// e.g. "24-bit / 96 kHz", "44.1 kHz".
    static func resolution(bitDepth: Int?, sampleRate: Int?, locale: Locale) -> String? {
        let rate = sampleRate.map { rate -> String in
            let kilohertz = Double(rate) / 1000
            return "\(kilohertz.formatted(.number.precision(.fractionLength(0...1)).locale(locale))) kHz"
        }
        switch (bitDepth, rate) {
        case let (depth?, rate?): return "\(depth)-bit / \(rate)"
        case let (depth?, nil): return "\(depth)-bit"
        case let (nil, rate?): return rate
        default: return nil
        }
    }

    static func channels(_ count: Int) -> String {
        switch count {
        case 1: "Mono"
        case 2: "Stereo"
        default: "\(count) channels"
        }
    }

    /// e.g. "Track −6.1 dB · Album −5.8 dB".
    static func replayGain(_ gain: ReplayGain?, locale: Locale) -> String? {
        guard let gain else { return nil }
        let parts = [
            gain.trackGain.map { "Track \(PlaybackQuality.decibels($0))" },
            gain.albumGain.map { "Album \(PlaybackQuality.decibels($0))" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A song's length as minutes and seconds, e.g. "4:51".
    static func clock(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = seconds % 3600 / 60
        let rest = seconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// An album's length, e.g. "41 min", "1 hr 12 min".
    static func length(_ seconds: Int, locale: Locale) -> String {
        let minutes = max((seconds + 30) / 60, 1)
        guard minutes >= 60 else { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min"
    }

    static func day(_ date: Date, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
    }

    /// Release types without "Album" when it's the only one (it says nothing).
    private static func releaseTypes(_ details: AlbumDetails) -> [String] {
        var types = details.releaseTypes.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        if details.isCompilation, !types.contains(where: { $0.caseInsensitiveCompare("Compilation") == .orderedSame }) {
            types.append("Compilation")
        }
        return types == ["Album"] ? [] : types
    }
}
