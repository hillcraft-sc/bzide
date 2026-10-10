/// A playlist. `songs` is only filled by `getPlaylist`.
public struct Playlist: Sendable, Equatable, Identifiable, Decodable {
    public var id: String
    public var name: String
    public var comment: String?
    public var owner: String?
    public var isPublic: Bool?
    public var songCount: Int?
    /// Seconds.
    public var duration: Int?
    public var coverArtID: String?
    public var songs: [Song]

    public init(
        id: String, name: String, comment: String? = nil, owner: String? = nil, isPublic: Bool? = nil,
        songCount: Int? = nil, duration: Int? = nil, coverArtID: String? = nil, songs: [Song] = []
    ) {
        self.id = id
        self.name = name
        self.comment = comment
        self.owner = owner
        self.isPublic = isPublic
        self.songCount = songCount
        self.duration = duration
        self.coverArtID = coverArtID
        self.songs = songs
    }

    private enum ServerKeys: String, CodingKey {
        case id, name, comment, owner, `public`, songCount, duration, coverArt, entry
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: ServerKeys.self)
        self.init(
            id: try c.requiredID(.id),
            name: c.lenientString(.name) ?? "",
            comment: c.lenientString(.comment),
            owner: c.lenientString(.owner),
            isPublic: c.lenientBool(.public),
            songCount: c.lenientInt(.songCount),
            duration: c.lenientInt(.duration),
            coverArtID: c.lenientString(.coverArt),
            songs: c.lossyArray(Song.self, forKey: .entry)
        )
    }
}
