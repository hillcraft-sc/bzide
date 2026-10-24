import CoreTransferable
import NavidromeCore
import SwiftUI
import UniformTypeIdentifiers

/// The Wishlist: songs heard on the radio, songs missing from albums, and
/// albums and artists to get, newest first, in sections (only those with
/// something in them). Opening it checks the library for each; ones found
/// since are marked and open your copy when tapped. Swipe to remove;
/// long-press to copy, buy it from a store, or open the MusicBrainz page.
/// Share exports the list as text or CSV (Gitea #29).
struct WishlistView: View {
    let library: Library

    @Environment(\.openURL) private var openURL

    private var wishlist: Wishlist { library.wishlist }

    var body: some View {
        List {
            ForEach(wishlist.sections, id: \.kind) { section in
                Section(section.kind.sectionTitle) {
                    ForEach(section.entries) { entry in
                        row(entry)
                            .swipeActions {
                                Button("Remove", systemImage: "trash", role: .destructive) { wishlist.remove(entry.id) }
                            }
                            .contextMenu { menu(entry) }
                    }
                }
                .themedRows()
            }
        }
        .listStyle(.plain)
        .themedList()
        .overlay {
            if wishlist.entries.isEmpty {
                ContentUnavailableView(
                    "Nothing Yet",
                    systemImage: "tag",
                    description: Text("Tag a song a radio station plays, add an album's missing songs from its ••• menu, or long-press an album under Not Owned or an artist under Similar Artists.")
                )
            }
        }
        .navigationTitle("Wishlist")
        .toolbar {
            if !wishlist.entries.isEmpty {
                ToolbarItem {
                    Menu("Share", systemImage: "square.and.arrow.up") {
                        ShareLink("Share as Text", item: wishlist.exportText())
                        ShareLink(
                            "Share as CSV", item: WishlistCSV(text: wishlist.exportCSV()),
                            preview: SharePreview("Wishlist.csv", image: Image(systemName: "tablecells"))
                        )
                    }
                }
            }
        }
        .task { await wishlist.checkLibrary() }
        .refreshable { await wishlist.checkLibrary() }
    }

    @ViewBuilder
    private func row(_ entry: WishlistEntry) -> some View {
        let match = wishlist.found[entry.id]
        switch match {
        case .album(let album):
            NavigationLink(value: LibraryRoute.album(id: album.id)) { label(entry, match: match) }
        case .artist(let artist):
            NavigationLink(value: LibraryRoute.artist(id: artist.id)) { label(entry, match: match) }
        case .song(let song):
            Button { library.engine.play(songs: [song]) } label: { label(entry, match: match) }
                .buttonStyle(.plain)
        case nil:
            label(entry, match: nil)
        }
    }

    private func label(_ entry: WishlistEntry, match: WishlistMatch?) -> some View {
        HStack(spacing: 12) {
            picture(entry, match: match)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).foregroundStyle(.primary).lineLimit(1)
                if entry.kind != .artist {
                    Text(entry.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(details(entry)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if match != nil {
                Image(systemName: "music.note.house")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("In your library")
            }
        }
        .contentShape(.rect)
    }

    @ViewBuilder
    private func picture(_ entry: WishlistEntry, match: WishlistMatch?) -> some View {
        switch match {
        case .song(let song):
            ArtworkView(library: library, coverArtID: song.coverArtID, side: 44)
        case .album(let album):
            ArtworkView(library: library, coverArtID: album.coverArtID, side: 44)
        case .artist(let artist):
            ArtworkView(library: library, coverArtID: artist.coverArtID, side: 44).clipShape(.circle)
        case nil:
            if entry.kind == .artist {
                Image(systemName: "music.microphone")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(.fill.secondary, in: .circle)
            } else {
                ArtworkView(library: library, coverArtID: entry.coverURL.map(StationLogo.coverArtID), side: 44)
            }
        }
    }

    /// "Heard on Beatle Radio · Oct 16 · Band on the Run", "From Weathered · Oct 24", "1999 · Oct 24".
    private func details(_ entry: WishlistEntry) -> String {
        var parts: [String] = []
        switch entry.kind {
        case .radioSong:
            if let station = entry.station { parts.append("Heard on \(station)") }
        case .missingSong:
            if let album = entry.album { parts.append("From \(album)") }
        case .album:
            if let year = entry.year { parts.append(String(year)) }
        case .artist:
            break
        }
        parts.append(entry.heardAt.formatted(.dateTime.month(.abbreviated).day()))
        if entry.kind == .radioSong, let album = entry.album { parts.append(album) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func menu(_ entry: WishlistEntry) -> some View {
        if case .song(let song) = wishlist.found[entry.id] {
            Button("Play", systemImage: "play.fill") { library.engine.play(songs: [song]) }
        }
        Button(entry.kind == .artist ? "Copy Name" : entry.kind == .album ? "Copy Artist and Album" : "Copy Artist and Title", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = entry.text
        }
        if let page = entry.musicBrainzURL {
            Button("Open MusicBrainz Page", systemImage: "safari") { openURL(page) }
        }
        // Buying it: a store's search, opened in Safari or the store's app.
        // Settings > Wishlist hides the menu, or chooses its stores.
        let links = wishlist.buyLinks(for: entry)
        if !links.isEmpty {
            Menu("Buy", systemImage: "cart") {
                ForEach(links) { link in
                    Button(link.store) { openURL(link.url) }
                }
            }
        }
        Button("Remove", systemImage: "trash", role: .destructive) { wishlist.remove(entry.id) }
    }
}

/// The Wishlist as a CSV file, for the share sheet (a spreadsheet, Files, a script).
private struct WishlistCSV: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.text.utf8) }
            .suggestedFileName("Wishlist.csv")
    }
}
