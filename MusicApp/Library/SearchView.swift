import NavidromeCore
import SwiftUI

struct SearchView: View {
    let library: Library
    @State private var model: SearchModel

    init(library: Library) {
        self.library = library
        _model = State(initialValue: library.searchModel())
    }

    var body: some View {
        List {
            Group {
                if let results = model.results {
                    if !results.artists.isEmpty {
                        Section("Artists") {
                            ForEach(results.artists) { artist in
                                NavigationLink(artist.name.isEmpty ? "Unknown Artist" : artist.name, value: LibraryRoute.artist(id: artist.id))
                            }
                        }
                    }
                    if !results.albums.isEmpty {
                        Section("Albums") {
                            ForEach(results.albums) { album in
                                NavigationLink(value: LibraryRoute.album(id: album.id)) {
                                    AlbumRow(library: library, album: album)
                                }
                            }
                        }
                    }
                    if !results.songs.isEmpty {
                        Section("Songs") {
                            ForEach(Array(results.songs.enumerated()), id: \.offset) { index, song in
                                Button {
                                    library.engine.play(songs: results.songs, startIndex: index)
                                } label: {
                                    SongRow(song: song, isCurrent: song.id == library.engine.queue.current?.song.id)
                                }
                                .foregroundStyle(.primary)
                                .contextMenu { SongActions(library: library, song: song) }
                            }
                        }
                    }
                }
            }
            .themedRows()
        }
        .listStyle(.plain)
        .themedList()
        .overlay { overlay }
        .navigationTitle("Search")
        .searchable(text: Binding(get: { model.query }, set: { model.updateQuery($0) }), prompt: "Artists, albums, songs")
    }

    @ViewBuilder private var overlay: some View {
        if let error = model.error {
            ContentUnavailableView {
                Label("Search Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { model.retry() }
            }
        } else if model.isSearching, model.results == nil {
            ProgressView()
        } else if let results = model.results, results.artists.isEmpty, results.albums.isEmpty, results.songs.isEmpty {
            ContentUnavailableView.search(text: model.query)
        }
    }
}
