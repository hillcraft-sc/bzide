import Foundation

/// Keeps downloaded playlists in step with the server, since a playlist can
/// change after it's downloaded (here or in another app). Every downloaded
/// playlist is checked when the app comes to the foreground, at most once per
/// `interval`; one is also checked whenever it's fetched anyway (opening its
/// page, or after adding songs to it).
///
/// Offline, nothing changes. A playlist the server no longer has keeps its
/// download until the user removes it: deleting music from the phone because
/// of one failed lookup would be worse than a stale copy.
@MainActor
public final class PlaylistDownloadRefresher {
    public typealias Fetch = @Sendable (_ id: String) async throws(SubsonicError) -> Playlist

    /// The shortest time between checks of every playlist.
    public static let interval: TimeInterval = 15 * 60

    private let downloads: DownloadManager
    private let fetch: Fetch
    private let now: () -> Date
    private var lastCheck: Date?
    private var isChecking = false

    public init(downloads: DownloadManager, fetch: @escaping Fetch, now: @escaping () -> Date = { .now }) {
        self.downloads = downloads
        self.fetch = fetch
        self.now = now
    }

    /// Checks every downloaded playlist, unless that was done within
    /// `interval`. Returns how many changed.
    @discardableResult
    public func refreshAllIfDue() async -> Int {
        if let lastCheck, now().timeIntervalSince(lastCheck) < Self.interval { return 0 }
        guard !isChecking else { return 0 }
        isChecking = true
        defer { isChecking = false }
        let ids = downloads.collections.filter { $0.kind == .playlist }.map(\.serverID)
        var reached = ids.isEmpty
        var changed = 0
        for id in ids {
            do {
                let playlist = try await fetch(id)
                reached = true
                if downloads.refresh(playlist) { changed += 1 }
            } catch {
                // The server answered (e.g. the playlist is gone): that counts as
                // reaching it. Only a network failure means try again soon.
                if case .network = error {} else { reached = true }
            }
        }
        // Not marked as done if the server couldn't be reached at all, so the
        // next return to the app tries again.
        if reached { lastCheck = now() }
        return changed
    }

    /// Updates a playlist's download from a copy just fetched.
    public func refresh(_ playlist: Playlist) {
        downloads.refresh(playlist)
    }

    /// Fetches a downloaded playlist and updates its download; does nothing
    /// if it isn't downloaded or can't be fetched.
    public func refresh(playlistID: String) async {
        guard downloads.collection(id: DownloadCollection.id(.playlist, serverID: playlistID)) != nil,
              let playlist = try? await fetch(playlistID) else { return }
        downloads.refresh(playlist)
    }
}
