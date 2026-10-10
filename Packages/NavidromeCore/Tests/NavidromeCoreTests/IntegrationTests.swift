import Foundation
import Testing
@testable import NavidromeCore

/// Runs against a real Navidrome server, only when these are set in the test
/// environment: NAVIDROME_URL, NAVIDROME_USER, NAVIDROME_PASSWORD.
/// In Xcode: Edit Scheme > Test > Arguments > Environment Variables.
/// From the command line: prefix each with TEST_RUNNER_.
///
/// Read-only on purpose: nothing here stars, scrobbles, or otherwise changes the
/// owner's library or play history.
enum IntegrationServer {
    static let credentials: ServerCredentials? = {
        let env = ProcessInfo.processInfo.environment
        guard
            let urlString = env["NAVIDROME_URL"], let url = URL(string: urlString),
            let user = env["NAVIDROME_USER"], !user.isEmpty,
            let password = env["NAVIDROME_PASSWORD"], !password.isEmpty
        else { return nil }
        return ServerCredentials(baseURL: url, username: user, password: password)
    }()

    static var isConfigured: Bool { credentials != nil }
}

@Suite(.enabled(if: IntegrationServer.isConfigured, "Set NAVIDROME_URL, NAVIDROME_USER and NAVIDROME_PASSWORD to run"))
struct IntegrationTests {
    private let client: SubsonicClient

    init() throws {
        client = SubsonicClient(credentials: try #require(IntegrationServer.credentials))
    }

    @Test func pingAcceptsCredentials() async throws {
        try await client.ping()
    }

    @Test func extensionsLookupSucceeds() async throws {
        // Navidrome advertises extensions; the point is that the call doesn't throw.
        _ = try await client.openSubsonicExtensions()
    }

    @Test func libraryBrowsingRoundTrip() async throws {
        let sections = try await client.artists()
        let artist = try #require(sections.flatMap(\.artists).first, "Library has no artists")
        let detail = try await client.artist(id: artist.id)
        #expect(detail.id == artist.id)

        let albumSummary = try #require(detail.albums.first, "Artist has no albums")
        let album = try await client.album(id: albumSummary.id)
        #expect(album.id == albumSummary.id)
        #expect(!album.songs.isEmpty)
    }

    @Test func albumListAndRandomSongs() async throws {
        let albums = try await client.albumList(.newest, size: 5)
        #expect(!albums.isEmpty)
        let songs = try await client.randomSongs(size: 5)
        #expect(!songs.isEmpty)
    }

    @Test func playlistsLoad() async throws {
        // An empty playlist list is valid; just check each listed one opens.
        for summary in try await client.playlists().prefix(3) {
            let playlist = try await client.playlist(id: summary.id)
            #expect(playlist.id == summary.id)
        }
    }

    @Test func searchFindsAKnownArtist() async throws {
        let artist = try #require(try await client.artists().flatMap(\.artists).first)
        let result = try await client.search(artist.name)
        #expect(result.artists.contains { $0.id == artist.id })
    }

    @Test func streamURLServesAudio() async throws {
        let song = try #require(try await client.randomSongs(size: 1).first)
        var request = URLRequest(url: try client.streamURL(songID: song.id))
        // Two bytes are enough to prove the URL is signed correctly and serves audio.
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect([200, 206].contains(http.statusCode))
        #expect(http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("audio/") == true)
    }

    @Test func coverArtURLServesAnImage() async throws {
        let albums = try await client.albumList(.newest, size: 20)
        let coverID = try #require(albums.compactMap(\.coverArtID).first, "No album has cover art")
        let (_, response) = try await URLSession.shared.data(from: try client.coverArtURL(id: coverID, size: 64))
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("image/") == true)
    }
}
