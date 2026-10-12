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
    }

    @Test func paragraphsAndEntitiesSurvive() {
        #expect(ArtistInfo.plainText(fromHTML: "<p>One &quot;two&quot;</p>\n\n\n<p>It&#39;s &amp;lt;3</p>") == "One \"two\"\n\nIt's &lt;3")
    }

    @Test func blankBiographyIsNil() {
        #expect(ArtistInfo.plainText(fromHTML: "  <br/> ") == nil)
    }
}
