import NavidromeCore
import SwiftUI

/// Where a library link goes. Each tab's navigation stack resolves these with
/// `libraryDestinations(_:)`.
enum LibraryRoute: Hashable {
    case artists
    case albums
    case playlists
    case downloads
    case history
    case artist(id: String)
    case album(id: String)
    case playlist(id: String)
}

extension View {
    func libraryDestinations(_ library: Library) -> some View {
        navigationDestination(for: LibraryRoute.self) { route in
            switch route {
            case .artists: ArtistsView(library: library)
            case .albums: AlbumsView(library: library)
            case .playlists: PlaylistsView(library: library)
            case .downloads: DownloadsView(library: library)
            case .history: HistoryView(library: library)
            case .artist(let id): ArtistView(library: library, id: id)
            case .album(let id): AlbumView(library: library, id: id)
            case .playlist(let id): PlaylistView(library: library, id: id)
            }
        }
    }
}

struct AlbumView: View {
    let library: Library
    @State private var model: LoadModel<Album>

    init(library: Library, id: String) {
        self.library = library
        _model = State(initialValue: library.albumModel(id: id))
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { album in
            SongListView(library: library, songs: album.songs, showsTrackNumbers: true) {
                SongListHeader(
                    library: library,
                    coverArtID: album.coverArtID,
                    title: album.name,
                    subtitle: [album.artist, album.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
                )
                .siriEntity(albumID: album.id)
            }
            .toolbar {
                ToolbarItem {
                    DownloadButton(downloads: library.downloads, collection: DownloadCollection(album: album))
                }
                ToolbarItem {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Play Next", systemImage: "text.insert") { library.engine.playNext(album.songs) }
                        Button("Add to Queue", systemImage: "text.append") { library.engine.append(album.songs) }
                        AddToPlaylistButton(library: library, songs: album.songs)
                        MarkActions(library: library, target: .album(id: album.id), isStarred: album.isStarred, userRating: album.userRating)
                        if let artistID = album.artistID {
                            NavigationLink("Go to Artist", value: LibraryRoute.artist(id: artistID))
                        }
                    }
                }
            }
        }
        .navigationTitle(model.value?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

struct PlaylistView: View {
    let library: Library
    @State private var model: LoadModel<Playlist>

    init(library: Library, id: String) {
        self.library = library
        _model = State(initialValue: library.playlistModel(id: id))
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { playlist in
            SongListView(library: library, songs: playlist.songs, showsTrackNumbers: false) {
                SongListHeader(
                    library: library,
                    coverArtID: playlist.coverArtID,
                    title: playlist.name,
                    subtitle: playlist.songCount.map { "\($0) songs" }
                )
                .siriEntity(playlistID: playlist.id)
            }
            .toolbar {
                ToolbarItem {
                    DownloadButton(downloads: library.downloads, collection: DownloadCollection(playlist: playlist))
                }
                ToolbarItem {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Play Next", systemImage: "text.insert") { library.engine.playNext(playlist.songs) }
                        Button("Add to Queue", systemImage: "text.append") { library.engine.append(playlist.songs) }
                        AddToPlaylistButton(library: library, songs: playlist.songs)
                    }
                }
            }
        }
        .navigationTitle(model.value?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

struct ArtistView: View {
    let library: Library
    @State private var model: LoadModel<Artist>
    /// Loaded separately: a slow or failed lookup never holds up the albums.
    @State private var info: LoadModel<ArtistInfo>

    init(library: Library, id: String) {
        self.library = library
        _model = State(initialValue: library.artistModel(id: id))
        _info = State(initialValue: library.artistInfoModel(id: id))
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { artist in
            List {
                Section {
                    ArtistHeader(library: library, artist: artist, biography: info.value?.biography)
                        .siriEntity(artistID: artist.id)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
                .themedRows()
                Section {
                    ForEach(artist.albums) { album in
                        NavigationLink(value: LibraryRoute.album(id: album.id)) {
                            AlbumRow(library: library, album: album)
                        }
                        .contextMenu { AlbumRowMenu(library: library, album: album, showsGoToArtist: false) }
                        .siriEntity(albumID: album.id)
                    }
                    if artist.albums.isEmpty {
                        Text("No Albums").foregroundStyle(.secondary)
                    }
                }
                .themedRows()
            }
            .listStyle(.plain)
            .themedList()
            .toolbar {
                ToolbarItem {
                    Menu("More", systemImage: "ellipsis") {
                        ArtistRowMenu(library: library, artist: artist)
                    }
                }
            }
        }
        .navigationTitle(model.value?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        async let albums: Void = model.load()
        async let biography: Void = info.load()
        _ = await (albums, biography)
    }
}

/// Artist image and name, then the first lines of the biography; tapping
/// More shows the rest.
private struct ArtistHeader: View {
    let library: Library
    let artist: Artist
    let biography: String?

    var body: some View {
        VStack(spacing: 8) {
            ArtworkView(library: library, coverArtID: artist.coverArtID, side: 220)
            Text(artist.name.isEmpty ? "Unknown Artist" : artist.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if let biography {
                Biography(text: biography)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct Biography: View {
    let text: String

    @State private var isExpanded = false
    @State private var shortHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    /// Only offer More when three lines don't already show it all.
    private var isTruncated: Bool { fullHeight > shortHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .lineLimit(isExpanded ? nil : 3)
                .foregroundStyle(.secondary)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if !isExpanded { shortHeight = $0 } }
                .background(alignment: .top) {
                    // The full text, unseen, to measure against.
                    Text(text)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                }
            if isTruncated {
                Button(isExpanded ? "Less" : "More") {
                    withAnimation { isExpanded.toggle() }
                }
                .font(.subheadline.bold())
                .buttonStyle(.borderless)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
