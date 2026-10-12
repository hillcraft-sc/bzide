import AppIntents
import Foundation
import MediaIntents
import NavidromeCore

/// Anything Siri can play or add to a playlist.
@UnionValue
enum PlayableEntity {
    case song(SongEntity)
    case album(AlbumEntity)
    case artist(ArtistEntity)
    case playlist(PlaylistEntity)

    nonisolated var title: String {
        switch self {
        case .song(let song): song.title
        case .album(let album): album.title
        case .artist(let artist): artist.name
        case .playlist(let playlist): playlist.title
        }
    }

    nonisolated var source: SongSource {
        switch self {
        case .song(let song): .songs([Song(id: song.id, title: song.title, artist: song.artistName, duration: Int(song.duration))])
        case .album(let album): .album(id: album.id)
        case .artist(let artist): .artist(id: artist.id)
        case .playlist(let playlist): .playlist(id: playlist.id)
        }
    }
}

extension PlayableEntity {
    /// Finds what a spoken request names ("play Kind of Blue in Bzide"): an
    /// exact name match first, then songs, albums, artists and playlists.
    struct AudioSearchQuery: IntentValueQuery {
        func values(for input: AudioSearch) async throws -> [PlayableEntity] {
            guard case .searchQuery(let query) = input.criteria else { return [] }
            let lookup = try await SiriAccess.lookup()
            let found = try await lookup.search(query)
            let playlists = (try? await lookup.playlists()) ?? []
            let candidates: [PlayableEntity] =
                found.songs.map { .song(SongEntity($0)) }
                + found.albums.map { .album(AlbumEntity($0)) }
                + found.artists.map { .artist(ArtistEntity($0)) }
                + playlists.filter { $0.name.localizedStandardContains(query) }.map { .playlist(PlaylistEntity($0)) }
            return Self.exactFirst(candidates, query: query)
        }

        static func exactFirst(_ candidates: [PlayableEntity], query: String) -> [PlayableEntity] {
            let wanted = query.trimmingCharacters(in: .whitespaces)
            let exact = candidates.filter { $0.title.compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            let rest = candidates.filter { $0.title.compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame }
            return exact + rest
        }
    }
}
