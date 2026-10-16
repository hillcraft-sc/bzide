import Foundation

/// Fetches a whole list a page at a time, a few pages at once, until a page
/// comes back short (the end). Shared by everything that has to look through
/// the library (Mix My Cuts, browsing Search by filter).
enum PagedListing {
    static let pageSize = 500
    static let parallelPages = 4

    static func all<Item: Sendable>(
        _ fetchPage: @escaping @Sendable (_ count: Int, _ offset: Int) async throws -> [Item]
    ) async throws -> [Item] {
        var items: [Item] = []
        var offset = 0
        while true {
            let pages = try await withThrowingTaskGroup(of: (Int, [Item]).self) { group in
                for index in 0..<parallelPages {
                    let pageOffset = offset + index * pageSize
                    group.addTask { (index, try await fetchPage(pageSize, pageOffset)) }
                }
                var results: [(Int, [Item])] = []
                for try await page in group { results.append(page) }
                return results.sorted { $0.0 < $1.0 }.map(\.1)
            }
            items += pages.flatMap { $0 }
            if pages.contains(where: { $0.count < pageSize }) { return items }
            offset += parallelPages * pageSize
        }
    }
}

/// The whole library, for browsing Search by filter with nothing typed:
/// every artist (`getArtists`), every album (`getAlbumList2`, alphabetically,
/// in pages) and every song (an empty `search3`, which Navidrome supports;
/// other servers may list none). Standard Subsonic wherever possible, so
/// artists and albums can be browsed on any server. Each list is kept for a
/// while, since a large library takes a few seconds to fetch.
public actor LibraryCatalog {
    public struct Sources: Sendable {
        public var artists: @Sendable () async throws -> [Artist]
        public var albumsPage: @Sendable (_ count: Int, _ offset: Int) async throws -> [Album]
        public var songsPage: @Sendable (_ count: Int, _ offset: Int) async throws -> [Song]

        public init(
            artists: @escaping @Sendable () async throws -> [Artist],
            albumsPage: @escaping @Sendable (Int, Int) async throws -> [Album],
            songsPage: @escaping @Sendable (Int, Int) async throws -> [Song]
        ) {
            self.artists = artists
            self.albumsPage = albumsPage
            self.songsPage = songsPage
        }
    }

    /// How long a fetched list is used before fetching again.
    public static let lifetime: TimeInterval = 30 * 60

    private let sources: Sources
    private let now: @Sendable () -> Date
    private var artists: (items: [Artist], at: Date)?
    private var albums: (items: [Album], at: Date)?
    private var songs: (items: [Song], at: Date)?

    public init(sources: Sources, now: @escaping @Sendable () -> Date = { .now }) {
        self.sources = sources
        self.now = now
    }

    /// Everything in the scope: one kind, or all three.
    public func browse(_ scope: SearchFilters.Scope) async throws -> SearchResult {
        SearchResult(
            artists: scope == .all || scope == .artists ? try await allArtists() : [],
            albums: scope == .all || scope == .albums ? try await allAlbums() : [],
            songs: scope == .all || scope == .songs ? try await allSongs() : []
        )
    }

    private func allArtists() async throws -> [Artist] {
        if let artists, isFresh(artists.at) { return artists.items }
        let fetched = try await sources.artists()
        artists = (fetched, now())
        return fetched
    }

    /// Every album, for Spin It Back.
    public func albums() async throws -> [Album] {
        try await allAlbums()
    }

    private func allAlbums() async throws -> [Album] {
        if let albums, isFresh(albums.at) { return albums.items }
        let fetched = Self.unique(try await PagedListing.all(sources.albumsPage))
        albums = (fetched, now())
        return fetched
    }

    private func allSongs() async throws -> [Song] {
        if let songs, isFresh(songs.at) { return songs.items }
        let fetched = Self.unique(try await PagedListing.all(sources.songsPage))
        songs = (fetched, now())
        return fetched
    }

    /// Fetches every list again now (Settings > Refresh Library), so the
    /// next browse has the server's latest. If the fetch fails, the lists
    /// are fetched again the next time they're needed.
    public func refresh() async throws {
        artists = nil
        albums = nil
        songs = nil
        _ = try await browse(.all)
    }

    private func isFresh(_ date: Date) -> Bool {
        now().timeIntervalSince(date) < Self.lifetime
    }

    /// Paging can repeat an item if the library changes mid-fetch.
    private static func unique<Item: Identifiable>(_ items: [Item]) -> [Item] where Item.ID == String {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
