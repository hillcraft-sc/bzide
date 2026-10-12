import Foundation
import Observation

/// Something whose songs a menu acts on without opening it.
public enum SongSource: Sendable, Equatable {
    case songs([Song])
    case album(id: String)
    case playlist(id: String)
    /// All of the artist's albums, oldest first, each in track order.
    case artist(id: String)

    /// Equal for the same thing, so a second request for it can be ignored.
    var key: String {
        switch self {
        case .songs(let songs): "songs:" + songs.map(\.id).joined(separator: ",")
        case .album(let id): "album:\(id)"
        case .playlist(let id): "playlist:\(id)"
        case .artist(let id): "artist:\(id)"
        }
    }
}

/// Plays, queues, downloads or adds to a playlist an album, playlist or
/// artist from a menu (a long-press on a list row, say), fetching its songs
/// first. Before acting on an artist with more than `confirmationThreshold`
/// songs it asks, through `confirmation`.
@MainActor
@Observable
public final class QuickActions {
    public enum Action: Sendable, Equatable {
        case play, shuffle, playNext, addToQueue, addToPlaylist, download
    }

    public struct Server: Sendable {
        public var album: @Sendable (_ id: String) async throws(SubsonicError) -> Album
        public var playlist: @Sendable (_ id: String) async throws(SubsonicError) -> Playlist
        public var artist: @Sendable (_ id: String) async throws(SubsonicError) -> Artist

        public init(
            album: @escaping @Sendable (_ id: String) async throws(SubsonicError) -> Album,
            playlist: @escaping @Sendable (_ id: String) async throws(SubsonicError) -> Playlist,
            artist: @escaping @Sendable (_ id: String) async throws(SubsonicError) -> Artist
        ) {
            self.album = album
            self.playlist = playlist
            self.artist = artist
        }
    }

    /// The songs to act on, and what to download for an album or playlist.
    public struct Resolved: Sendable, Equatable {
        public let songs: [Song]
        public let download: DownloadCollection?
    }

    /// "Play 340 songs by X?", waiting for `confirm()` or `cancelConfirmation()`.
    public struct Confirmation: Identifiable, Sendable {
        public let id = UUID()
        public let action: Action
        public let artist: Artist
        public let songCount: Int
    }

    public private(set) var error: String?
    public private(set) var confirmation: Confirmation?

    /// More songs than this, from an artist, needs a yes first.
    public static let confirmationThreshold = 100
    /// Album requests in flight at once when gathering an artist's songs.
    static let concurrentAlbumFetches = 4

    @ObservationIgnored private let server: Server
    @ObservationIgnored private let handle: (Action, Resolved) -> Void
    @ObservationIgnored private var inFlight: Set<String> = []

    /// `handle` does the action with the songs (plays them, opens the playlist sheet...).
    public init(server: Server, handle: @escaping (Action, Resolved) -> Void) {
        self.server = server
        self.handle = handle
    }

    public func perform(_ action: Action, on source: SongSource) async {
        // A second choice for the same thing while it loads would act twice.
        guard inFlight.insert(source.key).inserted else { return }
        defer { inFlight.remove(source.key) }
        error = nil
        do {
            switch source {
            case .songs(let songs):
                finish(action, Resolved(songs: songs, download: nil))
            case .album(let id):
                let album = try await server.album(id)
                finish(action, Resolved(songs: album.songs, download: DownloadCollection(album: album)))
            case .playlist(let id):
                let playlist = try await server.playlist(id)
                finish(action, Resolved(songs: playlist.songs, download: DownloadCollection(playlist: playlist)))
            case .artist(let id):
                let artist = try await server.artist(id)
                let count = artist.albums.reduce(0) { $0 + ($1.songCount ?? 0) }
                if count > Self.confirmationThreshold {
                    confirmation = Confirmation(action: action, artist: artist, songCount: count)
                } else {
                    try await finishArtist(action, artist)
                }
            }
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
        }
    }

    /// The user said yes to `confirmation`.
    public func confirm() async {
        guard let confirmation else { return }
        self.confirmation = nil
        let key = SongSource.artist(id: confirmation.artist.id).key
        guard inFlight.insert(key).inserted else { return }
        defer { inFlight.remove(key) }
        do {
            try await finishArtist(confirmation.action, confirmation.artist)
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
        }
    }

    public func cancelConfirmation() {
        confirmation = nil
    }

    public func dismissError() {
        error = nil
    }

    // MARK: - Private

    private func finish(_ action: Action, _ resolved: Resolved) {
        if resolved.songs.isEmpty {
            error = "There are no songs to play."
        } else {
            handle(action, resolved)
        }
    }

    private func finishArtist(_ action: Action, _ artist: Artist) async throws(SubsonicError) {
        let songs = try await songs(of: Self.oldestFirst(artist.albums))
        finish(action, Resolved(songs: songs, download: nil))
    }

    /// Each album's songs, concatenated in the albums' order. A few albums are
    /// fetched at a time; any failure fails the whole.
    private func songs(of albums: [Album]) async throws(SubsonicError) -> [Song] {
        let fetch = server.album
        let ids = albums.map(\.id)
        do {
            return try await withThrowingTaskGroup(of: (Int, [Song]).self) { group in
                var results = [[Song]](repeating: [], count: ids.count)
                var next = 0
                func startNext() {
                    guard next < ids.count else { return }
                    let index = next
                    let id = ids[index]
                    group.addTask { (index, try await fetch(id).songs) }
                    next += 1
                }
                for _ in 0..<Self.concurrentAlbumFetches { startNext() }
                while let (index, songs) = try await group.next() {
                    results[index] = songs
                    startNext()
                }
                return results.flatMap { $0 }
            }
        } catch let error as SubsonicError {
            throw error
        } catch {
            throw .decoding(String(describing: error))
        }
    }

    /// By year, earliest first; albums without a year go last. Otherwise the
    /// server's order is kept.
    static func oldestFirst(_ albums: [Album]) -> [Album] {
        albums.enumerated().sorted { a, b in
            switch (a.element.year, b.element.year) {
            case let (x?, y?) where x != y: x < y
            case (_?, nil): true
            case (nil, _?): false
            default: a.offset < b.offset
            }
        }.map(\.element)
    }
}
