import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct WishlistTests {
    private actor Searches {
        var queries: [String] = []
        var failing = false
        func add(_ query: String) { queries.append(query) }
        func setFailing(_ value: Bool) { failing = value }
    }

    /// A clock the tests move forward.
    private final class Clock: @unchecked Sendable {
        var now = WishlistTests.heard
        func advance(days: Double) { now = now.addingTimeInterval(days * 86_400) }
    }

    private let defaults = UserDefaults(suiteName: "WishlistTests-\(UUID().uuidString)")!
    private let clock = Clock()
    private let file = URL.temporaryDirectory.appending(path: "WishlistTests-\(UUID().uuidString)/Wishlist.json")
    nonisolated private static let heard = Date(timeIntervalSince1970: 1_800_000_000)
    private static let karma = OnAirSong(artist: "Radiohead", title: "Karma Police")

    private func wishlist(_ searches: Searches = Searches(), results: [String: [Song]] = [:]) -> Wishlist {
        let clock = clock
        return Wishlist(fileURL: file, defaults: defaults, search: { query async throws(SubsonicError) in
            await searches.add(query)
            if await searches.failing { throw .network(.notConnectedToInternet) }
            return results[query] ?? []
        }, now: { clock.now })
    }

    private static let mine = Song(id: "so-1", title: "Karma Police", albumID: "al-1", artist: "Radiohead")

    /// Karma Police, tagged and found in the library.
    private func foundKarma(_ searches: Searches = Searches()) async -> Wishlist {
        let list = wishlist(searches, results: ["Radiohead Karma Police": [Self.mine]])
        list.add(Self.karma, station: nil, details: nil)
        await list.checkLibrary()
        return list
    }

    @Test func aSongIsAddedOnceNewestFirst() {
        let list = wishlist()
        list.add(Self.karma, station: "Alt FM", details: nil)
        list.add(OnAirSong(artist: "Blur", title: "Song 2"), station: nil, details: nil)
        // The same song, as another station writes it.
        list.add(OnAirSong(artist: "radiohead", title: "Karma Police (Remastered)"), station: "Indie 101", details: nil)
        #expect(list.entries.map(\.title) == ["Song 2", "Karma Police"])
        #expect(list.entries.last?.station == "Alt FM")
        #expect(list.entries.last?.heardAt == Self.heard)
        #expect(list.contains(Self.karma))
        #expect(list.entries.last?.text == "Radiohead - Karma Police")
    }

    @Test func musicBrainzDetailsAreKept() {
        let list = wishlist()
        let cover = URL(string: "https://coverartarchive.org/release-group/rg/front-500.jpg")
        let details = OnAirDetails(
            title: "Karma Police", artist: "Radiohead", album: "OK Computer", year: 1997,
            recordingID: "rec-1", releaseGroupID: "rg", coverURL: cover
        )
        list.add(Self.karma, station: nil, details: details)
        let entry = list.entries.first
        #expect(entry?.album == "OK Computer")
        #expect(entry?.year == 1997)
        #expect(entry?.coverURL == cover)
        #expect(entry?.musicBrainzURL == URL(string: "https://musicbrainz.org/recording/rec-1"))
    }

    @Test func itsSavedRestoredAndRemoved() {
        let list = wishlist()
        list.add(Self.karma, station: "Alt FM", details: nil)
        let restored = wishlist()
        #expect(restored.entries == list.entries)
        restored.remove(restored.entries[0].id)
        #expect(restored.entries.isEmpty)
        #expect(wishlist().entries.isEmpty)
    }

    @Test func anUnreadableFileIsAnEmptyList() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nonsense".utf8).write(to: file)
        #expect(wishlist().entries.isEmpty)
    }

    @Test func songsFoundInTheLibraryAreMarked() async {
        let mine = Song(id: "so-1", title: "Karma Police", albumID: "al-1", artist: "Radiohead")
        let searches = Searches()
        let list = wishlist(searches, results: ["Karma Police": [Song(id: "x", title: "Creep", artist: "Radiohead"), mine]])
        list.add(Self.karma, station: nil, details: nil)
        list.add(OnAirSong(artist: "Blur", title: "Song 2"), station: nil, details: nil)
        await list.checkLibrary()
        let karmaID = list.entries[1].id
        #expect(list.owned == [karmaID: mine])
        // A song already found isn't searched again.
        let asked = await searches.queries.count
        await list.checkLibrary()
        #expect(await searches.queries.count == asked + 3)
        list.remove(karmaID)
        #expect(list.owned.isEmpty)
    }

    @Test func aFailedSearchLeavesTheSongAsItWas() async {
        let searches = Searches()
        await searches.setFailing(true)
        let list = wishlist(searches, results: ["Radiohead Karma Police": [Song(id: "so-1", title: "Karma Police", artist: "Radiohead")]])
        list.add(Self.karma, station: nil, details: nil)
        await list.checkLibrary()
        #expect(list.owned.isEmpty)
        #expect(await searches.queries == ["Radiohead Karma Police"])
    }

    @Test func theDayASongIsFoundIsKept() async {
        let list = await foundKarma()
        #expect(list.entries.first?.foundAt == Self.heard)
        clock.advance(days: 3)
        await wishlist(results: ["Radiohead Karma Police": [Self.mine]]).checkLibrary()
        // Saved, and not moved by a later check.
        #expect(wishlist().entries.first?.foundAt == Self.heard)
    }

    @Test func aSongGoneFromTheLibraryStartsItsCountAgain() async {
        _ = await foundKarma()
        let list = wishlist()
        await list.checkLibrary()
        #expect(list.entries.first?.foundAt == nil)
        #expect(list.owned.isEmpty)
    }

    @Test func foundSongsStayWithRemovalOff() async {
        let list = await foundKarma()
        clock.advance(days: 60)
        await list.checkLibrary()
        #expect(list.entries.count == 1)
    }

    @Test func immediatelyRemovesASongOnceFound() async {
        let setup = wishlist()
        setup.removesFound = true
        setup.removeFoundAfter = .immediately
        let list = await foundKarma()
        #expect(list.entries.isEmpty)
        #expect(list.owned.isEmpty)
        #expect(wishlist().entries.isEmpty)
    }

    @Test func aSongIsRemovedSevenDaysAfterItsFound() async {
        let setup = wishlist()
        setup.removesFound = true
        setup.removeFoundAfter = .week
        let list = await foundKarma()
        list.add(OnAirSong(artist: "Blur", title: "Song 2"), station: nil, details: nil)
        clock.advance(days: 6.9)
        await list.checkLibrary()
        #expect(list.entries.count == 2)
        clock.advance(days: 0.1)
        await list.checkLibrary()
        // Only the found song goes.
        #expect(list.entries.map(\.title) == ["Song 2"])
    }

    @Test func turningRemovalOnRemovesSongsAlreadyDue() async {
        let list = await foundKarma()
        clock.advance(days: 10)
        list.removeFoundAfter = .month
        list.removesFound = true
        #expect(list.entries.count == 1)
        list.removeFoundAfter = .week
        #expect(list.entries.isEmpty)
    }

    @Test func theSettingsAreKeptAndOffByDefault() {
        let list = wishlist()
        #expect(!list.removesFound)
        #expect(list.removeFoundAfter == .week)
        list.removesFound = true
        list.removeFoundAfter = .month
        let restored = wishlist()
        #expect(restored.removesFound)
        #expect(restored.removeFoundAfter == .month)
    }
}
