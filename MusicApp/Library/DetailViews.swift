import NavidromeCore
import SwiftUI

/// Where a library link goes. Each tab's navigation stack resolves these with
/// `libraryDestinations(_:)`.
enum LibraryRoute: Hashable {
    case artists
    case albums
    case playlists
    case downloads
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
            }
            .toolbar {
                ToolbarItem {
                    DownloadButton(downloads: library.downloads, collection: DownloadCollection(album: album))
                }
                ToolbarItem {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Add to Queue", systemImage: "text.append") { library.engine.append(album.songs) }
                        StarButton(stars: library.stars, target: .album(id: album.id), fromServer: album.isStarred)
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
            }
            .toolbar {
                ToolbarItem {
                    DownloadButton(downloads: library.downloads, collection: DownloadCollection(playlist: playlist))
                }
                ToolbarItem {
                    Button("Add to Queue", systemImage: "text.append") { library.engine.append(playlist.songs) }
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

    init(library: Library, id: String) {
        self.library = library
        _model = State(initialValue: library.artistModel(id: id))
    }

    var body: some View {
        LoadStateView(state: model.state, retry: model.load) { artist in
            List(artist.albums) { album in
                NavigationLink(value: LibraryRoute.album(id: album.id)) {
                    AlbumRow(library: library, album: album)
                }
            }
            .listStyle(.plain)
            .overlay {
                if artist.albums.isEmpty {
                    ContentUnavailableView("No Albums", systemImage: "square.stack")
                }
            }
            .toolbar {
                ToolbarItem {
                    StarButton(stars: library.stars, target: .artist(id: artist.id), fromServer: artist.isStarred)
                }
            }
        }
        .navigationTitle(model.value?.name ?? "")
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}
