import Foundation
import Testing
@testable import NavidromeCore

struct LibraryLayoutTests {
    @Test func everythingIsShownByDefaultInOrder() {
        let layout = LibraryLayout()
        #expect(layout.shown == LibraryFeature.allCases)
        #expect(layout.groups == [
            .recentlyAdded, .mixes([.randomMix, .ratedShuffle]),
            .links([.artists, .albums, .playlists, .favorites, .genres, .radio, .downloads, .history]),
        ])
    }

    @Test func hiddenItemsAreLeftOut() {
        var layout = LibraryLayout()
        layout.setShown(.radio, false)
        layout.setShown(.randomMix, false)
        layout.setShown(.ratedShuffle, false)
        #expect(!layout.shown.contains(.radio))
        #expect(layout.groups.first == .recentlyAdded)
        #expect(layout.groups.count == 2)
    }

    @Test func linksMovedFirstAreGroupedBeforeTheRest() {
        var layout = LibraryLayout()
        // Artists and Albums to the top; Recently Added after them.
        layout.move(fromOffsets: IndexSet([3, 4]), toOffset: 0)
        #expect(layout.shown.prefix(3) == [.artists, .albums, .recentlyAdded])
        #expect(layout.groups.prefix(3) == [.links([.artists, .albums]), .recentlyAdded, .mixes([.randomMix, .ratedShuffle])])
    }

    @Test func itsSavedAndRestored() throws {
        var layout = LibraryLayout()
        layout.setShown(.history, false)
        layout.move(fromOffsets: IndexSet([5]), toOffset: 0)
        let restored = try JSONDecoder().decode(LibraryLayout.self, from: JSONEncoder().encode(layout))
        #expect(restored == layout)
    }

    @Test func aSavedLayoutFromAnotherVersionStillWorks() throws {
        // Unknown "podcasts", a repeated "albums", and no Shuffle Rated, favorites, genres or history (added later).
        let saved = """
        {"entries":[{"item":"albums","isShown":true},{"item":"podcasts","isShown":true},
        {"item":"artists","isShown":false},{"item":"albums","isShown":false},{"item":"recentlyAdded","isShown":true},
        {"item":"randomMix","isShown":true},{"item":"playlists","isShown":true},{"item":"radio","isShown":true},
        {"item":"downloads","isShown":true}]}
        """
        let layout = try JSONDecoder().decode(LibraryLayout.self, from: Data(saved.utf8))
        // New items go in their usual place: Shuffle Rated after Random Mix,
        // Favorites and Genres after Playlists, History after Downloaded.
        #expect(layout.entries.map(\.item) == [
            .albums, .artists, .recentlyAdded, .randomMix, .ratedShuffle, .playlists, .favorites, .genres, .radio, .downloads, .history,
        ])
        #expect(layout.entries.first?.isShown == true)
        #expect(layout.entries[1].isShown == false)
        #expect(layout.entries.allSatisfy { [.ratedShuffle, .favorites, .genres, .history].contains($0.item) ? $0.isShown : true })
    }

    @Test func unreadableSavedLayoutFallsBackToTheDefault() throws {
        let layout = try JSONDecoder().decode(LibraryLayout.self, from: Data(#"{"entries":"nonsense"}"#.utf8))
        #expect(layout == LibraryLayout())
    }

    @MainActor
    @Test func theModelSavesAndResets() {
        let defaults = UserDefaults(suiteName: "LibraryLayoutTests-\(UUID().uuidString)")!
        let model = LibraryLayoutModel(defaults: defaults)
        model.layout.setShown(.genres, false)
        #expect(LibraryLayoutModel(defaults: defaults).layout.shown.contains(.genres) == false)
        model.reset()
        #expect(LibraryLayoutModel(defaults: defaults).layout == LibraryLayout())
    }

    @Test func favoritesComeFromGetStarred2() async throws {
        let transport = try FakeTransport(fixture: "getStarred2")
        let favorites = try await TestServer.client(transport).favorites()
        #expect(favorites.artists.map(\.id) == ["ar-1"])
        #expect(favorites.albums.map(\.id) == ["al-1"])
        #expect(favorites.songs.map(\.id) == ["so-1", "so-3"])
        #expect(favorites.songs.allSatisfy { $0.isStarred })
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path.hasSuffix("getStarred2"))
    }

    @Test func noFavoritesIsEmpty() async throws {
        let transport = FakeTransport(.json(TestServer.ok))
        let favorites = try await TestServer.client(transport).favorites()
        #expect(favorites == SearchResult())
    }
}
