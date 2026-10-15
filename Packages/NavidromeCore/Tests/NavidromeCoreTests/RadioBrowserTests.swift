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
        let found = try await client(transport).stations(.init(name: " waves "))
        #expect(found.map(\.id) == ["u-1"])

        let requests = await transport.requests
        #expect(requests.map { $0.url?.host() } == ["all.api.example.test", "one.api.example.test"])
        #expect(requests[0].url?.path() == "/json/servers")
        let search = try #require(requests[1].url)
        #expect(search.path() == "/json/stations/search")
        #expect(search.queryParameters["name"] == "waves")
        #expect(search.queryParameters["countrycode"] == nil)
        #expect(search.queryParameters["tag"] == nil)
        #expect(search.queryParameters["order"] == "clickcount")
        #expect(search.queryParameters["reverse"] == "true")
        #expect(search.queryParameters["hidebroken"] == "true")
        #expect(search.queryParameters["offset"] == "0")
        #expect(search.queryParameters["limit"] == "50")
        // It says who's asking, and sends nothing about the user.
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent") == RadioBrowserClient.userAgent })
    }

    @Test func filtersOrderAndPageAreSent() async throws {
        let transport = FakeTransport(.json(Sample.servers), .json("[]"))
        _ = try await client(transport).stations(.init(countryCode: "US", tag: "jazz", order: .name), offset: 100)
        let search = try #require(await transport.requests.last?.url)
        #expect(search.queryParameters["name"] == nil)
        #expect(search.queryParameters["countrycode"] == "US")
        #expect(search.queryParameters["tag"] == "jazz")
        #expect(search.queryParameters["tagExact"] == "true")
        #expect(search.queryParameters["order"] == "name")
        #expect(search.queryParameters["reverse"] == "false")
        #expect(search.queryParameters["offset"] == "100")
    }

    @Test func countriesAreCombinedAndCounted() async throws {
        let countries = #"[{"name":"The United States Of America","iso_3166_1":"US","stationcount":6000},{"name":"United States","iso_3166_1":"us","stationcount":12},{"name":"Germany","iso_3166_1":"DE","stationcount":3000},{"name":"Nowhere","iso_3166_1":"","stationcount":5},{"name":"Empty","iso_3166_1":"ZZ","stationcount":0}]"#
        let transport = FakeTransport(.json(Sample.servers), .json(countries))
        let found = try await client(transport).countries()
        #expect(found == [.init(code: "US", stationCount: 6012), .init(code: "DE", stationCount: 3000)])
        #expect(await transport.requests.last?.url?.path() == "/json/countries")
        // Named as the phone names it.
        #expect(found[0].name(in: Locale(identifier: "en_US")) == "United States")
    }

    @Test func tagsAreTheMostCommon() async throws {
        let tags = #"[{"name":"pop","stationcount":5000},{"name":" ","stationcount":40},{"name":"jazz","stationcount":2000}]"#
        let transport = FakeTransport(.json(Sample.servers), .json(tags))
        #expect(try await client(transport).tags() == [.init(name: "pop", stationCount: 5000), .init(name: "jazz", stationCount: 2000)])
        let url = try #require(await transport.requests.last?.url)
        #expect(url.path() == "/json/tags")
        #expect(url.queryParameters["order"] == "stationcount")
        #expect(url.queryParameters["reverse"] == "true")
        #expect(url.queryParameters["limit"] == "300")
    }

    @Test func aFailingServerIsSkippedAndTheWorkingOneRemembered() async throws {
        let transport = FakeTransport(
            .json(Sample.servers),
            .failure(.timedOut),
            .json(Sample.list(Sample.station("u-1"))),
            .json(Sample.list(Sample.station("u-2")))
        )
        let radioBrowser = client(transport)
        #expect(try await radioBrowser.stations(.init(name: "waves")).map(\.id) == ["u-1"])
        #expect(try await radioBrowser.stations(.init(name: "waves")).map(\.id) == ["u-2"])
        let hosts = await transport.requests.map { $0.url?.host() }
        // The server list is fetched once; the second search goes straight to the one that worked.
        #expect(hosts == ["all.api.example.test", "one.api.example.test", "two.api.example.test", "two.api.example.test"])
    }

    @Test func aServerErrorMovesOnToo() async throws {
        let transport = FakeTransport(.json(Sample.servers), .json("busy", status: 503), .json(Sample.list(Sample.station("u-1"))))
        #expect(try await client(transport).stations(.init()).map(\.id) == ["u-1"])
    }

    @Test func withoutTheServerListTheDirectoryIsAsked() async throws {
        let transport = FakeTransport(.failure(.cannotFindHost), .json(Sample.list(Sample.station("u-1"))))
        #expect(try await client(transport).stations(.init()).map(\.id) == ["u-1"])
        let urls = await transport.requests.compactMap(\.url)
        #expect(urls.map { $0.host() } == ["all.api.example.test", "all.api.example.test"])
        #expect(urls[1].path() == "/json/stations/search")
    }

    @Test func whenEveryServerFailsTheErrorSurfaces() async {
        let transport = FakeTransport(.json(Sample.servers), .failure(.notConnectedToInternet), .failure(.notConnectedToInternet))
        await #expect(throws: URLError.self) { try await client(transport).stations(.init(name: "waves")) }
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
        var queries: [(RadioBrowserClient.Query, Int)] = []
        var counted: [String] = []
        var countries = 0
        func asked(_ query: RadioBrowserClient.Query, _ offset: Int) { queries.append((query, offset)) }
        func count(_ id: String) { counted.append(id) }
        func askedCountries() { countries += 1 }
    }

    nonisolated private static func station(_ id: String) -> RadioBrowserStation {
        RadioBrowserStation(id: id, name: id, streamURL: URL(string: "https://stream.example.com/\(id)")!)
    }

    /// Answers with pages of `pageSize` from `total` stations, named by the
    /// query's name (or "s") and position.
    private func model(_ calls: Calls, total: Int = 3, pageSize: Int = 2, fails: Bool = false) -> StationSearchModel {
        StationSearchModel(sources: .init(
            stations: { query, offset in
                await calls.asked(query, offset)
                if fails { throw URLError(.notConnectedToInternet) }
                let prefix = query.name.isEmpty ? "s" : query.name
                return (offset..<min(offset + pageSize, total)).map { Self.station("\(prefix)\($0)") }
            },
            countries: {
                await calls.askedCountries()
                return [.init(code: "US", stationCount: 10)]
            },
            tags: { [.init(name: "jazz", stationCount: 5)] },
            countPlay: { id in await calls.count(id) }
        ), pause: .zero, pageSize: pageSize)
    }

    private func ids(_ model: StationSearchModel) -> [String] {
        if case .loaded(let stations) = model.state { stations.map(\.id) } else { [] }
    }

    @Test func startsWithWhatsPopular() async {
        let calls = Calls()
        let search = model(calls)
        await search.update()
        #expect(search.isShowingPopular)
        #expect(ids(search) == ["s0", "s1"])
        #expect(await calls.queries.first?.0 == RadioBrowserClient.Query())
    }

    @Test func filtersAndNameMakeOneSearch() async {
        let calls = Calls()
        let search = model(calls)
        search.query.name = "jazz"
        search.query.countryCode = "US"
        search.query.tag = "smooth jazz"
        await search.update()
        #expect(!search.isShowingPopular)
        #expect(ids(search) == ["jazz0", "jazz1"])
        let asked = await calls.queries.last
        #expect(asked?.0 == .init(name: "jazz", countryCode: "US", tag: "smooth jazz"))
        #expect(asked?.1 == 0)
    }

    @Test func morePagesFollowUntilThereAreNoMore() async {
        let calls = Calls()
        let search = model(calls, total: 5)
        await search.update()
        #expect(search.hasMore)
        await search.loadMore()
        #expect(ids(search) == ["s0", "s1", "s2", "s3"])
        await search.loadMore()
        #expect(ids(search) == ["s0", "s1", "s2", "s3", "s4"])
        // A short page: that's all.
        #expect(!search.hasMore)
        await search.loadMore()
        #expect(await calls.queries.map(\.1) == [0, 2, 4])
    }

    @Test func aNewSearchStartsFromTheFirstPage() async {
        let calls = Calls()
        let search = model(calls, total: 5)
        await search.update()
        await search.loadMore()
        search.query.order = .topRated
        await search.update()
        #expect(ids(search) == ["s0", "s1"])
        #expect(await calls.queries.last?.1 == 0)
    }

    @Test func theSameSearchIsntAskedTwice() async {
        let calls = Calls()
        let search = model(calls)
        await search.update()
        await search.update()
        #expect(await calls.queries.count == 1)
    }

    @Test func duplicateStreamsAreShownOnceButCountTowardThePage() async {
        let duplicate = Self.station("dup")
        let search = StationSearchModel(sources: .init(
            stations: { _, offset in offset == 0 ? [duplicate, duplicate] : [Self.station("next")] },
            countries: { [] }, tags: { [] }, countPlay: { _ in }
        ), pause: .zero, pageSize: 2)
        await search.update()
        #expect(ids(search) == ["dup"])
        #expect(search.hasMore)
        await search.loadMore()
        #expect(ids(search) == ["dup", "next"])
    }

    @Test func typingWaitsForAPause() async {
        let calls = Calls()
        let search = StationSearchModel(sources: .init(
            stations: { query, offset in await calls.asked(query, offset); return [] },
            countries: { [] }, tags: { [] }, countPlay: { _ in }
        ), pause: .seconds(30))
        search.query.name = "ja"
        let first = Task { await search.update() }
        await Task.yield()
        search.query.name = "jazz"
        let second = Task { await search.update() }
        first.cancel()
        second.cancel()
        await first.value
        await second.value
        // Both were superseded or canceled during the pause: nothing was sent.
        #expect(await calls.queries.isEmpty)
    }

    @Test func aFailureIsExplained() async {
        let search = model(Calls(), fails: true)
        search.query.name = "jazz"
        await search.update()
        #expect(search.state == .failed("Couldn't reach Radio Browser. Check your connection and try again."))
    }

    @Test func filterListsAreFetchedOnce() async {
        let calls = Calls()
        let search = model(calls)
        await search.loadCountries()
        await search.loadCountries()
        #expect(search.countries == .loaded([.init(code: "US", stationCount: 10)]))
        #expect(await calls.countries == 1)
        await search.loadTags()
        #expect(search.tags == .loaded([.init(name: "jazz", stationCount: 5)]))
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
