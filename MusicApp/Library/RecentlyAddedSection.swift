import NavidromeCore
import SwiftUI

/// The newest albums as a row of covers at the top of Library. The header
/// collapses it; See All opens the full list, newest first.
struct RecentlyAddedSection: View {
    let library: Library
    let model: LoadModel<[Album]>
    @Binding var isCollapsed: Bool

    var body: some View {
        Section {
            if !isCollapsed {
                content
            }
        } header: {
            header
        }
    }

    private var header: some View {
        HStack {
            Button {
                withAnimation { isCollapsed.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Recently Added")
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
            }
            .buttonStyle(.borderless)
            // A heading that also collapses, not a link: only See All is in the accent.
            .tint(.primary)
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
            .accessibilityHint(isCollapsed ? "Shows the newest albums" : "Hides the newest albums")
            Spacer()
            NavigationLink("See All", value: LibraryRoute.albums)
                .font(.subheadline)
        }
        .font(.headline)
        .textCase(nil)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
        case .failed(let message):
            VStack(spacing: 8) {
                Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Try Again") { Task { await model.load() } }
                    .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity)
        case .loaded(let albums) where albums.isEmpty:
            Text("No albums yet").foregroundStyle(.secondary)
        case .loaded(let albums):
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(albums) { album in
                        NavigationLink(value: LibraryRoute.album(id: album.id)) {
                            AlbumCard(library: library, album: album)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { AlbumRowMenu(library: library, album: album) }
                        .siriEntity(albumID: album.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
        }
    }
}

/// Cover, name and artist, for rows of albums.
private struct AlbumCard: View {
    let library: Library
    let album: Album

    private let side: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ArtworkView(library: library, coverArtID: album.coverArtID, side: side)
            Text(album.name.isEmpty ? "Untitled" : album.name)
                .font(.footnote)
                .lineLimit(1)
            if let artist = album.artist {
                Text(artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: side, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
