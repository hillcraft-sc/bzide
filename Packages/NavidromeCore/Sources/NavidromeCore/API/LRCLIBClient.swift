import Foundation
import os

/// Looks lyrics up on LRCLIB (lrclib.net), a free, open lyrics database with
/// synced lyrics for a lot of music. Used only when the user turns it on and
/// the server has none. A request sends the song's title, artist, album and
/// length, nothing else: no account, key or server details.
public struct LRCLIBClient: Sendable {
    /// What LRCLIB has for a song.
    public struct Result: Sendable, Equatable {
        public var synced: String?
        public var plain: String?
        public var isInstrumental: Bool
    }

    private let transport: any HTTPTransport
    private let baseURL: URL
    private static let logger = Logger(subsystem: "MusicApp", category: "LRCLIB")
    /// LRCLIB asks clients to say who they are.
    static let userAgent = "Bzide (iOS music player for Navidrome)"

    public static let lrclib = URL(string: "https://lrclib.net") ?? URL(filePath: "/")

    public init(transport: any HTTPTransport = URLSessionTransport(), baseURL: URL = LRCLIBClient.lrclib) {
        self.transport = transport
        self.baseURL = baseURL
    }

    /// The song's lyrics, or `nil` if LRCLIB doesn't have this recording's.
    /// Tries an exact match on title, artist, album and length, then the same
    /// with the title's version note removed ("(2025 Remaster)"), then a
    /// search by title and artist, keeping the best match (see
    /// `LyricsMatching`). A weak match is turned down: no lyrics beat lyrics
    /// for another recording.
    public func lyrics(title: String, artist: String?, album: String?, duration: Int?) async throws -> Result? {
        let cleaned = LyricsMatching.cleanTitle(title)
        if artist != nil {
            for name in cleaned == title ? [title] : [title, cleaned] {
                if let record = try await fetch("api/get", exactQuery(name, artist: artist, album: album, duration: duration), as: Record.self) {
                    return record.result
                }
            }
        }

        var search = [URLQueryItem(name: "track_name", value: cleaned)]
        if let artist { search.append(.init(name: "artist_name", value: artist)) }
        let found = try await fetch("api/search", search, as: [Record].self) ?? []
        let song = LyricsMatching.Song(title: title, artist: artist, album: album, duration: duration)
        let best = found
            .compactMap { record in LyricsMatching.score(record.candidate, for: song).map { (record, $0) } }
            .max { $0.1 < $1.1 }
        return best?.0.result
    }

    private func exactQuery(_ title: String, artist: String?, album: String?, duration: Int?) -> [URLQueryItem] {
        var query = [URLQueryItem(name: "track_name", value: title)]
        if let artist { query.append(.init(name: "artist_name", value: artist)) }
        if let album { query.append(.init(name: "album_name", value: album)) }
        if let duration { query.append(.init(name: "duration", value: String(duration))) }
        return query
    }

    /// `nil` for a 404 (not found); throws for other failures.
    private func fetch<T: Decodable>(_ path: String, _ query: [URLQueryItem], as type: T.Type) async throws -> T? {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = query
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        Self.logger.debug("GET \(path, privacy: .public)")
        let (data, response) = try await transport.data(for: request)
        if response.statusCode == 404 { return nil }
        guard (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct Record: Decodable {
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?

        var candidate: LyricsMatching.Candidate {
            LyricsMatching.Candidate(
                title: trackName, artist: artistName, album: albumName, duration: duration,
                isSynced: syncedLyrics?.isEmpty == false
            )
        }

        var result: Result {
            Result(
                synced: syncedLyrics.flatMap { $0.isEmpty ? nil : $0 },
                plain: plainLyrics.flatMap { $0.isEmpty ? nil : $0 },
                isInstrumental: instrumental ?? false
            )
        }
    }
}
