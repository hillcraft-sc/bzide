import NavidromeCore

/// What the library screens need, handed down from the root. Builds each
/// screen's model so views never see the server client.
final class Library {
    let engine: PlaybackEngine
    let stars: StarModel
    let ratings: RatingModel
    let albumQueue: AlbumQueueModel
    let playlistEditor: PlaylistEditor
    /// Which songs the Add to Playlist sheet is open for.
    let addToPlaylist = AddToPlaylistRequest()
    let artwork: ArtworkCache
    let settings: StreamingSettingsModel
    let downloads: DownloadManager
    let history: PlayHistory
    private let client: SubsonicClient

    init(
        client: SubsonicClient, username: String, engine: PlaybackEngine, artwork: ArtworkCache,
        settings: StreamingSettingsModel, downloads: DownloadManager, history: PlayHistory
    ) {
        self.downloads = downloads
        self.history = history
        self.client = client
        self.engine = engine
        self.artwork = artwork
        self.settings = settings
        self.stars = StarModel { [client] target, starred async throws(SubsonicError) in
            if starred {
                try await client.star(target)
            } else {
                try await client.unstar(target)
            }
        }
        self.ratings = RatingModel { [client] target, stars async throws(SubsonicError) in
            try await client.setRating(target, stars: stars)
        }
        self.playlistEditor = PlaylistEditor(username: username, server: PlaylistEditor.Server(
            playlists: { [client] () async throws(SubsonicError) in try await client.playlists() },
            playlist: { [client] id async throws(SubsonicError) in try await client.playlist(id: id) },
            albumSongs: { [client] id async throws(SubsonicError) in try await client.album(id: id).songs },
            create: { [client] name, ids async throws(SubsonicError) in try await client.createPlaylist(name: name, songIDs: ids) },
            add: { [client] id, ids async throws(SubsonicError) in try await client.addToPlaylist(id: id, songIDs: ids) }
        ))
        self.albumQueue = AlbumQueueModel(
            fetch: { [client] id async throws(SubsonicError) in try await client.album(id: id).songs },
            perform: { [engine] action, songs in
                switch action {
                case .play: engine.play(songs: songs)
                case .playNext: engine.playNext(songs)
                case .addToQueue: engine.append(songs)
                }
            }
        )
    }

    func artistsModel() -> LoadModel<[ArtistSection]> {
        LoadModel { [client] () async throws(SubsonicError) in try await client.artists() }
    }

    func artistModel(id: String) -> LoadModel<Artist> {
        LoadModel { [client] () async throws(SubsonicError) in try await client.artist(id: id) }
    }

    func artistInfoModel(id: String) -> LoadModel<ArtistInfo> {
        LoadModel { [client] () async throws(SubsonicError) in try await client.artistInfo(id: id) }
    }

    /// The newest albums, for the row at the top of Library.
    func recentlyAddedModel() -> LoadModel<[Album]> {
        LoadModel { [client] () async throws(SubsonicError) in try await client.albumList(.newest, size: 15) }
    }

    func albumModel(id: String) -> LoadModel<Album> {
        LoadModel { [client] () async throws(SubsonicError) in try await client.album(id: id) }
    }

    func playlistsModel() -> LoadModel<[Playlist]> {
        LoadModel { [client] () async throws(SubsonicError) in try await client.playlists() }
    }

    func playlistModel(id: String) -> LoadModel<Playlist> {
        LoadModel { [client] () async throws(SubsonicError) in try await client.playlist(id: id) }
    }

    func albumsModel(sort: AlbumSort = .newest) -> AlbumsModel {
        AlbumsModel(sort: sort) { [client] type, size, offset async throws(SubsonicError) in
            try await client.albumList(type, size: size, offset: offset)
        }
    }

    func randomMixModel() -> RandomMixModel {
        RandomMixModel(
            fetch: { [client] count async throws(SubsonicError) in try await client.randomSongs(size: count) },
            downloadedSongs: { [downloads] in downloads.downloadedSongs() },
            play: { [engine] songs in engine.play(songs: songs) }
        )
    }

    func searchModel() -> SearchModel {
        SearchModel(scheduler: TaskScheduler()) { [client] query async throws(SubsonicError) in
            try await client.search(query)
        }
    }
}
