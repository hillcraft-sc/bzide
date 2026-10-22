import NavidromeCore
import SwiftUI

/// A row of album covers on Library (Recently Added, Recently Played, Spin It
/// Back). The header collapses it; See All, where there is one, opens the
/// full list.
struct AlbumCarouselSection: View {
    let library: Library
    let title: String
    /// What the header's hint says it shows, e.g. "the newest albums".
    let shows: String
    let emptyText: String
    let model: LoadModel<[Album]>
    @Binding var isCollapsed: Bool
    var seeAll: LibraryRoute?

    var body: some View {
        Section {
            if !isCollapsed {
                content
            }
        } header: {
            header
        }
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    /// At the accessibility text sizes, See All goes under the title, which
    /// would otherwise be squeezed into a narrow column, broken mid-word.
    private var header: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout())
        return layout {
            Button {
                withAnimation { isCollapsed.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                        // A button centers wrapped lines; a heading reads from the left.
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
            }
            .buttonStyle(.borderless)
            // A heading that also collapses, not a link: only See All is in the accent.
            .tint(.primary)
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
            .accessibilityHint(isCollapsed ? "Shows \(shows)" : "Hides \(shows)")
            if !typeSize.isAccessibilitySize { Spacer() }
            if let seeAll {
                NavigationLink("See All", value: seeAll)
                    .font(.subheadline)
            }
        }
        .font(.headline)
        .textCase(nil)
        .padding(.leading, -14)   // pull the heading toward the screen edge
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
            Text(emptyText).foregroundStyle(.secondary)
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
