import Foundation

/// What the Favorites screen shows: one kind or all (the scope), a rating,
/// downloaded only, and the order; plus the text typed in its search field,
/// which isn't saved. The rest is remembered on this device until cleared.
public struct FavoritesFilters: Codable, Equatable, Sendable {
    public enum Sort: String, Codable, CaseIterable, Sendable {
        case recentlyFavorited, name, artist

        public var title: String {
            switch self {
            case .recentlyFavorited: "Recently Favorited"
            case .name: "Name"
            case .artist: "Artist"
            }
        }
    }

    public var scope: SearchFilters.Scope
    public var rating: SearchFilters.RatingFilter
    /// Only downloaded songs and albums (artists aren't downloads).
    public var downloadedOnly: Bool
    public var sort: Sort

    public init(
        scope: SearchFilters.Scope = .all, rating: SearchFilters.RatingFilter = .any,
        downloadedOnly: Bool = false, sort: Sort = .recentlyFavorited
    ) {
        self.scope = scope
        self.rating = rating
        self.downloadedOnly = downloadedOnly
        self.sort = sort
    }

    /// A rating or Downloaded Only is on (the scope and order aren't filters).
    public var isFiltering: Bool { rating != .any || downloadedOnly }

    /// The filters in use, e.g. "Love · Downloaded"; `nil` when none.
    public var summary: String? {
        let parts = [rating == .any ? nil : rating.title, downloadedOnly ? "Downloaded" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Clears the rating and Downloaded Only, keeping the scope and order.
    public mutating func clear() {
        rating = .any
        downloadedOnly = false
    }

    /// The favorites that pass, in the chosen order. `text` matches a song's
    /// title, artist or album, an album's name or artist, an artist's name.
    public func apply(
        to favorites: SearchResult, text: String,
        isSongDownloaded: (String) -> Bool, isAlbumDownloaded: (String) -> Bool
    ) -> SearchResult {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ fields: [String?]) -> Bool {
            text.isEmpty || fields.contains { $0?.localizedStandardContains(text) == true }
        }
        let songs = scope == .all || scope == .songs
            ? favorites.songs.filter {
                rating.matches($0.userRating) && (!downloadedOnly || isSongDownloaded($0.id)) && matches([$0.title, $0.artist, $0.album])
            }
            : []
        let albums = scope == .all || scope == .albums
            ? favorites.albums.filter {
                rating.matches($0.userRating) && (!downloadedOnly || isAlbumDownloaded($0.id)) && matches([$0.name, $0.artist])
            }
            : []
        let artists = (scope == .all || scope == .artists) && !downloadedOnly
            ? favorites.artists.filter { rating.matches($0.userRating) && matches([$0.name]) }
            : []
        return SearchResult(
            artists: sorted(artists, starredAt: \.starredAt, name: \.name, artist: \.name),
            albums: sorted(albums, starredAt: \.starredAt, name: \.name, artist: { $0.artist ?? "" }),
            songs: sorted(songs, starredAt: \.starredAt, name: \.title, artist: { $0.artist ?? "" })
        )
    }

    /// Newest favorite first (those the server gave no date keep its order,
    /// after the rest), or by name, or by artist then name. Ties keep the
    /// server's order.
    private func sorted<Item>(
        _ items: [Item], starredAt: (Item) -> Date?, name: (Item) -> String, artist: (Item) -> String
    ) -> [Item] {
        let indexed = Array(items.enumerated())
        let ordered = indexed.sorted { a, b in
            switch sort {
            case .recentlyFavorited:
                let (left, right) = (starredAt(a.element), starredAt(b.element))
                if left != right {
                    guard let left else { return false }
                    guard let right else { return true }
                    return left > right
                }
            case .name:
                let order = name(a.element).localizedStandardCompare(name(b.element))
                if order != .orderedSame { return order == .orderedAscending }
            case .artist:
                let order = artist(a.element).localizedStandardCompare(artist(b.element))
                if order != .orderedSame { return order == .orderedAscending }
                let byName = name(a.element).localizedStandardCompare(name(b.element))
                if byName != .orderedSame { return byName == .orderedAscending }
            }
            return a.offset < b.offset
        }
        return ordered.map(\.element)
    }
}
