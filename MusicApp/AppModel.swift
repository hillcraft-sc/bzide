import Foundation
import NavidromeCore
import Observation
import os

/// Builds the app's long-lived objects and runs the few server calls the screens
/// need. Views read its state and call its methods; they never talk to the
/// server or the engine's dependencies directly.
@MainActor
@Observable
final class AppModel {
    /// The one instance, shared by the phone window and CarPlay. CarPlay can
    /// start without the phone's window (launched from the car with the phone
    /// locked), so this can't belong to the SwiftUI view tree.
    static let shared = AppModel()

    private(set) var engine: PlaybackEngine?
    private(set) var library: Library?
    private(set) var isSigningIn = false
    private(set) var signInError: String?
    /// A sign-in that would switch accounts, waiting for the user to confirm.
    private(set) var pendingSwitch: AccountSwitch?
    private(set) var albums: [Album] = []
    private(set) var playlists: [Playlist] = []
    private(set) var libraryError: String?
    /// Who is signed in, for Settings.
    private(set) var account: AccountSummary?
    /// A Home Screen quick action waiting to run: the signed-in screens run
    /// it as soon as they're up (at once if they already are) and clear it.
    var pendingHomeScreenAction: HomeScreenAction?
    /// Visualizer phase 1 test: the player's live level meter, and the switch
    /// that taps playback for it. Off at every launch.
    var levelMeter: AudioLevelMeter { system.player.levelMeter }
    var isMetering: Bool {
        get { system.player.isMetering }
        set { system.player.isMetering = newValue }
    }

    /// Device-wide, so the theme also applies to the sign-in screen and survives sign-out.
    let appearance = AppearanceModel()
    /// What the Library screen shows, and in what order.
    let libraryLayout = LibraryLayoutModel()

    @ObservationIgnored private var client: SubsonicClient?
    @ObservationIgnored private var scrobbler: Scrobbler?
    @ObservationIgnored private let credentialStore = KeychainCredentialStore()
    @ObservationIgnored private lazy var system = SystemServices { [weak self] id in
        await self?.library?.artwork.image(for: id, pixels: 600)
    }
    private static let logger = Logger(subsystem: "MusicApp", category: "AppModel")

    private init() {
        do {
            if let saved = try credentialStore.load() {
                start(with: saved)
            }
        } catch {
            Self.logger.error("Couldn't read saved login: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Home Screen quick actions

    /// Returns whether the action is one of Bzide's.
    @discardableResult
    func requestHomeScreenAction(type: String) -> Bool {
        guard let action = HomeScreenAction(type: type) else { return false }
        pendingHomeScreenAction = action
        return true
    }

    // MARK: - Sign in

    /// With an API key, `username` and `password` are ignored: the server
    /// says whose key it is (OpenSubsonic `tokenInfo`).
    func signIn(serverURL: String, username: String, password: String, apiKey: String? = nil) async {
        signInError = nil
        let trimmed = serverURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            signInError = "Enter the full server address, starting with http:// or https://."
            return
        }
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        var credentials = ServerCredentials(baseURL: url, username: username, password: key == nil ? password : "", apiKey: key)
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            if credentials.apiKey != nil {
                credentials.username = try await SubsonicClient(credentials: credentials).apiKeyUsername()
            }
            try await SubsonicClient(credentials: credentials).ping()
            // Another account's data is here: say what a switch removes first.
            if let scope = try? Self.accountScope(), scope.isDifferentAccount(credentials) {
                let downloads = (try? DownloadManager.applicationSupportDirectory()).map(AccountScope.size) ?? 0
                pendingSwitch = AccountSwitch(credentials: credentials, downloadBytes: downloads)
                return
            }
            try credentialStore.save(credentials)
            start(with: credentials)
        } catch let error as SubsonicError {
            signInError = error.localizedDescription
        } catch {
            signInError = error.localizedDescription
        }
    }

    /// Goes ahead with the pending switch. `sameServer`: it's the same server at
    /// another address, so everything here is kept as this account's.
    func confirmSwitch(sameServer: Bool) {
        guard let pending = pendingSwitch else { return }
        pendingSwitch = nil
        if sameServer { try? Self.accountScope().adopt(pending.credentials) }
        do {
            try credentialStore.save(pending.credentials)
            start(with: pending.credentials)
        } catch {
            signInError = error.localizedDescription
        }
    }

    func cancelSwitch() {
        pendingSwitch = nil
    }

    private static func accountScope() throws -> AccountScope {
        AccountScope(dataLocations: try AccountScope.standardDataLocations(), settings: try AccountSettings.standard())
    }

    /// Builds everything that belongs to the signed-in account on top of the
    /// app-lifetime system services.
    private func start(with credentials: ServerCredentials) {
        removeOtherAccountsData(for: credentials)
        let client = SubsonicClient(credentials: credentials)
        let scrobbler = Scrobbler(
            sender: client, store: FileScrobbleStore.applicationSupport() ?? InMemoryScrobbleStore(),
            isEnabled: { [settings = system.settings] in settings.settings.sendPlaysToServer }
        )
        let queueStore: any QueueStore
        do {
            queueStore = try FileQueueStore.applicationSupport()
        } catch {
            Self.logger.error("Queue won't persist: \(String(describing: error), privacy: .public)")
            queueStore = InMemoryQueueStore()
        }
        let artwork = ArtworkCache(client: client, store: Self.coverArtStore(downloadsDirectory: system.downloadsDirectory))
        let history = Self.makeHistory()
        let downloads = makeDownloads(client: client, artwork: artwork)
        let resolver = TrackResolver(client: client, settings: system.settings, network: system.network, downloads: downloads)
        let engine = PlaybackEngine(
            player: system.player,
            session: system.session,
            nowPlaying: system.nowPlaying,
            urls: resolver,
            store: queueStore,
            scheduler: TaskScheduler(),
            network: system.network,
            scrobbler: scrobbler,
            history: history
        )
        self.engine = engine
        library = Library(
            client: client, username: credentials.username, engine: engine, artwork: artwork,
            settings: system.settings, downloads: downloads, history: history
        )
        account = AccountSummary(credentials: credentials)
        self.client = client
        if let library {
            Task { await library.profile.refresh() }
            // Tagged radio songs now in the library get marked (and removed
            // when due) even if the list isn't opened.
            Task { await library.wishlist.checkLibrary() }
        }
        self.scrobbler = scrobbler
        // Send anything left over from a previous run.
        Task { await scrobbler.flush() }
    }

    /// Downloads, queue, history, unsent scrobbles and cached artwork belong to
    /// one account; signing in to another removes them first.
    private func removeOtherAccountsData(for credentials: ServerCredentials) {
        do {
            if try Self.accountScope().prepare(for: credentials) {
                Self.logger.notice("Signed in to a different account; switched settings and removed the previous account's data")
                // These stay loaded between sign-ins; read this account's.
                system.settings.reload()
                appearance.reload()
                libraryLayout.reload()
                // Recreated with its backup exclusion, which went with the old folder.
                _ = try DownloadManager.applicationSupportDirectory()
            }
        } catch {
            // Leaves the owner unchanged, so the check runs again next sign-in.
            Self.logger.error("Couldn't check which account owns the data: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Restore Default Settings

    /// Puts the signed-in account's settings back to how Bzide starts (see
    /// `AccountSettings.restoreDefaults`), and has the screens already loaded
    /// read them again. Data, Tagged Radio Songs and the profile stay.
    func restoreDefaultSettings() {
        do {
            try AccountSettings.standard().restoreDefaults()
        } catch {
            Self.logger.error("Couldn't restore the default settings: \(String(describing: error), privacy: .public)")
            return
        }
        system.settings.reload()
        appearance.reload()
        libraryLayout.reload()
        library?.wishlist.reloadSettings()
    }

    // MARK: - Sign out

    /// Removes the login and stops playback. The account's data stays on the
    /// device for when the same account signs in again.
    func signOut() {
        if let engine {
            engine.pause()
        }
        system.player.setItems([], startPosition: 0)
        // The lock screen would otherwise keep controls for an engine that's gone.
        system.nowPlaying.update(nil)
        WidgetBridge.clear()
        if let scrobbler {
            Task { await scrobbler.flush() }
        }
        do {
            try credentialStore.delete()
        } catch {
            Self.logger.error("Couldn't remove the saved login: \(error.localizedDescription, privacy: .public)")
        }
        library = nil
        engine = nil
        client = nil
        scrobbler = nil
        account = nil
        albums = []
        playlists = []
        libraryError = nil
    }

    // MARK: - Library

    func loadLibrary() async {
        guard let client else { return }
        libraryError = nil
        do {
            albums = try await client.albumList(.newest, size: 30)
            playlists = try await client.playlists()
        } catch {
            libraryError = error.localizedDescription
        }
    }

    func playRandomSongs() async {
        await play { client in try await client.randomSongs(size: 30) }
    }

    func play(album: Album) async {
        await play { client in try await client.album(id: album.id).songs }
    }

    func play(playlist: Playlist) async {
        await play { client in try await client.playlist(id: playlist.id).songs }
    }

    private func play(_ fetchSongs: (SubsonicClient) async throws -> [Song]) async {
        guard let client, let engine else { return }
        libraryError = nil
        do {
            engine.play(songs: try await fetchSongs(client))
        } catch {
            libraryError = error.localizedDescription
        }
    }

    // MARK: - History

    private static func makeHistory() -> PlayHistory {
        do {
            return PlayHistory(fileURL: try PlayHistory.applicationSupportFile())
        } catch {
            logger.error("Play history won't persist: \(String(describing: error), privacy: .public)")
            return PlayHistory(fileURL: URL.temporaryDirectory.appending(path: "PlayHistory.json"))
        }
    }

    // MARK: - Downloads

    private static func coverArtStore(downloadsDirectory: URL) -> CoverArtStore {
        do {
            return try CoverArtStore.standard(downloadsDirectory: downloadsDirectory)
        } catch {
            logger.error("Cover art won't be cached on disk: \(String(describing: error), privacy: .public)")
            let temporary = URL.temporaryDirectory
            return CoverArtStore(cacheDirectory: temporary.appending(path: "CoverArt"), pinnedDirectory: downloadsDirectory.appending(path: "CoverArt"))
        }
    }

    private func makeDownloads(client: SubsonicClient, artwork: ArtworkCache) -> DownloadManager {
        let settings = system.settings
        let manager = DownloadManager(
            directory: system.downloadsDirectory,
            transport: system.downloadTransport,
            downloadURL: { songID in try client.downloadURL(songID: songID) },
            convertedURL: { songID, quality in
                try client.streamURL(songID: songID, maxBitRate: quality.maxBitRate, format: DownloadManager.convertedFormat)
            },
            quality: { settings.settings.downloadQuality },
            allowsCellular: { settings.settings.downloadOverCellular },
            artwork: artwork
        )
        Task { await manager.resume() }
        return manager
    }
}

/// The signed-in account as shown in Settings. No password.
struct AccountSummary: Equatable {
    let server: String
    let username: String

    init(credentials: ServerCredentials) {
        server = credentials.baseURL.host(percentEncoded: false) ?? credentials.baseURL.absoluteString
        username = credentials.username
    }
}

/// Signing in as an account other than the one whose data is on the iPhone.
struct AccountSwitch: Identifiable {
    let id = UUID()
    let credentials: ServerCredentials
    /// What the previous account's downloads take up, removed by the switch.
    let downloadBytes: Int64
}
