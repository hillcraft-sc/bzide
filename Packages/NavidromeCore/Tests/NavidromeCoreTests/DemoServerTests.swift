import Foundation
import Testing
@testable import NavidromeCore

struct DemoServerTests {
    @Test func credentialsPointAtTheNavidromeDemoOverHTTPS() {
        let credentials = DemoServer.credentials
        #expect(credentials.baseURL.scheme == "https")
        #expect(credentials.baseURL.host() == "demo.navidrome.org")
        #expect(credentials.apiKey == nil)
        #expect(!credentials.exposesLogin)
    }

    @Test func recognizesTheDemoByItsHost() {
        #expect(DemoServer.isDemo(DemoServer.credentials))
        let withSlash = ServerCredentials(baseURL: URL(string: "https://Demo.Navidrome.org/")!, username: "other", password: "x")
        #expect(DemoServer.isDemo(withSlash))
    }

    @Test func otherServersAreNotTheDemo() {
        #expect(!DemoServer.isDemo(TestServer.credentials))
        let lookAlike = ServerCredentials(baseURL: URL(string: "https://demo.navidrome.org.example.test")!, username: "demo", password: "demo")
        #expect(!DemoServer.isDemo(lookAlike))
    }

    @Test func demoTurnsOffTheSharedServerWritesOnly() {
        var settings = StreamingSettings()
        settings.downloadOverCellular = true
        let adjusted = DemoServer.adjusting(settings)
        #expect(!adjusted.syncQueueWithServer)
        #expect(!adjusted.sendPlaysToServer)
        // Nothing else is touched.
        var expected = settings
        expected.syncQueueWithServer = false
        expected.sendPlaysToServer = false
        #expect(adjusted == expected)
    }
}
