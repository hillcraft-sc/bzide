import Foundation

/// An album, playlist or single song the user downloaded, with its songs as
/// they were at the time. Kept so it can be listed and played without the server.
public struct DownloadCollection: Sendable, Equatable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        case album
        case playlist
        /// One song downloaded on its own.
        case song
    }

    public let kind: Kind
    /// The album or playlist id on the server.
    public let serverID: String
    public var name: String
    public var artist: String?
    public var coverArtID: String?
    public var songs: [Song]
    public var addedAt: Date

    public var id: String { Self.id(kind, serverID: serverID) }

    /// The id a collection of this kind and server id has, to look it up
    /// without fetching it.
    public static func id(_ kind: Kind, serverID: String) -> String {
        "\(kind.rawValue):\(serverID)"
    }

    public init(kind: Kind, serverID: String, name: String, artist: String? = nil, coverArtID: String? = nil, songs: [Song], addedAt: Date = Date()) {
        self.kind = kind
        self.serverID = serverID
        self.name = name
        self.artist = artist
        self.coverArtID = coverArtID
        self.songs = songs
        self.addedAt = addedAt
    }

    /// Whether the name, artist, or any song title or artist contains `query`,
    /// ignoring case and accents. An empty query matches everything.
    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let fields: [String?] = [name, artist] + songs.flatMap { [$0.title, $0.artist] }
        return fields.contains { $0?.localizedStandardContains(query) == true }
    }

    public init(song: Song) {
        self.init(kind: .song, serverID: song.id, name: song.title, artist: song.artist, coverArtID: song.coverArtID, songs: [song])
    }

    public init(album: Album) {
        self.init(kind: .album, serverID: album.id, name: album.name, artist: album.artist, coverArtID: album.coverArtID, songs: album.songs)
    }

    public init(playlist: Playlist) {
        self.init(kind: .playlist, serverID: playlist.id, name: playlist.name, coverArtID: playlist.coverArtID, songs: playlist.songs)
    }
}

/// How a song is downloaded. See `DownloadManager.membership(ofSong:)`.
public enum SongDownloadMembership: Sendable, Equatable {
    /// Downloaded on its own (it may also be in a downloaded album or playlist).
    case own
    /// Only as part of a downloaded album or playlist.
    case inCollection
    case none
}

/// Where one song's download stands.
public enum SongDownloadState: Sendable, Equatable {
    case notDownloaded
    case waiting
    /// 0...1, or `nil` before the size is known.
    case downloading(progress: Double?)
    case done
    case failed(String)
}

/// Where a whole album or playlist's download stands.
public struct CollectionDownloadStatus: Sendable, Equatable {
    public var songCount: Int
    public var doneCount: Int
    public var failedCount: Int
    /// 0...1 across all songs, counting partial progress of running downloads.
    public var progress: Double

    public var isComplete: Bool { doneCount == songCount }
}

/// A finished song file, by name inside the downloads folder.
struct StoredFile: Sendable, Equatable, Codable {
    var fileName: String
    var bytes: Int64
    /// Kbps it was converted to; `nil` for an original.
    var convertedBitRate: Int?
}

/// What's saved between launches.
struct DownloadIndex: Sendable, Equatable, Codable {
    var collections: [DownloadCollection] = []
    /// Keyed by song id.
    var files: [String: StoredFile] = [:]
    /// Songs downloading converted, by song id, with the file extension their
    /// file must get. Saved so a download that finishes after a relaunch is
    /// still named for what it is.
    var convertedFormats: [String: String] = [:]
    /// The bitrate each of those is being converted to.
    var convertedBitRates: [String: Int] = [:]

    init(
        collections: [DownloadCollection] = [], files: [String: StoredFile] = [:],
        convertedFormats: [String: String] = [:], convertedBitRates: [String: Int] = [:]
    ) {
        self.collections = collections
        self.files = files
        self.convertedFormats = convertedFormats
        self.convertedBitRates = convertedBitRates
    }

    private enum CodingKeys: String, CodingKey { case collections, files, convertedFormats, convertedBitRates }

    /// An index saved before conversion existed has no formats.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        collections = try c.decode([DownloadCollection].self, forKey: .collections)
        files = try c.decode([String: StoredFile].self, forKey: .files)
        convertedFormats = (try? c.decodeIfPresent([String: String].self, forKey: .convertedFormats)) ?? [:]
        convertedBitRates = (try? c.decodeIfPresent([String: Int].self, forKey: .convertedBitRates)) ?? [:]
    }
}

/// What the downloader reports back.
public enum DownloadEvent: Sendable, Equatable {
    case progress(songID: String, fraction: Double?)
    /// The file has been moved out of the system's temporary location to `file`,
    /// which the manager now owns. `fileExtension` comes from the server's
    /// response, for songs whose metadata has no suffix.
    case finished(songID: String, file: URL, fileExtension: String?)
    case failed(songID: String, message: String)
}

/// The download boundary. Production uses a background `URLSession`; tests use a fake.
@MainActor
public protocol DownloadTransport: AnyObject {
    var onEvent: (@MainActor (DownloadEvent) -> Void)? { get set }
    func start(songID: String, from url: URL, allowsCellular: Bool)
    func cancel(songID: String)
    /// Songs the system is still downloading, e.g. ones started before the app
    /// was last terminated.
    func activeSongIDs() async -> Set<String>
}
