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

    @Test func theStoreRemembersLogosAndMisses() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "StationLogos-\(UUID().uuidString).json")
        let stream = try #require(URL(string: "https://stream.example.com/waves"))
        let other = try #require(URL(string: "https://stream.example.com/other"))
        let logo = try #require(URL(string: "https://example.com/logo.png"))
        let store = StationLogoStore(fileURL: file)
        #expect(store.entry(for: stream) == nil)
        store.set(.logo(logo), for: stream)
        store.set(.noLogo, for: other)

        let reopened = StationLogoStore(fileURL: file)
        #expect(reopened.entry(for: stream) == .logo(logo))
        #expect(reopened.entry(for: other) == .noLogo)
    }

    @Test func radioBrowserIsAskedByStreamAddress() async throws {
        let servers = #"[{"name":"one.api.example.test"}]"#
        let found = #"[{"stationuuid":"u-1","name":"A","url":"https://stream.example.com/waves","favicon":""},{"stationuuid":"u-2","name":"B","url":"https://stream.example.com/waves","favicon":"http://example.com/logo.png"}]"#
        let transport = FakeTransport(.json(servers), .json(found))
        let client = RadioBrowserClient(transport: transport, directory: URL(string: "https://all.api.example.test")!, shuffle: { $0 })
        let logo = try await client.logo(forStream: URL(string: "http://radio.example.org:8000/;")!)
        // The first station with a usable logo, over https.
        #expect(logo?.absoluteString == "https://example.com/logo.png")
        let url = try #require(await transport.requests.last?.url)
        #expect(url.path() == "/json/stations/byurl")
        #expect(url.queryParameters["url"] == "http://radio.example.org:8000/;")
    }
}

@MainActor
struct StationLogoLookupTests {
    private actor Asked {
        var streams: [URL] = []
        func add(_ url: URL) { streams.append(url) }
    }

    private static let waves = RadioStation(id: "rs-1", name: "Night Waves", streamURL: URL(string: "https://stream.example.com/waves")!)
    private static let bop = RadioStation(id: "rs-2", name: "Bop", streamURL: URL(string: "https://stream.example.com/bop")!)
    nonisolated private static let logo = URL(string: "https://example.com/waves.png")!

    private func model(
        stations: [RadioStation], logos: StationLogoStore = StationLogoStore(fileURL: nil), asked: Asked,
        answer: @escaping @Sendable (URL) throws -> URL? = { $0.lastPathComponent == "waves" ? StationLogoLookupTests.logo : nil }
    ) -> RadioStationsModel {
        RadioStationsModel(sources: .init(
            stations: { stations },
            isAdmin: { false },
            create: { _ in }, update: { _, _ in }, delete: { _ in },
            logo: { stream in
                await asked.add(stream)
                return try answer(stream)
            }
        ), phone: PhoneStationStore(fileURL: nil), logos: logos)
    }

    @Test func missingLogosAreLookedUpOnceAndShown() async {
        let asked = Asked()
        let logos = StationLogoStore(fileURL: nil)
        let radio = model(stations: [Self.waves, Self.bop], logos: logos, asked: asked)
        radio.findsLogosOnline = true
        await radio.load()
        #expect(radio.stations.allSatisfy { $0.logoURL == nil })
        await radio.findMissingLogos()
        #expect(radio.stations.first { $0.id == "rs-1" }?.logoURL == Self.logo)
        #expect(radio.stations.first { $0.id == "rs-2" }?.logoURL == nil)

        // Next time: known, logo or not, so nothing is asked.
        let again = model(stations: [Self.waves, Self.bop], logos: logos, asked: asked)
        again.findsLogosOnline = true
        await again.load()
        #expect(again.stations.first { $0.id == "rs-1" }?.logoURL == Self.logo)
        await again.findMissingLogos()
        #expect(await asked.streams.count == 2)
    }

    @Test func nothingIsLookedUpWhileFindingOnlineIsOff() async {
        let asked = Asked()
        let radio = model(stations: [Self.waves], asked: asked)
        await radio.load()
        await radio.findMissingLogos()
        #expect(await asked.streams.isEmpty)
    }

    @Test func aFailedLookupIsTriedAgain() async {
        let asked = Asked()
        let logos = StationLogoStore(fileURL: nil)
        let radio = model(stations: [Self.waves], logos: logos, asked: asked, answer: { _ in throw URLError(.timedOut) })
        radio.findsLogosOnline = true
        await radio.load()
        await radio.findMissingLogos()
        #expect(logos.entry(for: Self.waves.streamURL) == nil)
    }

    @Test func aStationAddedFromFindStationsKeepsItsLogo() async throws {
        let radio = model(stations: [], asked: Asked())
        await radio.load()
        try await radio.add(RadioStationDraft(name: "Aria", streamURL: "https://aria.example.org/live"), logo: Self.logo)
        #expect(radio.phoneStations.first?.logoURL == Self.logo)
        #expect(radio.phoneStations.first?.coverArtID == StationLogo.coverArtID(for: Self.logo))
    }
}
