import NavidromeCore
import SwiftUI

/// The Library tab's first screen.
/// The Library tab: Recently Added, Random Mix and links to each kind of
/// list, shown and ordered as the user chooses (Edit).
struct LibraryView: View {
    let model: AppModel
    let library: Library
    @State private var randomMix: RandomMixModel
    @State private var recentlyAdded: LoadModel<[Album]>
    @State private var isEditing = false
    /// Remembered on this device: a display preference, nothing to sync.
    @AppStorage("recentlyAddedCollapsed") private var isRecentlyAddedCollapsed = false

    init(model: AppModel, library: Library) {
        self.model = model
        self.library = library
        _randomMix = State(initialValue: library.randomMixModel())
        _recentlyAdded = State(initialValue: library.recentlyAddedModel())
    }

    private var layout: LibraryLayout { model.libraryLayout.layout }

    var body: some View {
        List {
            ForEach(Array(layout.groups.enumerated()), id: \.offset) { _, group in
                switch group {
                case .recentlyAdded:
                    RecentlyAddedSection(library: library, model: recentlyAdded, isCollapsed: $isRecentlyAddedCollapsed)
                        .themedRows(grouped: true)
                case .randomMix:
                    randomMixSection
                case .links(let items):
                    Section {
                        ForEach(items, id: \.self) { item in
                            if let route = item.route {
                                NavigationLink(value: route) { Label(item.title, systemImage: item.symbol) }
                            }
                        }
                    }
                    .themedRows(grouped: true)
                }
            }
        }
        .themedList(grouped: true)
        .navigationTitle("Library")
        .overlay {
            if layout.shown.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Shown", systemImage: "eye.slash")
                } description: {
                    Text("Tap Edit to choose what Library shows.")
                }
            }
        }
        // Each return to Library checks for new albums; the row stays on screen meanwhile.
        .task {
            if layout.shown.contains(.recentlyAdded) { await recentlyAdded.load() }
        }
        .refreshable { await recentlyAdded.load() }
        .toolbar {
            ToolbarItem {
                Button("Edit") { isEditing = true }
            }
            ToolbarItem {
                NavigationLink {
                    SettingsView(
                        settings: library.settings, downloads: library.downloads, history: library.history,
                        appearance: model.appearance, account: model.account, signOut: model.signOut,
                        debugPlayer: { DebugPlayerView(model: model, engine: library.engine) }
                    )
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditLibrarySheet(layout: model.libraryLayout)
        }
    }

    private var randomMixSection: some View {
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
    }
}

/// Chooses what Library shows and in what order: tap a row to show or hide
/// it, drag to move it.
private struct EditLibrarySheet: View {
    @Bindable var layout: LibraryLayoutModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layout.layout.entries, id: \.item) { entry in
                        Button {
                            layout.layout.setShown(entry.item, !entry.isShown)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: entry.isShown ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(entry.isShown ? Color.accentColor : .secondary)
                                Label(entry.item.title, systemImage: entry.item.symbol)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .accessibilityValue(entry.isShown ? "Shown" : "Hidden")
                    }
                    .onMove { source, destination in
                        layout.layout.move(fromOffsets: source, toOffset: destination)
                    }
                } footer: {
                    Text("Tap to show or hide. Drag to reorder.")
                }
                .themedRows(grouped: true)
            }
            .themedList(grouped: true)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { layout.reset() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

extension LibraryFeature {
    var symbol: String {
        switch self {
        case .recentlyAdded: "clock.badge"
        case .randomMix: "shuffle"
        case .artists: "music.microphone"
        case .albums: "square.stack"
        case .playlists: "music.note.list"
        case .favorites: "heart"
        case .genres: "guitars"
        case .radio: "dot.radiowaves.left.and.right"
        case .downloads: "arrow.down.circle"
        case .history: "clock.arrow.circlepath"
        }
    }

    /// Where a link opens; `nil` for the sections that aren't links.
    var route: LibraryRoute? {
        switch self {
        case .artists: .artists
        case .albums: .albums
        case .playlists: .playlists
        case .favorites: .favorites
        case .genres: .genres
        case .radio: .radio
        case .downloads: .downloads
        case .history: .history
        case .recentlyAdded, .randomMix: nil
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
