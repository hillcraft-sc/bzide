import Foundation
import Testing
@testable import NavidromeCore

/// Hand-written Radio Browser replies; all stations and addresses are invented.
private enum Sample {
    static let servers = #"[{"ip":"192.0.2.1","name":"one.api.example.test"},{"ip":"2001:db8::1","name":"one.api.example.test"},{"ip":"192.0.2.2","name":"two.api.example.test"}]"#

    static func station(
        _ uuid: String, name: String = "Night Waves", url: String = "https://example.com/waves.pls",
        resolved: String = "https://stream.example.com/waves", codec: String = "MP3", bitrate: String = "128",
        tags: String = "jazz,smooth jazz, lounge,ambient", country: String = "us"
    ) -> String {
        #"{"stationuuid":"\#(uuid)","name":"\#(name)","url":"\#(url)","url_resolved":"\#(resolved)","homepage":"https://example.com","favicon":"https://example.com/logo.png","tags":"\#(tags)","countrycode":"\#(country)","codec":"\#(codec)","bitrate":\#(bitrate),"hls":0,"lastcheckok":1}"#
    }

    static func list(_ stations: String...) -> String { "[" + stations.joined(separator: ",") + "]" }
}

struct RadioBrowserStationTests {
    private func decode(_ json: String) throws -> [RadioBrowserStation] {
        try JSONDecoder().decode(LossyList<RadioBrowserStation>.self, from: Data(json.utf8)).items
    }

    @Test func decodesAStation() throws {
        let station = try #require(try decode(Sample.list(Sample.station("u-1"))).first)
        #expect(station.id == "u-1")
        #expect(station.name == "Night Waves")
        // The direct stream, not the playlist file.
        #expect(station.streamURL.absoluteString == "https://stream.example.com/waves")
        #expect(station.homePageURL?.absoluteString == "https://example.com")
        #expect(station.faviconURL?.absoluteString == "https://example.com/logo.png")
        #expect(station.tags == ["jazz", "smooth jazz", "lounge", "ambient"])
        #expect(station.countryCode == "US")
        #expect(station.summary == "US · MP3 128 kbps · jazz, smooth jazz, lounge")
    }

    @Test func messyStationsKeepWhatTheyCan() throws {
        let stations = try decode(Sample.list(
            // No resolved stream: the address as entered.
            Sample.station("u-1", resolved: ""),
            // Nothing playable: dropped, not the whole list.
            Sample.station("u-2", url: "", resolved: ""),
            // Unknown codec, no bitrate, no tags, no name.
            Sample.station("u-3", name: " ", codec: "UNKNOWN", bitrate: "0", tags: "", country: ""),
            #"{"name":"No id","url":"https://example.com/x"}"#
        ))
        #expect(stations.map(\.id) == ["u-1", "u-3"])
        #expect(stations[0].streamURL.absoluteString == "https://example.com/waves.pls")
        #expect(stations[1].name == "stream.example.com")
        #expect(stations[1].summary.isEmpty)
    }

    @Test func playsAndSavesAsARadioStation() {
        let station = RadioBrowserStation(id: "u-1", name: "Night Waves", streamURL: URL(string: "https://stream.example.com/waves")!, homePageURL: URL(string: "https://example.com")!)
        #expect(station.radioStation.id == "radiobrowser:u-1")
        #expect(station.radioStation.songID == "radio:radiobrowser:u-1")
        #expect(station.draft == RadioStationDraft(name: "Night Waves", streamURL: "https://stream.example.com/waves", homePageURL: "https://example.com"))
    }
}

struct RadioBrowserClientTests {
    /// Keeps the servers in the order listed.
    private func client(_ transport: FakeTransport) -> RadioBrowserClient {
        RadioBrowserClient(transport: transport, directory: URL(string: "https://all.api.example.test")!, shuffle: { $0 })
    }

    @Test func searchesAServerFromTheDirectory() async throws {
        let transport = FakeTransport(.json(Sample.servers), .json(Sample.list(Sample.station("u-1"))))
        let found = try await client(transport).search("jazz", by: .tag)
        #expect(found.map(\.id) == ["u-1"])

        let requests = await transport.requests
        #expect(requests.map { $0.url?.host() } == ["all.api.example.test", "one.api.example.test"])
        #expect(requests[0].url?.path() == "/json/servers")
        let search = try #require(requests[1].url)
        #expect(search.path() == "/json/stations/search")
        #expect(search.queryParameters["tag"] == "jazz")
        #expect(search.queryParameters["order"] == "clickcount")
        #expect(search.queryParameters["reverse"] == "true")
        #expect(search.queryParameters["hidebroken"] == "true")
        #expect(search.queryParameters["limit"] == "50")
        // It says who's asking, and sends nothing about the user.
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent") == RadioBrowserClient.userAgent })
    }

    @Test func aFailingServerIsSkippedAndTheWorkingOneRemembered() async throws {
        let transport = FakeTransport(
            .json(Sample.servers),
            .failure(.timedOut),
            .json(Sample.list(Sample.station("u-1"))),
            .json(Sample.list(Sample.station("u-2")))
        )
        let radioBrowser = client(transport)
        #expect(try await radioBrowser.search("waves", by: .name).map(\.id) == ["u-1"])
        #expect(try await radioBrowser.search("waves", by: .name).map(\.id) == ["u-2"])
        let hosts = await transport.requests.map { $0.url?.host() }
        // The server list is fetched once; the second search goes straight to the one that worked.
        #expect(hosts == ["all.api.example.test", "one.api.example.test", "two.api.example.test", "two.api.example.test"])
    }

    @Test func aServerErrorMovesOnToo() async throws {
        let transport = FakeTransport(.json(Sample.servers), .json("busy", status: 503), .json(Sample.list(Sample.station("u-1"))))
        #expect(try await client(transport).popular().map(\.id) == ["u-1"])
    }

    @Test func withoutTheServerListTheDirectoryIsAsked() async throws {
        let transport = FakeTransport(.failure(.cannotFindHost), .json(Sample.list(Sample.station("u-1"))))
        #expect(try await client(transport).popular().map(\.id) == ["u-1"])
        let urls = await transport.requests.compactMap(\.url)
        #expect(urls.map { $0.host() } == ["all.api.example.test", "all.api.example.test"])
        #expect(urls[1].path() == "/json/stations/topclick/50")
    }

    @Test func whenEveryServerFailsTheErrorSurfaces() async {
        let transport = FakeTransport(.json(Sample.servers), .failure(.notConnectedToInternet), .failure(.notConnectedToInternet))
        await #expect(throws: URLError.self) { try await client(transport).search("waves", by: .name) }
    }

    @Test func theSameStreamIsListedOnce() async throws {
        let transport = FakeTransport(.json(Sample.servers), .json(Sample.list(Sample.station("u-1"), Sample.station("u-2"), Sample.station("u-3", resolved: "https://stream.example.com/other"))))
        #expect(try await client(transport).search("waves", by: .name).map(\.id) == ["u-1", "u-3"])
    }

    @Test func aPlayIsCounted() async throws {
        let transport = FakeTransport(.json(Sample.servers), .json(#"{"ok":"true","message":"retrieved station url"}"#))
        try await client(transport).countPlay(of: "u-1")
        #expect(await transport.requests.last?.url?.path() == "/json/url/u-1")
    }
}

@MainActor
struct StationSearchModelTests {
    private actor Calls {
        var searches: [String] = []
        var popular = 0
        var counted: [String] = []
        func search(_ text: String) { searches.append(text) }
        func countPopular() { popular += 1 }
        func count(_ id: String) { counted.append(id) }
    }

    nonisolated private static func station(_ id: String) -> RadioBrowserStation {
        RadioBrowserStation(id: id, name: id, streamURL: URL(string: "https://stream.example.com/\(id)")!)
    }

    private func model(_ calls: Calls, fails: Bool = false) -> StationSearchModel {
        StationSearchModel(sources: .init(
            search: { text, field in
                await calls.search("\(field.rawValue):\(text)")
                if fails { throw URLError(.notConnectedToInternet) }
                return [Self.station(text)]
            },
            popular: {
                await calls.countPopular()
                return [Self.station("popular")]
            },
            countPlay: { id in await calls.count(id) }
        ), pause: .zero)
    }

    @Test func showsPopularStationsUntilSomethingIsTyped() async {
        let calls = Calls()
        let search = model(calls)
        await search.update()
        #expect(search.state == .loaded([Self.station("popular")]))
        #expect(search.isShowingPopular)

        search.text = " jazz "
        search.field = .tag
        await search.update()
        #expect(search.state == .loaded([Self.station("jazz")]))
        #expect(await calls.searches == ["tag:jazz"])

        // Cleared: the popular list comes back without asking again.
        search.text = ""
        await search.update()
        #expect(search.state == .loaded([Self.station("popular")]))
        #expect(await calls.popular == 1)
    }

    @Test func typingWaitsForAPause() async {
        let calls = Calls()
        let search = StationSearchModel(sources: .init(
            search: { text, _ in await calls.search(text); return [] },
            popular: { [] },
            countPlay: { _ in }
        ), pause: .seconds(30))
        search.text = "ja"
        let first = Task { await search.update() }
        await Task.yield()
        search.text = "jazz"
        let second = Task { await search.update() }
        first.cancel()
        second.cancel()
        await first.value
        await second.value
        // Both were superseded or canceled during the pause: nothing was sent.
        #expect(await calls.searches.isEmpty)
    }

    @Test func aFailureIsExplained() async {
        let search = model(Calls(), fails: true)
        search.text = "jazz"
        await search.update()
        #expect(search.state == .failed("Couldn't reach Radio Browser. Check your connection and try again."))
    }

    @Test func playingCountsThePlay() async {
        let calls = Calls()
        model(calls).played(Self.station("u-1"))
        while await calls.counted.isEmpty { await Task.yield() }
        #expect(await calls.counted == ["u-1"])
    }

    @Test func findingStationsIsOffByDefault() throws {
        #expect(StreamingSettings().findStationsOnline == false)
        let older = try JSONDecoder().decode(StreamingSettings.self, from: Data(#"{"wifiQuality":0,"cellularQuality":192}"#.utf8))
        #expect(older.findStationsOnline == false)
    }
}
