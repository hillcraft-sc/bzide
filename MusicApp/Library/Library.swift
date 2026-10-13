import Foundation
import NavidromeCore

/// What the library screens need, handed down from the root. Builds each
/// screen's model so views never see the server client.
final class Library {
    let engine: PlaybackEngine
    let stars: StarModel
    let ratings: RatingModel
    let quickActions: QuickActions
    let radio: RadioPlayer
    /// Shared so covers fetched once stay for the session.
    let genreCovers: GenreCovers
    let playlistEditor: PlaylistEditor
    /// How Siri finds things on the server. Not for views, which use the models.
    let siriLookup: SiriLookup
    /// Which songs the Add to Playlist sheet is open for.
    let addToPlaylist: AddToPlaylistRequest
    let artwork: ArtworkCache
    let settings: StreamingSettingsModel
    let downloads: DownloadManager
    let history: PlayHistory
    let lyrics: LyricsModel
    let profile: ProfileModel
    /// Keeps downloaded playlists in step with the server.
    let playlistRefresher: PlaylistDownloadRefresher
    private let client: SubsonicClient

    init(
        client: SubsonicClient, username: String, engine: PlaybackEngine, artwork: ArtworkCache,
        settings: StreamingSettingsModel, downloads: DownloadManager, history: PlayHistory
    ) {
        self.downloads = downloads
        self.history = history
        let playlistRefresher = PlaylistDownloadRefresher(downloads: downloads) { [client] id async throws(SubsonicError) in
            try await client.playlist(id: id)
        }
        self.playlistRefresher = playlistRefresher
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
            create: { [client] name, ids async throws(SubsonicError) in try await client.createPlaylist(name: name, songIDs: ids) },
            add: { [client] id, ids async throws(SubsonicError) in
                try await client.addToPlaylist(id: id, songIDs: ids)
                // A downloaded playlist gets the new songs too.
                await playlistRefresher.refresh(playlistID: id)
            }
        ))
        self.siriLookup = SiriLookup(
            artist: { [client] id async throws(SubsonicError) in try await client.artist(id: id) },
            album: { [client] id async throws(SubsonicError) in try await client.album(id: id) },
            playlist: { [client] id async throws(SubsonicError) in try await client.playlist(id: id) },
            song: { [client] id async throws(SubsonicError) in try await client.song(id: id) },
            playlists: { [client] () async throws(SubsonicError) in try await client.playlists() },
            search: { [client] query async throws(SubsonicError) in try await client.search(query, artistCount: 10, albumCount: 10, songCount: 10) }
        )
        self.genreCovers = GenreCovers { [client] genre async throws(SubsonicError) in
            try await client.albumList(.byGenre(genre), size: 1).first?.coverArtID
        }
        self.profile = Self.makeProfile(client: client, username: username)
        // LRCLIB is on the open internet: no shared cache or cookies.
        let lyricsSession = URLSession(configuration: .ephemeral)
        self.lyrics = LyricsModel(sources: .live(
            client: client,
            lrclib: LRCLIBClient(transport: URLSessionTransport(session: lyricsSession))
        ))
        // Station playlist files live on the open internet: no shared cache or cookies.
        let playlistSession = URLSession(configuration: .ephemeral)
        self.radio = RadioPlayer(
            fetchPlaylist: { url in try await playlistSession.data(from: url).0 },
            play: { [engine] station in engine.play(songs: [station]) }
        )
        let addToPlaylist = AddToPlaylistRequest()
        self.addToPlaylist = addToPlaylist
        self.quickActions = QuickActions(
            server: QuickActions.Server(
                album: { [client] id async throws(SubsonicError) in try await client.album(id: id) },
                playlist: { [client] id async throws(SubsonicError) in try await client.playlist(id: id) },
                artist: { [client] id async throws(SubsonicError) in try await client.artist(id: id) },
                genreSongs: { [client] genre async throws(SubsonicError) in try await client.songs(inGenre: genre) }
            ),
            handle: { [engine, downloads] action, resolved in
                switch action {
                case .play: engine.play(songs: resolved.songs)
                case .shuffle: engine.playShuffled(resolved.songs)
                case .playNext: engine.playNext(resolved.songs)
                case .addToQueue: engine.append(resolved.songs)
                case .addToPlaylist: addToPlaylist.open(resolved.songs)
                case .download: if let collection = resolved.download { downloads.download(collection) }
                }
            }
        )
    }

    /// The profile picture settings, saved with the account's other data.
    private static func makeProfile(client: SubsonicClient, username: String) -> ProfileModel {
        let fileManager = FileManager.default
        let support = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let caches = try? fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        // Gravatar is on the open internet: no shared cache or cookies.
        let session = URLSession(configuration: .ephemeral)
        return ProfileModel(
            fileURL: support?.appending(path: ProfileModel.fileName),
            picturesDirectory: support?.appending(path: ProfileModel.picturesDirectoryName),
            cacheDirectory: caches?.appending(path: ProfileModel.cacheDirectoryName),
            services: .init(
                serverEmail: { try await client.userEmail(username: username) },
                image: { url in try await fetchGravatar(url, session: session) }
            )
        )
    }

    /// The picture, or `nil` when Gravatar has none (it answers 404).
    nonisolated private static func fetchGravatar(_ url: URL, session: URLSession) async throws -> Data? {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return data
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

    func favoritesModel() -> LoadModel<SearchResult> {
        LoadModel { [client] () async throws(SubsonicError) in try await client.favorites() }
    }

    func genresModel() -> LoadModel<[Genre]> {
        LoadModel { [client] () async throws(SubsonicError) in Genre.forBrowsing(try await client.genres()) }
    }

    func genreAlbumsModel(_ genre: String) -> AlbumsModel {
        AlbumsModel(listType: .byGenre(genre)) { [client] type, size, offset async throws(SubsonicError) in
            try await client.albumList(type, size: size, offset: offset)
        }
    }

    func radioStationsModel() -> LoadModel<[RadioStation]> {
        LoadModel { [client] () async throws(SubsonicError) in
            try await client.radioStations().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func albumModel(id: String) -> LoadModel<Album> {
        LoadModel { [client] () async throws(SubsonicError) in try await client.album(id: id) }
    }

    func playlistsModel() -> LoadModel<[Playlist]> {
        LoadModel { [client] () async throws(SubsonicError) in try await client.playlists() }
    }

    func playlistModel(id: String) -> LoadModel<Playlist> {
        LoadModel { [client, playlistRefresher] () async throws(SubsonicError) in
            let playlist = try await client.playlist(id: id)
            // Opening a downloaded playlist brings its download up to date.
            await playlistRefresher.refresh(playlist)
            return playlist
        }
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
