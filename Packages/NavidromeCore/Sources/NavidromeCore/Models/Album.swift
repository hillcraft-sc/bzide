import Foundation

/// An album (Subsonic `AlbumID3`). `songs` is only filled by `getAlbum`.
public struct Album: Sendable, Equatable, Identifiable, Decodable {
    public var id: String
    public var name: String
    public var artist: String?
    public var artistID: String?
    public var coverArtID: String?
    public var songCount: Int?
    /// Seconds.
    public var duration: Int?
    public var year: Int?
    public var genre: String?
    public var isStarred: Bool
    /// When it was favorited, if the server said.
    public var starredAt: Date?
    /// The server's 1–5 stars; `nil` when unrated. See `Rating`.
    public var userRating: Int?
    public var songs: [Song]
    /// Everything else the server said, for the Info screen and header.
    public var details = AlbumDetails()
    /// The MusicBrainz release this is (OpenSubsonic), if the files are tagged.
    public var musicBrainzID: String?

    public init(
        id: String, name: String, artist: String? = nil, artistID: String? = nil,
        coverArtID: String? = nil, songCount: Int? = nil, duration: Int? = nil,
        year: Int? = nil, genre: String? = nil, isStarred: Bool = false, userRating: Int? = nil, songs: [Song] = []
    ) {
        self.id = id
        self.name = name
        self.artist = artist
        self.artistID = artistID
        self.coverArtID = coverArtID
        self.songCount = songCount
        self.duration = duration
        self.year = year
        self.genre = genre
        self.isStarred = isStarred
        self.userRating = userRating
        self.songs = songs
    }

    private enum ServerKeys: String, CodingKey {
        case id, name, title, artist, artistId, coverArt, songCount, duration, year, genre, starred, userRating, song, musicBrainzId
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: ServerKeys.self)
        self.init(
            id: try c.requiredID(.id),
            // Some responses use `title` for albums instead of `name`.
            name: c.lenientString(.name) ?? c.lenientString(.title) ?? "",
            artist: c.lenientString(.artist),
            artistID: c.lenientString(.artistId),
            coverArtID: c.lenientString(.coverArt),
            songCount: c.lenientInt(.songCount),
            duration: c.lenientInt(.duration),
            year: c.lenientInt(.year),
            genre: c.lenientString(.genre),
            isStarred: c.contains(.starred),
            userRating: c.rating(.userRating),
            songs: c.lossyArray(Song.self, forKey: .song)
        )
        starredAt = c.lenientDate(.starred)
        details = AlbumDetails(from: decoder)
        musicBrainzID = c.lenientString(.musicBrainzId).flatMap { $0.isEmpty ? nil : $0 }
    }
}
