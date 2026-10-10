import Foundation
import Testing
@testable import NavidromeCore

struct LogRedactionTests {
    @Test func hidesAuthParametersButKeepsTheRest() {
        let url = URL(string: "https://music.example.test/rest/getAlbum?u=listener&t=abc123&s=salt&p=secret&id=42&f=json")!
        let logged = LogRedaction.redact(url)
        #expect(!logged.contains("listener"))
        #expect(!logged.contains("abc123"))
        #expect(!logged.contains("salt"))
        #expect(!logged.contains("secret"))
        #expect(logged.contains("id=42"))
        #expect(logged.contains("u=REDACTED"))
    }
}
