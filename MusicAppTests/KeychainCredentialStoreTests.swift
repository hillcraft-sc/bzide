import Foundation
import NavidromeCore
import Testing

// These live in the app's test target, not the package, because Keychain access
// needs a host app: in a bare package test runner every call fails with -34018.
@Suite(.serialized)
struct KeychainCredentialStoreTests {
    /// A unique service per test so runs never touch the app's real item or each other.
    private let store = KeychainCredentialStore(service: "MusicApp.tests.\(UUID().uuidString)")

    private let credentials = ServerCredentials(
        baseURL: URL(string: "https://music.example.test")!,
        username: "listener",
        password: "sesame"
    )

    @Test func emptyStoreLoadsNil() throws {
        #expect(try store.load() == nil)
    }

    @Test func roundTripsAndOverwrites() throws {
        defer { try? store.delete() }
        try store.save(credentials)
        #expect(try store.load() == credentials)

        var changed = credentials
        changed.password = "new password"
        try store.save(changed)
        #expect(try store.load() == changed)
    }

    /// Signed in with an API key: the key is kept, and no password.
    @Test func roundTripsAnAPIKey() throws {
        defer { try? store.delete() }
        let keyed = ServerCredentials(baseURL: URL(string: "https://music.example.test")!, username: "listener", password: "", apiKey: "k-123")
        try store.save(keyed)
        #expect(try store.load() == keyed)
        #expect(try store.load()?.apiKey == "k-123")
    }

    @Test func deleteRemovesAndIsIdempotent() throws {
        try store.save(credentials)
        try store.delete()
        #expect(try store.load() == nil)
        try store.delete()
    }
}
