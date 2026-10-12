import NavidromeCore
import SwiftUI

/// The Library tab's first screen.
struct LibraryView: View {
    let model: AppModel
    let library: Library
    @State private var randomMix: RandomMixModel

    init(model: AppModel, library: Library) {
        self.model = model
        self.library = library
        _randomMix = State(initialValue: library.randomMixModel())
    }

    var body: some View {
        List {
            Section {
                Button {
                    Task { await randomMix.start() }
                } label: {
                    HStack {
                        Label("Random Mix", systemImage: "shuffle")
                        Spacer()
                        if randomMix.isLoading { ProgressView() }
                    }
                }
                .disabled(randomMix.isLoading)
            } footer: {
                if let error = randomMix.error {
                    Text(error).foregroundStyle(.red)
                } else if let notice = randomMix.notice {
                    Text(notice)
                }
            }
            .themedRows(grouped: true)
            Section {
                NavigationLink(value: LibraryRoute.artists) { Label("Artists", systemImage: "music.microphone") }
                NavigationLink(value: LibraryRoute.albums) { Label("Albums", systemImage: "square.stack") }
                NavigationLink(value: LibraryRoute.playlists) { Label("Playlists", systemImage: "music.note.list") }
                NavigationLink(value: LibraryRoute.downloads) { Label("Downloaded", systemImage: "arrow.down.circle") }
                NavigationLink(value: LibraryRoute.history) { Label("History", systemImage: "clock.arrow.circlepath") }
            }
            .themedRows(grouped: true)
        }
        .themedList(grouped: true)
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem {
                NavigationLink {
                    SettingsView(
                        settings: library.settings, downloads: library.downloads, history: library.history,
                        appearance: model.appearance, account: model.account, signOut: model.signOut
                    )
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
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
                .themedRows()
            }
            .listStyle(.plain)
            .themedList()
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
                .themedRows()
                Group {
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
                .themedRows()
            }
            .listStyle(.plain)
            .themedList()
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
                .themedRows()
            }
            .listStyle(.plain)
            .themedList()
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
