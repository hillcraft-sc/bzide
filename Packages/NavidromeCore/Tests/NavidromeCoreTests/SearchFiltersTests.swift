import Foundation
import Synchronization
import Testing
@testable import NavidromeCore

@MainActor
struct SearchFiltersTests {
    private let results = SearchResult(
        artists: [
            Artist(id: "ar-1", name: "Loved Band", isStarred: true, userRating: 5),
            Artist(id: "ar-2", name: "Other Band"),
        ],
        albums: [
            Album(id: "al-1", name: "Great Album", isStarred: false, userRating: 3),
            Album(id: "al-2", name: "Meh Album", userRating: 2),
            Album(id: "al-3", name: "Kept Album", isStarred: true),
        ],
        songs: [
            Song(id: "so-1", title: "Rocks", isStarred: true, userRating: 5),
            Song(id: "so-2", title: "Meh", userRating: 1),
            Song(id: "so-3", title: "Plain"),
        ]
    )

    private func apply(_ filters: SearchFilters, downloadedSongs: Set<String> = [], downloadedAlbums: Set<String> = []) -> SearchResult {
        filters.apply(to: results, isSongDownloaded: downloadedSongs.contains, isAlbumDownloaded: downloadedAlbums.contains)
    }

    // MARK: Filters

    @Test func noFiltersShowsEverything() {
        #expect(apply(SearchFilters()) == results)
        #expect(!SearchFilters().isFiltering)
        #expect(SearchFilters().summary == nil)
    }

    @Test func aScopeShowsOneKind() {
        let albums = apply(SearchFilters(scope: .albums))
        #expect(albums.artists.isEmpty && albums.songs.isEmpty)
        #expect(albums.albums.count == 3)
    }

    @Test func ratingFilters() {
        #expect(apply(SearchFilters(rating: .rocks)).songs.map(\.id) == ["so-1"])
        #expect(apply(SearchFilters(rating: .meh)).albums.map(\.id) == ["al-2"])
        #expect(apply(SearchFilters(rating: .dontHateIt)).albums.map(\.id) == ["al-1"])
        let unrated = apply(SearchFilters(rating: .unrated))
        #expect(unrated.songs.map(\.id) == ["so-3"])
        #expect(unrated.artists.map(\.id) == ["ar-2"])
    }

    @Test func favoritesOnly() {
        let favorites = apply(SearchFilters(favoritesOnly: true))
        #expect(favorites.artists.map(\.id) == ["ar-1"])
        #expect(favorites.albums.map(\.id) == ["al-3"])
        #expect(favorites.songs.map(\.id) == ["so-1"])
    }

    @Test func downloadedOnlyHasNoArtists() {
        let downloaded = apply(SearchFilters(downloadedOnly: true), downloadedSongs: ["so-3"], downloadedAlbums: ["al-1"])
        #expect(downloaded.artists.isEmpty)
        #expect(downloaded.albums.map(\.id) == ["al-1"])
        #expect(downloaded.songs.map(\.id) == ["so-3"])
    }

    @Test func filtersCombine() {
        let filters = SearchFilters(scope: .songs, rating: .rocks, favoritesOnly: true)
        #expect(apply(filters).songs.map(\.id) == ["so-1"])
        #expect(filters.summary == "Rocks · Favorites")
    }

    @Test func asksForMoreWhenFocusedOrFiltering() {
        #expect(SearchFilters().requestCounts == (20, 20, 20))
        #expect(SearchFilters(rating: .rocks).requestCounts == (100, 100, 100))
        #expect(SearchFilters(scope: .songs).requestCounts == (0, 0, 100))
        #expect(SearchFilters(scope: .artists, favoritesOnly: true).requestCounts == (100, 0, 0))
    }

    @Test func clearingKeepsTheScope() {
        var filters = SearchFilters(scope: .albums, rating: .meh, favoritesOnly: true, downloadedOnly: true)
        filters.clear()
        #expect(filters == SearchFilters(scope: .albums))
    }

    @Test func savedAndRestored() throws {
        let filters = SearchFilters(scope: .songs, rating: .unrated, downloadedOnly: true)
        #expect(try JSONDecoder().decode(SearchFilters.self, from: JSONEncoder().encode(filters)) == filters)
    }

    // MARK: The search model

    private final class Server: @unchecked Sendable {
        var requests: [SearchRequest] = []
        var answer = SearchResult()
    }

    private func makeModel(_ server: Server, scheduler: FakeScheduler = FakeScheduler()) -> SearchModel {
        SearchModel(scheduler: scheduler) { request async throws(SubsonicError) in
            server.requests.append(request)
            return server.answer
        }
    }

    @Test func changingFiltersSearchesAgainAtOnce() async {
        let server = Server()
        let scheduler = FakeScheduler()
        let model = makeModel(server, scheduler: scheduler)
        model.updateQuery("band")
        scheduler.fireNext()
        await model.searchTask?.value
        #expect(server.requests.last?.songCount == 20)
        model.filters.scope = .songs
        await model.searchTask?.value
        #expect(server.requests.count == 2)
        #expect(server.requests.last == SearchRequest(query: "band", artistCount: 0, albumCount: 0, songCount: 100, isBrowse: false, scope: .songs))
    }

    @Test func aFilterWithNothingTypedBrowsesTheLibrary() async {
        let server = Server()
        server.answer = results
        let model = makeModel(server)
        #expect(model.results == nil)
        model.filters.favoritesOnly = true
        #expect(model.isBrowsing)
        await model.searchTask?.value
        #expect(server.requests.last?.isBrowse == true)
        #expect(model.visibleResults?.songs.map(\.id) == ["so-1"])
        // Clearing the filters goes back to nothing (the genre grid).
        model.filters = SearchFilters()
        #expect(model.results == nil)
        #expect(!model.isBrowsing)
    }

    @Test func aScopeAloneWithNothingTypedDoesntBrowse() {
        let server = Server()
        let model = makeModel(server)
        model.filters.scope = .albums
        #expect(model.results == nil)
        #expect(server.requests.isEmpty)
    }

    // MARK: The library catalog

    @Test func theCatalogListsTheWholeLibraryOnceForAWhile() async throws {
        // Pages are fetched from several tasks at once, so the count is locked.
        let albumPages = Mutex(0)
        let albums = (0..<1_234).map { Album(id: "al-\($0)", name: "Album \($0)") }
        let catalog = LibraryCatalog(sources: .init(
            artists: { [Artist(id: "ar-1", name: "Band")] },
            albumsPage: { count, offset in
                albumPages.withLock { $0 += 1 }
                return Array(albums[min(offset, albums.count)..<min(offset + count, albums.count)])
            },
            songsPage: { _, _ in [] }
        ))
        let first = try await catalog.browse(.albums)
        #expect(first.albums.count == 1_234)
        #expect(first.artists.isEmpty && first.songs.isEmpty)
        let pages = albumPages.withLock { $0 }
        _ = try await catalog.browse(.all)
        #expect(albumPages.withLock { $0 } == pages)
    }
}
