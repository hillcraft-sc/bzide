import AppIntents
import NavidromeCore

// The library as Siri sees it, using the system's audio schemas so Siri knows
// these are songs, albums, artists and playlists. Ids are the server's ids.
// Related entities (an album's songs, an artist's albums) are left empty:
// Siri gets them by asking for the entity itself, and filling them would mean
// fetching half the library for every lookup.

@AppEntity(schema: .audio.artist)
struct ArtistEntity {
    static let defaultQuery = ArtistEntityQuery()

    var name: String
    var albums: [AlbumEntity]
    var songs: [SongEntity]

    let id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: "music.microphone"))
    }

    init(_ artist: Artist) {
        // The macro wraps most schema properties; these plain ones go first.
        id = artist.id
        albums = []
        songs = []
        name = artist.name
    }
}

@AppEntity(schema: .audio.album)
struct AlbumEntity {
    static let defaultQuery = AlbumEntityQuery()

    var title: String
    var artistName: String
    var artists: [ArtistEntity]
    var songs: [SongEntity]
    var universalProductCode: String?

    let id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(artistName)",
            image: .init(systemName: "square.stack"),
            synonyms: ["album \(title)", "\(artistName) album \(title)"]
        )
    }

    init(_ album: Album) {
        id = album.id
        songs = []
        title = album.name
        artistName = album.artist ?? ""
        artists = album.artistID.map { [ArtistEntity(Artist(id: $0, name: album.artist ?? ""))] } ?? []
        universalProductCode = nil
    }
}

@AppEntity(schema: .audio.song)
struct SongEntity {
    static let defaultQuery = SongEntityQuery()

    var title: String
    var artistName: String
    var albumTitle: String?
    var composerName: String?
    var internationalStandardRecordingCode: String?
    var album: AlbumEntity?
    var artists: [ArtistEntity]
    var composers: [ArtistEntity]
    var duration: TimeInterval

    let id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(artistName)",
            image: .init(systemName: "music.note"),
            synonyms: ["\(title) by \(artistName)"]
        )
    }

    init(_ song: Song) {
        id = song.id
        duration = TimeInterval(song.duration ?? 0)
        title = song.title
        artistName = song.artist ?? ""
        albumTitle = song.album
        composerName = nil
        internationalStandardRecordingCode = nil
        album = song.albumID.map { AlbumEntity(Album(id: $0, name: song.album ?? "", artist: song.artist, artistID: song.artistID)) }
        artists = song.artistID.map { [ArtistEntity(Artist(id: $0, name: song.artist ?? ""))] } ?? []
        composers = []
    }
}

@AppEntity(schema: .audio.playlist)
struct PlaylistEntity {
    static let defaultQuery = PlaylistEntityQuery()

    var title: String
    var owner: PlaylistOwnerUnion?
    var trackCount: Int
    var totalDuration: TimeInterval
    var createdByMe: Bool?
    var curatedForMe: Bool?

    let id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "^[\(trackCount) song](inflect: true)",
            image: .init(systemName: "music.note.list"),
            synonyms: ["\(title) playlist"]
        )
    }

    init(_ playlist: Playlist) {
        id = playlist.id
        trackCount = playlist.songCount ?? playlist.songs.count
        totalDuration = TimeInterval(playlist.duration ?? 0)
        title = playlist.name
        owner = playlist.owner.map { .curator($0) }
        createdByMe = nil
        curatedForMe = nil
    }
}

/// Who a playlist belongs to, as the playlist schema expects. Navidrome
/// gives only a username, so it's always a curator name here.
@UnionValue
enum PlaylistOwnerUnion {
    case curator(String)
    case person(IntentPerson)
}

// MARK: - Queries

struct ArtistEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ArtistEntity] {
        let lookup = try await SiriAccess.lookup()
        return await SiriAccess.each(identifiers, lookup.artist).map(ArtistEntity.init)
    }

    func entities(matching string: String) async throws -> [ArtistEntity] {
        try await SiriAccess.lookup().search(string).artists.map(ArtistEntity.init)
    }
}

struct AlbumEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [AlbumEntity] {
        let lookup = try await SiriAccess.lookup()
        return await SiriAccess.each(identifiers, lookup.album).map(AlbumEntity.init)
    }

    func entities(matching string: String) async throws -> [AlbumEntity] {
        try await SiriAccess.lookup().search(string).albums.map(AlbumEntity.init)
    }
}

struct SongEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SongEntity] {
        let lookup = try await SiriAccess.lookup()
        return await SiriAccess.each(identifiers, lookup.song).map(SongEntity.init)
    }

    func entities(matching string: String) async throws -> [SongEntity] {
        try await SiriAccess.lookup().search(string).songs.map(SongEntity.init)
    }
}

struct PlaylistEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PlaylistEntity] {
        let lookup = try await SiriAccess.lookup()
        return await SiriAccess.each(identifiers, lookup.playlist).map(PlaylistEntity.init)
    }

    /// The server has no playlist search, so this filters the list by name.
    func entities(matching string: String) async throws -> [PlaylistEntity] {
        try await SiriAccess.lookup().playlists()
            .filter { $0.name.localizedStandardContains(string) }
            .map(PlaylistEntity.init)
    }

    func suggestedEntities() async throws -> [PlaylistEntity] {
        try await SiriAccess.lookup().playlists().map(PlaylistEntity.init)
    }
}
