import Foundation
import Testing
@testable import NavidromeCore

/// Gitea #20: API keys, the http warning, and no shared disk cache.
struct APIKeyTests {
    private let credentials = ServerCredentials(
        baseURL: URL(string: "https://music.example.test")!, username: "listener", password: "", apiKey: "k-123"
    )

    @Test func anAPIKeyReplacesTheUsernameAndToken() throws {
        let url = try RequestBuilder(credentials: credentials, identity: ClientIdentity(), makeSalt: { "c19b2d" }).url(endpoint: "ping")
        #expect(url.queryParameters == ["apiKey": "k-123", "v": "1.16.1", "c": "Bzide", "f": "json"])
    }

    @Test func anEmptyKeyIsNoKey() {
        let empty = ServerCredentials(baseURL: URL(string: "https://music.example.test")!, username: "listener", password: "sesame", apiKey: "")
        #expect(empty.apiKey == nil)
    }

    @Test func theKeyIsRedactedFromLogs() {
        let logged = LogRedaction.redact(URL(string: "https://music.example.test/rest/ping?apiKey=k-123&v=1.16.1")!)
        #expect(!logged.contains("k-123"))
        #expect(logged.contains("apiKey=REDACTED"))
    }

    @Test func theServerSaysWhoseKeyItIs() async throws {
        let transport = FakeTransport(.json(#"{"subsonic-response":{"status":"ok","version":"1.16.1","openSubsonic":true,"tokenInfo":{"username":"listener"}}}"#))
        let client = TestServer.client(transport, credentials: credentials)
        #expect(try await client.apiKeyUsername() == "listener")
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path() == "/rest/tokenInfo")
        #expect(url.queryParameters["u"] == nil)
    }

    @Test func anInvalidKeyIsAnAuthenticationFailure() async {
        let transport = FakeTransport(.json(TestServer.failed(code: 44, message: "Invalid API key")))
        let client = TestServer.client(transport, credentials: credentials)
        await #expect(throws: SubsonicError.server(code: 44, message: "Invalid API key")) { try await client.apiKeyUsername() }
        let error = SubsonicError.server(code: 44, message: "Invalid API key")
        #expect(error.isAuthenticationFailure)
        #expect(error.localizedDescription.contains("API key isn't valid"))
        #expect(SubsonicError.server(code: 41, message: "").localizedDescription.contains("API key"))
    }
}

struct ServerAddressTests {
    private func exposes(_ address: String) -> Bool {
        ServerAddress.exposesLogin(URL(string: address)!)
    }

    @Test func plainHTTPToAPublicAddressExposesTheLogin() {
        #expect(exposes("http://music.example.com"))
        #expect(exposes("http://203.0.113.7:4533"))
        #expect(exposes("http://8.8.8.8/navidrome"))
    }

    @Test func httpsNeverDoes() {
        #expect(!exposes("https://music.example.com"))
        #expect(!exposes("HTTPS://music.example.com"))
    }

    @Test func localAndPrivateAddressesDont() {
        for address in [
            "http://192.168.1.10:4533", "http://10.0.0.5", "http://172.20.1.1", "http://127.0.0.1:4533",
            "http://169.254.3.4", "http://100.101.102.103", "http://nas", "http://nas.local:4533",
            "http://music.lan", "http://server.home.arpa", "http://localhost:4533",
            "http://[::1]:4533", "http://[fd12:3456::1]", "http://[fe80::1]",
        ] {
            #expect(!exposes(address), "\(address)")
        }
        // Just outside the private ranges.
        #expect(exposes("http://172.32.0.1"))
        #expect(exposes("http://100.128.0.1"))
    }
}

struct PrivateSessionTests {
    @Test func keepsNothingOnDisk() {
        let configuration = URLSessionTransport.privateSession.configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCredentialStorage == nil)
    }
}
