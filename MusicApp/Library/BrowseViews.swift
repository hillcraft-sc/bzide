import NavidromeCore
import SwiftUI

/// The Library tab's first screen.
/// The Library tab: Recently Added, Random Mix and links to each kind of
/// list, shown and ordered as the user chooses (Edit).
struct LibraryView: View {
    let model: AppModel
    let library: Library
    @State private var recentlyAdded: LoadModel<[Album]>
    @State private var recentlyPlayed: LoadModel<[Album]>
    @State private var spinItBack: LoadModel<[Album]>
    @State private var isEditing = false
    /// Spin the Dial was tapped with Find Stations Online off.
    @State private var isAskingForStations = false
    /// Remembered on this device: display preferences, nothing to sync.
    @AppStorage("recentlyAddedCollapsed") private var isRecentlyAddedCollapsed = false
    @AppStorage("recentlyPlayedCollapsed") private var isRecentlyPlayedCollapsed = false
    @AppStorage("spinItBackCollapsed") private var isSpinItBackCollapsed = false

    init(model: AppModel, library: Library) {
        self.model = model
        self.library = library
        _recentlyAdded = State(initialValue: library.recentlyAddedModel())
        _recentlyPlayed = State(initialValue: library.recentlyPlayedModel())
        _spinItBack = State(initialValue: library.spinItBackModel())
    }

    private var layout: LibraryLayout { model.libraryLayout.layout }
    private var randomMix: RandomMixModel { library.randomMix }

    var body: some View {
        List {
            ForEach(Array(layout.groups.enumerated()), id: \.offset) { _, group in
                switch group {
                case .carousel(let item):
                    carousel(item)
                        .themedRows(grouped: true)
                case .mixes(let items):
                    mixesSection(items)
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
        // Each return to Library refreshes the carousels shown, as does showing
        // one in Edit Library; they stay on screen meanwhile.
        .task(id: layout.shown) { await loadCarousels() }
        .refreshable { await loadCarousels() }
        .toolbar {
            ToolbarItem {
                Button("Edit", systemImage: "rectangle.grid.1x3") { isEditing = true } // square.stack
            }
            ToolbarItem {
                NavigationLink {
                    SettingsView(
                        settings: library.settings, equalizer: model.equalizer, engine: library.engine, downloads: library.downloads, history: library.history, wishlist: library.wishlist,
                        appearance: model.appearance, profile: library.profile, account: model.account, signOut: model.signOut, restoreDefaults: model.restoreDefaultSettings,
                        debugPlayer: { DebugPlayerView(model: model, engine: library.engine) },
                        stationSearch: { library.stationSearchModel() },
                        refreshLibrary: { try await library.refreshLibrary() }
                    )
                } label: {
                    // The user's Gravatar, if they've turned it on and one was found.
                    // Drawn as a view, not a label icon, which the toolbar would flatten.
                    if let avatar = library.profile.avatar {
                        AvatarImage(data: avatar, side: 30)
                            .accessibilityHidden(false)
                            .accessibilityLabel("Settings")
                    } else {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
        }
        .alert("Find Stations Online", isPresented: $isAskingForStations) {
            Button("Turn On and Spin") {
                library.settings.settings.findStationsOnline = true
                Task { await library.spinTheDialNow() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Spin the Dial finds stations on Radio Browser (radio-browser.info). Turning on Find Stations Online sends it the genre and settings for each spin, never your listening history.")
        }
        .sheet(isPresented: $isEditing) {
            EditLibrarySheet(layout: model.libraryLayout)
        }
    }

    @ViewBuilder
    private func carousel(_ item: LibraryFeature) -> some View {
        switch item {
        case .recentlyPlayed:
            AlbumCarouselSection(
                library: library, title: item.title, shows: "albums played this week",
                emptyText: "Nothing played this week", model: recentlyPlayed, isCollapsed: $isRecentlyPlayedCollapsed,
                seeAll: .history
            )
        case .spinItBack:
            AlbumCarouselSection(
                library: library, title: item.title, shows: "albums worth hearing again",
                emptyText: "Rate or favorite some albums, and ones you haven't played in a while will appear here",
                model: spinItBack, isCollapsed: $isSpinItBackCollapsed
            )
        default:
            AlbumCarouselSection(
                library: library, title: item.title, shows: "the newest albums",
                emptyText: "No albums yet", model: recentlyAdded, isCollapsed: $isRecentlyAddedCollapsed,
                seeAll: .albums
            )
        }
    }

    /// Only the carousels shown are fetched, all at once.
    private func loadCarousels() async {
        let shown = Set(layout.shown)
        async let added: Void = shown.contains(.recentlyAdded) ? recentlyAdded.load() : ()
        async let played: Void = shown.contains(.recentlyPlayed) ? recentlyPlayed.load() : ()
        async let again: Void = shown.contains(.spinItBack) ? spinItBack.load() : ()
        _ = await (added, played, again)
    }

    /// Random Mix, Mix My Cuts and Spin the Dial, in the order chosen, in one block.
    private func mixesSection(_ items: [LibraryFeature]) -> some View {
        Section {
            ForEach(items, id: \.self) { item in
                switch item {
                case .spinTheDial:
                    Button {
                        if library.settings.settings.findStationsOnline {
                            Task { await library.spinTheDialNow() }
                        } else {
                            isAskingForStations = true
                        }
                    } label: {
                        HStack {
                            Label("Spin the Dial", systemImage: item.symbol)
                            Spacer()
                            if library.spinTheDial.isSpinning { ProgressView() }
                        }
                    }
                    .disabled(library.spinTheDial.isSpinning)
                    .accessibilityHint("Plays a radio station picked for you from Radio Browser")
                case .ratedShuffle:
                    Button {
                        Task { await library.spinOff.startRated() }
                    } label: {
                        HStack {
                            Label("Mix My Cuts", systemImage: item.symbol) // item.symbol
                            Spacer()
                            if library.spinOff.isStarting { ProgressView() }
                        }
                    }
                    .disabled(library.spinOff.isStarting)
                    .accessibilityHint(library.settings.settings.useSimplifiedRating
                        ? "Plays the songs you Love or Like, and favorites if included, shuffled, without end"
                        : "Plays the songs you rated 3 stars or more, and favorites if included, shuffled, without end")
                default:
                    Button {
                        Task { await randomMix.start() }
                    } label: {
                        HStack {
                            Label("Random Mix", systemImage: item.symbol)
                            Spacer()
                            if randomMix.isLoading { ProgressView() }
                        }
                    }
                    .disabled(randomMix.isLoading)
                }
            }
        } footer: {
            if let error = randomMix.error {
                Text(error).foregroundStyle(.red)
            } else if let notice = randomMix.notice {
                Text(notice)
            }
        }
        .labelStyle(WrappingLabelStyle())
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
                                if entry.item.isCarousel {
                                    Spacer()
                                    // Marks the rows of album covers.
                                    Image(systemName: "rectangle.split.3x1")
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Carousel")
                                }
                            }
                        }
                        .accessibilityValue(entry.isShown ? "Shown" : "Hidden")
                    }
                    .onMove { source, destination in
                        layout.layout.move(fromOffsets: source, toOffset: destination)
                    }
                } footer: {
                    Text("Tap to show or hide. Drag to reorder. \(Image(systemName: "rectangle.split.3x1")) marks a carousel, a row of album covers.")
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
        case .recentlyPlayed: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .spinItBack: "arrow.uturn.backward.circle"
        case .randomMix: "shuffle"
        case .ratedShuffle: "flame" // "hand.thumbsup" 
        case .spinTheDial: "dial.medium"
        case .artists: "music.microphone"
        case .albums: "square.stack"
        case .playlists: "music.note.list"
        case .favorites: "heart"
        case .genres: "guitars"
        case .radio: "headphones.sensor.tag.radiowaves.left.and.right" // dot.radiowaves.left.and.right
        case .downloads: "arrow.down.circle"
        case .history: "clock.arrow.circlepath"
        case .wishlist: "tag"
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
        case .wishlist: .wishlist
        case .recentlyAdded, .recentlyPlayed, .spinItBack, .randomMix, .ratedShuffle, .spinTheDial: nil
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
                        ForEach(AlbumSort.phoneSorts, id: \.self) { sort in
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
                    await library.playlistEditor.create(named: newName, with: [])
                }
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        // Failed changes show from the root (`playlistPrompts`).
        .task { await model.load() }
        .refreshable { await model.load() }
        // A rename, share, delete or new playlist from anywhere shows here.
        .onChange(of: library.playlistEditor.revision) {
            Task { await model.load() }
        }
    }
}
