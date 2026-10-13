import Foundation
import Testing
@testable import NavidromeCore

struct GravatarTests {
    @Test func hashesTheTrimmedLowercasedAddress() {
        let expected = "bd2681d6fb78c2199ebe1f6b47e30b47c80744cb0e2d5ab045109e5ee90f15d9"
        #expect(Gravatar.hash(of: "listener@example.test") == expected)
        #expect(Gravatar.hash(of: "  Listener@Example.TEST \n") == expected)
    }

    @Test func rejectsWhatIsntAnEmail() {
        for text in ["", "listener", "@example.test", "listener@", "listener@example", "a b@example.test", "a@b@c.test", "x@.test", "x@test."] {
            #expect(Gravatar.hash(of: text) == nil, "\(text)")
        }
    }

    @Test func asksForARealPictureOnly() throws {
        let url = try #require(Gravatar.imageURL(forHash: "abc123", pixels: 240))
        #expect(url.absoluteString == "https://gravatar.com/avatar/abc123?s=240&d=404")
    }

    @Test func readsTheServerAccountsEmail() async throws {
        let body = #"{"subsonic-response":{"status":"ok","version":"1.16.1","user":{"username":"listener","email":"listener@example.test","adminRole":false}}}"#
        let transport = FakeTransport(.json(body))
        #expect(try await TestServer.client(transport).userEmail(username: "listener") == "listener@example.test")
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path.hasSuffix("getUser"))
        #expect(url.queryParameters["username"] == "listener")
    }

    @Test func anAccountWithoutAnEmailHasNone() async throws {
        let empty = #"{"subsonic-response":{"status":"ok","version":"1.16.1","user":{"username":"listener","email":""}}}"#
        #expect(try await TestServer.client(FakeTransport(.json(empty))).userEmail(username: "listener") == nil)
        let missing = #"{"subsonic-response":{"status":"ok","version":"1.16.1","user":{"username":"listener"}}}"#
        #expect(try await TestServer.client(FakeTransport(.json(missing))).userEmail(username: "listener") == nil)
    }
}
