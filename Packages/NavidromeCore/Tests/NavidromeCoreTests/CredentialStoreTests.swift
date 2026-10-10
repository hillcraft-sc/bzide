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

// KeychainCredentialStore is tested in MusicAppTests: Keychain access needs a host app.
