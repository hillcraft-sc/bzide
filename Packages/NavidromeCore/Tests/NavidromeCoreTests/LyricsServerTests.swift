import Foundation
import Testing
@testable import NavidromeCore

struct LyricsServerTests {
    private static let extensions = #"{"subsonic-response":{"status":"ok","version":"1.16.1","openSubsonicExtensions":[{"name":"songLyrics","versions":[1]}]}}"#
    private static let noExtensions = #"{"subsonic-response":{"status":"ok","version":"1.16.1","openSubsonicExtensions":[]}}"#
    private let song = Song(id: "so-1", title: "Morning Static", album: "Placeholder Album", artist: "The Placeholders", duration: 200)

    @Test func readsStructuredLyrics() async throws {
        let transport = try FakeTransport(fixture: "getLyricsBySongId")
        let sets = try await TestServer.client(transport).structuredLyrics(songID: "so-1")
        #expect(sets.count == 2)
        #expect(sets[0].synced == false)
        #expect(sets[1].synced)
        #expect(sets[1].offset == -500)
        #expect(sets[1].lines.count == 4)
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path.hasSuffix("getLyricsBySongId"))
        #expect(url.queryParameters["id"] == "so-1")
    }

    @Test func syncedLyricsTakeTheOffsetAndWordTimes() async throws {
        let transport = try FakeTransport(fixture: "getLyricsBySongId")
        let sets = try await TestServer.client(transport).structuredLyrics(songID: "so-1")
        let lyrics = sets[1].lyrics(songDuration: 200, source: .server)
        #expect(lyrics.isSynced)
        #expect(lyrics.lines.map(\.start) == [12, 15.5, 19.5, 29.5])
        #expect(lyrics.lines[1].text == "Coffee going cold again")
        #expect(lyrics.lines[1].hasExactWordTimes)
        #expect(lyrics.lines[1].words.map(\.start) == [15.5, 16.1, 16.6, 17])
        #expect(lyrics.lines[2].isBreak)
        #expect(lyrics.lines[3].isBreak)
    }

    @Test func aSetWithAnUntimedLineIsPlain() async throws {
        let transport = try FakeTransport(fixture: "getLyricsBySongId-messy")
        let sets = try await TestServer.client(transport).structuredLyrics(songID: "so-1")
        #expect(sets.count == 1)
        #expect(sets[0].synced == false)
        #expect(sets[0].lines.map(\.value) == ["A line with a time", "A line without one"])
        #expect(!sets[0].lyrics(songDuration: nil, source: .server).isSynced)
    }

    @Test func readsPlainLyrics() async throws {
        let transport = try FakeTransport(fixture: "getLyrics")
        let text = try await TestServer.client(transport).plainLyrics(artist: "The Placeholders", title: "Morning Static")
        let lyrics = Lyrics(plain: try #require(text), source: .server)
        #expect(lyrics.lines.map(\.text) == ["Wake up to the morning static", "Coffee going cold again", "", "Second verse, same as the first"])
        let url = try #require(await transport.requests.first?.url)
        #expect(url.queryParameters["artist"] == "The Placeholders")
        #expect(url.queryParameters["title"] == "Morning Static")
    }

    @Test func noPlainLyricsIsNil() async throws {
        let transport = try FakeTransport(fixture: "getLyrics-empty")
        #expect(try await TestServer.client(transport).plainLyrics(artist: nil, title: "Instrumental") == nil)
    }

    @Test func aServerWithTheExtensionGivesSyncedLyrics() async throws {
        let transport = FakeTransport(.json(Self.extensions), .json(try Fixture.json("getLyricsBySongId")))
        let sources = LyricsModel.Sources.live(client: TestServer.client(transport), lrclib: LRCLIBClient(transport: FakeTransport()))
        let lyrics = try #require(try await sources.server(song))
        #expect(lyrics.isSynced)
        #expect(lyrics.source == .server)
    }

    @Test func aServerWithoutTheExtensionIsAskedForPlainLyrics() async throws {
        let transport = FakeTransport(.json(Self.noExtensions), .json(try Fixture.json("getLyrics")))
        let sources = LyricsModel.Sources.live(client: TestServer.client(transport), lrclib: LRCLIBClient(transport: FakeTransport()))
        let lyrics = try #require(try await sources.server(song))
        #expect(!lyrics.isSynced)
        let paths = await transport.requests.compactMap { $0.url?.lastPathComponent }
        #expect(paths.contains { $0.hasPrefix("getLyrics") && !$0.contains("BySongId") })
        #expect(!paths.contains { $0.contains("getLyricsBySongId") })
    }

    @Test func theExtensionCheckIsMadeOnce() async throws {
        let transport = FakeTransport(.json(Self.extensions), .json(try Fixture.json("getLyricsBySongId")), .json(try Fixture.json("getLyricsBySongId")))
        let sources = LyricsModel.Sources.live(client: TestServer.client(transport), lrclib: LRCLIBClient(transport: FakeTransport()))
        _ = try await sources.server(song)
        _ = try await sources.server(song)
        let paths = await transport.requests.compactMap { $0.url?.lastPathComponent }
        #expect(paths.filter { $0.contains("getOpenSubsonicExtensions") }.count == 1)
    }
}
