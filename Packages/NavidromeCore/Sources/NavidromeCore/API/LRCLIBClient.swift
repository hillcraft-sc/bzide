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
        /// LRCLIB's id for this entry, to find it again among `matches`.
        public var id: Int? = nil
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
        if case .found(let result) = try await lookUp(title: title, artist: artist, album: album, duration: duration) {
            return result
        }
        return nil
    }

    /// What a lookup found: lyrics, or why there were none.
    public enum Lookup: Equatable, Sendable {
        case found(Result)
        /// The closest candidate turned down, or `nil` if LRCLIB had none.
        case notFound(LyricsMatching.Rejection?)
    }

    /// The same as `lyrics`, saying why when nothing qualifies.
    ///
    /// An exact match with synced lyrics wins at once. One with only plain
    /// lyrics is kept while the search looks for synced ones, as synced
    /// lyrics win wherever they come from. An exact lookup that fails (on a
    /// miss, `api/get` looks elsewhere, which can be slow or fail) doesn't end
    /// the lookup: the search is still tried, and only its failure, with
    /// nothing else found, is an error.
    public func lookUp(title: String, artist: String?, album: String?, duration: Int?) async throws -> Lookup {
        let cleaned = LyricsMatching.cleanTitle(title)
        var plainExact: Result?
        if artist != nil {
            for name in cleaned == title ? [title] : [title, cleaned] {
                do {
                    if let record = try await fetch("api/get", exactQuery(name, artist: artist, album: album, duration: duration), as: Record.self) {
                        // Synced, or known to have no words: nothing better to find.
                        if record.result.synced != nil || record.result.isInstrumental { return .found(record.result) }
                        plainExact = plainExact ?? record.result
                    }
                } catch let error as URLError where error.code == .cancelled {
                    throw error
                } catch {
                    // On to the search.
                }
            }
        }

        var search = [URLQueryItem(name: "track_name", value: cleaned)]
        if let artist { search.append(.init(name: "artist_name", value: artist)) }
        let found: [Record]
        do {
            found = try await fetch("api/search", search, as: [Record].self) ?? []
        } catch {
            if let plainExact { return .found(plainExact) }
            throw error
        }
        let song = LyricsMatching.Song(title: title, artist: artist, album: album, duration: duration)
        var best: (record: Record, score: Double)?
        var rejections: [LyricsMatching.Rejection] = []
        for record in found {
            switch LyricsMatching.judge(record.candidate, for: song) {
            case .success(let score):
                if score > best?.score ?? -.infinity { best = (record, score) }
            case .failure(let rejection):
                rejections.append(rejection)
            }
        }
        if let best, best.record.result.synced != nil || plainExact == nil { return .found(best.record.result) }
        if let plainExact { return .found(plainExact) }
        return .notFound(LyricsMatching.closest(rejections))
    }

    /// Every entry that fits the song, best first, for "Wrong lyrics?": the
    /// search's matches by score (the search returns the exact matches too).
    /// Only the search, not the exact lookups `lookUp` starts with: on a miss,
    /// `api/get` looks the song up elsewhere, which can be slow or fail. A
    /// timeout or server error is tried once more. An entry whose words are
    /// the same as an earlier one's is left out, so the next one is really
    /// different.
    public func matches(title: String, artist: String?, album: String?, duration: Int?) async throws -> [Result] {
        var search = [URLQueryItem(name: "track_name", value: LyricsMatching.cleanTitle(title))]
        if let artist { search.append(.init(name: "artist_name", value: artist)) }
        let records: [Record]
        do {
            records = try await fetch("api/search", search, as: [Record].self) ?? []
        } catch let error as URLError where error.code != .cancelled {
            records = try await fetch("api/search", search, as: [Record].self) ?? []
        }
        let song = LyricsMatching.Song(title: title, artist: artist, album: album, duration: duration)
        let scored = records.compactMap { record -> (Result, Double)? in
            guard case .success(let score) = LyricsMatching.judge(record.candidate, for: song) else { return nil }
            return (record.result, score)
        }
        var seenIDs = Set<Int>()
        var seenWords = Set<String>()
        return scored.sorted { $0.1 > $1.1 }.map(\.0).filter { result in
            if let id = result.id, !seenIDs.insert(id).inserted { return false }
            return seenWords.insert(Self.words(result)).inserted
        }
    }

    /// The words alone, to tell versions apart: timing and spacing don't count.
    static func words(_ result: Result) -> String {
        let text = result.plain ?? result.synced.map { $0.replacing(#/\[[0-9:.]+\]/#, with: "") } ?? ""
        return text.lowercased().filter { $0.isLetter || $0.isNumber }
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
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        Self.logger.debug("GET \(path, privacy: .public)")
        // Failures are logged by kind only (no song details), to tell an
        // outage from LRCLIB turning requests away or an unreadable reply.
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as URLError where error.code != .cancelled {
            Self.logger.error("GET \(path, privacy: .public) failed: URLError \(error.code.rawValue, privacy: .public)")
            throw error
        }
        if response.statusCode == 404 { return nil }
        guard (200..<300).contains(response.statusCode) else {
            Self.logger.error("GET \(path, privacy: .public) failed: HTTP \(response.statusCode, privacy: .public)")
            throw URLError(.badServerResponse)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Self.logger.error("GET \(path, privacy: .public) failed: unreadable reply (\(data.count, privacy: .public) bytes)")
            throw error
        }
    }

    private struct Record: Decodable {
        let id: Int?
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
                isInstrumental: instrumental ?? false,
                id: id
            )
        }
    }
}
