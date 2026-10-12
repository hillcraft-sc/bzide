import Foundation
import Testing
@testable import NavidromeCore

struct RequestBuilderTests {
    private func builder(baseURL: String = "https://music.example.test", username: String = "listener") -> RequestBuilder {
        let credentials = ServerCredentials(baseURL: URL(string: baseURL)!, username: username, password: "sesame")
        return RequestBuilder(credentials: credentials, identity: ClientIdentity(), makeSalt: { "c19b2d" })
    }

    @Test func addsAuthAndFormatParametersToEveryRequest() throws {
        let url = try builder().url(endpoint: "ping")
        #expect(url.path() == "/rest/ping")
        #expect(url.queryParameters == [
            "u": "listener",
            "t": "26719a1196d2a940705a59634eb18eab",
            "s": "c19b2d",
            "v": "1.16.1",
            "c": "Bzide",
            "f": "json",
        ])
    }

    @Test func neverSendsThePlainPassword() throws {
        let url = try builder().url(endpoint: "ping")
        #expect(url.queryParameters["p"] == nil)
        #expect(!url.absoluteString.contains("sesame"))
    }

    @Test func keepsReverseProxySubpath() throws {
        let url = try builder(baseURL: "http://192.168.1.10:4533/navidrome/").url(endpoint: "ping")
        #expect(url.absoluteString.hasPrefix("http://192.168.1.10:4533/navidrome/rest/ping?"))
    }

    @Test func escapesPlusSoServerDoesNotReadItAsSpace() throws {
        let url = try builder(username: "a+b").url(endpoint: "search3", parameters: [URLQueryItem(name: "query", value: "AC+DC & co")])
        let query = url.query(percentEncoded: true) ?? ""
        #expect(query.contains("u=a%2Bb"))
        #expect(query.contains("query=AC%2BDC%20%26%20co"))
    }

    @Test func rejectsNonHTTPSchemes() {
        #expect(throws: SubsonicError.invalidBaseURL) {
            try builder(baseURL: "ftp://music.example.test").url(endpoint: "ping")
        }
    }
}
