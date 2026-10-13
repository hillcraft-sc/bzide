import Foundation
import Testing
@testable import NavidromeCore

struct LRCLIBClientTests {
    private static let record = #"{"id":1,"trackName":"Morning Static","artistName":"The Placeholders","albumName":"Placeholder Album","duration":200,"instrumental":false,"plainLyrics":"Wake up","syncedLyrics":"[00:12.50] Wake up"}"#

    @Test func findsAnExactMatch() async throws {
        let transport = FakeTransport(.json(Self.record))
        let result = try await LRCLIBClient(transport: transport).lyrics(title: "Morning Static", artist: "The Placeholders", album: "Placeholder Album", duration: 200)
        #expect(result?.synced == "[00:12.50] Wake up")
        #expect(result?.plain == "Wake up")
        let request = try #require(await transport.requests.first)
        let url = try #require(request.url)
        #expect(url.host() == "lrclib.net")
        #expect(url.path == "/api/get")
        #expect(url.queryParameters == [
            "track_name": "Morning Static", "artist_name": "The Placeholders",
            "album_name": "Placeholder Album", "duration": "200",
        ])
        #expect(request.value(forHTTPHeaderField: "User-Agent") == LRCLIBClient.userAgent)
    }

    @Test func withoutAnExactMatchItSearchesAndPicksSyncedLyricsOfTheSameLength() async throws {
        let results = """
        [{"duration":300,"syncedLyrics":"[00:01.00] a live version"},
         {"duration":201,"plainLyrics":"plain only"},
         {"duration":199,"syncedLyrics":"[00:01.00] the right one"}]
        """
        let transport = FakeTransport(.json("{}", status: 404), .json(results))
        let result = try await LRCLIBClient(transport: transport).lyrics(title: "Morning Static", artist: "The Placeholders", album: nil, duration: 200)
        #expect(result?.synced == "[00:01.00] the right one")
        let paths = await transport.requests.compactMap { $0.url?.path }
        #expect(paths == ["/api/get", "/api/search"])
    }

    @Test func withoutAnArtistItOnlySearches() async throws {
        let transport = FakeTransport(.json("[]"))
        let result = try await LRCLIBClient(transport: transport).lyrics(title: "Untitled", artist: nil, album: nil, duration: nil)
        #expect(result == nil)
        let paths = await transport.requests.compactMap { $0.url?.path }
        #expect(paths == ["/api/search"])
    }

    @Test func notFoundAnywhereIsNil() async throws {
        let transport = FakeTransport(.json("{}", status: 404), .json("[]"))
        #expect(try await LRCLIBClient(transport: transport).lyrics(title: "Rare", artist: "Nobody", album: nil, duration: 100) == nil)
    }

    @Test func aServerErrorThrows() async {
        let transport = FakeTransport(.json("oops", status: 500))
        await #expect(throws: (any Error).self) {
            try await LRCLIBClient(transport: transport).lyrics(title: "Song", artist: "Band", album: nil, duration: nil)
        }
    }

    @Test func instrumentalIsReported() async throws {
        let transport = FakeTransport(.json(#"{"duration":200,"instrumental":true,"plainLyrics":null,"syncedLyrics":null}"#))
        let result = try await LRCLIBClient(transport: transport).lyrics(title: "Interlude", artist: "Band", album: nil, duration: 200)
        #expect(result?.isInstrumental == true)
        #expect(result?.synced == nil)
    }
}
