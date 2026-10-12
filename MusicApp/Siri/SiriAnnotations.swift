import AppIntents
import NavidromeCore
import SwiftUI

// Tells Siri what a view shows, so "Ask Siri" on a long-pressed row, or
// "play this" on a page, means that artist, album, song or playlist.

extension View {
    func siriEntity(artistID id: String) -> some View {
        appEntityIdentifier(EntityIdentifier(for: ArtistEntity.self, identifier: id))
    }

    func siriEntity(albumID id: String) -> some View {
        appEntityIdentifier(EntityIdentifier(for: AlbumEntity.self, identifier: id))
    }

    /// `nil` (a radio station) annotates nothing.
    func siriEntity(songID id: String?) -> some View {
        appEntityIdentifier(id.map { EntityIdentifier(for: SongEntity.self, identifier: $0) })
    }

    func siriEntity(playlistID id: String) -> some View {
        appEntityIdentifier(EntityIdentifier(for: PlaylistEntity.self, identifier: id))
    }

    /// A download is an album or a playlist on the server.
    func siriEntity(download collection: DownloadCollection) -> some View {
        appEntityIdentifier(
            collection.kind == .album
                ? EntityIdentifier(for: AlbumEntity.self, identifier: collection.serverID)
                : EntityIdentifier(for: PlaylistEntity.self, identifier: collection.serverID)
        )
    }
}
