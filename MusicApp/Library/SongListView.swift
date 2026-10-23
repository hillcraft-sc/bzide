import NavidromeCore
import SwiftUI

/// Changing a list's songs: a playlist the user owns.
struct SongListEditing {
    let remove: (IndexSet) -> Void
    let move: (IndexSet, Int) -> Void
}

/// The body of an album or playlist screen: header, play/shuffle, then the songs.
/// Tapping a song plays the whole list from that song. With `editing`, songs
/// can be swiped away, removed from their long-press menu, and dragged into
/// a new order, like the queue.
struct SongListView<Header: View>: View {
    let library: Library
    let songs: [Song]
    let showsTrackNumbers: Bool
    var editing: SongListEditing? = nil
    @ViewBuilder let header: () -> Header

    var body: some View {
        List {
            Section {
                header()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                HStack(spacing: 12) {
                    Button("Play", systemImage: "play.fill") { library.engine.play(songs: songs) }
                    Button("Shuffle", systemImage: "shuffle") { library.engine.playShuffled(songs) }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(songs.isEmpty)
                .listRowSeparator(.hidden)
            }
            .themedRows()
            Section {
                ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                    Button {
                        library.engine.play(songs: songs, startIndex: index)
                    } label: {
                        SongRow(
                            song: song,
                            isCurrent: song.id == library.engine.queue.current?.song.id,
                            showsTrackNumber: showsTrackNumbers,
                            isFavorite: library.isFavorite(song),
                            stars: library.stars(of: song)
                        )
                    }
                    .foregroundStyle(.primary)
                    // Track numbers mean this is the album itself.
                    .contextMenu {
                        SongActions(library: library, song: song, showsGoToAlbum: !showsTrackNumbers)
                        if let editing {
                            removeButton(at: index, editing)
                        }
                    }
                    .swipeActions {
                        if let editing {
                            removeButton(at: index, editing)
                        }
                    }
                    .siriEntity(songID: song.id)
                }
                .onMove(perform: editing.map { editing in { editing.move($0, $1) } })
            }
            .themedRows()
        }
        .listStyle(.plain)
        .themedList()
    }

    /// Takes the song out of this list only; it stays in the library.
    private func removeButton(at index: Int, _ editing: SongListEditing) -> some View {
        Button("Remove from Playlist", systemImage: "minus.circle", role: .destructive) {
            editing.remove(IndexSet(integer: index))
        }
    }
}

/// Artwork and titles at the top of an album or playlist.
struct SongListHeader: View {
    let library: Library
    let coverArtID: String?
    let title: String
    let subtitle: String?
    /// A smaller line of details, e.g. an album's genre, songs and length.
    var detail: String?

    var body: some View {
        VStack(spacing: 8) {
            ArtworkView(library: library, coverArtID: coverArtID, side: 220)
            Text(title.isEmpty ? "Untitled" : title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 8)
    }
}
