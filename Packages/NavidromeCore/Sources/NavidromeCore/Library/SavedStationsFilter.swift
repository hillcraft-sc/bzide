import Foundation

/// Searching, filtering and sorting the saved radio stations (the Radio
/// screen), with the same filters as Find Stations: a name, a country, a
/// genre and a minimum quality. Country, genre and quality come from each
/// station's `details`; a station without them doesn't match those filters,
/// and sorts after those that have them.
public struct SavedStationsFilter: Codable, Equatable, Sendable {
    public enum Sort: String, Codable, CaseIterable, Sendable {
        case name, country, quality, dateAdded

        public var title: String {
            switch self {
            case .name: "Name"
            case .country: "Country"
            case .quality: "Quality"
            case .dateAdded: "Date Added"
            }
        }
    }

    /// Typed in the search field; not remembered between visits.
    public var name = ""
    public var countryCode: String?
    public var tag: String?
    /// In kbps.
    public var minimumBitrate: Int?
    public var sort = Sort.name

    public init(name: String = "", countryCode: String? = nil, tag: String? = nil, minimumBitrate: Int? = nil, sort: Sort = .name) {
        self.name = name
        self.countryCode = countryCode
        self.tag = tag
        self.minimumBitrate = minimumBitrate
        self.sort = sort
    }

    private enum CodingKeys: String, CodingKey { case countryCode, tag, minimumBitrate, sort }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        countryCode = (try? c.decodeIfPresent(String.self, forKey: .countryCode)) ?? nil
        tag = (try? c.decodeIfPresent(String.self, forKey: .tag)) ?? nil
        minimumBitrate = (try? c.decodeIfPresent(Int.self, forKey: .minimumBitrate)) ?? nil
        sort = (try? c.decodeIfPresent(Sort.self, forKey: .sort)) ?? .name
    }

    /// Whether a country, genre or quality is chosen (the search text aside).
    public var hasFilters: Bool { countryCode != nil || tag != nil || minimumBitrate != nil }

    public mutating func clearFilters() {
        countryCode = nil
        tag = nil
        minimumBitrate = nil
    }

    /// The stations that match, in the chosen order. `countryName` names a
    /// country code as the phone does, for sorting by country.
    public func apply(_ stations: [RadioStation], countryName: (String) -> String) -> [RadioStation] {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = stations.filter { station in
            if !query.isEmpty, !station.name.localizedStandardContains(query) { return false }
            if let countryCode, station.details?.countryCode != countryCode { return false }
            if let tag, !(station.details?.tags ?? []).contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { return false }
            if let minimumBitrate, (station.details?.bitrate ?? 0) < minimumBitrate { return false }
            return true
        }
        return matching.sorted { a, b in
            switch sort {
            case .name:
                return Self.byName(a, b)
            case .country:
                return Self.compare(a.details?.countryCode.map(countryName), b.details?.countryCode.map(countryName), a, b) {
                    $0.localizedStandardCompare($1) == .orderedAscending
                }
            case .quality:
                return Self.compare(a.details?.bitrate, b.details?.bitrate, a, b, by: >)
            case .dateAdded:
                return Self.compare(a.firstSeen, b.firstSeen, a, b, by: >)
            }
        }
    }

    /// By `key` (unknown last), then by name.
    private static func compare<Key: Equatable>(_ keyA: Key?, _ keyB: Key?, _ a: RadioStation, _ b: RadioStation, by isBefore: (Key, Key) -> Bool) -> Bool {
        switch (keyA, keyB) {
        case let (x?, y?) where x != y: isBefore(x, y)
        case (.some, nil): true
        case (nil, .some): false
        default: byName(a, b)
        }
    }

    private static func byName(_ a: RadioStation, _ b: RadioStation) -> Bool {
        a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    // MARK: - What the pickers offer

    /// The countries the stations come from, most stations first.
    public static func countries(in stations: [RadioStation]) -> [RadioBrowserClient.Country] {
        let counts = Dictionary(grouping: stations.compactMap { $0.details?.countryCode }, by: { $0 }).mapValues(\.count)
        return counts.map { RadioBrowserClient.Country(code: $0.key, stationCount: $0.value) }
            .sorted { ($0.stationCount, $1.code) > ($1.stationCount, $0.code) }
    }

    /// The stations' genres, most stations first, then by name.
    public static func tags(in stations: [RadioStation]) -> [RadioBrowserClient.Tag] {
        var counts: [String: Int] = [:]
        for station in stations {
            for tag in Set((station.details?.tags ?? []).map { $0.lowercased() }) {
                counts[tag, default: 0] += 1
            }
        }
        return counts.map { RadioBrowserClient.Tag(name: $0.key, stationCount: $0.value) }
            .sorted { $0.stationCount != $1.stationCount ? $0.stationCount > $1.stationCount : $0.name < $1.name }
    }
}
