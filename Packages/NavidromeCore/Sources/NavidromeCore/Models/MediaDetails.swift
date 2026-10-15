import Foundation

/// The extra things a server may say about a song, for its Info screen. Plain
/// Subsonic gives some (size, play count, when added); Navidrome adds more
/// through OpenSubsonic (sample rate, bit depth, BPM, several genres…). Each
/// is `nil` or empty when the server didn't say, so nothing is ever required.
public struct SongDetails: Sendable, Equatable, Codable {
    /// Bytes.
    public var size: Int64?
    public var added: Date?
    public var playCount: Int?
    public var lastPlayed: Date?
    /// Hertz.
    public var sampleRate: Int?
    public var bitDepth: Int?
    public var channels: Int?
    public var bpm: Int?
    public var comment: String?
    public var composer: String?
    public var albumArtist: String?
    /// All its genres, when the server lists several.
    public var genres: [String]
    public var moods: [String]

    public init(
        size: Int64? = nil, added: Date? = nil, playCount: Int? = nil, lastPlayed: Date? = nil,
        sampleRate: Int? = nil, bitDepth: Int? = nil, channels: Int? = nil, bpm: Int? = nil,
        comment: String? = nil, composer: String? = nil, albumArtist: String? = nil,
        genres: [String] = [], moods: [String] = []
    ) {
        self.size = size
        self.added = added
        self.playCount = playCount
        self.lastPlayed = lastPlayed
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channels = channels
        self.bpm = bpm
        self.comment = comment
        self.composer = composer
        self.albumArtist = albumArtist
        self.genres = genres
        self.moods = moods
    }

    /// The server's names for these, at the same level as the song's other fields.
    enum Keys: String, CodingKey {
        case size, created, playCount, played, samplingRate, bitDepth, channelCount, bpm, comment
        case displayComposer, displayAlbumArtist, genres, moods
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        size = c.lenientInt(.size).map(Int64.init)
        added = c.lenientDate(.created)
        playCount = c.lenientInt(.playCount)
        lastPlayed = c.lenientDate(.played)
        sampleRate = c.positive(.samplingRate)
        bitDepth = c.positive(.bitDepth)
        channels = c.positive(.channelCount)
        bpm = c.positive(.bpm)
        comment = c.nonEmptyString(.comment)
        composer = c.nonEmptyString(.displayComposer)
        albumArtist = c.nonEmptyString(.displayAlbumArtist)
        genres = c.names(.genres)
        moods = c.strings(.moods)
    }

    /// Written in the server's shape, so a saved queue reads back through the same path.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encodeIfPresent(size, forKey: .size)
        try c.encodeIfPresent(added.map(MediaDates.string), forKey: .created)
        try c.encodeIfPresent(playCount, forKey: .playCount)
        try c.encodeIfPresent(lastPlayed.map(MediaDates.string), forKey: .played)
        try c.encodeIfPresent(sampleRate, forKey: .samplingRate)
        try c.encodeIfPresent(bitDepth, forKey: .bitDepth)
        try c.encodeIfPresent(channels, forKey: .channelCount)
        try c.encodeIfPresent(bpm, forKey: .bpm)
        try c.encodeIfPresent(comment, forKey: .comment)
        try c.encodeIfPresent(composer, forKey: .displayComposer)
        try c.encodeIfPresent(albumArtist, forKey: .displayAlbumArtist)
        if !genres.isEmpty { try c.encode(genres.map { ["name": $0] }, forKey: .genres) }
        if !moods.isEmpty { try c.encode(moods, forKey: .moods) }
    }
}

/// The extra things a server may say about an album, for its Info screen and header.
public struct AlbumDetails: Sendable, Equatable {
    public var playCount: Int?
    public var added: Date?
    public var labels: [String]
    /// e.g. "Album", "EP", "Live", "Compilation".
    public var releaseTypes: [String]
    /// When it first came out, if different from this release's year.
    public var originalYear: Int?
    public var genres: [String]
    public var isCompilation: Bool

    public init(
        playCount: Int? = nil, added: Date? = nil, labels: [String] = [], releaseTypes: [String] = [],
        originalYear: Int? = nil, genres: [String] = [], isCompilation: Bool = false
    ) {
        self.playCount = playCount
        self.added = added
        self.labels = labels
        self.releaseTypes = releaseTypes
        self.originalYear = originalYear
        self.genres = genres
        self.isCompilation = isCompilation
    }

    enum Keys: String, CodingKey {
        case playCount, created, recordLabels, releaseTypes, originalReleaseDate, genres, isCompilation
    }

    private enum DateKeys: String, CodingKey { case year }

    init(from decoder: any Decoder) {
        guard let c = try? decoder.container(keyedBy: Keys.self) else {
            self.init()
            return
        }
        let original = try? c.nestedContainer(keyedBy: DateKeys.self, forKey: .originalReleaseDate)
        self.init(
            playCount: c.lenientInt(.playCount),
            added: c.lenientDate(.created),
            labels: c.names(.recordLabels),
            releaseTypes: c.strings(.releaseTypes),
            originalYear: original?.lenientInt(.year).flatMap { $0 > 0 ? $0 : nil },
            genres: c.names(.genres),
            isCompilation: c.lenientBool(.isCompilation) ?? false
        )
    }
}

/// Dates as servers write them: ISO 8601, with or without fractions of a second.
enum MediaDates {
    static func date(_ text: String) -> Date? {
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? withFraction.parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
    }

    static func string(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle())
    }
}

extension KeyedDecodingContainer {
    func lenientDate(_ key: Key) -> Date? {
        lenientString(key).flatMap(MediaDates.date)
    }

    /// A number above zero; 0 usually means "unknown".
    func positive(_ key: Key) -> Int? {
        lenientInt(key).flatMap { $0 > 0 ? $0 : nil }
    }

    func nonEmptyString(_ key: Key) -> String? {
        lenientString(key).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    /// A list of strings, skipping anything that isn't one.
    func strings(_ key: Key) -> [String] {
        lossyArray(String.self, forKey: key).filter { !$0.isEmpty }
    }

    /// OpenSubsonic's lists of `{ "name": … }` objects (genres, record labels).
    func names(_ key: Key) -> [String] {
        lossyArray(NamedItem.self, forKey: key).map(\.name).filter { !$0.isEmpty }
    }
}

private struct NamedItem: Decodable {
    let name: String
}
