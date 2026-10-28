#if DEBUG
import NavidromeCore
import SwiftUI

/// Debug builds: sets the app up for an App Store screenshot from launch
/// arguments, so the whole set can be taken again in the Simulator without
/// tapping (`scripts/screenshots.sh` takes the set).
///
/// - `-screenshot <screen>`: what to open (`Screen`).
/// - `-screenshotAlbum <id>`: the album to play, shown by `album` and `artist`.
/// - `-screenshotTrack <number>`: which of its songs to start with (from 1).
/// - `-screenshotSeek <seconds>`: where in that song to be.
/// - `-screenshotTheme <theme>`: the theme (`AppTheme`), e.g. `light` or `tokyoNight`.
/// - `-screenshotShowAll YES`: every Library section shown (the carousels
///   start hidden). Collapsed carousels open with their own settings:
///   `-recentlyAddedCollapsed NO` and so on.
/// - `-screenshotDownload YES`: downloads the album.
/// - `-screenshotStationGenre <genre>`: what `findStations` searches for;
///   it turns Find Stations Online on.
/// - Signed out, it signs in with `SCREENSHOT_SERVER`, `SCREENSHOT_USER` and
///   `SCREENSHOT_PASSWORD` from the environment (`SIMCTL_CHILD_…` with
///   `simctl launch`), never from code.
///
/// The visualizer's style and colors are already settings, so they're set
/// the same way: `-visualizerStyle violentSphere -visualizerColors multicolor`.
enum ScreenshotScript {
    enum Screen: String {
        case library, albums, album, artist, nowPlaying, visualizer, lyrics, findStations
    }

    static var screen: Screen? {
        UserDefaults.standard.string(forKey: "screenshot").flatMap(Screen.init)
    }

    private static var albumID: String? {
        UserDefaults.standard.string(forKey: "screenshotAlbum")
    }

    static var stationGenre: String? {
        UserDefaults.standard.string(forKey: "screenshotStationGenre")
    }

    /// The theme and Library sections, once signed in (signing in puts the
    /// account's own settings in place).
    static func applySettings(_ model: AppModel, _ library: Library) {
        let defaults = UserDefaults.standard
        if let theme = defaults.string(forKey: "screenshotTheme").flatMap(AppTheme.init) {
            model.appearance.settings.theme = theme
        }
        if defaults.bool(forKey: "screenshotShowAll") {
            for feature in LibraryFeature.allCases { model.libraryLayout.layout.setShown(feature, true) }
        }
        if screen == .findStations {
            library.settings.settings.findStationsOnline = true
        }
    }

    static func signInIfNeeded(_ model: AppModel) async {
        let environment = ProcessInfo.processInfo.environment
        guard screen != nil, model.library == nil,
              let server = environment["SCREENSHOT_SERVER"],
              let user = environment["SCREENSHOT_USER"],
              let password = environment["SCREENSHOT_PASSWORD"]
        else { return }
        await model.signIn(serverURL: server, username: user, password: password)
    }

    /// Plays the album from the chosen place (the visualizer needs it
    /// playing) and returns it.
    static func playAlbum(_ library: Library) async -> Album? {
        guard let albumID else { return nil }
        let model = library.albumModel(id: albumID)
        await model.load()
        guard let album = model.value, !album.songs.isEmpty else { return nil }
        let defaults = UserDefaults.standard
        let track = min(max(defaults.integer(forKey: "screenshotTrack"), 1), album.songs.count)
        library.engine.play(songs: album.songs, startIndex: track - 1, from: defaults.double(forKey: "screenshotSeek"))
        if defaults.bool(forKey: "screenshotDownload") {
            library.downloads.download(DownloadCollection(album: album))
        }
        return album
    }
}
#endif
