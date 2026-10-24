import AppIntents
import Foundation
import MediaIntents
import NavidromeCore
import os

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
    /// Siri's audio search: "play Kind of Blue in Bzide", or just "play music
    /// in Bzide". On iOS 27, Siri sends these here and falls back to Apple
    /// Music if the answer is empty or slow (Gitea #34), so the work is done by
    /// `AudioRequestFinder`, which answers within a few seconds.
    struct AudioSearchQuery: IntentValueQuery {
        private static let logger = Logger(subsystem: "MusicApp", category: "Siri")

        func values(for input: AudioSearch) async throws -> [PlayableEntity] {
            let started = ContinuousClock.now
            let finder = try await MainActor.run { try SiriAccess.library().audioFinder }
            let matches: [AudioMatch]
            let kind: String
            switch input.criteria {
            case .searchQuery(let query):
                kind = "search"
                Self.logger.notice("Audio search for \(query, privacy: .private)")
                matches = await finder.find(query)
            case .unspecified:
                kind = "unspecified"
                matches = await finder.unspecified()
            default:
                // A web address: nothing in a Navidrome library has one.
                kind = "other"
                matches = []
            }
            let elapsed = ContinuousClock.now - started
            Self.logger.notice("Audio search (\(kind, privacy: .public)): \(matches.count) results in \(elapsed, privacy: .public)")
            return await MainActor.run { matches.map(PlayableEntity.init) }
        }
    }

    init(_ match: AudioMatch) {
        switch match {
        case .song(let song), .resume(let song): self = .song(SongEntity(song))
        case .album(let album): self = .album(AlbumEntity(album))
        case .artist(let artist): self = .artist(ArtistEntity(artist))
        case .playlist(let playlist): self = .playlist(PlaylistEntity(playlist))
        case .randomMix: self = .playlist(.randomMix)
        }
    }
}
