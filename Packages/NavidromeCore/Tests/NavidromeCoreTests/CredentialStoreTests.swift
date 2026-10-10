import Foundation
import Testing
@testable import NavidromeCore

struct InMemoryCredentialStoreTests {
    @Test func savesLoadsAndDeletes() {
        let store = InMemoryCredentialStore()
        #expect(store.load() == nil)
        store.save(TestServer.credentials)
        #expect(store.load() == TestServer.credentials)
        store.delete()
        #expect(store.load() == nil)
    }
}

// Only compiled for iOS: run on the macOS host, these would write to the user's
// login keychain. In the iOS Simulator they use the simulator's own keychain.
#if os(iOS)
// Package tests run in a bare test runner with no Keychain entitlement, so every
// call fails with -34018 (errSecMissingEntitlement). Re-enable once the app target
// hosts the tests (start of M2). See docs/ISSUES.md.
@Suite(.serialized, .disabled("Needs a host app for Keychain access; see docs/ISSUES.md"))
struct KeychainCredentialStoreTests {
    /// A unique service per test so runs never touch the app's real item or each other.
    private let store = KeychainCredentialStore(service: "MusicApp.tests.\(UUID().uuidString)")

    @Test func emptyStoreLoadsNil() throws {
        #expect(try store.load() == nil)
    }

    @Test func roundTripsAndOverwrites() throws {
        defer { try? store.delete() }
        try store.save(TestServer.credentials)
        #expect(try store.load() == TestServer.credentials)

        var changed = TestServer.credentials
        changed.password = "new password"
        try store.save(changed)
        #expect(try store.load() == changed)
    }

    @Test func deleteRemovesAndIsIdempotent() throws {
        try store.save(TestServer.credentials)
        try store.delete()
        #expect(try store.load() == nil)
        try store.delete()
    }
}
#endif
