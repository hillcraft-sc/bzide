import CarPlay
import NavidromeCore

/// Builds the CarPlay screens from the same library models the phone uses.
/// CarPlay draws its own UI from templates; this only fills them in.
///
/// Tabs: Recently Played, Albums (recently added), Playlists, Downloaded.
/// Choosing a song plays its album or playlist from there and shows CarPlay's
/// Now Playing screen, which runs off the same Now Playing info as the lock screen.
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
        let recent = albumsTab(library, title: "Recently Played", systemImage: "clock", sort: .recentlyPlayed)
        let albums = albumsTab(library, title: "Albums", systemImage: "square.stack", sort: .newest)
        let playlists = playlistsTab(library)
        let downloads = downloadsTab(library)
        downloadsTab = downloads
        interfaceController.setRootTemplate(CPTabBarTemplate(templates: [recent, albums, playlists, downloads]), animated: false, completion: nil)
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
        let albums = library.albumsModel(sort: sort)
        models.append(albums)
        Task { [weak self] in
            await albums.load()
            guard let self else { return }
            switch albums.state {
            case .loaded(let list):
                template.updateSections([CPListSection(items: list.prefix(Self.maxItems).map { albumItem($0, library) })])
                template.emptyViewTitleVariants = ["No Albums"]
            case .failed(let message):
                showError(message, in: template) { [weak self] in self?.start() }
            case .loading:
                break
            }
        }
        return template
    }

    private func playlistsTab(_ library: Library) -> CPListTemplate {
        let template = loadingTemplate(title: "Playlists", systemImage: "music.note.list")
        let playlists = library.playlistsModel()
        models.append(playlists)
        Task { [weak self] in
            await playlists.load()
            guard let self else { return }
            switch playlists.state {
            case .loaded(let list):
                let items = list.prefix(Self.maxItems).map { playlist in
                    listItem(playlist.name, detail: playlist.songCount.map { "\($0) songs" }, coverArtID: playlist.coverArtID, library) { [weak self] in
                        self?.pushPlaylist(id: playlist.id, title: playlist.name, library)
                    }
                }
                template.updateSections([CPListSection(items: items)])
                template.emptyViewTitleVariants = ["No Playlists"]
            case .failed(let message):
                showError(message, in: template) { [weak self] in self?.start() }
            case .loading:
                break
            }
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

    // MARK: - Albums and playlists

    private func albumItem(_ album: Album, _ library: Library) -> CPListItem {
        listItem(album.name, detail: album.artist, coverArtID: album.coverArtID, library) { [weak self] in
            self?.pushAlbum(id: album.id, title: album.name, library)
        }
    }

    private func pushAlbum(id: String, title: String, _ library: Library) {
        let model = library.albumModel(id: id)
        pushLoaded(title: title, load: model.load, state: { model.state }, songs: \.songs, library)
    }

    private func pushPlaylist(id: String, title: String, _ library: Library) {
        let model = library.playlistModel(id: id)
        pushLoaded(title: title, load: model.load, state: { model.state }, songs: \.songs, library)
    }

    /// Pushes a song list straight away, filled in when its load finishes.
    private func pushLoaded<Value>(
        title: String,
        load: @escaping () async -> Void,
        state: @escaping () -> LoadState<Value>,
        songs: KeyPath<Value, [Song]>,
        _ library: Library
    ) {
        let template = CPListTemplate(title: title, sections: [])
        template.emptyViewTitleVariants = ["Loading…"]
        interfaceController.pushTemplate(template, animated: true, completion: nil)
        Task { [weak self] in
            await load()
            guard let self else { return }
            switch state() {
            case .loaded(let value):
                template.updateSections(songSections(value[keyPath: songs], library))
                template.emptyViewTitleVariants = ["No Songs"]
            case .failed(let message):
                showError(message, in: template) { [weak self] in
                    self?.interfaceController.popTemplate(animated: false, completion: nil)
                    self?.pushLoaded(title: title, load: load, state: state, songs: songs, library)
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
    private func songSections(_ songs: [Song], _ library: Library) -> [CPListSection] {
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
        return [CPListSection(items: [shuffle]), CPListSection(items: items)]
    }

    private func showNowPlaying() {
        let nowPlaying = CPNowPlayingTemplate.shared
        guard interfaceController.topTemplate !== nowPlaying else { return }
        interfaceController.pushTemplate(nowPlaying, animated: true, completion: nil)
    }

    // MARK: - Helpers

    /// CarPlay caps list length; anything past it wouldn't show.
    private static var maxItems: Int { CPListTemplate.maximumItemCount }

    private func loadingTemplate(title: String, systemImage: String) -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: [])
        template.tabImage = UIImage(systemName: systemImage)
        template.emptyViewTitleVariants = ["Loading…"]
        return template
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
