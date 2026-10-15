import Foundation

/// What Search shows: which kind of result (the scope), and filters on
/// rating, favorites and downloads. Remembered until the user clears them.
public struct SearchFilters: Codable, Equatable, Sendable {
    public enum Scope: String, Codable, CaseIterable, Sendable {
        case all, artists, albums, songs

        public var title: String {
            switch self {
            case .all: "All"
            case .artists: "Artists"
            case .albums: "Albums"
            case .songs: "Songs"
            }
        }
    }

    public enum RatingFilter: String, Codable, CaseIterable, Sendable {
        case any, rocks, dontHateIt, meh, unrated

        public var title: String {
            switch self {
            case .any: "Any Rating"
            case .rocks: Rating.rocks.title
            case .dontHateIt: Rating.dontHateIt.title
            case .meh: Rating.meh.title
            case .unrated: "Unrated"
            }
        }

        /// Whether a server rating (Subsonic's 1–5 stars, or none) passes.
        func matches(_ serverRating: Int?) -> Bool {
            let rating = Rating(serverValue: serverRating)
            switch self {
            case .any: return true
            case .rocks: return rating == .rocks
            case .dontHateIt: return rating == .dontHateIt
            case .meh: return rating == .meh
            case .unrated: return rating == nil
            }
        }
    }

    public var scope: Scope
    public var rating: RatingFilter
    public var favoritesOnly: Bool
    /// Only what's on this device: downloaded songs and albums (artists aren't downloads).
    public var downloadedOnly: Bool

    public init(scope: Scope = .all, rating: RatingFilter = .any, favoritesOnly: Bool = false, downloadedOnly: Bool = false) {
        self.scope = scope
        self.rating = rating
        self.favoritesOnly = favoritesOnly
        self.downloadedOnly = downloadedOnly
    }

    /// Any filter beyond the scope is on.
    public var isFiltering: Bool {
        rating != .any || favoritesOnly || downloadedOnly
    }

    /// The filters in use, e.g. "Rocks · Favorites"; `nil` when none.
    public var summary: String? {
        let parts = [
            rating == .any ? nil : rating.title,
            favoritesOnly ? "Favorites" : nil,
            downloadedOnly ? "Downloaded" : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Clears the filters, keeping the scope.
    public mutating func clear() {
        rating = .any
        favoritesOnly = false
        downloadedOnly = false
    }

    /// How many of each kind to ask the server for: 20 of each normally;
    /// more of the chosen kind, or of every kind when filtering, so enough
    /// are left once filtered; none of kinds outside the scope.
    public var requestCounts: (artists: Int, albums: Int, songs: Int) {
        let deep = 100
        let each = isFiltering ? deep : 20
        switch scope {
        case .all: return (each, each, each)
        case .artists: return (deep, 0, 0)
        case .albums: return (0, deep, 0)
        case .songs: return (0, 0, deep)
        }
    }

    /// The results that pass the scope and filters.
    public func apply(
        to results: SearchResult,
        isSongDownloaded: (String) -> Bool,
        isAlbumDownloaded: (String) -> Bool
    ) -> SearchResult {
        let artists = (scope == .all || scope == .artists) && !downloadedOnly
            ? results.artists.filter { passes(rating: $0.userRating, starred: $0.isStarred) }
            : []
        let albums = scope == .all || scope == .albums
            ? results.albums.filter { passes(rating: $0.userRating, starred: $0.isStarred) && (!downloadedOnly || isAlbumDownloaded($0.id)) }
            : []
        let songs = scope == .all || scope == .songs
            ? results.songs.filter { passes(rating: $0.userRating, starred: $0.isStarred) && (!downloadedOnly || isSongDownloaded($0.id)) }
            : []
        return SearchResult(artists: artists, albums: albums, songs: songs)
    }

    private func passes(rating serverRating: Int?, starred: Bool) -> Bool {
        rating.matches(serverRating) && (!favoritesOnly || starred)
    }
}
