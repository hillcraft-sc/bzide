import NavidromeCore
import SwiftUI

/// The body of an album or playlist screen: header, play/shuffle, then the songs.
/// Tapping a song plays the whole list from that song.
struct SongListView<Header: View>: View {
    let library: Library
    let songs: [Song]
    let showsTrackNumbers: Bool
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
                    .contextMenu { SongActions(library: library, song: song, showsGoToAlbum: !showsTrackNumbers) }
                    .siriEntity(songID: song.id)
                }
            }
            .themedRows()
        }
        .listStyle(.plain)
        .themedList()
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
