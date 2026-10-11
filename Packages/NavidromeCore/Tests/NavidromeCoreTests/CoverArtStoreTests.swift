import Foundation
import Testing
@testable import NavidromeCore

struct CoverArtStoreTests {
    private let root = URL.temporaryDirectory.appending(path: "CoverArtStoreTests-\(UUID().uuidString)")
    private var store: CoverArtStore {
        CoverArtStore(cacheDirectory: root.appending(path: "cache"), pinnedDirectory: root.appending(path: "pinned"))
    }

    private func bytes(_ text: String) -> Data { Data(text.utf8) }

    @Test func cachedImagesAreFoundBySize() {
        store.save(bytes("small"), id: "al-1", pixels: 96)
        #expect(store.image(id: "al-1", pixels: 96) == bytes("small"))
        #expect(store.image(id: "al-1", pixels: 600) == nil)
    }

    @Test func aPinnedImageServesEverySize() {
        store.pin(bytes("pinned"), id: "al-1")
        #expect(store.image(id: "al-1", pixels: 96) == bytes("pinned"))
        #expect(store.pinnedIDs() == ["al-1"])
    }

    @Test func offlineFallbackPrefersPinnedThenTheLargestSize() {
        store.save(bytes("small"), id: "al-1", pixels: 96)
        store.save(bytes("large"), id: "al-1", pixels: 600)
        store.save(bytes("other"), id: "al-10", pixels: 900)
        #expect(store.anyImage(id: "al-1") == bytes("large"))

        store.pin(bytes("pinned"), id: "al-1")
        #expect(store.anyImage(id: "al-1") == bytes("pinned"))
        #expect(store.anyImage(id: "al-2") == nil)
    }

    @Test func unpinRemovesOnlyThePinnedCopy() {
        store.save(bytes("small"), id: "al-1", pixels: 96)
        store.pin(bytes("pinned"), id: "al-1")
        store.unpin(id: "al-1")
        #expect(store.pinnedIDs().isEmpty)
        #expect(store.image(id: "al-1", pixels: 96) == bytes("small"))
    }

    @Test func idsCannotEscapeTheFolder() {
        #expect(CoverArtStore.fileName(for: "../../etc/passwd") == "%2E%2E%2F%2E%2E%2Fetc%2Fpasswd")
        store.pin(bytes("x"), id: "../escape")
        #expect(store.pinnedIDs() == ["../escape"])
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "escape").path(percentEncoded: false)))
    }
}
