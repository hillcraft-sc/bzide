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
    var equalizer: EqualizerModel { system.equalizer }
    var isMetering: Bool {
        get { system.player.isMetering }
        set { system.player.isMetering = newValue }
    }

    /// Kept for the app's lifetime, so the theme also applies to the sign-in
    /// screen (the defaults there: signing out sets the account's aside).
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
    /// "Try the Demo": the Navidrome project's public library, signed in to
    /// like any other server.
    func signInToDemo() async {
        await signIn(serverURL: DemoServer.baseURL.absoluteString, username: DemoServer.username, password: DemoServer.password)
    }

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
        // Shared by everyone who tries it, so it keeps its writes small.
        if DemoServer.isDemo(credentials) {
            system.settings.settings = DemoServer.adjusting(system.settings.settings)
        }
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
        // A car's own play as it connects is ignored unless this is on (#27).
        engine.playsWhenDeviceConnects = { [settings = system.settings] in settings.settings.playWhenCarPlayConnects }
        self.engine = engine
        library = Library(
            client: client, username: credentials.username, engine: engine, artwork: artwork,
            settings: system.settings, downloads: downloads, history: history
        )
        account = AccountSummary(credentials: credentials)
        self.client = client
        if let library {
            Task { await library.profile.refresh() }
            // Wishlist entries now in the library get marked (and removed
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
                Self.logger.notice("Put this account's settings in place (a different account, or back after signing out)")
                // Recreated with its backup exclusion, if it went with another account's data.
                _ = try DownloadManager.applicationSupportDirectory()
            }
            // These stay loaded between sign-ins; read this account's. Always,
            // as Same Server, Keep Everything brings back settings in `adopt`.
            reloadSettings()
        } catch {
            // Leaves the owner unchanged, so the check runs again next sign-in.
            Self.logger.error("Couldn't check which account owns the data: \(String(describing: error), privacy: .public)")
        }
    }

    /// The settings models that stay loaded between sign-ins read their
    /// values again, after another account's (or the defaults) were put in place.
    private func reloadSettings() {
        system.settings.reload()
        appearance.reload()
        libraryLayout.reload()
    }

    // MARK: - Restore Default Settings

    /// Puts the signed-in account's settings back to how Bzide starts (see
    /// `AccountSettings.restoreDefaults`), and has the screens already loaded
    /// read them again. Data, the Wishlist and the profile stay.
    func restoreDefaultSettings() {
        do {
            try AccountSettings.standard().restoreDefaults()
        } catch {
            Self.logger.error("Couldn't restore the default settings: \(String(describing: error), privacy: .public)")
            return
        }
        reloadSettings()
        library?.wishlist.reloadSettings()
    }

    // MARK: - Back Up and Restore (Gitea #38)

    /// The signed-in account's data, as a backup to save.
    func makeBackup(includingHistory: Bool) throws(BackupError) -> AccountBackup {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return try Self.accountSettings().backup(includingHistory: includingHistory, appVersion: version)
    }

    /// Whether a backup is from another server or user than this one.
    func isFromAnotherAccount(_ backup: AccountBackup) -> Bool {
        (try? Self.accountSettings().isFromAnotherAccount(backup)) ?? false
    }

    /// Replaces this account's settings and data with the backup's, then has
    /// everything already loaded read them again.
    func restore(_ backup: AccountBackup) throws(BackupError) {
        try Self.accountSettings().restore(backup)
        reloadSettings()
        library?.reloadAfterRestore()
    }

    private static func accountSettings() throws(BackupError) -> AccountSettings {
        do {
            return try AccountSettings.standard()
        } catch {
            throw .io(String(describing: error))
        }
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
        // Plays not yet sent stay with the account and go at its next sign-in
        // (`start` sends them). Sending now could finish after they're set
        // aside below, and send them twice.
        do {
            try credentialStore.delete()
        } catch {
            Self.logger.error("Couldn't remove the saved login: \(error.localizedDescription, privacy: .public)")
        }
        // The sign-in screen, and whoever signs in next, start from the
        // defaults; this account's settings come back when it signs in again.
        do {
            try Self.accountScope().setAside()
        } catch {
            Self.logger.error("Couldn't set the account's settings aside: \(String(describing: error), privacy: .public)")
        }
        reloadSettings()
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
    let isDemo: Bool

    init(credentials: ServerCredentials) {
        isDemo = DemoServer.isDemo(credentials)
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
