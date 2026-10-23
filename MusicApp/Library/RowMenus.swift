import NavidromeCore
import SwiftUI

// Long-press menus for list rows, so common actions don't need the item opened.
// Anything not already loaded has its songs fetched first (`QuickActions`).

/// Play, shuffle, queue or add to a playlist.
struct QuickActionButtons: View {
    let library: Library
    let source: SongSource

    var body: some View {
        Section {
            Button("Play", systemImage: "play.fill") { run(.play) }
            Button("Shuffle", systemImage: "shuffle") { run(.shuffle) }
            Button("Play Next", systemImage: "text.insert") { run(.playNext) }
            Button("Add to Queue", systemImage: "text.append") { run(.addToQueue) }
        }
        Button("Add to Playlist…", systemImage: "music.note.list") { run(.addToPlaylist) }
    }

    private func run(_ action: QuickActions.Action) {
        Task { await library.quickActions.perform(action, on: source) }
    }
}

/// Download, or Remove Download once it's stored.
private struct DownloadMenuButton: View {
    let library: Library
    let kind: DownloadCollection.Kind
    let serverID: String
    let source: SongSource

    var body: some View {
        if let stored = library.downloads.collection(id: DownloadCollection.id(kind, serverID: serverID)) {
            Button("Remove Download", systemImage: "trash", role: .destructive) {
                library.downloads.remove(collectionID: stored.id)
            }
        } else {
            Button("Download", systemImage: "arrow.down.circle") {
                Task { await library.quickActions.perform(.download, on: source) }
            }
        }
    }
}

struct ArtistRowMenu: View {
    let library: Library
    let artist: Artist

    var body: some View {
        QuickActionButtons(library: library, source: .artist(id: artist.id))
        Button("Spin Off", systemImage: "opticaldisc") {
            Task { await library.spinOff.start(fromArtist: artist) }
        }
        Section {
            MarkActions(library: library, target: .artist(id: artist.id), isStarred: artist.isStarred, userRating: artist.userRating)
        }
    }
}

struct AlbumRowMenu: View {
    let library: Library
    let album: Album
    /// Off on the artist's own page.
    var showsGoToArtist = true

    var body: some View {
        QuickActionButtons(library: library, source: .album(id: album.id))
        DownloadMenuButton(library: library, kind: .album, serverID: album.id, source: .album(id: album.id))
        AlbumInfoButton(library: library, albumID: album.id)
        Section {
            MarkActions(library: library, target: .album(id: album.id), isStarred: album.isStarred, userRating: album.userRating)
        }
        if showsGoToArtist, let artistID = album.artistID {
            NavigationLink(value: LibraryRoute.artist(id: artistID)) {
                Label("Go to Artist", systemImage: "music.microphone")
            }
        }
    }
}

struct PlaylistRowMenu: View {
    let library: Library
    let playlist: Playlist

    var body: some View {
        QuickActionButtons(library: library, source: .playlist(id: playlist.id))
        DownloadMenuButton(library: library, kind: .playlist, serverID: playlist.id, source: .playlist(id: playlist.id))
        PlaylistManageButtons(library: library, playlist: playlist)
    }
}

/// A download's songs are on the phone, so these work offline.
struct DownloadRowMenu: View {
    let library: Library
    let collection: DownloadCollection

    var body: some View {
        QuickActionButtons(library: library, source: .songs(collection.songs))
        Button("Remove Download", systemImage: "trash", role: .destructive) {
            library.downloads.remove(collectionID: collection.id)
        }
    }
}
