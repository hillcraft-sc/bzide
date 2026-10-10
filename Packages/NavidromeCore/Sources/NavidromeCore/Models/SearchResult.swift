/// Results from `search3`.
public struct SearchResult: Sendable, Equatable, Decodable {
    public var artists: [Artist]
    public var albums: [Album]
    public var songs: [Song]

    public init(artists: [Artist] = [], albums: [Album] = [], songs: [Song] = []) {
        self.artists = artists
        self.albums = albums
        self.songs = songs
    }

    private enum ServerKeys: String, CodingKey { case artist, album, song }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: ServerKeys.self)
        self.init(
            artists: c.lossyArray(Artist.self, forKey: .artist),
            albums: c.lossyArray(Album.self, forKey: .album),
            songs: c.lossyArray(Song.self, forKey: .song)
        )
    }
}
