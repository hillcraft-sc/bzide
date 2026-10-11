import NavidromeCore
import SwiftUI

/// The Library tab's first screen.
struct LibraryView: View {
    let model: AppModel
    let library: Library

    var body: some View {
        List {
            NavigationLink(value: LibraryRoute.artists) { Label("Artists", systemImage: "music.microphone") }
            NavigationLink(value: LibraryRoute.albums) { Label("Albums", systemImage: "square.stack") }
            NavigationLink(value: LibraryRoute.playlists) { Label("Playlists", systemImage: "music.note.list") }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem {
                // Kept for exercising playback during development.
                NavigationLink {
                    DebugPlayerView(model: model, engine: library.engine)
                } label: {
                    Label("Debug Player", systemImage: "ladybug")
                }
            }
        }
    }
}

struct ArtistsView: View {
    let library: Library
    @State private var model: LoadModel<[ArtistSection]>

    init(library: Library) {
        self.library = library
        _model = State(initialValue: library.artistsModel())
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { sections in
            List {
                ForEach(sections, id: \.name) { section in
                    Section(section.name) {
                        ForEach(section.artists) { artist in
                            NavigationLink(value: LibraryRoute.artist(id: artist.id)) {
                                Text(artist.name.isEmpty ? "Unknown Artist" : artist.name)
                            }
                        }
                    }
                    .sectionIndexLabel(section.name)
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Artists")
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

struct AlbumsView: View {
    let library: Library
    @State private var model: AlbumsModel

    init(library: Library) {
        self.library = library
        _model = State(initialValue: library.albumsModel())
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { albums in
            List {
                ForEach(albums) { album in
                    NavigationLink(value: LibraryRoute.album(id: album.id)) {
                        AlbumRow(library: library, album: album)
                    }
                    .task { await model.loadMoreIfNeeded(after: album) }
                }
                if model.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let error = model.loadMoreError {
                    VStack(spacing: 8) {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        Button("Load More") { Task { await model.loadMore() } }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.plain)
            .overlay {
                if albums.isEmpty {
                    ContentUnavailableView("No Albums", systemImage: "square.stack")
                }
            }
        }
        .navigationTitle(model.sort.title)
        .toolbar {
            ToolbarItem {
                Menu("Sort", systemImage: "arrow.up.arrow.down") {
                    Picker("Sort", selection: Binding(get: { model.sort }, set: { sort in Task { await model.setSort(sort) } })) {
                        ForEach(AlbumSort.allCases, id: \.self) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                }
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

struct PlaylistsView: View {
    let library: Library
    @State private var model: LoadModel<[Playlist]>

    init(library: Library) {
        self.library = library
        _model = State(initialValue: library.playlistsModel())
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { playlists in
            List(playlists) { playlist in
                NavigationLink(value: LibraryRoute.playlist(id: playlist.id)) {
                    HStack(spacing: 12) {
                        ArtworkView(library: library, coverArtID: playlist.coverArtID, side: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlist.name.isEmpty ? "Untitled" : playlist.name).lineLimit(1)
                            if let count = playlist.songCount {
                                Text("\(count) songs").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if playlists.isEmpty {
                    ContentUnavailableView("No Playlists", systemImage: "music.note.list")
                }
            }
        }
        .navigationTitle("Playlists")
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}
