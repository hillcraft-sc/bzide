import Foundation
import os

/// Searches Radio Browser (radio-browser.info), a free, open directory of
/// internet radio stations, used only when the user turns on Find Stations
/// Online. A search sends what the user typed; playing a station found there
/// tells Radio Browser it was played (its popularity count). Nothing else is
/// sent: no account, key or server details.
///
/// Radio Browser runs on several mirrors that come and go, and asks clients
/// to look them up rather than name one: the list comes from
/// `all.api.radio-browser.info/json/servers`, in random order, and the next
/// one is tried if one fails.
public struct RadioBrowserClient: Sendable {
    /// What a search matches.
    public enum Field: String, CaseIterable, Sendable {
        case name, tag, country

        public var title: String {
            switch self {
            case .name: "Name"
            case .tag: "Genre"
            case .country: "Country"
            }
        }
    }

    private let transport: any HTTPTransport
    private let servers: Servers
    private static let logger = Logger(subsystem: "MusicApp", category: "RadioBrowser")
    /// Radio Browser asks clients to say who they are.
    static let userAgent = "Bzide (iOS music player for Navidrome)"
    public static let directory = URL(string: "https://all.api.radio-browser.info") ?? URL(filePath: "/")
    /// Results per search; the most played first.
    public static let resultLimit = 50

    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        directory: URL = RadioBrowserClient.directory,
        shuffle: @escaping @Sendable ([URL]) -> [URL] = { $0.shuffled() }
    ) {
        self.transport = transport
        self.servers = Servers(directory: directory, shuffle: shuffle)
    }

    /// Stations whose name, genre tag or country contains `text`, most played
    /// first, leaving out ones Radio Browser found broken.
    public func search(_ text: String, by field: Field) async throws -> [RadioBrowserStation] {
        let query = [
            URLQueryItem(name: field.rawValue, value: text),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "limit", value: String(Self.resultLimit)),
        ]
        return Self.unique(try await get("json/stations/search", query, as: LossyList<RadioBrowserStation>.self).items)
    }

    /// The most played stations right now, for before anything is typed.
    public func popular() async throws -> [RadioBrowserStation] {
        let query = [URLQueryItem(name: "hidebroken", value: "true")]
        return Self.unique(try await get("json/stations/topclick/\(Self.resultLimit)", query, as: LossyList<RadioBrowserStation>.self).items)
    }

    /// Tells Radio Browser a station was played, as it asks clients to; it
    /// counts one per station per day from the same address.
    public func countPlay(of stationID: String) async throws {
        _ = try await get("json/url/\(stationID)", [], as: Ignored.self)
    }

    // MARK: - Plumbing

    /// Tries each server in turn. A network failure or server error moves on
    /// to the next; anything else (a cancel, an unreadable reply) stops.
    private func get<T: Decodable>(_ path: String, _ query: [URLQueryItem], as type: T.Type) async throws -> T {
        var lastError: any Error = URLError(.cannotFindHost)
        for base in await servers.list(using: transport) {
            do {
                let data = try await fetch(base, path, query)
                await servers.worked(base)
                do {
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    Self.logger.error("GET \(path, privacy: .public): unreadable reply (\(data.count, privacy: .public) bytes)")
                    throw error
                }
            } catch let error as URLError where error.code != .cancelled {
                Self.logger.error("GET \(path, privacy: .public) on \(base.host() ?? "?", privacy: .public) failed: URLError \(error.code.rawValue, privacy: .public)")
                lastError = error
            }
        }
        throw lastError
    }

    private func fetch(_ base: URL, _ path: String, _ query: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw URLError(.badURL) }
        let (data, response) = try await transport.data(for: Self.request(url))
        // A server that's struggling: try the next.
        guard (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }

    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Radio Browser lists some stations more than once; one per stream.
    static func unique(_ stations: [RadioBrowserStation]) -> [RadioBrowserStation] {
        var seen = Set<URL>()
        return stations.filter { seen.insert($0.streamURL).inserted }
    }

    /// The mirrors, found once and then reused, the last one that worked first.
    actor Servers {
        private let directory: URL
        private let shuffle: @Sendable ([URL]) -> [URL]
        private var known: [URL]?

        init(directory: URL, shuffle: @escaping @Sendable ([URL]) -> [URL]) {
            self.directory = directory
            self.shuffle = shuffle
        }

        /// If the list can't be fetched, the directory address itself, which
        /// reaches one of them; the list is tried again next time.
        func list(using transport: any HTTPTransport) async -> [URL] {
            if let known { return known }
            struct Server: Decodable { let name: String? }
            let url = directory.appending(path: "json/servers")
            guard let (data, response) = try? await transport.data(for: RadioBrowserClient.request(url)),
                  (200..<300).contains(response.statusCode),
                  let found = try? JSONDecoder().decode(LossyList<Server>.self, from: data).items else {
                return [directory]
            }
            var seen = Set<String>()
            let names = found.compactMap(\.name).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            let servers = names.compactMap { URL(string: "https://\($0)") }
            guard !servers.isEmpty else { return [directory] }
            known = shuffle(servers)
            return known ?? [directory]
        }

        func worked(_ server: URL) {
            guard var list = known, let index = list.firstIndex(of: server), index > 0 else { return }
            list.remove(at: index)
            list.insert(server, at: 0)
            known = list
        }
    }

    /// A reply whose content doesn't matter.
    private struct Ignored: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}

/// A JSON array where an element that doesn't decode is skipped, not fatal.
struct LossyList<Element: Decodable>: Decodable {
    let items: [Element]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var items: [Element] = []
        while !container.isAtEnd {
            if let item = try? container.decode(Element.self) {
                items.append(item)
            } else {
                // Step past the bad element.
                _ = try? container.decode(Skipped.self)
            }
        }
        self.items = items
    }

    private struct Skipped: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}
