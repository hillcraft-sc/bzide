import Foundation
import Testing
@testable import NavidromeCore

struct SavedStationsFilterTests {
    private static func station(
        _ id: String, _ name: String, country: String? = nil, tags: [String] = [], bitrate: Int? = nil, seen: Double? = nil
    ) -> RadioStation {
        var station = RadioStation(id: id, name: name, streamURL: URL(string: "https://stream.example.com/\(id)")!)
        if country != nil || !tags.isEmpty || bitrate != nil {
            station.details = StationDetails(countryCode: country, tags: tags, bitrate: bitrate)
        }
        station.firstSeen = seen.map { Date(timeIntervalSince1970: $0) }
        return station
    }

    private static let stations = [
        station("a", "Night Waves", country: "US", tags: ["jazz", "smooth jazz"], bitrate: 128, seen: 300),
        station("b", "bebop FM", country: "DE", tags: ["Jazz"], bitrate: 320, seen: 100),
        station("c", "Radio Paradise", country: "US", tags: ["rock", "eclectic"], bitrate: 256, seen: 200),
        station("d", "Hand Added"),
    ]

    private static func names(_ filter: SavedStationsFilter) -> [String] {
        filter.apply(stations) { code in ["US": "United States", "DE": "Germany"][code] ?? code }.map(\.name)
    }

    @Test func byNameItIsAlphabeticalAndSearchable() {
        #expect(Self.names(SavedStationsFilter()) == ["bebop FM", "Hand Added", "Night Waves", "Radio Paradise"])
        #expect(Self.names(SavedStationsFilter(name: "radio")) == ["Radio Paradise"])
    }

    @Test func filtersCombineAndStationsWithoutDetailsDropOut() {
        #expect(Self.names(SavedStationsFilter(countryCode: "US")) == ["Night Waves", "Radio Paradise"])
        // Genres match without regard to case.
        #expect(Self.names(SavedStationsFilter(tag: "jazz")) == ["bebop FM", "Night Waves"])
        #expect(Self.names(SavedStationsFilter(minimumBitrate: 256)) == ["bebop FM", "Radio Paradise"])
        #expect(Self.names(SavedStationsFilter(countryCode: "US", tag: "jazz", minimumBitrate: 128)) == ["Night Waves"])
    }

    @Test func sortsPutUnknownsLast() {
        #expect(Self.names(SavedStationsFilter(sort: .country)) == ["bebop FM", "Night Waves", "Radio Paradise", "Hand Added"])
        #expect(Self.names(SavedStationsFilter(sort: .quality)) == ["bebop FM", "Radio Paradise", "Night Waves", "Hand Added"])
        #expect(Self.names(SavedStationsFilter(sort: .dateAdded)) == ["Night Waves", "Radio Paradise", "bebop FM", "Hand Added"])
    }

    @Test func thePickersOfferWhatTheStationsHave() {
        #expect(SavedStationsFilter.countries(in: Self.stations) == [.init(code: "US", stationCount: 2), .init(code: "DE", stationCount: 1)])
        let tags = SavedStationsFilter.tags(in: Self.stations)
        #expect(tags.first == .init(name: "jazz", stationCount: 2))
        #expect(tags.map(\.name).contains("eclectic"))
    }

    @Test func theFiltersAreRememberedButNotTheSearch() throws {
        var filter = SavedStationsFilter(name: "waves", countryCode: "US", tag: "jazz", minimumBitrate: 192, sort: .dateAdded)
        let restored = try JSONDecoder().decode(SavedStationsFilter.self, from: JSONEncoder().encode(filter))
        filter.name = ""
        #expect(restored == filter)
        #expect(filter.hasFilters)
        filter.clearFilters()
        #expect(!filter.hasFilters)
        #expect(filter.sort == .dateAdded)
    }
}
