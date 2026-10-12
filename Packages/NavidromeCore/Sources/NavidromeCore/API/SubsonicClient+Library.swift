import Foundation

// Library browsing, search, and user actions. List endpoints treat a missing
// wrapper object as an empty list; single-item endpoints treat it as an error.

extension SubsonicClient {
    public func artists() async throws(SubsonicError) -> [ArtistSection] {
        try await request("getArtists", as: ListPayload<ArtistSection, ArtistsKeys>.self).elements
    }

    /// The artist with its albums.
    public func artist(id: String) async throws(SubsonicError) -> Artist {
        try await request("getArtist", parameters: [.init(name: "id", value: id)], as: ItemPayload<Artist, ArtistKey>.self).item
    }

    /// The biography and other details the server has looked up. An artist the
    /// server knows nothing about gives an empty `ArtistInfo`, not an error.
    public func artistInfo(id: String) async throws(SubsonicError) -> ArtistInfo {
        try await request("getArtistInfo2", parameters: [.init(name: "id", value: id)], as: ArtistInfoPayload.self).info
    }

    /// The album with its songs.
    public func album(id: String) async throws(SubsonicError) -> Album {
        try await request("getAlbum", parameters: [.init(name: "id", value: id)], as: ItemPayload<Album, AlbumKey>.self).item
    }

    /// `size` is capped at 500 by the server.
    public func albumList(_ type: AlbumListType, size: Int = 20, offset: Int = 0) async throws(SubsonicError) -> [Album] {
        let parameters = type.queryItems + [
            .init(name: "size", value: String(size)),
            .init(name: "offset", value: String(offset)),
        ]
        return try await request("getAlbumList2", parameters: parameters, as: ListPayload<Album, AlbumList2Keys>.self).elements
    }

    public func playlists() async throws(SubsonicError) -> [Playlist] {
        try await request("getPlaylists", as: ListPayload<Playlist, PlaylistsKeys>.self).elements
    }

    /// The playlist with its songs.
    public func playlist(id: String) async throws(SubsonicError) -> Playlist {
        try await request("getPlaylist", parameters: [.init(name: "id", value: id)], as: ItemPayload<Playlist, PlaylistKey>.self).item
    }

    public func search(
        _ query: String, artistCount: Int = 20, albumCount: Int = 20, songCount: Int = 20
    ) async throws(SubsonicError) -> SearchResult {
        let parameters: [URLQueryItem] = [
            .init(name: "query", value: query),
            .init(name: "artistCount", value: String(artistCount)),
            .init(name: "albumCount", value: String(albumCount)),
            .init(name: "songCount", value: String(songCount)),
        ]
        return try await request("search3", parameters: parameters, as: SearchPayload.self).result
    }

    public func randomSongs(size: Int = 50) async throws(SubsonicError) -> [Song] {
        try await request("getRandomSongs", parameters: [.init(name: "size", value: String(size))], as: ListPayload<Song, RandomSongsKeys>.self).elements
    }

    public func star(_ target: StarTarget) async throws(SubsonicError) {
        _ = try await request("star", parameters: [target.queryItem], as: EmptyPayload.self)
    }

    public func unstar(_ target: StarTarget) async throws(SubsonicError) {
        _ = try await request("unstar", parameters: [target.queryItem], as: EmptyPayload.self)
    }

    /// 1–5 stars, or `nil` to clear the rating (sent as 0).
    public func setRating(_ target: StarTarget, stars: Int?) async throws(SubsonicError) {
        let parameters: [URLQueryItem] = [
            .init(name: "id", value: target.id),
            .init(name: "rating", value: String(stars ?? 0)),
        ]
        _ = try await request("setRating", parameters: parameters, as: EmptyPayload.self)
    }

    /// `submission: false` only updates "now playing"; `true` records a play.
    /// When the play threshold is reached is the playback engine's decision.
    public func scrobble(songID: String, playedAt: Date? = nil, submission: Bool) async throws(SubsonicError) {
        var parameters: [URLQueryItem] = [
            .init(name: "id", value: songID),
            .init(name: "submission", value: String(submission)),
        ]
        if let playedAt {
            parameters.append(.init(name: "time", value: String(Int64(playedAt.timeIntervalSince1970 * 1000))))
        }
        _ = try await request("scrobble", parameters: parameters, as: EmptyPayload.self)
    }
}

// MARK: - Payload shapes

/// Names the keys of a `{"<wrapper>": {"<list>": [...]}}` response.
protocol ListKeys {
    static var wrapper: String { get }
    static var list: String { get }
}

/// A list response. Lossy, and empty when the wrapper or list is missing.
struct ListPayload<Element: Decodable, Keys: ListKeys>: Decodable {
    let elements: [Element]

    init(from decoder: any Decoder) throws {
        let outer = try decoder.container(keyedBy: AnyKey.self)
        let inner = try? outer.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey(Keys.wrapper))
        elements = inner?.lossyArray(Element.self, forKey: AnyKey(Keys.list)) ?? []
    }
}

enum ArtistsKeys: ListKeys { static let wrapper = "artists"; static let list = "index" }
enum AlbumList2Keys: ListKeys { static let wrapper = "albumList2"; static let list = "album" }
enum PlaylistsKeys: ListKeys { static let wrapper = "playlists"; static let list = "playlist" }
enum RandomSongsKeys: ListKeys { static let wrapper = "randomSongs"; static let list = "song" }

/// Names the key of a `{"<key>": {...}}` response.
protocol ItemKey {
    static var key: String { get }
}

/// A single-item response. The item must decode; there is nothing to fall back to.
struct ItemPayload<Item: Decodable, Key: ItemKey>: Decodable {
    let item: Item

    init(from decoder: any Decoder) throws {
        item = try decoder.container(keyedBy: AnyKey.self).decode(Item.self, forKey: AnyKey(Key.key))
    }
}

enum ArtistKey: ItemKey { static let key = "artist" }
enum AlbumKey: ItemKey { static let key = "album" }
enum PlaylistKey: ItemKey { static let key = "playlist" }

/// `getArtistInfo2` may omit `artistInfo2`, or send it empty.
struct ArtistInfoPayload: Decodable {
    let info: ArtistInfo

    private enum Keys: String, CodingKey { case artistInfo2 }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        info = (try? c.decodeIfPresent(ArtistInfo.self, forKey: .artistInfo2)) ?? ArtistInfo()
    }
}

/// `search3` with no matches may omit `searchResult3` entirely.
struct SearchPayload: Decodable {
    let result: SearchResult

    private enum Keys: String, CodingKey { case searchResult3 }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        result = (try? c.decodeIfPresent(SearchResult.self, forKey: .searchResult3)) ?? SearchResult()
    }
}

struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
