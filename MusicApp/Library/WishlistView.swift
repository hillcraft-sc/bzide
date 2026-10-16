import NavidromeCore
import SwiftUI

/// Songs heard on the radio to remember, newest first. Opening it checks the
/// library for each; songs found since are marked and play your copy when
/// tapped. Swipe to remove; long-press to copy "Artist - Title" or open the
/// MusicBrainz page.
struct WishlistView: View {
    let library: Library

    @Environment(\.openURL) private var openURL

    private var wishlist: Wishlist { library.wishlist }

    var body: some View {
        List {
            ForEach(wishlist.entries) { entry in
                row(entry)
                    .swipeActions {
                        Button("Remove", systemImage: "trash", role: .destructive) { wishlist.remove(entry.id) }
                    }
                    .contextMenu { menu(entry) }
            }
            .themedRows()
        }
        .listStyle(.plain)
        .themedList()
        .overlay {
            if wishlist.entries.isEmpty {
                ContentUnavailableView(
                    "No Songs Yet",
                    systemImage: "tag",
                    description: Text("When a radio station plays a song that isn't in your library, Tag Song in Now Playing keeps it here.")
                )
            }
        }
        .navigationTitle("Tagged Radio Songs")
        .task { await wishlist.checkLibrary() }
        .refreshable { await wishlist.checkLibrary() }
    }

    private func row(_ entry: WishlistEntry) -> some View {
        let owned = wishlist.owned[entry.id]
        return Button {
            if let owned { library.engine.play(songs: [owned]) }
        } label: {
            HStack(spacing: 12) {
                ArtworkView(library: library, coverArtID: owned?.coverArtID ?? entry.coverURL.map(StationLogo.coverArtID), side: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).foregroundStyle(.primary).lineLimit(1)
                    Text(entry.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Text(heard(entry)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if owned != nil {
                    Label("In Your Library", systemImage: "music.note.house")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.tint)
                        .accessibilityLabel("In your library")
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(owned == nil)
    }

    /// "Heard on Beatle Radio · Oct 16", with the album when known.
    private func heard(_ entry: WishlistEntry) -> String {
        var parts: [String] = []
        if let station = entry.station { parts.append("Heard on \(station)") }
        parts.append(entry.heardAt.formatted(.dateTime.month(.abbreviated).day()))
        if let album = entry.album { parts.append(album) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func menu(_ entry: WishlistEntry) -> some View {
        if let owned = wishlist.owned[entry.id] {
            Button("Play", systemImage: "play.fill") { library.engine.play(songs: [owned]) }
        }
        Button("Copy Artist and Title", systemImage: "doc.on.doc") { UIPasteboard.general.string = entry.text }
        if let page = entry.musicBrainzURL {
            Button("Open MusicBrainz Page", systemImage: "safari") { openURL(page) }
        }
        Button("Remove", systemImage: "trash", role: .destructive) { wishlist.remove(entry.id) }
    }
}
