import Foundation
import Testing
@testable import NavidromeCore

struct SubsonicClientSystemTests {
    @Test func pingSucceedsOnOkStatus() async throws {
        let transport = FakeTransport(.json(TestServer.ok))
        try await TestServer.client(transport).ping()
        let requests = await transport.requests
        #expect(requests.first?.url?.path() == "/rest/ping")
    }

    @Test func wrongPasswordIsReportedAsAuthFailure() async {
        let transport = FakeTransport(.json(TestServer.failed(code: 40, message: "Wrong username or password")))
        do {
            try await TestServer.client(transport).ping()
            Issue.record("Expected ping to throw")
        } catch {
            #expect(error == .server(code: 40, message: "Wrong username or password"))
            #expect(error.isAuthenticationFailure)
        }
    }

    @Test func httpErrorStatusIsReported() async {
        let transport = FakeTransport(.json("<html>Bad Gateway</html>", status: 502))
        await #expect(throws: SubsonicError.httpStatus(502)) {
            try await TestServer.client(transport).ping()
        }
    }

    @Test func networkFailureIsReported() async {
        let transport = FakeTransport(.failure(.notConnectedToInternet))
        await #expect(throws: SubsonicError.network(.notConnectedToInternet)) {
            try await TestServer.client(transport).ping()
        }
    }

    @Test func nonJSONBodyIsADecodingError() async {
        let transport = FakeTransport(.json("<html>Captive portal</html>"))
        do {
            try await TestServer.client(transport).ping()
            Issue.record("Expected ping to throw")
        } catch {
            guard case .decoding = error else {
                Issue.record("Expected a decoding error, got \(error)")
                return
            }
        }
    }

    @Test func readsAdvertisedExtensions() async throws {
        let body = #"""
        {"subsonic-response":{"status":"ok","version":"1.16.1","openSubsonic":true,
          "openSubsonicExtensions":[{"name":"transcodeOffset","versions":[1]},{"name":"formPost"}]}}
        """#
        let extensions = try await TestServer.client(FakeTransport(.json(body))).openSubsonicExtensions()
        #expect(extensions == [
            OpenSubsonicExtension(name: "transcodeOffset", versions: [1]),
            OpenSubsonicExtension(name: "formPost", versions: []),
        ])
    }

    @Test func plainSubsonicServerHasNoExtensions() async throws {
        let notFound = FakeTransport(.json("", status: 404))
        #expect(try await TestServer.client(notFound).openSubsonicExtensions().isEmpty)

        let unknownEndpoint = FakeTransport(.json(TestServer.failed(code: 0, message: "Unknown endpoint")))
        #expect(try await TestServer.client(unknownEndpoint).openSubsonicExtensions().isEmpty)
    }

    @Test func extensionsLookupStillReportsNetworkFailure() async {
        let transport = FakeTransport(.failure(.timedOut))
        await #expect(throws: SubsonicError.network(.timedOut)) {
            try await TestServer.client(transport).openSubsonicExtensions()
        }
    }
}
