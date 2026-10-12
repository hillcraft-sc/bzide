import NavidromeCore
import SwiftUI

/// Toolbar control on an album or playlist: download it, watch it download,
/// retry what failed, or remove it.
struct DownloadButton: View {
    let downloads: DownloadManager
    let collection: DownloadCollection

    var body: some View {
        if let stored = downloads.collection(id: collection.id) {
            let status = downloads.status(of: stored)
            Menu {
                if status.failedCount > 0 {
                    Button("Retry \(status.failedCount) Failed", systemImage: "arrow.clockwise") {
                        downloads.retryFailed(in: stored)
                    }
                }
                Button("Remove Download", systemImage: "trash", role: .destructive) {
                    downloads.remove(collectionID: stored.id)
                }
            } label: {
                if status.isComplete {
                    Label("Downloaded", systemImage: "arrow.down.circle.fill")
                } else if status.failedCount > 0 {
                    Label("Download Failed", systemImage: "exclamationmark.circle")
                } else {
                    ProgressView(value: status.progress)
                        .progressViewStyle(.circular)
                        .accessibilityLabel("Downloading")
                }
            }
        } else {
            Button("Download", systemImage: "arrow.down.circle") {
                downloads.download(collection)
            }
            .disabled(collection.songs.isEmpty)
        }
    }
}

/// Everything stored on the phone. Built from the saved records, so it works offline.
struct DownloadsView: View {
    let library: Library
    @State private var query = ""

    private var downloads: DownloadManager { library.downloads }

    var body: some View {
        List {
            let songs = downloads.songDownloads(matching: query)
            if !songs.isEmpty {
                NavigationLink {
                    DownloadedSongsView(library: library)
                } label: {
                    // One row for every song downloaded on its own, counted together.
                    DownloadRow(library: library, collection: DownloadCollection(
                        kind: .song, serverID: "all", name: "Downloaded Songs",
                        songs: songs.flatMap(\.songs)
                    ), symbol: "music.note")
                }
                .contextMenu { QuickActionButtons(library: library, source: .songs(songs.flatMap(\.songs))) }
                .themedRows()
            }
            ForEach(downloads.collections(matching: query)) { collection in
                NavigationLink {
                    DownloadedCollectionView(library: library, collectionID: collection.id)
                } label: {
                    DownloadRow(library: library, collection: collection)
                }
                .contextMenu { DownloadRowMenu(library: library, collection: collection) }
                .siriEntity(download: collection)
                .swipeActions {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        downloads.remove(collectionID: collection.id)
                    }
                }
            }
            .themedRows()
        }
        .listStyle(.plain)
        .themedList()
        .overlay {
            if downloads.collections.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Download albums, playlists and songs to play them without a connection.")
                )
            } else if downloads.collections(matching: query).isEmpty, downloads.songDownloads(matching: query).isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Downloaded")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Albums, playlists, songs")
    }
}

private struct DownloadRow: View {
    let library: Library
    let collection: DownloadCollection
    /// Shown instead of a cover, for the Downloaded Songs row.
    var symbol: String?

    var body: some View {
        let status = library.downloads.status(of: collection)
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
                    .background(.quaternary, in: .rect(cornerRadius: 6))
                    .accessibilityHidden(true)
            } else {
                ArtworkView(library: library, coverArtID: collection.coverArtID, side: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name.isEmpty ? "Untitled" : collection.name).lineLimit(1)
                Text(detail(status))
                    .font(.caption)
                    .foregroundStyle(status.failedCount > 0 ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer()
            if !status.isComplete, status.failedCount == 0 {
                ProgressView(value: status.progress).progressViewStyle(.circular)
            }
        }
    }

    private func detail(_ status: CollectionDownloadStatus) -> String {
        if status.failedCount > 0 { return "\(status.failedCount) of \(status.songCount) failed" }
        if !status.isComplete { return "\(status.doneCount) of \(status.songCount) songs" }
        return [collection.artist, "\(status.songCount) songs"].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A downloaded album or playlist, from the saved song list rather than the server.
struct DownloadedCollectionView: View {
    let library: Library
    let collectionID: String

    var body: some View {
        if let collection = library.downloads.collection(id: collectionID) {
            SongListView(library: library, songs: collection.songs, showsTrackNumbers: collection.kind == .album) {
                SongListHeader(library: library, coverArtID: collection.coverArtID, title: collection.name, subtitle: collection.artist)
            }
            .navigationTitle(collection.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem { DownloadButton(downloads: library.downloads, collection: collection) }
            }
        } else {
            ContentUnavailableView("Removed", systemImage: "arrow.down.circle")
        }
    }
}

/// Every song downloaded on its own, newest first. Each is removed from its
/// long-press menu (Remove Download).
struct DownloadedSongsView: View {
    let library: Library

    var body: some View {
        let songs = library.downloads.songDownloads(matching: "").flatMap(\.songs)
        SongListView(library: library, songs: songs, showsTrackNumbers: false) {
            SongListHeader(
                library: library, coverArtID: nil, title: "Downloaded Songs",
                subtitle: songs.count == 1 ? "1 song" : "\(songs.count) songs"
            )
        }
        .navigationTitle("Downloaded Songs")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if songs.isEmpty {
                ContentUnavailableView("No Downloaded Songs", systemImage: "music.note")
            }
        }
    }
}
