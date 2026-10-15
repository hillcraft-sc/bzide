import Foundation
import Testing
@testable import NavidromeCore

/// Adding, editing and deleting stations on the server.
struct RadioStationRequestTests {
    private let station = RadioStationDraft.Valid(
        name: "Night Waves",
        streamURL: URL(string: "http://radio.example.org:8000/live")!,
        homePageURL: URL(string: "https://example.com/nightwaves")!
    )

    private func sentURL(_ call: (SubsonicClient) async throws -> Void) async throws -> URL {
        let transport = FakeTransport(.json(TestServer.ok))
        try await call(TestServer.client(transport))
        return try #require(await transport.requests.first?.url)
    }

    @Test func createSendsTheStation() async throws {
        let url = try await sentURL { try await $0.createRadioStation(station) }
        #expect(url.path() == "/rest/createInternetRadioStation")
        #expect(url.queryParameters["name"] == "Night Waves")
        #expect(url.queryParameters["streamUrl"] == "http://radio.example.org:8000/live")
        #expect(url.queryParameters["homepageUrl"] == "https://example.com/nightwaves")
    }

    @Test func noHomepageIsLeftOut() async throws {
        var plain = station
        plain.homePageURL = nil
        let url = try await sentURL { try await $0.createRadioStation(plain) }
        #expect(url.queryParameters["homepageUrl"] == nil)
    }

    @Test func updateAndDeleteNameTheStation() async throws {
        let update = try await sentURL { try await $0.updateRadioStation(id: "rs-1", station) }
        #expect(update.path() == "/rest/updateInternetRadioStation")
        #expect(update.queryParameters["id"] == "rs-1")
        #expect(update.queryParameters["streamUrl"] == "http://radio.example.org:8000/live")

        let delete = try await sentURL { try await $0.deleteRadioStation(id: "rs-1") }
        #expect(delete.path() == "/rest/deleteInternetRadioStation")
        #expect(delete.queryParameters["id"] == "rs-1")
    }

    @Test func adminRoleComesFromTheUser() async throws {
        let admin = #"{"subsonic-response":{"status":"ok","version":"1.16.1","user":{"username":"listener","adminRole":true}}}"#
        let transport = FakeTransport(.json(admin))
        #expect(try await TestServer.client(transport).isAdmin(username: "listener"))
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path() == "/rest/getUser")
        #expect(url.queryParameters["username"] == "listener")

        let notSaid = #"{"subsonic-response":{"status":"ok","version":"1.16.1","user":{"username":"listener"}}}"#
        #expect(try await TestServer.client(FakeTransport(.json(notSaid))).isAdmin(username: "listener") == false)
    }
}

struct RadioStationDraftTests {
    @Test func aBlankNameBecomesTheHost() throws {
        let valid = try RadioStationDraft(name: "  ", streamURL: " http://radio.example.org:8000/live ").validated().get()
        #expect(valid.name == "radio.example.org")
        #expect(valid.streamURL.absoluteString == "http://radio.example.org:8000/live")
        #expect(valid.homePageURL == nil)
    }

    @Test func addressesMustBeWebAddresses() {
        #expect(RadioStationDraft(name: "A").validated() == .failure(.missingStream))
        #expect(RadioStationDraft(name: "A", streamURL: "radio.example.org/live").validated() == .failure(.invalidStream))
        #expect(RadioStationDraft(name: "A", streamURL: "ftp://example.org/live").validated() == .failure(.invalidStream))
        #expect(RadioStationDraft(name: "A", streamURL: "https://example.org/live", homePageURL: "example.org").validated() == .failure(.invalidHomePage))
    }

    @Test func editingStartsFromTheStation() {
        let station = RadioStation(id: "rs-1", name: "Night Waves", streamURL: URL(string: "https://example.com/a.pls")!)
        #expect(RadioStationDraft(station) == RadioStationDraft(name: "Night Waves", streamURL: "https://example.com/a.pls", homePageURL: ""))
    }
}

@MainActor
struct RadioStationsModelTests {
    /// A fake server's stations, changed by the model's calls.
    private actor FakeServer {
        var stations: [RadioStation]
        var calls: [String] = []
        let isAdmin: Result<Bool, SubsonicError>
        let failure: SubsonicError?

        init(stations: [RadioStation], isAdmin: Result<Bool, SubsonicError> = .success(true), failure: SubsonicError? = nil) {
            self.stations = stations
            self.isAdmin = isAdmin
            self.failure = failure
        }

        func list() -> [RadioStation] { stations }
        func admin() throws(SubsonicError) -> Bool { try isAdmin.get() }

        func create(_ station: RadioStationDraft.Valid) throws(SubsonicError) {
            calls.append("create")
            if let failure { throw failure }
            stations.append(RadioStation(id: "rs-\(stations.count + 1)", name: station.name, streamURL: station.streamURL))
        }

        func update(_ id: String, _ station: RadioStationDraft.Valid) throws(SubsonicError) {
            calls.append("update")
            if let failure { throw failure }
            stations = stations.map { $0.id == id ? RadioStation(id: id, name: station.name, streamURL: station.streamURL) : $0 }
        }

        func delete(_ id: String) throws(SubsonicError) {
            calls.append("delete")
            if let failure { throw failure }
            stations.removeAll { $0.id == id }
        }
    }

    private static let waves = RadioStation(id: "rs-1", name: "Night Waves", streamURL: URL(string: "https://example.com/waves")!)
    private static let bop = RadioStation(id: "rs-2", name: "bebop", streamURL: URL(string: "https://example.com/bop")!)

    private func model(_ server: FakeServer) -> RadioStationsModel {
        RadioStationsModel(sources: .init(
            stations: { await server.list() },
            isAdmin: { () async throws(SubsonicError) in try await server.admin() },
            create: { station async throws(SubsonicError) in try await server.create(station) },
            update: { id, station async throws(SubsonicError) in try await server.update(id, station) },
            delete: { id async throws(SubsonicError) in try await server.delete(id) }
        ))
    }

    @Test func stationsAreSortedByName() async {
        let stations = model(FakeServer(stations: [Self.waves, Self.bop]))
        await stations.load()
        #expect(stations.stations.map(\.name) == ["bebop", "Night Waves"])
    }

    @Test func onlyAdminsMayEdit() async {
        let admin = model(FakeServer(stations: []))
        await admin.load()
        #expect(admin.canEdit)

        let listener = model(FakeServer(stations: [], isAdmin: .success(false)))
        await listener.load()
        #expect(!listener.canEdit)

        // Not known: not offered.
        let unknown = model(FakeServer(stations: [], isAdmin: .failure(.httpStatus(500))))
        await unknown.load()
        #expect(!unknown.canEdit)
    }

    @Test func addingSavesOnTheServerAndShowsIt() async throws {
        let server = FakeServer(stations: [Self.waves])
        let stations = model(server)
        await stations.load()
        try await stations.add(RadioStationDraft(name: "Aria", streamURL: "http://aria.example.org/live"))
        #expect(stations.stations.map(\.name) == ["Aria", "Night Waves"])
    }

    @Test func editingReplacesTheStation() async throws {
        let stations = model(FakeServer(stations: [Self.waves]))
        await stations.load()
        try await stations.update(Self.waves, to: RadioStationDraft(name: "Night Waves FM", streamURL: "https://example.com/waves"))
        #expect(stations.stations.map(\.name) == ["Night Waves FM"])
        #expect(stations.stations.map(\.id) == ["rs-1"])
    }

    @Test func deletingRemovesIt() async throws {
        let stations = model(FakeServer(stations: [Self.waves, Self.bop]))
        await stations.load()
        try await stations.delete(Self.bop)
        #expect(stations.stations.map(\.id) == ["rs-1"])
    }

    @Test func anInvalidStationIsNeverSent() async {
        let server = FakeServer(stations: [])
        let stations = model(server)
        await stations.load()
        await #expect(throws: RadioStationsModel.ChangeError.invalid(.invalidStream)) {
            try await stations.add(RadioStationDraft(name: "Aria", streamURL: "aria.example.org"))
        }
        #expect(await server.calls.isEmpty)
    }

    @Test func aRefusalFromTheServerIsExplained() async {
        let stations = model(FakeServer(stations: [Self.waves], failure: .server(code: 50, message: "User not authorized")))
        await stations.load()
        await #expect(throws: RadioStationsModel.ChangeError.server("Only an admin can change the server's radio stations.")) {
            try await stations.delete(Self.waves)
        }
        // Still listed: nothing changed on the server.
        #expect(stations.stations.map(\.id) == ["rs-1"])
    }
}
