import Foundation
import Testing
@testable import NavidromeCore

struct AccountScopeTests {
    private let root = URL.temporaryDirectory.appending(path: "AccountScopeTests-\(UUID().uuidString)")
    private let defaults = UserDefaults(suiteName: "AccountScopeTests-\(UUID().uuidString)")!

    private var file: URL { root.appending(path: "PlaybackQueue.json") }
    private var folder: URL { root.appending(path: "Downloads") }
    private var scope: AccountScope { AccountScope(defaults: defaults, dataLocations: [file, folder]) }

    private func account(_ url: String, _ user: String = "listener") -> ServerCredentials {
        ServerCredentials(baseURL: URL(string: url)!, username: user, password: "sesame")
    }

    private func writeData() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("queue".utf8).write(to: file)
        try Data("song".utf8).write(to: folder.appending(path: "so-1.flac"))
    }

    private var dataExists: Bool {
        FileManager.default.fileExists(atPath: file.path(percentEncoded: false))
            || FileManager.default.fileExists(atPath: folder.path(percentEncoded: false))
    }

    @Test func existingDataIsKeptOnFirstUse() throws {
        try writeData()
        #expect(!scope.prepare(for: account("https://music.example.test")))
        #expect(dataExists)
    }

    @Test func theSameAccountKeepsItsData() throws {
        scope.prepare(for: account("https://music.example.test"))
        try writeData()
        #expect(!scope.prepare(for: account("https://music.example.test")))
        #expect(dataExists)
    }

    @Test func anotherServerRemovesTheData() throws {
        scope.prepare(for: account("https://music.example.test"))
        try writeData()
        #expect(scope.prepare(for: account("https://other.example.test")))
        #expect(!dataExists)
    }

    @Test func anotherUserRemovesTheData() throws {
        scope.prepare(for: account("https://music.example.test", "listener"))
        try writeData()
        #expect(scope.prepare(for: account("https://music.example.test", "guest")))
        #expect(!dataExists)
    }

    @Test func theNewAccountBecomesTheOwner() throws {
        scope.prepare(for: account("https://music.example.test"))
        scope.prepare(for: account("https://other.example.test"))
        try writeData()
        #expect(!scope.prepare(for: account("https://other.example.test")))
        #expect(dataExists)
    }

    @Test func theSameServerWrittenDifferentlyIsTheSameAccount() {
        let a = AccountScope.fingerprint(of: account("https://music.example.test/navidrome"))
        #expect(a == AccountScope.fingerprint(of: account("HTTPS://Music.Example.test/navidrome/")))
        #expect(a != AccountScope.fingerprint(of: account("http://music.example.test/navidrome")))
        #expect(a != AccountScope.fingerprint(of: account("https://music.example.test/navidrome", "Listener")))
    }

    @Test func nothingReadableIsStored() {
        scope.prepare(for: account("https://music.example.test"))
        let stored = defaults.string(forKey: AccountScope.fingerprintKey) ?? ""
        #expect(!stored.contains("example"))
        #expect(!stored.contains("listener"))
        #expect(stored.count == 64)
    }
}
