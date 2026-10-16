import Foundation
import Testing
@testable import NavidromeCore

/// Hand-written MusicBrainz replies, shaped like the real ones; ids invented.
private enum Sample {
    static func recording(_ id: String, title: String = "Karma Police", artist: String = "Radiohead", score: Int = 100, length: Int = 262_000, releases: [String]) -> String {
        #"{"id":"\#(id)","score":\#(score),"title":"\#(title)","length":\#(length),"artist-credit":[{"name":"\#(artist)"}],"releases":[\#(releases.joined(separator: ","))]}"#
    }

    static func release(_ title: String, date: String, status: String = "Official", type: String = "Album", secondary: [String] = [], group: String = "rg-1") -> String {
        let secondaryJSON = secondary.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"title":"\#(title)","date":"\#(date)","status":"\#(status)","release-group":{"id":"\#(group)","primary-type":"\#(type)","secondary-types":[\#(secondaryJSON)]}}"#
    }

    static func search(_ recordings: String...) -> String {
        #"{"count":\#(recordings.count),"recordings":[\#(recordings.joined(separator: ","))]}"#
    }

    static let covers = #"{"images":[{"front":false,"image":"https://archive.example.org/back.jpg"},{"front":true,"image":"http://archive.example.org/front.jpg","thumbnails":{"500":"http://archive.example.org/front-500.jpg","250":"x"}}]}"#
}

struct MusicBrainzClientTests {
    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_000)
        var slept: [TimeInterval] = []
    }

    private func client(_ transport: FakeTransport, clock: Clock = Clock(), contact: String = "https://example.test") -> MusicBrainzClient {
        MusicBrainzClient(contact: contact, transport: transport, now: { clock.now }, sleep: { seconds in
            clock.slept.append(seconds)
            clock.now = clock.now.addingTimeInterval(seconds)
        })
    }

    private static let song = OnAirSong(artist: "Radiohead", title: "Karma Police")

    @Test func theEarliestStudioAlbumWinsWithItsCover() async throws {
        let studio = Sample.search(
            Sample.recording("rec-live", releases: [Sample.release("Live at Somewhere", date: "2001", secondary: ["Live"], group: "rg-live")]),
            Sample.recording("rec-1", releases: [Sample.release("Best Of", date: "2008", secondary: ["Compilation"], group: "rg-best"), Sample.release("OK Computer", date: "1997-05-21", group: "rg-ok")])
        )
        let transport = FakeTransport(.json(studio), .json(Sample.covers))
        let details = try await client(transport).details(for: Self.song)
        #expect(details?.album == "OK Computer")
        #expect(details?.year == 1997)
        #expect(details?.length == 262)
        #expect(details?.recordingID == "rec-1")
        #expect(details?.releaseGroupID == "rg-ok")
        // The front cover, over https.
        #expect(details?.coverURL?.absoluteString == "https://archive.example.org/front-500.jpg")

        let requests = await transport.requests
        let search = try #require(requests.first?.url)
        #expect(search.path() == "/ws/2/recording")
        #expect(search.queryParameters["query"] == #"recording:"Karma Police" AND artist:"Radiohead" AND status:official AND primarytype:album"#)
        #expect(search.queryParameters["fmt"] == "json")
        #expect(requests.first?.value(forHTTPHeaderField: "User-Agent") == "Bzide/1.0 ( https://example.test )")
        #expect(requests.last?.url?.absoluteString == "https://coverartarchive.org/release-group/rg-ok")
    }

    @Test func withoutAStudioAlbumTheBestMatchAnywhere() async throws {
        let none = Sample.search()
        let any = Sample.search(
            Sample.recording("rec-low", score: 85, releases: [Sample.release("Single", date: "2020", type: "Single", group: "rg-a")]),
            Sample.recording("rec-top", score: 100, releases: [Sample.release("Bootleg", date: "1999", status: "Bootleg", group: "rg-b"), Sample.release("EP", date: "2001", type: "EP", group: "rg-c")])
        )
        let clock = Clock()
        let transport = FakeTransport(.json(none), .json(any), .json("{}", status: 404))
        let details = try await client(transport, clock: clock).details(for: Self.song)
        #expect(details?.recordingID == "rec-top")
        // Its official release, not the bootleg.
        #expect(details?.album == "EP")
        #expect(details?.coverURL == nil)
        let second = try #require(await transport.requests.dropFirst().first?.url)
        #expect(second.queryParameters["query"] == #"recording:"Karma Police" AND artist:"Radiohead""#)
        // The second MusicBrainz request waited out the second.
        #expect(clock.slept == [MusicBrainzClient.minimumGap])
    }

    @Test func otherSongsAndArtistsDontCount() async throws {
        let wrong = Sample.search(
            Sample.recording("rec-a", title: "Creep", releases: [Sample.release("Pablo Honey", date: "1993")]),
            Sample.recording("rec-b", artist: "Someone Else", releases: [Sample.release("Covers", date: "2010")]),
            Sample.recording("rec-c", score: 40, releases: [Sample.release("OK Computer", date: "1997")])
        )
        let transport = FakeTransport(.json(wrong), .json(wrong))
        #expect(try await client(transport).details(for: Self.song) == nil)
    }

    @Test func whenBusyItWaitsAndAsksAgain() async throws {
        let found = Sample.search(Sample.recording("rec-1", releases: [Sample.release("OK Computer", date: "1997", group: "rg-ok")]))
        let clock = Clock()
        let transport = FakeTransport(.json("busy", status: 503), .json(found), .json("{}", status: 404))
        let details = try await client(transport, clock: clock).details(for: Self.song)
        #expect(details?.album == "OK Computer")
        #expect(clock.slept.first == MusicBrainzClient.busyWait)
        // Busy every time: it gives up after the retries.
        let busy = FakeTransport(.json("busy", status: 503), .json("busy", status: 503), .json("busy", status: 503))
        await #expect(throws: MusicBrainzClient.Failure.badResponse(503)) { try await client(busy).details(for: Self.song) }
        #expect(await busy.requests.count == 1 + MusicBrainzClient.busyRetries)
    }

    @Test func quotesAreEscapedAndAContactIsRequired() async {
        #expect(MusicBrainzClient.escaped(#"Say "Hi" \ Bye"#) == #"Say \"Hi\" \\ Bye"#)
        let transport = FakeTransport()
        await #expect(throws: MusicBrainzClient.Failure.noContact) { try await client(transport, contact: " ").details(for: Self.song) }
        #expect(await transport.requests.isEmpty)
    }
}

@MainActor
struct OnAirInfoModelTests {
    private actor Asked {
        var songs: [OnAirSong] = []
        var failing = false
        func add(_ song: OnAirSong) { songs.append(song) }
        func setFailing(_ value: Bool) { failing = value }
    }

    private static let karma = OnAirSong(artist: "Radiohead", title: "Karma Police")

    private func model(_ asked: Asked) -> OnAirInfoModel {
        OnAirInfoModel { song in
            await asked.add(song)
            if await asked.failing { throw URLError(.notConnectedToInternet) }
            return OnAirDetails(title: song.title, artist: song.artist, album: "OK Computer", recordingID: "rec-1")
        }
    }

    @Test func lookedUpOnceAndOnlyWhenOn() async {
        let asked = Asked()
        let info = model(asked)
        await info.update(Self.karma, enabled: false)
        #expect(info.details == nil)
        #expect(await asked.songs.isEmpty)
        await info.update(Self.karma, enabled: true)
        #expect(info.details?.album == "OK Computer")
        await info.update(nil, enabled: true)
        #expect(info.details == nil)
        await info.update(Self.karma, enabled: true)
        #expect(info.details?.album == "OK Computer")
        #expect(await asked.songs.count == 1)
    }

    @Test func aFailureIsAskedAgain() async {
        let asked = Asked()
        let info = model(asked)
        await asked.setFailing(true)
        await info.update(Self.karma, enabled: true)
        #expect(info.details == nil)
        await asked.setFailing(false)
        await info.update(Self.karma, enabled: true)
        #expect(info.details != nil)
        #expect(await asked.songs.count == 2)
    }

    @Test func songInfoShowsWhatsKnown() {
        let details = OnAirDetails(title: "Karma Police", artist: "Radiohead", album: "OK Computer", year: 1997, length: 262, recordingID: "rec-1")
        let rows = details.sections.flatMap(\.rows)
        #expect(rows.map(\.label) == ["Title", "Artist", "Album", "Year", "Length", "Page"])
        #expect(rows.first { $0.label == "Length" }?.value == "4:22")
        #expect(rows.last?.value == "https://musicbrainz.org/recording/rec-1")
        #expect(Self.karma.sections.flatMap(\.rows).map(\.value) == ["Karma Police", "Radiohead"])
        #expect(StreamingSettings().lookUpSongsOnline == false)
    }
}
