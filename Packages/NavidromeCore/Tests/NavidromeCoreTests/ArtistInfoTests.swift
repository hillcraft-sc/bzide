import Foundation
import Testing
@testable import NavidromeCore

struct ArtistInfoTests {
    @Test func biographyIsPlainTextWithoutTheLastFmLink() async throws {
        let info = try await TestServer.client(FakeTransport(fixture: "getArtistInfo2")).artistInfo(id: "ar-1")
        #expect(info.biography == """
            Aurora Lines is an ambient duo formed in 2015.
            Their debut, First Light, came out in 2019 & was recorded at home.
            """)
    }

    @Test func onlyTheLinkMeansNoBiography() async throws {
        let info = try await TestServer.client(FakeTransport(fixture: "getArtistInfo2-empty")).artistInfo(id: "ar-1")
        #expect(info.biography == nil)
    }

    @Test func missingInfoIsEmptyNotAnError() async throws {
        let info = try await TestServer.client(FakeTransport(.json(TestServer.ok))).artistInfo(id: "ar-1")
        #expect(info == ArtistInfo())
    }

    @Test func requestsTheArtistByID() async throws {
        let transport = FakeTransport(.json(TestServer.ok))
        _ = try await TestServer.client(transport).artistInfo(id: "ar-1")
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path() == "/rest/getArtistInfo2")
        #expect(url.queryParameters["id"] == "ar-1")
        // Similar artists not in the library too, for Similar Artists.
        #expect(url.queryParameters["includeNotPresent"] == "true")
        #expect(url.queryParameters["count"] == "20")
    }

    @Test func similarArtistsInAndOutOfTheLibrary() async throws {
        let info = try await TestServer.client(FakeTransport(fixture: "getArtistInfo2")).artistInfo(id: "ar-1")
        #expect(info.similarArtists == [
            SimilarArtist(name: "Tidal Rooms", artistID: "ar-2", coverArtID: "ar-2"),
            // Navidrome's "-1": not in the library, so no id or cover; a nameless one is dropped.
            SimilarArtist(name: "Glass Harbor"),
        ])
        #expect(info.similarArtists.map(\.isInLibrary) == [true, false])
    }

    @Test func anArtistNotOwnedIsSearchedForOnMusicBrainz() throws {
        let url = try #require(SimilarArtist(name: "Glass Harbor").musicBrainzSearch)
        #expect(url.absoluteString == "https://musicbrainz.org/search?query=Glass%20Harbor&type=artist")
    }

    @Test func paragraphsAndEntitiesSurvive() {
        #expect(ArtistInfo.plainText(fromHTML: "<p>One &quot;two&quot;</p>\n\n\n<p>It&#39;s &amp;lt;3</p>") == "One \"two\"\n\nIt's &lt;3")
    }

    @Test func blankBiographyIsNil() {
        #expect(ArtistInfo.plainText(fromHTML: "  <br/> ") == nil)
    }
}
