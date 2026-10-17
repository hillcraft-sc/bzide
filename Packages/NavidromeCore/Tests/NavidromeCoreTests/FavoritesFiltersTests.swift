import Foundation
import Testing
@testable import NavidromeCore

struct FavoritesFiltersTests {
    private static func song(_ id: String, _ title: String, artist: String, album: String? = nil, rating: Int? = nil, day: Int?) -> Song {
        var song = Song(id: id, title: title, album: album, artist: artist, isStarred: true, userRating: rating)
        song.starredAt = day.map { Date(timeIntervalSince1970: Double($0) * 86_400) }
        return song
    }

    private static let favorites: SearchResult = {
        var album = Album(id: "al-1", name: "OK Computer", artist: "Radiohead", isStarred: true, userRating: 5)
        album.starredAt = Date(timeIntervalSince1970: 86_400)
        return SearchResult(
            artists: [Artist(id: "ar-1", name: "Björk", isStarred: true), Artist(id: "ar-2", name: "Blur", isStarred: true, userRating: 5)],
            albums: [album, Album(id: "al-2", name: "Parklife", artist: "Blur", isStarred: true)],
            songs: [
                song("so-1", "Karma Police", artist: "Radiohead", album: "OK Computer", rating: 5, day: 1),
                song("so-2", "Song 2", artist: "Blur", rating: 2, day: 3),
                song("so-3", "Hyperballad", artist: "Björk", day: nil),
                song("so-4", "Airbag", artist: "Radiohead", album: "OK Computer", day: 2),
            ]
        )
    }()

    private func apply(_ filters: FavoritesFilters, text: String = "", downloaded: Set<String> = []) -> SearchResult {
        filters.apply(
            to: Self.favorites, text: text,
            isSongDownloaded: { downloaded.contains($0) }, isAlbumDownloaded: { downloaded.contains($0) }
        )
    }

    @Test func byDefaultEverythingShowsNewestFavoriteFirst() {
        let shown = apply(FavoritesFilters())
        // Undated ones last, in the server's order.
        #expect(shown.songs.map(\.id) == ["so-2", "so-4", "so-1", "so-3"])
        #expect(shown.albums.map(\.id) == ["al-1", "al-2"])
        #expect(shown.artists.count == 2)
        #expect(!FavoritesFilters().isFiltering)
    }

    @Test func theScopeShowsOneKind() {
        let songs = apply(FavoritesFilters(scope: .songs))
        #expect(songs.albums.isEmpty && songs.artists.isEmpty && songs.songs.count == 4)
        let artists = apply(FavoritesFilters(scope: .artists))
        #expect(artists.songs.isEmpty && artists.albums.isEmpty && artists.artists.count == 2)
    }

    @Test func textMatchesTitlesArtistsAndAlbums() {
        let shown = apply(FavoritesFilters(), text: " ok computer ")
        #expect(shown.songs.map(\.id) == ["so-4", "so-1"])
        #expect(shown.albums.map(\.id) == ["al-1"])
        #expect(shown.artists.isEmpty)
        // Accents aside.
        #expect(apply(FavoritesFilters(), text: "bjork").artists.map(\.id) == ["ar-1"])
    }

    @Test func ratingAndDownloadedFilter() {
        let love = apply(FavoritesFilters(rating: .love))
        #expect(love.songs.map(\.id) == ["so-1"])
        #expect(love.albums.map(\.id) == ["al-1"])
        #expect(love.artists.map(\.id) == ["ar-2"])
        let downloaded = apply(FavoritesFilters(downloadedOnly: true), downloaded: ["so-3", "al-2"])
        #expect(downloaded.songs.map(\.id) == ["so-3"])
        #expect(downloaded.albums.map(\.id) == ["al-2"])
        // Artists aren't downloads.
        #expect(downloaded.artists.isEmpty)
        #expect(FavoritesFilters(rating: .meh, downloadedOnly: true).summary == "Meh · Downloaded")
    }

    @Test func sortsByNameOrArtist() {
        #expect(apply(FavoritesFilters(sort: .name)).songs.map(\.title) == ["Airbag", "Hyperballad", "Karma Police", "Song 2"])
        #expect(apply(FavoritesFilters(sort: .artist)).songs.map(\.title) == ["Hyperballad", "Song 2", "Airbag", "Karma Police"])
        #expect(apply(FavoritesFilters(sort: .artist)).albums.map(\.name) == ["Parklife", "OK Computer"])
    }

    @Test func clearKeepsTheScopeAndOrder() throws {
        var filters = FavoritesFilters(scope: .albums, rating: .like, downloadedOnly: true, sort: .name)
        filters.clear()
        #expect(filters == FavoritesFilters(scope: .albums, sort: .name))
        let restored = try JSONDecoder().decode(FavoritesFilters.self, from: JSONEncoder().encode(filters))
        #expect(restored == filters)
    }

    @Test func aSavedSongKeepsWhenItWasFavorited() throws {
        let original = Self.song("so-1", "Karma Police", artist: "Radiohead", day: 5)
        let decoded = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.isStarred)
    }
}
