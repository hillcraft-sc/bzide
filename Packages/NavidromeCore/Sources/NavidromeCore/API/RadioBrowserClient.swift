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
    /// What to look for: a name, filters, and the order. Empty means any.
    public struct Query: Equatable, Hashable, Sendable {
        public var name: String
        /// ISO 3166-1 alpha-2, e.g. "US".
        public var countryCode: String?
        /// A genre tag, matched exactly (e.g. "jazz", not "acid jazz").
        public var tag: String?
        public var order: Order

        public init(name: String = "", countryCode: String? = nil, tag: String? = nil, order: Order = .mostPlayed) {
            self.name = name
            self.countryCode = countryCode
            self.tag = tag
            self.order = order
        }

        /// No name or filters, most played first: what's popular right now.
        public var isPopular: Bool {
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && countryCode == nil && tag == nil && order == .mostPlayed
        }
    }

    public enum Order: String, CaseIterable, Sendable {
        /// Radio Browser's `clickcount`: plays in the last day.
        case mostPlayed = "clickcount"
        /// Radio Browser's `votes`.
        case topRated = "votes"
        case name

        public var title: String {
            switch self {
            case .mostPlayed: "Most Played"
            case .topRated: "Top Rated"
            case .name: "Name"
            }
        }
    }

    /// A country Radio Browser has stations for.
    public struct Country: Equatable, Identifiable, Sendable {
        /// ISO 3166-1 alpha-2, e.g. "US".
        public var code: String
        public var stationCount: Int
        public var id: String { code }

        public init(code: String, stationCount: Int) {
            self.code = code
            self.stationCount = stationCount
        }

        /// The name as the phone says it ("United States"), not Radio
        /// Browser's ("The United States Of America").
        public func name(in locale: Locale = .current) -> String {
            locale.localizedString(forRegionCode: code) ?? code
        }
    }

    /// A genre tag and how many stations have it.
    public struct Tag: Equatable, Identifiable, Sendable {
        public var name: String
        public var stationCount: Int
        public var id: String { name }

        public init(name: String, stationCount: Int) {
            self.name = name
            self.stationCount = stationCount
        }
    }

    private let transport: any HTTPTransport
    private let servers: Servers
    private static let logger = Logger(subsystem: "MusicApp", category: "RadioBrowser")
    /// Radio Browser asks clients to say who they are.
    static let userAgent = "Bzide (iOS music player for Navidrome)"
    public static let directory = URL(string: "https://all.api.radio-browser.info") ?? URL(filePath: "/")
    /// Stations per page.
    public static let pageSize = 50
    /// How many genre tags the Genre filter offers.
    public static let tagLimit = 300

    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        directory: URL = RadioBrowserClient.directory,
        shuffle: @escaping @Sendable ([URL]) -> [URL] = { $0.shuffled() }
    ) {
        self.transport = transport
        self.servers = Servers(directory: directory, shuffle: shuffle)
    }

    /// A page of stations matching `query`, leaving out ones Radio Browser
    /// found broken. As Radio Browser returns them: the same stream may be
    /// listed twice (see `unique`), and a full page means there may be more.
    public func stations(_ query: Query, offset: Int = 0, limit: Int = RadioBrowserClient.pageSize) async throws -> [RadioBrowserStation] {
        var items = [URLQueryItem]()
        let name = query.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { items.append(.init(name: "name", value: name)) }
        if let code = query.countryCode { items.append(.init(name: "countrycode", value: code)) }
        if let tag = query.tag {
            items.append(.init(name: "tag", value: tag))
            items.append(.init(name: "tagExact", value: "true"))
        }
        items += [
            .init(name: "order", value: query.order.rawValue),
            // Most played and top rated: highest first.
            .init(name: "reverse", value: query.order == .name ? "false" : "true"),
            .init(name: "hidebroken", value: "true"),
            .init(name: "offset", value: String(offset)),
            .init(name: "limit", value: String(limit)),
        ]
        return try await get("json/stations/search", items, as: LossyList<RadioBrowserStation>.self).items
    }

    /// Every country with working stations, most stations first. Radio
    /// Browser sometimes lists a country under two names; they're combined.
    public func countries() async throws -> [Country] {
        struct Entry: Decodable {
            let iso_3166_1: String?
            let stationcount: Int?
        }
        let query = [URLQueryItem(name: "hidebroken", value: "true")]
        var counts: [String: Int] = [:]
        for entry in try await get("json/countries", query, as: LossyList<Entry>.self).items {
            guard let code = entry.iso_3166_1?.trimmingCharacters(in: .whitespaces).uppercased(), code.count == 2 else { continue }
            counts[code, default: 0] += entry.stationcount ?? 0
        }
        return counts.filter { $0.value > 0 }
            .map { Country(code: $0.key, stationCount: $0.value) }
            .sorted { ($0.stationCount, $1.code) > ($1.stationCount, $0.code) }
    }

    /// The most common genre tags, most stations first.
    public func tags(limit: Int = RadioBrowserClient.tagLimit) async throws -> [Tag] {
        struct Entry: Decodable {
            let name: String?
            let stationcount: Int?
        }
        let query = [
            URLQueryItem(name: "order", value: "stationcount"),
            URLQueryItem(name: "reverse", value: "true"),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return try await get("json/tags", query, as: LossyList<Entry>.self).items.compactMap { entry in
            guard let name = entry.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
            return Tag(name: name, stationCount: entry.stationcount ?? 0)
        }
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
