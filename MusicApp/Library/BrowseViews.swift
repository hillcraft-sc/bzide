import NavidromeCore
import SwiftUI

/// The Library tab's first screen.
struct LibraryView: View {
    let model: AppModel
    let library: Library
    @State private var randomMix: RandomMixModel
    @State private var recentlyAdded: LoadModel<[Album]>
    /// Remembered on this device: a display preference, nothing to sync.
    @AppStorage("recentlyAddedCollapsed") private var isRecentlyAddedCollapsed = false

    init(model: AppModel, library: Library) {
        self.model = model
        self.library = library
        _randomMix = State(initialValue: library.randomMixModel())
        _recentlyAdded = State(initialValue: library.recentlyAddedModel())
    }

    var body: some View {
        List {
            RecentlyAddedSection(library: library, model: recentlyAdded, isCollapsed: $isRecentlyAddedCollapsed)
                .themedRows(grouped: true)
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
        // Each return to Library checks for new albums; the row stays on screen meanwhile.
        .task { await recentlyAdded.load() }
        .refreshable { await recentlyAdded.load() }
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
                            .contextMenu { ArtistRowMenu(library: library, artist: artist) }
                            .siriEntity(artistID: artist.id)
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
                    .contextMenu { AlbumRowMenu(library: library, album: album) }
                    .siriEntity(albumID: album.id)
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
    @State private var isNaming = false
    @State private var newName = ""

    init(library: Library) {
        self.library = library
        _model = State(initialValue: library.playlistsModel())
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { playlists in
            List(playlists) { playlist in
                NavigationLink(value: LibraryRoute.playlist(id: playlist.id)) {
                    PlaylistRow(library: library, playlist: playlist)
                }
                .contextMenu { PlaylistRowMenu(library: library, playlist: playlist) }
                .siriEntity(playlistID: playlist.id)
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
        .toolbar {
            ToolbarItem {
                Button("New Playlist", systemImage: "plus") {
                    newName = ""
                    isNaming = true
                }
            }
        }
        .alert("New Playlist", isPresented: $isNaming) {
            TextField("Name", text: $newName)
            Button("Create") {
                Task {
                    if await library.playlistEditor.create(named: newName, with: []) {
                        await model.load()
                    }
                }
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't Save Playlist", isPresented: Binding(
            get: { library.playlistEditor.error != nil && !library.addToPlaylist.isOpen },
            set: { if !$0 { library.playlistEditor.dismissError() } }
        )) {
            Button("OK") { library.playlistEditor.dismissError() }
        } message: {
            Text(library.playlistEditor.error ?? "")
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}
