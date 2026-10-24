import CarPlay
import NavidromeCore

/// CarPlay's Now Playing screen (Gitea #28): CarPlay draws it from the same
/// Now Playing info as the lock screen; this adds the buttons under it.
/// Shuffle and repeat (CarPlay's own, showing their state from the engine's
/// Now Playing info), a heart for Favorite, and ••• for Spin Off; the Up Next
/// button at the top (the list icon: tap a song to jump to it), and the album name
/// opening the album. A station has none of them.
final class CarPlayNowPlaying: NSObject, CPNowPlayingTemplateObserver {
    private let interfaceController: CPInterfaceController
    private let library: Library
    /// Opens an album's page (id, title), as the library's lists do.
    private let openAlbum: (String, String) -> Void
    private let template = CPNowPlayingTemplate.shared

    init(interfaceController: CPInterfaceController, library: Library, openAlbum: @escaping (String, String) -> Void) {
        self.interfaceController = interfaceController
        self.library = library
        self.openAlbum = openAlbum
        super.init()
        // No title: CarPlay then draws its own Up Next button, the list icon
        // (a title replaces the icon with text).
        template.add(self)
        follow()
    }

    func stop() {
        template.remove(self)
    }

    private var current: Song? { library.engine.queue.current?.song }

    /// Updates the buttons now and whenever the song or its heart changes.
    private func follow() {
        withObservationTracking {
            refreshButtons()
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
    }

    private func refreshButtons() {
        guard let song = current, !song.isLive else {
            template.updateNowPlayingButtons([])
            template.isUpNextButtonEnabled = false
            template.isAlbumArtistButtonEnabled = false
            return
        }
        let isFavorite = library.isFavorite(song)
        let heart = UIImage(systemName: isFavorite ? "heart.fill" : "heart") ?? UIImage()
        template.updateNowPlayingButtons([
            CPNowPlayingShuffleButton { [weak self] _ in self?.library.engine.toggleShuffle() },
            CPNowPlayingRepeatButton { [weak self] _ in self?.library.engine.cycleRepeatMode() },
            CPNowPlayingImageButton(image: heart) { [weak self] _ in
                guard let self else { return }
                Task { await self.library.stars.toggle(.song(id: song.id), fromServer: song.isStarred) }
            },
            CPNowPlayingMoreButton { [weak self] _ in self?.showSpinOff(song) },
        ])
        template.isUpNextButtonEnabled = !library.engine.queue.upNext.isEmpty
        template.isAlbumArtistButtonEnabled = song.albumID != nil
    }

    /// Spin Off from the song, or from its artist.
    private func showSpinOff(_ song: Song) {
        var actions = [
            CPAlertAction(title: "Spin Off from This Song", style: .default) { [weak self] _ in
                self?.dismissThen { await self?.library.spinOff.start(from: song) }
            },
        ]
        if let artistID = song.artistID, let name = song.artist, !name.isEmpty {
            actions.append(CPAlertAction(title: "Spin Off from \(name)", style: .default) { [weak self] _ in
                self?.dismissThen { await self?.library.spinOff.start(fromArtist: Artist(id: artistID, name: name)) }
            })
        }
        actions.append(CPAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.interfaceController.dismissTemplate(animated: true, completion: nil)
        })
        let sheet = CPActionSheetTemplate(title: "Spin Off", message: "Songs like this one, without end.", actions: actions)
        interfaceController.presentTemplate(sheet, animated: true, completion: nil)
    }

    private func dismissThen(_ action: @escaping () async -> Void) {
        interfaceController.dismissTemplate(animated: true, completion: nil)
        Task { await action() }
    }

    // MARK: - CPNowPlayingTemplateObserver

    /// The queue: what's playing, then what's next; choosing one jumps there.
    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        let engine = library.engine
        let entries = ([engine.queue.current].compactMap { $0 } + engine.queue.upNext).prefix(CPListTemplate.maximumItemCount)
        let items = entries.map { entry in
            let item = CPListItem(text: entry.song.title, detailText: entry.song.artist)
            item.isPlaying = entry.id == engine.queue.current?.id
            item.handler = { [weak self] _, completion in
                engine.jump(to: entry.id)
                self?.interfaceController.popTemplate(animated: true, completion: nil)
                completion()
            }
            return item
        }
        let queue = CPListTemplate(title: "Queue", sections: [CPListSection(items: Array(items))])
        interfaceController.pushTemplate(queue, animated: true, completion: nil)
    }

    func nowPlayingTemplateAlbumArtistButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        guard let song = current, let albumID = song.albumID else { return }
        openAlbum(albumID, song.album ?? "")
    }
}
