/// A track (Subsonic `Child`).
public struct Song: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var title: String
    public var album: String?
    public var albumID: String?
    public var artist: String?
    public var artistID: String?
    public var track: Int?
    public var discNumber: Int?
    public var year: Int?
    public var genre: String?
    public var coverArtID: String?
    /// Seconds.
    public var duration: Int?
    /// Kbps.
    public var bitRate: Int?
    public var suffix: String?
    public var contentType: String?
    public var isStarred: Bool

    public init(
        id: String, title: String, album: String? = nil, albumID: String? = nil,
        artist: String? = nil, artistID: String? = nil, track: Int? = nil, discNumber: Int? = nil,
        year: Int? = nil, genre: String? = nil, coverArtID: String? = nil, duration: Int? = nil,
        bitRate: Int? = nil, suffix: String? = nil, contentType: String? = nil, isStarred: Bool = false
    ) {
        self.id = id
        self.title = title
        self.album = album
        self.albumID = albumID
        self.artist = artist
        self.artistID = artistID
        self.track = track
        self.discNumber = discNumber
        self.year = year
        self.genre = genre
        self.coverArtID = coverArtID
        self.duration = duration
        self.bitRate = bitRate
        self.suffix = suffix
        self.contentType = contentType
        self.isStarred = isStarred
    }
}

extension Song {
    private enum ServerKeys: String, CodingKey {
        case id, title, album, albumId, artist, artistId, track, discNumber, year, genre
        case coverArt, duration, bitRate, suffix, contentType, starred
    }

    // Encoding writes the same shape the server sends, so a saved queue decodes through
    // the same tolerant path as a network response.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: ServerKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(album, forKey: .album)
        try c.encodeIfPresent(albumID, forKey: .albumId)
        try c.encodeIfPresent(artist, forKey: .artist)
        try c.encodeIfPresent(artistID, forKey: .artistId)
        try c.encodeIfPresent(track, forKey: .track)
        try c.encodeIfPresent(discNumber, forKey: .discNumber)
        try c.encodeIfPresent(year, forKey: .year)
        try c.encodeIfPresent(genre, forKey: .genre)
        try c.encodeIfPresent(coverArtID, forKey: .coverArt)
        try c.encodeIfPresent(duration, forKey: .duration)
        try c.encodeIfPresent(bitRate, forKey: .bitRate)
        try c.encodeIfPresent(suffix, forKey: .suffix)
        try c.encodeIfPresent(contentType, forKey: .contentType)
        // The server signals "starred" by the key being present, so write it only when true.
        if isStarred { try c.encode(true, forKey: .starred) }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: ServerKeys.self)
        self.init(
            id: try c.requiredID(.id),
            title: c.lenientString(.title) ?? "",
            album: c.lenientString(.album),
            albumID: c.lenientString(.albumId),
            artist: c.lenientString(.artist),
            artistID: c.lenientString(.artistId),
            track: c.lenientInt(.track),
            discNumber: c.lenientInt(.discNumber),
            year: c.lenientInt(.year),
            genre: c.lenientString(.genre),
            coverArtID: c.lenientString(.coverArt),
            duration: c.lenientInt(.duration),
            bitRate: c.lenientInt(.bitRate),
            suffix: c.lenientString(.suffix),
            contentType: c.lenientString(.contentType),
            isStarred: c.contains(.starred)
        )
    }
}
