import CarPlay
import NavidromeCore

/// Builds the CarPlay screens from the same library models the phone uses.
/// CarPlay draws its own UI from templates; this only fills them in.
///
/// Tabs: Recently Played, Library (Random Mix and Mix My Cuts, then
/// Artists, Albums, Playlists, Favorites and Genres), Radio, Downloaded.
/// CarPlay allows audio apps only a few tabs, so the rest of the library is
/// one tap into Library. Choosing a song plays its list from there and
/// shows CarPlay's Now Playing screen, which runs off the same Now Playing
/// info as the lock screen.
final class CarPlayController: NSObject, CPInterfaceControllerDelegate {
    private let interfaceController: CPInterfaceController
    private let model: AppModel
    private var downloadsTab: CPListTemplate?
    /// Kept so their loads aren't dropped mid-flight.
    private var models: [AnyObject] = []

    init(interfaceController: CPInterfaceController, model: AppModel) {
        self.interfaceController = interfaceController
        self.model = model
        super.init()
        interfaceController.delegate = self
    }

    func start() {
        // Rebuild on sign-in and sign-out, whichever screen CarPlay is on.
        withObservationTracking {
            _ = model.library
        } onChange: { [weak self] in
            Task { @MainActor in self?.start() }
        }
        guard let library = model.library else {
            showSignIn()
            return
        }
        models = []
        let recent = albumsTab(library, title: "Recently Played", systemImage: "clock", sort: .recentlyPlayed)
        let downloads = downloadsTab(library)
        downloadsTab = downloads
        let tabs = [recent, libraryTab(library), radioTab(library), downloads]
        // The car decides how many tabs fit; the most used come first.
        let fitting = Array(tabs.prefix(max(CPTabBarTemplate.maximumTabCount, 1)))
        interfaceController.setRootTemplate(CPTabBarTemplate(templates: fitting), animated: false, completion: nil)
    }

    // MARK: - CPInterfaceControllerDelegate

    func templateWillAppear(_ aTemplate: CPTemplate, animated: Bool) {
        // Downloads change while browsing; the list is local, so rebuilding is cheap.
        if aTemplate === downloadsTab, let library = model.library {
            fillDownloads(aTemplate as? CPListTemplate, library)
        }
    }

    // MARK: - Tabs

    private func showSignIn() {
        let template = CPListTemplate(title: "Music", sections: [])
        template.emptyViewTitleVariants = ["Sign in on your iPhone"]
        interfaceController.setRootTemplate(template, animated: false, completion: nil)
    }

    private func albumsTab(_ library: Library, title: String, systemImage: String, sort: AlbumSort) -> CPListTemplate {
        let template = loadingTemplate(title: title, systemImage: systemImage)
        fillAlbums(template, library.albumsModel(sort: sort), library) { [weak self] in self?.start() }
        return template
    }

    /// The mixes first, as the quickest way to music, then the ways in.
    private func libraryTab(_ library: Library) -> CPListTemplate {
        let randomMix = actionItem("Random Mix", systemImage: "shuffle") { [weak self] in
            await library.randomMix.start()
            self?.showNowPlayingOrAlert(library.randomMix.error, library)
        }
        let myCuts = actionItem("Mix My Cuts", systemImage: "flame") { [weak self] in
            await library.spinOff.startRated()
            self?.showNowPlayingOrAlert(library.spinOff.notice, library)
        }
        let links = [
            linkItem("Artists", systemImage: "music.microphone") { [weak self] in self?.pushArtists(library) },
            linkItem("Albums", detail: "Recently added", systemImage: "square.stack") { [weak self] in
                self?.pushAlbums(title: "Albums", library.albumsModel(sort: .newest), library)
            },
            linkItem("Playlists", systemImage: "music.note.list") { [weak self] in self?.pushPlaylists(library) },
            linkItem("Favorites", systemImage: "heart") { [weak self] in self?.pushFavorites(library) },
            linkItem("Genres", systemImage: "guitars") { [weak self] in self?.pushGenres(library) },
        ]
        let template = CPListTemplate(title: "Library", sections: [CPListSection(items: [randomMix, myCuts]), CPListSection(items: links)])
        template.tabImage = UIImage(systemName: "music.note.house")
        return template
    }

    /// The saved stations, on the server and this iPhone, by name; with Find
    /// Stations Online on, Spin the Dial first.
    private func radioTab(_ library: Library) -> CPListTemplate {
        let template = loadingTemplate(title: "Radio", systemImage: "dot.radiowaves.left.and.right")
        let stations = library.radioStationsModel()
        models.append(stations)
        Task { [weak self] in
            await stations.load()
            guard let self else { return }
            var sections: [CPListSection] = []
            if library.settings.settings.findStationsOnline {
                let dial = actionItem("Spin the Dial", systemImage: "dial.medium") { [weak self] in
                    await library.spinTheDialNow()
                    self?.showNowPlayingOrAlert(library.spinTheDial.error, library)
                }
                sections.append(CPListSection(items: [dial]))
            }
            let all = (stations.stations + stations.phoneStations)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let items = all.prefix(Self.maxItems).map { station in
                stationItem(station, library)
            }
            if !items.isEmpty { sections.append(CPListSection(items: items)) }
            if case .failed(let message) = stations.state, stations.phoneStations.isEmpty {
                showError(message, in: template) { [weak self] in self?.start() }
                return
            }
            template.updateSections(sections)
            template.emptyViewTitleVariants = ["No Stations"]
        }
        return template
    }

    private func downloadsTab(_ library: Library) -> CPListTemplate {
        let template = CPListTemplate(title: "Downloaded", sections: [])
        template.tabImage = UIImage(systemName: "arrow.down.circle")
        template.emptyViewTitleVariants = ["No Downloads"]
        fillDownloads(template, library)
        return template
    }

    private func fillDownloads(_ template: CPListTemplate?, _ library: Library) {
        let collections = library.downloads.collections.sorted { $0.addedAt > $1.addedAt }
        let items = collections.prefix(Self.maxItems).map { collection in
            listItem(collection.name, detail: collection.artist, coverArtID: collection.coverArtID, library) { [weak self] in
                guard let self else { return }
                // From the saved song list, so it works with no connection.
                let current = library.downloads.collection(id: collection.id)?.songs ?? collection.songs
                interfaceController.pushTemplate(songsTemplate(collection.name, songs: current, library), animated: true, completion: nil)
            }
        }
        template?.updateSections([CPListSection(items: items)])
    }

    // MARK: - Library screens

    /// By letter, as on the phone, with the letters as an index.
    private func pushArtists(_ library: Library) {
        let artists = library.artistsModel()
        pushLoaded(title: "Artists", load: artists.load, state: { artists.state }) { [weak self] sections in
            guard let self else { return [] }
            var remaining = Self.maxItems
            var listSections: [CPListSection] = []
            for section in sections.prefix(Self.maxSections) where remaining > 0 && !section.artists.isEmpty {
                let items = section.artists.prefix(remaining).map { artist in
                    self.listItem(artist.name, detail: artist.albumCount.map { $0 == 1 ? "1 album" : "\($0) albums" }, coverArtID: artist.coverArtID, library) { [weak self] in
                        self?.pushArtist(artist, library)
                    }
                }
                remaining -= items.count
                listSections.append(CPListSection(items: items, header: section.name, sectionIndexTitle: String(section.name.prefix(1))))
            }
            return listSections
        }
    }

    /// Shuffle all their songs, then their albums.
    private func pushArtist(_ artist: Artist, _ library: Library) {
        let model = library.artistModel(id: artist.id)
        pushLoaded(title: artist.name, load: model.load, state: { model.state }) { [weak self] loaded in
            guard let self else { return [] }
            let shuffle = actionItem("Shuffle", systemImage: "shuffle") { [weak self] in
                guard let songs = try? await library.quickActions.resolve(.artist(id: artist.id)).songs, !songs.isEmpty else {
                    self?.showAlert("Couldn't load \(artist.name)'s songs.")
                    return
                }
                library.engine.playShuffled(songs)
                self?.showNowPlaying()
            }
            let albums = loaded.albums.prefix(Self.maxItems).map { albumItem($0, library) }
            return [CPListSection(items: [shuffle]), CPListSection(items: albums)]
        }
    }

    private func pushAlbums(title: String, _ albums: AlbumsModel, _ library: Library) {
        let template = CPListTemplate(title: title, sections: [])
        template.emptyViewTitleVariants = ["Loading…"]
        interfaceController.pushTemplate(template, animated: true, completion: nil)
        fillAlbums(template, albums, library) { [weak self] in
            self?.interfaceController.popTemplate(animated: false, completion: nil)
            self?.pushAlbums(title: title, albums, library)
        }
    }

    private func pushPlaylists(_ library: Library) {
        let playlists = library.playlistsModel()
        pushLoaded(title: "Playlists", load: playlists.load, state: { playlists.state }) { [weak self] list in
            guard let self else { return [] }
            let items = list.prefix(Self.maxItems).map { playlist in
                self.listItem(playlist.name, detail: playlist.songCount.map { "\($0) songs" }, coverArtID: playlist.coverArtID, library) { [weak self] in
                    self?.pushPlaylist(id: playlist.id, title: playlist.name, library)
                }
            }
            return [CPListSection(items: items)]
        }
    }

    /// Favorite songs (with Shuffle), then albums, then artists.
    private func pushFavorites(_ library: Library) {
        let favorites = library.favoritesModel()
        pushLoaded(title: "Favorites", load: favorites.load, state: { favorites.state }) { [weak self] result in
            guard let self else { return [] }
            var sections = songSections(result.songs, library, header: "Songs")
            let albums = result.albums.prefix(Self.maxItems).map { albumItem($0, library) }
            if !albums.isEmpty { sections.append(CPListSection(items: albums, header: "Albums", sectionIndexTitle: nil)) }
            let artists = result.artists.prefix(Self.maxItems).map { artist in
                self.listItem(artist.name, detail: nil, coverArtID: artist.coverArtID, library) { [weak self] in
                    self?.pushArtist(artist, library)
                }
            }
            if !artists.isEmpty { sections.append(CPListSection(items: artists, header: "Artists", sectionIndexTitle: nil)) }
            return sections
        }
    }

    private func pushGenres(_ library: Library) {
        let genres = library.genresModel()
        pushLoaded(title: "Genres", load: genres.load, state: { genres.state }) { [weak self] list in
            guard let self else { return [] }
            let items = list.prefix(Self.maxItems).map { genre in
                self.linkItem(genre.name, detail: genre.albumCount.map { $0 == 1 ? "1 album" : "\($0) albums" }, systemImage: "guitars") { [weak self] in
                    self?.pushAlbums(title: genre.name, library.genreAlbumsModel(genre.name), library)
                }
            }
            return [CPListSection(items: items)]
        }
    }

    // MARK: - Albums and playlists

    private func fillAlbums(_ template: CPListTemplate, _ albums: AlbumsModel, _ library: Library, retry: @escaping () -> Void) {
        models.append(albums)
        Task { [weak self] in
            await albums.load()
            guard let self else { return }
            switch albums.state {
            case .loaded(let list):
                template.updateSections([CPListSection(items: list.prefix(Self.maxItems).map { albumItem($0, library) })])
                template.emptyViewTitleVariants = ["No Albums"]
            case .failed(let message):
                showError(message, in: template, retry: retry)
            case .loading:
                break
            }
        }
    }

    private func albumItem(_ album: Album, _ library: Library) -> CPListItem {
        listItem(album.name, detail: album.artist, coverArtID: album.coverArtID, library) { [weak self] in
            self?.pushAlbum(id: album.id, title: album.name, library)
        }
    }

    private func pushAlbum(id: String, title: String, _ library: Library) {
        let model = library.albumModel(id: id)
        pushLoaded(title: title, load: model.load, state: { model.state }) { [weak self] album in
            self?.songSections(album.songs, library) ?? []
        }
    }

    private func pushPlaylist(id: String, title: String, _ library: Library) {
        let model = library.playlistModel(id: id)
        pushLoaded(title: title, load: model.load, state: { model.state }) { [weak self] playlist in
            self?.songSections(playlist.songs, library) ?? []
        }
    }

    /// Pushes a list straight away, filled in when its load finishes.
    private func pushLoaded<Value>(
        title: String,
        load: @escaping () async -> Void,
        state: @escaping () -> LoadState<Value>,
        sections: @escaping (Value) -> [CPListSection]
    ) {
        let template = CPListTemplate(title: title, sections: [])
        template.emptyViewTitleVariants = ["Loading…"]
        interfaceController.pushTemplate(template, animated: true, completion: nil)
        Task { [weak self] in
            await load()
            guard let self else { return }
            switch state() {
            case .loaded(let value):
                template.updateSections(sections(value))
                template.emptyViewTitleVariants = ["Nothing Here"]
            case .failed(let message):
                showError(message, in: template) { [weak self] in
                    self?.interfaceController.popTemplate(animated: false, completion: nil)
                    self?.pushLoaded(title: title, load: load, state: state, sections: sections)
                }
            case .loading:
                break
            }
        }
    }

    private func songsTemplate(_ title: String, songs: [Song], _ library: Library) -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: songSections(songs, library))
        template.emptyViewTitleVariants = ["No Songs"]
        return template
    }

    /// Shuffle first, then the songs; choosing one plays the list from it.
    private func songSections(_ songs: [Song], _ library: Library, header: String? = nil) -> [CPListSection] {
        guard !songs.isEmpty else { return [] }
        let shuffle = CPListItem(text: "Shuffle", detailText: nil, image: UIImage(systemName: "shuffle"))
        shuffle.handler = { [weak self] _, completion in
            library.engine.playShuffled(songs)
            self?.showNowPlaying()
            completion()
        }
        let items = songs.prefix(Self.maxItems).enumerated().map { index, song in
            let item = CPListItem(text: song.title, detailText: song.artist)
            item.handler = { [weak self] _, completion in
                library.engine.play(songs: songs, startIndex: index)
                self?.showNowPlaying()
                completion()
            }
            return item
        }
        return [CPListSection(items: [shuffle]), CPListSection(items: items, header: header, sectionIndexTitle: nil)]
    }

    // MARK: - Radio

    private func stationItem(_ station: RadioStation, _ library: Library) -> CPListItem {
        let item = listItem(station.name, detail: station.details?.summary, coverArtID: station.logoURL.map(StationLogo.coverArtID), library) { [weak self] in
            Task { [weak self] in
                await library.radio.start(station)
                self?.showNowPlayingOrAlert(library.radio.error, library)
            }
        }
        // Plays, rather than opening a list.
        item.accessoryType = .none
        return item
    }

    // MARK: - Now Playing and alerts

    private func showNowPlaying() {
        let nowPlaying = CPNowPlayingTemplate.shared
        guard interfaceController.topTemplate !== nowPlaying else { return }
        interfaceController.pushTemplate(nowPlaying, animated: true, completion: nil)
    }

    /// After a mix or station starts: Now Playing, or what went wrong (the
    /// phone shows the same message when it's next opened, so it's
    /// dismissed there only by the user).
    private func showNowPlayingOrAlert(_ error: String?, _ library: Library) {
        if let error, !library.engine.status.isActive {
            showAlert(error)
        } else if library.engine.queue.current != nil {
            showNowPlaying()
        }
    }

    private func showAlert(_ message: String) {
        let alert = CPAlertTemplate(titleVariants: [message], actions: [
            CPAlertAction(title: "OK", style: .cancel) { [weak self] _ in
                self?.interfaceController.dismissTemplate(animated: true, completion: nil)
            },
        ])
        interfaceController.presentTemplate(alert, animated: true, completion: nil)
    }

    // MARK: - Helpers

    /// CarPlay caps list length and sections; anything past them wouldn't show.
    private static var maxItems: Int { CPListTemplate.maximumItemCount }
    private static var maxSections: Int { CPListTemplate.maximumSectionCount }

    private func loadingTemplate(title: String, systemImage: String) -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: [])
        template.tabImage = UIImage(systemName: systemImage)
        template.emptyViewTitleVariants = ["Loading…"]
        return template
    }

    /// A row that opens another list.
    private func linkItem(_ title: String, detail: String? = nil, systemImage: String, onSelect: @escaping () -> Void) -> CPListItem {
        let item = CPListItem(text: title, detailText: detail, image: UIImage(systemName: systemImage))
        item.accessoryType = .disclosureIndicator
        item.handler = { _, completion in
            onSelect()
            completion()
        }
        return item
    }

    /// A row that starts music. CarPlay shows a spinner on it until it has.
    private func actionItem(_ title: String, systemImage: String, action: @escaping () async -> Void) -> CPListItem {
        let item = CPListItem(text: title, detailText: nil, image: UIImage(systemName: systemImage))
        item.handler = { _, completion in
            Task {
                await action()
                completion()
            }
        }
        return item
    }

    private func listItem(_ title: String, detail: String?, coverArtID: String?, _ library: Library, onSelect: @escaping () -> Void) -> CPListItem {
        let item = CPListItem(text: title.isEmpty ? "Untitled" : title, detailText: detail, image: UIImage(systemName: "music.note"))
        item.accessoryType = .disclosureIndicator
        item.handler = { _, completion in
            onSelect()
            completion()
        }
        if let coverArtID {
            let pixels = Int(CPListItem.maximumImageSize.width * interfaceController.carTraitCollection.displayScale)
            Task {
                if let image = await library.artwork.image(for: coverArtID, pixels: pixels) {
                    item.setImage(image)
                }
            }
        }
        return item
    }

    private func showError(_ message: String, in template: CPListTemplate, retry: @escaping () -> Void) {
        let item = CPListItem(text: "Try Again", detailText: message, image: UIImage(systemName: "arrow.clockwise"))
        item.handler = { _, completion in
            retry()
            completion()
        }
        template.updateSections([CPListSection(items: [item])])
    }
}
