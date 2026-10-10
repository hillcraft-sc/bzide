import Foundation
import Testing
@testable import NavidromeCore

/// Checks that each call sends the endpoint and parameters the server expects.
struct LibraryRequestTests {
    private func sentURL(_ call: (SubsonicClient) async throws -> Void) async throws -> URL {
        let transport = FakeTransport(.json(TestServer.ok))
        try await call(TestServer.client(transport))
        let url = try #require(await transport.requests.first?.url)
        return url
    }

    @Test func albumListSendsTypeAndPaging() async throws {
        let url = try await sentURL { _ = try await $0.albumList(.byYear(from: 1990, to: 1999), size: 50, offset: 100) }
        #expect(url.path() == "/rest/getAlbumList2")
        #expect(url.queryParameters["type"] == "byYear")
        #expect(url.queryParameters["fromYear"] == "1990")
        #expect(url.queryParameters["toYear"] == "1999")
        #expect(url.queryParameters["size"] == "50")
        #expect(url.queryParameters["offset"] == "100")
    }

    @Test func starUsesTheRightParameterForEachKind() async throws {
        let song = try await sentURL { try await $0.star(.song(id: "so-1")) }
        #expect(song.path() == "/rest/star")
        #expect(song.queryParameters["id"] == "so-1")

        let album = try await sentURL { try await $0.unstar(.album(id: "al-1")) }
        #expect(album.path() == "/rest/unstar")
        #expect(album.queryParameters["albumId"] == "al-1")

        let artist = try await sentURL { try await $0.star(.artist(id: "ar-1")) }
        #expect(artist.queryParameters["artistId"] == "ar-1")
    }

    @Test func scrobbleSendsSubmissionFlagAndTimeInMilliseconds() async throws {
        let playedAt = Date(timeIntervalSince1970: 1_700_000_000.5)
        let url = try await sentURL { try await $0.scrobble(songID: "so-1", playedAt: playedAt, submission: true) }
        #expect(url.path() == "/rest/scrobble")
        #expect(url.queryParameters["id"] == "so-1")
        #expect(url.queryParameters["submission"] == "true")
        #expect(url.queryParameters["time"] == "1700000000500")
    }

    @Test func nowPlayingScrobbleOmitsTime() async throws {
        let url = try await sentURL { try await $0.scrobble(songID: "so-1", submission: false) }
        #expect(url.queryParameters["submission"] == "false")
        #expect(url.queryParameters["time"] == nil)
    }

    @Test func searchSendsQueryAndCounts() async throws {
        let url = try await sentURL { _ = try await $0.search("first light", artistCount: 1, albumCount: 2, songCount: 3) }
        #expect(url.path() == "/rest/search3")
        #expect(url.queryParameters["query"] == "first light")
        #expect(url.queryParameters["artistCount"] == "1")
        #expect(url.queryParameters["albumCount"] == "2")
        #expect(url.queryParameters["songCount"] == "3")
    }
}

struct MediaURLTests {
    private let client = TestServer.client(FakeTransport())

    @Test func streamURLIsSignedAndCarriesTranscodeOptions() throws {
        let url = try client.streamURL(songID: "so-1", maxBitRate: 192, format: "mp3")
        #expect(url.path() == "/rest/stream")
        #expect(url.queryParameters["id"] == "so-1")
        #expect(url.queryParameters["maxBitRate"] == "192")
        #expect(url.queryParameters["format"] == "mp3")
        #expect(url.queryParameters["t"] == "26719a1196d2a940705a59634eb18eab")
    }

    @Test func streamURLOmitsTranscodeOptionsByDefault() throws {
        let url = try client.streamURL(songID: "so-1")
        #expect(url.queryParameters["maxBitRate"] == nil)
        #expect(url.queryParameters["format"] == nil)
    }

    @Test func downloadAndCoverArtURLs() throws {
        #expect(try client.downloadURL(songID: "so-1").path() == "/rest/download")
        let cover = try client.coverArtURL(id: "al-al-1", size: 600)
        #expect(cover.path() == "/rest/getCoverArt")
        #expect(cover.queryParameters["id"] == "al-al-1")
        #expect(cover.queryParameters["size"] == "600")
    }
}
