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

    public func song(id: String) async throws(SubsonicError) -> Song {
        try await request("getSong", parameters: [.init(name: "id", value: id)], as: ItemPayload<Song, SongKey>.self).item
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

    /// A new playlist with these songs, in order. Navidrome answers with the
    /// playlist; older Subsonic servers answer with nothing, hence `nil`.
    /// A long list belongs in several calls (see `PlaylistEditor`): every id
    /// goes in the URL, which servers and proxies limit in length.
    public func createPlaylist(name: String, songIDs: [String]) async throws(SubsonicError) -> Playlist? {
        let parameters = [URLQueryItem(name: "name", value: name)] + songIDs.map { URLQueryItem(name: "songId", value: $0) }
        return try await request("createPlaylist", parameters: parameters, as: OptionalItemPayload<Playlist, PlaylistKey>.self).item
    }

    /// Appends songs to the end of a playlist. Only the owner may; the server
    /// refuses others (and smart playlists).
    public func addToPlaylist(id: String, songIDs: [String]) async throws(SubsonicError) {
        let parameters = [URLQueryItem(name: "playlistId", value: id)] + songIDs.map { URLQueryItem(name: "songIdToAdd", value: $0) }
        _ = try await request("updatePlaylist", parameters: parameters, as: EmptyPayload.self)
    }

    /// Renames a playlist or makes it public (shared with every user) or
    /// private. Only the owner may.
    public func updatePlaylist(id: String, name: String? = nil, isPublic: Bool? = nil) async throws(SubsonicError) {
        var parameters = [URLQueryItem(name: "playlistId", value: id)]
        if let name { parameters.append(URLQueryItem(name: "name", value: name)) }
        if let isPublic { parameters.append(URLQueryItem(name: "public", value: isPublic ? "true" : "false")) }
        _ = try await request("updatePlaylist", parameters: parameters, as: EmptyPayload.self)
    }

    /// Removes songs by their 0-based position, then appends songs, in one
    /// request, so it happens entirely or not at all. Positions rather than ids,
    /// because a playlist can hold a song twice. `post` sends it as a form POST
    /// (OpenSubsonic `formPost`), for lists too long for a URL.
    public func editPlaylist(
        id: String, removingIndexes: [Int], adding songIDs: [String], post: Bool
    ) async throws(SubsonicError) {
        let parameters = [URLQueryItem(name: "playlistId", value: id)]
            + removingIndexes.map { URLQueryItem(name: "songIndexToRemove", value: String($0)) }
            + songIDs.map { URLQueryItem(name: "songIdToAdd", value: $0) }
        _ = try await request("updatePlaylist", parameters: parameters, post: post, as: EmptyPayload.self)
    }

    /// Deletes a playlist from the server. Only the owner may.
    public func deletePlaylist(id: String) async throws(SubsonicError) {
        _ = try await request("deletePlaylist", parameters: [URLQueryItem(name: "id", value: id)], as: EmptyPayload.self)
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

    /// The email on the user's account, or `nil` if it has none. Navidrome
    /// fills this from the user's profile.
    public func userEmail(username: String) async throws(SubsonicError) -> String? {
        struct Payload: Decodable {
            struct User: Decodable {
                let email: String?
            }
            let user: User?
        }
        let email = try await request("getUser", parameters: [.init(name: "username", value: username)], as: Payload.self).user?.email
        guard let email, !email.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return email
    }

    /// Whether the user is an admin on the server, which Navidrome requires
    /// for changing radio stations. Missing means no.
    public func isAdmin(username: String) async throws(SubsonicError) -> Bool {
        struct Payload: Decodable {
            struct User: Decodable {
                let adminRole: Bool?
            }
            let user: User?
        }
        let user = try await request("getUser", parameters: [.init(name: "username", value: username)], as: Payload.self).user
        return user?.adminRole ?? false
    }

    /// Everything the user has favorited (starred): artists, albums and songs.
    public func favorites() async throws(SubsonicError) -> SearchResult {
        try await request("getStarred2", as: StarredPayload.self).result
    }

    /// A page of every song in the library, by searching for nothing.
    /// Navidrome supports this (it's how clients list the whole library);
    /// other servers may return nothing.
    public func allSongs(count: Int, offset: Int) async throws(SubsonicError) -> [Song] {
        let parameters: [URLQueryItem] = [
            .init(name: "query", value: ""),
            .init(name: "artistCount", value: "0"),
            .init(name: "albumCount", value: "0"),
            .init(name: "songCount", value: String(count)),
            .init(name: "songOffset", value: String(offset)),
        ]
        return try await request("search3", parameters: parameters, as: SearchPayload.self).result.songs
    }

    public func genres() async throws(SubsonicError) -> [Genre] {
        try await request("getGenres", as: ListPayload<Genre, GenresKeys>.self).elements
    }

    /// `count` is capped at 500 by the server.
    public func songs(inGenre genre: String, count: Int = 500, offset: Int = 0) async throws(SubsonicError) -> [Song] {
        let parameters: [URLQueryItem] = [
            .init(name: "genre", value: genre),
            .init(name: "count", value: String(count)),
            .init(name: "offset", value: String(offset)),
        ]
        return try await request("getSongsByGenre", parameters: parameters, as: ListPayload<Song, SongsByGenreKeys>.self).elements
    }

    public func radioStations() async throws(SubsonicError) -> [RadioStation] {
        try await request("getInternetRadioStations", as: ListPayload<RadioStation, RadioStationsKeys>.self).elements
    }

    /// Saves a new station on the server. Navidrome lets only admins change
    /// stations (others get error 50) and doesn't return the new station, so
    /// reload the list afterwards.
    public func createRadioStation(_ station: RadioStationDraft.Valid) async throws(SubsonicError) {
        _ = try await request("createInternetRadioStation", parameters: Self.stationParameters(station), as: EmptyPayload.self)
    }

    /// Replaces a station's name and addresses. Admins only on Navidrome.
    public func updateRadioStation(id: String, _ station: RadioStationDraft.Valid) async throws(SubsonicError) {
        let parameters = [URLQueryItem(name: "id", value: id)] + Self.stationParameters(station)
        _ = try await request("updateInternetRadioStation", parameters: parameters, as: EmptyPayload.self)
    }

    /// Removes a station from the server, for every client. Admins only on Navidrome.
    public func deleteRadioStation(id: String) async throws(SubsonicError) {
        _ = try await request("deleteInternetRadioStation", parameters: [.init(name: "id", value: id)], as: EmptyPayload.self)
    }

    private static func stationParameters(_ station: RadioStationDraft.Valid) -> [URLQueryItem] {
        var parameters = [
            URLQueryItem(name: "streamUrl", value: station.streamURL.absoluteString),
            URLQueryItem(name: "name", value: station.name),
        ]
        if let homePage = station.homePageURL {
            parameters.append(.init(name: "homepageUrl", value: homePage.absoluteString))
        }
        return parameters
    }

    /// Random songs from the library, optionally only from one genre.
    public func randomSongs(size: Int = 50, genre: String? = nil) async throws(SubsonicError) -> [Song] {
        var parameters = [URLQueryItem(name: "size", value: String(size))]
        if let genre { parameters.append(.init(name: "genre", value: genre)) }
        return try await request("getRandomSongs", parameters: parameters, as: ListPayload<Song, RandomSongsKeys>.self).elements
    }

    /// Songs similar to a song, from the server's artist-similarity data
    /// (Navidrome needs an agent such as Last.fm set up). Empty when the
    /// server has none.
    public func similarSongs(toSongID id: String, count: Int = 50) async throws(SubsonicError) -> [Song] {
        let parameters: [URLQueryItem] = [.init(name: "id", value: id), .init(name: "count", value: String(count))]
        return try await request("getSimilarSongs", parameters: parameters, as: ListPayload<Song, SimilarSongsKeys>.self).elements
    }

    /// Songs by artists similar to this one (and the artist's own). Empty when
    /// the server has none.
    public func similarSongs(toArtistID id: String, count: Int = 50) async throws(SubsonicError) -> [Song] {
        let parameters: [URLQueryItem] = [.init(name: "id", value: id), .init(name: "count", value: String(count))]
        return try await request("getSimilarSongs2", parameters: parameters, as: ListPayload<Song, SimilarSongs2Keys>.self).elements
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
enum GenresKeys: ListKeys { static let wrapper = "genres"; static let list = "genre" }
enum SongsByGenreKeys: ListKeys { static let wrapper = "songsByGenre"; static let list = "song" }
enum RadioStationsKeys: ListKeys { static let wrapper = "internetRadioStations"; static let list = "internetRadioStation" }
enum RandomSongsKeys: ListKeys { static let wrapper = "randomSongs"; static let list = "song" }
enum SimilarSongsKeys: ListKeys { static let wrapper = "similarSongs"; static let list = "song" }
enum SimilarSongs2Keys: ListKeys { static let wrapper = "similarSongs2"; static let list = "song" }

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

/// A single item the server may leave out.
struct OptionalItemPayload<Item: Decodable, Key: ItemKey>: Decodable {
    let item: Item?

    init(from decoder: any Decoder) throws {
        item = try? decoder.container(keyedBy: AnyKey.self).decodeIfPresent(Item.self, forKey: AnyKey(Key.key))
    }
}

enum ArtistKey: ItemKey { static let key = "artist" }
enum AlbumKey: ItemKey { static let key = "album" }
enum PlaylistKey: ItemKey { static let key = "playlist" }
enum SongKey: ItemKey { static let key = "song" }

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

/// `getStarred2` with nothing starred may omit `starred2` entirely.
struct StarredPayload: Decodable {
    let result: SearchResult

    private enum Keys: String, CodingKey { case starred2 }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        result = (try? c.decodeIfPresent(SearchResult.self, forKey: .starred2)) ?? SearchResult()
    }
}

struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
