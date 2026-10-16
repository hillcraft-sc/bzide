import Foundation
import Testing
@testable import NavidromeCore

struct StationLogoTests {
    @Test func logosAreLoadedOverHTTPS() {
        #expect(StationLogo.usableURL("https://example.com/logo.png")?.absoluteString == "https://example.com/logo.png")
        #expect(StationLogo.usableURL("http://example.com/favicon.ico")?.absoluteString == "https://example.com/favicon.ico")
        #expect(StationLogo.usableURL("http://example.com:80/a.png")?.absoluteString == "https://example.com/a.png")
        #expect(StationLogo.usableURL("") == nil)
        #expect(StationLogo.usableURL("ftp://example.com/a.png") == nil)
        #expect(StationLogo.usableURL("logo.png") == nil)
    }

    @Test func aLogoIsCoverArt() throws {
        let logo = try #require(URL(string: "https://example.com/logo.png"))
        let id = StationLogo.coverArtID(for: logo)
        #expect(StationLogo.url(fromCoverArtID: id) == logo)
        // A server's cover art id isn't a logo.
        #expect(StationLogo.url(fromCoverArtID: "al-1") == nil)
    }

    @Test func aStationPlaysWithItsLogo() throws {
        let logo = try #require(URL(string: "https://example.com/logo.png"))
        let station = RadioStation(id: "rs-1", name: "Night Waves", streamURL: URL(string: "https://stream.example.com/waves")!, logoURL: logo)
        let song = Song(station: station, stream: station.streamURL)
        #expect(song.coverArtID == StationLogo.coverArtID(for: logo))
        #expect(Song(station: RadioStation(id: "rs-2", name: "Plain", streamURL: station.streamURL), stream: station.streamURL).coverArtID == nil)
    }

    @Test func aFoundStationsFaviconBecomesItsLogo() {
        let station = RadioBrowserStation(id: "u-1", name: "Night Waves", streamURL: URL(string: "https://stream.example.com/waves")!, faviconURL: URL(string: "http://example.com/favicon.ico")!)
        #expect(station.logoURL?.absoluteString == "https://example.com/favicon.ico")
        #expect(station.radioStation.logoURL == station.logoURL)
    }

    @Test func longCoverIDsGetShortFileNames() {
        let id = StationLogo.coverArtID(for: URL(string: "https://example.com/" + String(repeating: "a", count: 300) + ".png")!)
        let name = CoverArtStore.fileName(for: id)
        #expect(name.hasPrefix("sha256-"))
        #expect(name.count == 7 + 64)
        #expect(CoverArtStore.fileName(for: id) == name)
        #expect(CoverArtStore.fileName(for: "al-1") == "al-1")
    }

    @Test func theStoreRemembersDetailsAndMisses() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "StationDetails-\(UUID().uuidString).json")
        let stream = try #require(URL(string: "https://stream.example.com/waves"))
        let other = try #require(URL(string: "https://stream.example.com/other"))
        let details = StationDetails(logoURL: URL(string: "https://example.com/logo.png"), countryCode: "US", tags: ["jazz"], codec: "MP3", bitrate: 128)
        let store = StationDetailsStore(fileURL: file)
        #expect(store.entry(for: stream) == nil)
        #expect(store.needsLookUp(stream))
        store.set(details, for: stream)
        store.set(nil, for: other)

        let reopened = StationDetailsStore(fileURL: file)
        #expect(reopened.details(for: stream) == details)
        #expect(reopened.entry(for: other) == .notListed)
        #expect(!reopened.needsLookUp(stream))
        #expect(!reopened.needsLookUp(other))
    }

    @Test func logosFromTheOldStoreCarryOverAndAreLookedUpOnceMore() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Details-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = #"{"https://stream.example.com/waves":"https://example.com/logo.png","https://stream.example.com/none":""}"#
        try Data(old.utf8).write(to: folder.appending(path: StationDetailsStore.oldLogosFileName))
        let store = StationDetailsStore(fileURL: folder.appending(path: StationDetailsStore.fileName))
        let waves = try #require(URL(string: "https://stream.example.com/waves"))
        #expect(store.details(for: waves)?.logoURL?.absoluteString == "https://example.com/logo.png")
        #expect(store.needsLookUp(waves))
        #expect(store.needsLookUp(try #require(URL(string: "https://stream.example.com/none"))))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: StationDetailsStore.oldLogosFileName).path(percentEncoded: false)))
    }

    @Test func firstSeenIsRecordedOnce() {
        let store = StationDetailsStore(fileURL: nil)
        let monday = Date(timeIntervalSince1970: 1_000_000)
        store.noteSeen(["rs-1"], at: monday)
        store.noteSeen(["rs-1", "rs-2"], at: monday.addingTimeInterval(86_400))
        #expect(store.firstSeen("rs-1") == monday)
        #expect(store.firstSeen("rs-2") == monday.addingTimeInterval(86_400))
        #expect(store.firstSeen("rs-3") == nil)
    }

    @Test func radioBrowserIsAskedByStreamAddress() async throws {
        let servers = #"[{"name":"one.api.example.test"}]"#
        let found = #"[{"stationuuid":"u-1","name":"A","url":"https://stream.example.com/waves","favicon":"","countrycode":"GB","bitrate":192,"codec":"AAC","tags":"news"},{"stationuuid":"u-2","name":"B","url":"https://stream.example.com/waves","favicon":"http://example.com/logo.png","countrycode":"","bitrate":0,"tags":""}]"#
        let transport = FakeTransport(.json(servers), .json(found))
        let client = RadioBrowserClient(transport: transport, directory: URL(string: "https://all.api.example.test")!, shuffle: { $0 })
        let details = try await client.details(forStream: URL(string: "http://radio.example.org:8000/;")!)
        // The listing with a usable logo (over https), filled in from the other.
        #expect(details?.logoURL?.absoluteString == "https://example.com/logo.png")
        #expect(details?.countryCode == "GB")
        #expect(details?.bitrate == 192)
        #expect(details?.tags == ["news"])
        let url = try #require(await transport.requests.last?.url)
        #expect(url.path() == "/json/stations/byurl")
        #expect(url.queryParameters["url"] == "http://radio.example.org:8000/;")
    }
}

@MainActor
struct StationDetailsLookupTests {
    private actor Asked {
        var streams: [URL] = []
        func add(_ url: URL) { streams.append(url) }
    }

    private static let waves = RadioStation(id: "rs-1", name: "Night Waves", streamURL: URL(string: "https://stream.example.com/waves")!)
    private static let bop = RadioStation(id: "rs-2", name: "Bop", streamURL: URL(string: "https://stream.example.com/bop")!)
    nonisolated private static let logo = URL(string: "https://example.com/waves.png")!
    nonisolated private static let wavesDetails = StationDetails(logoURL: logo, countryCode: "US", tags: ["jazz"], codec: "MP3", bitrate: 128)

    private func model(
        stations: [RadioStation], details: StationDetailsStore = StationDetailsStore(fileURL: nil), asked: Asked,
        now: @escaping @Sendable () -> Date = { .now },
        answer: @escaping @Sendable (URL) throws -> StationDetails? = { $0.lastPathComponent == "waves" ? StationDetailsLookupTests.wavesDetails : nil }
    ) -> RadioStationsModel {
        RadioStationsModel(sources: .init(
            stations: { stations },
            isAdmin: { false },
            create: { _ in }, update: { _, _ in }, delete: { _ in },
            details: { stream in
                await asked.add(stream)
                return try answer(stream)
            }
        ), phone: PhoneStationStore(fileURL: nil), details: details, now: now)
    }

    @Test func missingDetailsAreLookedUpOnceAndShown() async {
        let asked = Asked()
        let store = StationDetailsStore(fileURL: nil)
        let radio = model(stations: [Self.waves, Self.bop], details: store, asked: asked)
        radio.findsDetailsOnline = true
        await radio.load()
        #expect(radio.stations.allSatisfy { $0.logoURL == nil && $0.details == nil })
        await radio.findMissingDetails()
        let waves = radio.stations.first { $0.id == "rs-1" }
        #expect(waves?.logoURL == Self.logo)
        #expect(waves?.details?.countryCode == "US")
        #expect(radio.stations.first { $0.id == "rs-2" }?.details == nil)

        // Next time: known, listed or not, so nothing is asked.
        let again = model(stations: [Self.waves, Self.bop], details: store, asked: asked)
        again.findsDetailsOnline = true
        await again.load()
        #expect(again.stations.first { $0.id == "rs-1" }?.details == Self.wavesDetails)
        await again.findMissingDetails()
        #expect(await asked.streams.count == 2)
    }

    @Test func nothingIsLookedUpWhileFindingOnlineIsOff() async {
        let asked = Asked()
        let radio = model(stations: [Self.waves], asked: asked)
        await radio.load()
        await radio.findMissingDetails()
        #expect(await asked.streams.isEmpty)
    }

    @Test func aFailedLookupIsTriedAgain() async {
        let store = StationDetailsStore(fileURL: nil)
        let radio = model(stations: [Self.waves], details: store, asked: Asked(), answer: { _ in throw URLError(.timedOut) })
        radio.findsDetailsOnline = true
        await radio.load()
        await radio.findMissingDetails()
        #expect(store.needsLookUp(Self.waves.streamURL))
    }

    @Test func aStationAddedFromFindStationsKeepsItsDetails() async throws {
        let radio = model(stations: [], asked: Asked())
        await radio.load()
        try await radio.add(RadioStationDraft(name: "Aria", streamURL: "https://aria.example.org/live"), details: Self.wavesDetails)
        #expect(radio.phoneStations.first?.logoURL == Self.logo)
        #expect(radio.phoneStations.first?.details == Self.wavesDetails)
        #expect(radio.phoneStations.first?.coverArtID == StationLogo.coverArtID(for: Self.logo))
    }

    @Test func stationsAreDatedWhenFirstSeen() async throws {
        let monday = Date(timeIntervalSince1970: 1_000_000)
        let radio = model(stations: [Self.waves], asked: Asked(), now: { monday })
        await radio.load()
        #expect(radio.stations.first?.firstSeen == monday)
        try await radio.add(RadioStationDraft(name: "Aria", streamURL: "https://aria.example.org/live"))
        #expect(radio.phoneStations.first?.firstSeen == monday)
    }
}
