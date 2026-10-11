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
            ForEach(downloads.collections(matching: query)) { collection in
                NavigationLink {
                    DownloadedCollectionView(library: library, collectionID: collection.id)
                } label: {
                    DownloadRow(library: library, collection: collection)
                }
                .swipeActions {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        downloads.remove(collectionID: collection.id)
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if downloads.collections.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Download albums and playlists to play them without a connection.")
                )
            } else if downloads.collections(matching: query).isEmpty {
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

    var body: some View {
        let status = library.downloads.status(of: collection)
        HStack(spacing: 12) {
            ArtworkView(library: library, coverArtID: collection.coverArtID, side: 48)
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
