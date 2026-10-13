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
    /// A search result this close in length (seconds) is the same recording.
    static let durationTolerance: Double = 3

    public static let lrclib = URL(string: "https://lrclib.net") ?? URL(filePath: "/")

    public init(transport: any HTTPTransport = URLSessionTransport(), baseURL: URL = LRCLIBClient.lrclib) {
        self.transport = transport
        self.baseURL = baseURL
    }

    /// The song's lyrics, or `nil` if LRCLIB doesn't have it. Tries an exact
    /// match on title, artist, album and length first, then a search by title
    /// and artist, keeping a result of about the same length.
    public func lyrics(title: String, artist: String?, album: String?, duration: Int?) async throws -> Result? {
        var exact = [URLQueryItem(name: "track_name", value: title)]
        if let artist { exact.append(.init(name: "artist_name", value: artist)) }
        if let album { exact.append(.init(name: "album_name", value: album)) }
        if let duration { exact.append(.init(name: "duration", value: String(duration))) }
        if artist != nil, let record = try await fetch("api/get", exact, as: Record.self) {
            return record.result
        }

        var search = [URLQueryItem(name: "track_name", value: title)]
        if let artist { search.append(.init(name: "artist_name", value: artist)) }
        let found = try await fetch("api/search", search, as: [Record].self) ?? []
        let sameLength = found.filter { record in
            guard let duration, let length = record.duration else { return true }
            return abs(length - Double(duration)) <= Self.durationTolerance
        }
        // Synced lyrics are better than plain ones.
        let best = sameLength.first { $0.syncedLyrics?.isEmpty == false } ?? sameLength.first
        return best?.result
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
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?

        var result: Result {
            Result(
                synced: syncedLyrics.flatMap { $0.isEmpty ? nil : $0 },
                plain: plainLyrics.flatMap { $0.isEmpty ? nil : $0 },
                isInstrumental: instrumental ?? false
            )
        }
    }
}
