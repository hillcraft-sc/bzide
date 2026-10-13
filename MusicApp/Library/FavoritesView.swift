import NavidromeCore
import SwiftUI

/// Everything favorited (hearted), from the server: songs first, with Play
/// and Shuffle, then albums and artists. Unfavoriting something anywhere takes
/// it off the list at once; it reloads each time it's opened.
struct FavoritesView: View {
    let library: Library
    @State private var model: LoadModel<SearchResult>

    init(library: Library) {
        self.library = library
        _model = State(initialValue: library.favoritesModel())
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { favorites in
            let songs = favorites.songs.filter { library.stars.isStarred(.song(id: $0.id), fromServer: true) }
            let albums = favorites.albums.filter { library.stars.isStarred(.album(id: $0.id), fromServer: true) }
            let artists = favorites.artists.filter { library.stars.isStarred(.artist(id: $0.id), fromServer: true) }
            List {
                if !songs.isEmpty {
                    Section {
                        HStack(spacing: 12) {
                            Button("Play", systemImage: "play.fill") { library.engine.play(songs: songs) }
                            Button("Shuffle", systemImage: "shuffle") { library.engine.playShuffled(songs) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            Button {
                                library.engine.play(songs: songs, startIndex: index)
                            } label: {
                                SongRow(
                                    song: song,
                                    isCurrent: song.id == library.engine.queue.current?.song.id,
                                    showsTrackNumber: false,
                                    isFavorite: library.isFavorite(song),
                                    rating: library.rating(of: song)
                                )
                            }
                            .foregroundStyle(.primary)
                            .contextMenu { SongActions(library: library, song: song, showsGoToAlbum: true) }
                            .siriEntity(songID: song.id)
                        }
                    } header: {
                        Text("Songs")
                    }
                    .themedRows()
                }
                if !albums.isEmpty {
                    Section("Albums") {
                        ForEach(albums) { album in
                            NavigationLink(value: LibraryRoute.album(id: album.id)) {
                                AlbumRow(library: library, album: album)
                            }
                            .contextMenu { AlbumRowMenu(library: library, album: album) }
                            .siriEntity(albumID: album.id)
                        }
                    }
                    .themedRows()
                }
                if !artists.isEmpty {
                    Section("Artists") {
                        ForEach(artists) { artist in
                            NavigationLink(value: LibraryRoute.artist(id: artist.id)) {
                                Text(artist.name.isEmpty ? "Unknown Artist" : artist.name)
                            }
                            .contextMenu { ArtistRowMenu(library: library, artist: artist) }
                            .siriEntity(artistID: artist.id)
                        }
                    }
                    .themedRows()
                }
            }
            .listStyle(.plain)
            .themedList()
            .overlay {
                if songs.isEmpty && albums.isEmpty && artists.isEmpty {
                    ContentUnavailableView(
                        "No Favorites",
                        systemImage: "heart",
                        description: Text("Tap the heart on a song, album or artist to add it here.")
                    )
                }
            }
        }
        .navigationTitle("Favorites")
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}
