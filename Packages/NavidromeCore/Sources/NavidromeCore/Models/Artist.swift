/// An artist (Subsonic `ArtistID3`). `albums` is only filled by `getArtist`.
public struct Artist: Sendable, Equatable, Identifiable, Decodable {
    public var id: String
    public var name: String
    public var albumCount: Int?
    public var coverArtID: String?
    public var isStarred: Bool
    /// The server's 1–5 stars; `nil` when unrated. See `Rating`.
    public var userRating: Int?
    public var albums: [Album]

    public init(
        id: String, name: String, albumCount: Int? = nil, coverArtID: String? = nil,
        isStarred: Bool = false, userRating: Int? = nil, albums: [Album] = []
    ) {
        self.id = id
        self.name = name
        self.albumCount = albumCount
        self.coverArtID = coverArtID
        self.isStarred = isStarred
        self.userRating = userRating
        self.albums = albums
    }

    private enum ServerKeys: String, CodingKey {
        case id, name, albumCount, coverArt, starred, userRating, album
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: ServerKeys.self)
        self.init(
            id: try c.requiredID(.id),
            name: c.lenientString(.name) ?? "",
            albumCount: c.lenientInt(.albumCount),
            coverArtID: c.lenientString(.coverArt),
            isStarred: c.contains(.starred),
            userRating: c.rating(.userRating),
            albums: c.lossyArray(Album.self, forKey: .album)
        )
    }
}

/// One letter group from `getArtists`, in the server's order.
public struct ArtistSection: Sendable, Equatable, Decodable {
    public var name: String
    public var artists: [Artist]

    public init(name: String, artists: [Artist]) {
        self.name = name
        self.artists = artists
    }

    private enum ServerKeys: String, CodingKey { case name, artist }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: ServerKeys.self)
        self.init(name: c.lenientString(.name) ?? "", artists: c.lossyArray(Artist.self, forKey: .artist))
    }
}
