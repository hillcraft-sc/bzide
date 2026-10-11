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
    private(set) var albums: [Album] = []
    private(set) var playlists: [Playlist] = []
    private(set) var libraryError: String?

    @ObservationIgnored private var client: SubsonicClient?
    @ObservationIgnored private var scrobbler: Scrobbler?
    @ObservationIgnored private let credentialStore = KeychainCredentialStore()
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

    // MARK: - Sign in

    func signIn(serverURL: String, username: String, password: String) async {
        signInError = nil
        let trimmed = serverURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            signInError = "Enter the full server address, starting with http:// or https://."
            return
        }
        let credentials = ServerCredentials(baseURL: url, username: username, password: password)
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await SubsonicClient(credentials: credentials).ping()
            try credentialStore.save(credentials)
            start(with: credentials)
        } catch let error as SubsonicError {
            signInError = error.localizedDescription
        } catch {
            signInError = error.localizedDescription
        }
    }

    private func start(with credentials: ServerCredentials) {
        let client = SubsonicClient(credentials: credentials)
        let scrobbler = Scrobbler(sender: client, store: FileScrobbleStore.applicationSupport() ?? InMemoryScrobbleStore())
        let queueStore: any QueueStore
        do {
            queueStore = try FileQueueStore.applicationSupport()
        } catch {
            Self.logger.error("Queue won't persist: \(String(describing: error), privacy: .public)")
            queueStore = InMemoryQueueStore()
        }
        let downloadsDirectory = Self.downloadsDirectory()
        let artwork = ArtworkCache(client: client, store: Self.coverArtStore(downloadsDirectory: downloadsDirectory))
        let settings = StreamingSettingsModel()
        let history = Self.makeHistory()
        let network = SystemNetworkMonitor()
        let downloads = Self.makeDownloads(directory: downloadsDirectory, client: client, settings: settings, artwork: artwork)
        let resolver = TrackResolver(client: client, settings: settings, network: network, downloads: downloads)
        let engine = PlaybackEngine(
            player: AVQueueAudioPlayer(),
            session: SystemAudioSession(),
            nowPlaying: SystemNowPlaying(loadArtwork: { id in await artwork.image(for: id, pixels: 600) }),
            urls: resolver,
            store: queueStore,
            scheduler: TaskScheduler(),
            network: network,
            scrobbler: scrobbler,
            history: history
        )
        self.engine = engine
        library = Library(client: client, engine: engine, artwork: artwork, settings: settings, downloads: downloads, history: history)
        self.client = client
        self.scrobbler = scrobbler
        // Send anything left over from a previous run.
        Task { await scrobbler.flush() }
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

    private static func downloadsDirectory() -> URL {
        do {
            return try DownloadManager.applicationSupportDirectory()
        } catch {
            // Without a place to keep files, downloads can't persist; use temporary
            // storage so the rest of the app still works.
            logger.error("Downloads won't persist: \(String(describing: error), privacy: .public)")
            return URL.temporaryDirectory.appending(path: "Downloads")
        }
    }

    private static func coverArtStore(downloadsDirectory: URL) -> CoverArtStore {
        do {
            return try CoverArtStore.standard(downloadsDirectory: downloadsDirectory)
        } catch {
            logger.error("Cover art won't be cached on disk: \(String(describing: error), privacy: .public)")
            let temporary = URL.temporaryDirectory
            return CoverArtStore(cacheDirectory: temporary.appending(path: "CoverArt"), pinnedDirectory: downloadsDirectory.appending(path: "CoverArt"))
        }
    }

    private static func makeDownloads(
        directory: URL, client: SubsonicClient, settings: StreamingSettingsModel, artwork: ArtworkCache
    ) -> DownloadManager {
        let manager = DownloadManager(
            directory: directory,
            transport: BackgroundDownloadTransport(stagingDirectory: directory.appending(path: "Incoming")),
            downloadURL: { songID in try client.downloadURL(songID: songID) },
            allowsCellular: { settings.settings.downloadOverCellular },
            artwork: artwork
        )
        Task { await manager.resume() }
        return manager
    }
}
