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
    /// What the Info sheet is open for.
    let info = InfoRequest()
    let artwork: ArtworkCache
    let settings: StreamingSettingsModel
    let downloads: DownloadManager
    let history: PlayHistory
    let lyrics: LyricsModel
    /// The user's timing fixes for synced lyrics, per song.
    let lyricsTiming = LyricsTiming()
    let profile: ProfileModel
    /// Keeps downloaded playlists in step with the server.
    let playlistRefresher: PlaylistDownloadRefresher
    let sleepTimer: SleepTimer
    /// The whole library, for browsing Search by filter (kept for 30 minutes).
    let catalog: LibraryCatalog
    /// The songs Mix My Cuts picks from (kept for 30 minutes).
    private let ratedSongs: RatedSongPool
    /// Endless music grown from a song or artist, and Keep Spinning.
    let spinOff: SpinOffModel
    private let client: SubsonicClient
    private let username: String
    /// What's known about saved radio stations (logo, country, genres,
    /// quality, first seen), shared by every Radio screen.
    private let stationDetails: StationDetailsStore = {
        let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return StationDetailsStore(fileURL: support?.appending(path: StationDetailsStore.fileName))
    }()
    /// Weather (Live)'s place and weather, shared so a forecast and a found
    /// place are reused between openings. MET Norway is on the open internet:
    /// no shared cache or cookies.
    let liveWeather = LiveWeatherSource(met: METNorwayClient(
        contact: Bundle.main.object(forInfoDictionaryKey: "METNorwayContact") as? String ?? "",
        transport: URLSessionTransport(session: URLSession(configuration: .ephemeral))
    ))
    /// Whether the song a station is playing is in the library (Now Playing's
    /// "In Your Library"). Only the user's server is searched.
    private(set) lazy var onAir = OnAirMatchModel { [client] query async throws(SubsonicError) in
        try await client.search(query, artistCount: 0, albumCount: 0, songCount: 20).songs
    }
    /// MusicBrainz's details for the song a station is playing (Song Info and
    /// the cover), while Look Up Songs Online is on.
    private(set) lazy var onAirInfo: OnAirInfoModel = makeOnAirInfo()
    /// One for the app, so radio songs and artist pages share MusicBrainz's
    /// one-request-a-second limit. MusicBrainz is on the open internet: no
    /// shared cache or cookies.
    private let musicBrainz = MusicBrainzClient(
        contact: Library.musicBrainzContact,
        transport: URLSessionTransport(session: URLSession(configuration: .ephemeral))
    )
    /// Look Up Artists Online's biographies and releases, kept on disk for a while.
    private lazy var artistLookup: OnlineArtistLookup = {
        let caches = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let wikipedia = WikipediaClient(
            contact: Library.musicBrainzContact,
            language: Locale.current.language.languageCode?.identifier ?? "en",
            transport: URLSessionTransport(session: URLSession(configuration: .ephemeral))
        )
        return OnlineArtistLookup(musicBrainz: musicBrainz, wikipedia: wikipedia, directory: caches?.appending(path: OnlineArtistLookup.directoryName))
    }()
    private static var musicBrainzContact: String {
        Bundle.main.object(forInfoDictionaryKey: "MusicBrainzContact") as? String ?? ""
    }
    /// Songs heard on the radio to remember (Tagged Radio Songs). On this
    /// iPhone; each account has its own (see `AccountSettings`).
    private(set) lazy var wishlist: Wishlist = {
        let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return Wishlist(fileURL: support?.appending(path: Wishlist.fileName)) { [client] query async throws(SubsonicError) in
            try await client.search(query, artistCount: 0, albumCount: 0, songCount: 20).songs
        }
    }()
    /// Follows what a station is playing, for the on-air cover everywhere
    /// (the lock screen too) and Now Playing's badge and Song Info.
    private var onAirTracker: OnAirTracker?
    /// Spin the Dial, shared by the Library button and Next on a dialed station.
    private(set) lazy var spinTheDial: SpinTheDialModel = makeSpinTheDial()
    /// Radio Browser is on the open internet: no shared cache or cookies.
    private let radioBrowser = RadioBrowserClient(transport: URLSessionTransport(session: URLSession(configuration: .ephemeral)))

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
        self.username = username
        self.engine = engine
        self.sleepTimer = SleepTimer(target: engine)
        self.catalog = LibraryCatalog(sources: .init(
            artists: { try await client.artists().flatMap(\.artists) },
            albumsPage: { count, offset in try await client.albumList(.alphabeticalByName, size: count, offset: offset) },
            songsPage: { count, offset in try await client.allSongs(count: count, offset: offset) }
        ))
        // Mix My Cuts looks through the whole library for rated and favorite songs.
        let ratedSongs = RatedSongPool { count, offset in try await client.allSongs(count: count, offset: offset) }
        self.ratedSongs = ratedSongs
        self.spinOff = SpinOffModel(
            engine: engine,
            sources: .init(
                similarToSong: { id in try await client.similarSongs(toSongID: id) },
                similarToArtist: { id in try await client.similarSongs(toArtistID: id) },
                random: { genre in try await client.randomSongs(size: SpinOffModel.batchSize, genre: genre) },
                rated: { [ratedSongs] in try await ratedSongs.songs() }
            ),
            keepSpinning: { [settings] in settings.settings.keepSpinning },
            includeMeh: { [settings] in settings.settings.includeMehInMixes },
            includeFavorites: { [settings] in settings.settings.myCutsIncludeFavorites }
        )
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
        // Next on a dialed station spins again.
        engine.stationSkipper = .init(
            canSkip: { SpinTheDialModel.isDialed($0) },
            skip: { [weak self] _ in Task { await self?.spinTheDialNow() } }
        )
        let tracker = OnAirTracker(engine: engine, match: onAir, info: onAirInfo) { [settings] in
            settings.settings.lookUpSongsOnline
        }
        onAirTracker = tracker
        tracker.start()
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

    /// The artist page's Wikipedia biography and releases not owned, while
    /// Look Up Artists Online is on.
    func onlineArtistModel() -> OnlineArtistModel {
        OnlineArtistModel(lookup: artistLookup)
    }

    /// The newest albums, for the row at the top of Library.
    func recentlyAddedModel() -> LoadModel<[Album]> {
        LoadModel { [client] () async throws(SubsonicError) in try await client.albumList(.newest, size: 15) }
    }

    func favoritesModel() -> LoadModel<SearchResult> {
        LoadModel { [client] () async throws(SubsonicError) in try await client.favorites() }
    }

    /// Albums played in the last week, from any app.
    func recentlyPlayedModel() -> LoadModel<[Album]> {
        LoadModel { [client] () async throws(SubsonicError) in
            RecentlyPlayed.albums(from: try await client.albumList(.recent, size: 50), now: .now)
        }
    }

    /// Albums worth hearing again, from the whole album list; a server
    /// without plays or ratings there gets its most played, less recent ones.
    func spinItBackModel() -> LoadModel<[Album]> {
        LoadModel { [client, catalog] () async throws(SubsonicError) in
            let all: [Album]
            do {
                all = try await catalog.albums()
            } catch let failure as SubsonicError {
                throw failure
            } catch {
                throw .network(.unknown)
            }
            let picks = SpinItBack.picks(from: all, now: .now)
            guard picks.isEmpty else { return picks }
            return SpinItBack.fallback(
                frequent: try await client.albumList(.frequent, size: 50),
                recent: try await client.albumList(.recent, size: 30)
            )
        }
    }

    func genresModel() -> LoadModel<[Genre]> {
        LoadModel { [client] () async throws(SubsonicError) in Genre.forBrowsing(try await client.genres()) }
    }

    func genreAlbumsModel(_ genre: String) -> AlbumsModel {
        AlbumsModel(listType: .byGenre(genre)) { [client] type, size, offset async throws(SubsonicError) in
            try await client.albumList(type, size: size, offset: offset)
        }
    }

    func radioStationsModel() -> RadioStationsModel {
        let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return RadioStationsModel(sources: .init(
            stations: { [client] () async throws(SubsonicError) in try await client.radioStations() },
            isAdmin: { [client, username] () async throws(SubsonicError) in try await client.isAdmin(username: username) },
            create: { [client] station async throws(SubsonicError) in try await client.createRadioStation(station) },
            update: { [client] id, station async throws(SubsonicError) in try await client.updateRadioStation(id: id, station) },
            delete: { [client] id async throws(SubsonicError) in try await client.deleteRadioStation(id: id) },
            details: { [radioBrowser] stream in try await radioBrowser.details(forStream: stream) }
        ), phone: PhoneStationStore(fileURL: support?.appending(path: PhoneStationStore.fileName)), details: stationDetails)
    }

    private func makeOnAirInfo() -> OnAirInfoModel {
        let musicBrainz = musicBrainz
        return OnAirInfoModel { song in try await musicBrainz.details(for: song) }
    }

    private func makeSpinTheDial() -> SpinTheDialModel {
        let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let phone = PhoneStationStore(fileURL: support?.appending(path: PhoneStationStore.fileName))
        return SpinTheDialModel(
            sources: .init(
                stations: { [radioBrowser] query in try await radioBrowser.stations(query, limit: 100) },
                history: { [history] in history.entries },
                favorites: { [client] () async throws(SubsonicError) in try await client.favorites().songs },
                libraryGenres: { [client] () async throws(SubsonicError) in try await client.genres() },
                popularTags: { [radioBrowser] in try await radioBrowser.tags() },
                savedStreams: { [client] in
                    let server = (try? await client.radioStations()) ?? []
                    return Set((server + phone.load()).map(\.streamURL))
                },
                play: { [radio] station in await radio.start(station) },
                countPlay: { [radioBrowser] id in try await radioBrowser.countPlay(of: id) }
            ),
            log: DialLog(fileURL: support?.appending(path: DialLog.fileName))
        )
    }

    /// Fetches the library's lists again now, rather than waiting out their
    /// 30 minutes (Settings > Refresh Library): what Search browses by
    /// filter and Spin It Back use, and the songs Mix My Cuts picks from.
    func refreshLibrary() async throws {
        async let catalogDone: Void = catalog.refresh()
        async let ratedDone: Void = ratedSongs.refresh()
        _ = try await (catalogDone, ratedDone)
    }

    /// Spins the dial with the current settings: from the Library button,
    /// and Next on a dialed station.
    func spinTheDialNow() async {
        await spinTheDial.spin(settings.settings.spinTheDial, countryCode: Locale.current.region?.identifier)
    }

    func stationInfoModel() -> StationInfoModel {
        StationInfoModel(sources: .init(
            listing: { [radioBrowser] stream in try await radioBrowser.listing(forStream: stream) },
            headers: { stream in try await StreamHeaderReader.headers(stream) }
        ))
    }

    func stationSearchModel() -> StationSearchModel {
        StationSearchModel(sources: .init(
            stations: { [radioBrowser] query, offset in try await radioBrowser.stations(query, offset: offset) },
            countries: { [radioBrowser] in try await radioBrowser.countries() },
            tags: { [radioBrowser] in try await radioBrowser.tags() },
            countPlay: { [radioBrowser] id in try await radioBrowser.countPlay(of: id) }
        ))
    }

    /// How favoriting the playing song went, for Siri, the lock screen
    /// control and the system's like command.
    enum CurrentFavoriteOutcome {
        case done(Song)
        case nothingPlaying
        case radio
        case failed(String)
    }

    /// Favorites (or unfavorites) the song playing now. Sets rather than
    /// flips, so a second press can't undo it. A failure is left in
    /// `stars.error` for the app's alert; Siri clears it and says it instead.
    @discardableResult
    func setCurrentSongFavorite(_ favorite: Bool) async -> CurrentFavoriteOutcome {
        guard let song = engine.queue.current?.song else { return .nothingPlaying }
        guard !song.isLive else { return .radio }
        guard await stars.set(.song(id: song.id), starred: favorite, fromServer: song.isStarred) else {
            return .failed(stars.error ?? "Couldn't reach your server.")
        }
        return .done(song)
    }

    func songModel(id: String) -> LoadModel<Song> {
        LoadModel { [client] () async throws(SubsonicError) in try await client.song(id: id) }
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

    /// Shared by the Library screen and the Random Mix quick action, so its
    /// progress and errors show in one place.
    private(set) lazy var randomMix: RandomMixModel = randomMixModel()

    private func randomMixModel() -> RandomMixModel {
        RandomMixModel(
            fetch: { [client] count async throws(SubsonicError) in try await client.randomSongs(size: count) },
            downloadedSongs: { [downloads] in downloads.downloadedSongs() },
            includeMeh: { [settings] in settings.settings.includeMehInMixes },
            play: { [engine] songs in engine.play(songs: songs) }
        )
    }

    func isSongDownloaded(_ id: String) -> Bool { downloads.localFile(forSongID: id) != nil }
    func isAlbumDownloaded(_ id: String) -> Bool { downloads.collection(id: DownloadCollection.id(.album, serverID: id)) != nil }

    func searchModel() -> SearchModel {
        SearchModel(
            scheduler: TaskScheduler(),
            isSongDownloaded: { [downloads] id in downloads.localFile(forSongID: id) != nil },
            isAlbumDownloaded: { [downloads] id in downloads.collection(id: DownloadCollection.id(.album, serverID: id)) != nil }
        ) { [client, catalog] request async throws(SubsonicError) in
            guard request.isBrowse else {
                return try await client.search(
                    request.query, artistCount: request.artistCount, albumCount: request.albumCount, songCount: request.songCount
                )
            }
            do {
                return try await catalog.browse(request.scope)
            } catch let failure as SubsonicError {
                throw failure
            } catch {
                throw .network(.unknown)
            }
        }
    }
}
