import Foundation
import Observation

/// The orders the album list can be shown in.
public enum AlbumSort: String, CaseIterable, Sendable {
    case newest
    case recentlyPlayed
    case mostPlayed
    case name
    case artist
    case random
    case starred

    public var title: String {
        switch self {
        case .newest: "Recently Added"
        case .recentlyPlayed: "Recently Played"
        case .mostPlayed: "Most Played"
        case .name: "Name"
        case .artist: "Artist"
        case .random: "Random"
        case .starred: "Favorites"
        }
    }

    var listType: AlbumListType {
        switch self {
        case .newest: .newest
        case .recentlyPlayed: .recent
        case .mostPlayed: .frequent
        case .name: .alphabeticalByName
        case .artist: .alphabeticalByArtist
        case .random: .random
        case .starred: .starred
        }
    }

    /// Random has no stable order to page through: every request is a fresh
    /// pick, so later pages would repeat earlier albums. It shows one page, and
    /// a refresh picks again.
    var isPaged: Bool { self != .random }
}

/// The album list: one sort at a time, fetched a page at a time as the user
/// scrolls. Same refresh rules as `LoadModel`.
@MainActor
@Observable
public final class AlbumsModel {
    public typealias Fetch = @Sendable (_ type: AlbumListType, _ size: Int, _ offset: Int) async throws(SubsonicError) -> [Album]

    public private(set) var sort: AlbumSort
    public private(set) var state: LoadState<[Album]> = .loading
    public private(set) var refreshError: String?
    public private(set) var isLoadingMore = false
    /// Set when fetching the next page failed. Scrolling won't retry by itself;
    /// `loadMore()` does.
    public private(set) var loadMoreError: String?

    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private var hasMore = false
    /// Where the next page starts on the server. Not `albums.count`: duplicates
    /// are dropped, and the server's offset must not drift because of that.
    @ObservationIgnored private var nextOffset = 0
    /// Bumped by every first-page load, so a reply for an older load or another
    /// sort is dropped instead of overwriting newer content.
    @ObservationIgnored private var generation = 0

    static let pageSize = 40
    /// Fetch the next page once the user is this many albums from the end.
    static let prefetchDistance = 10

    public init(sort: AlbumSort = .newest, fetch: @escaping Fetch) {
        self.sort = sort
        self.fetch = fetch
    }

    public var albums: [Album]? {
        if case .loaded(let albums) = state { albums } else { nil }
    }

    /// First load, retry, and pull to refresh.
    public func load() async {
        generation += 1
        let thisLoad = generation
        isLoadingMore = false
        refreshError = nil
        loadMoreError = nil
        let hadContent = albums != nil
        if !hadContent { state = .loading }
        do {
            let page = try await fetch(sort.listType, Self.pageSize, 0)
            guard thisLoad == generation else { return }
            state = .loaded(Self.withoutDuplicates(page, after: []))
            nextOffset = page.count
            hasMore = sort.isPaged && page.count == Self.pageSize
        } catch {
            guard thisLoad == generation, !Task.isCancelled else { return }
            if hadContent {
                refreshError = error.localizedDescription
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Switches to another order. It's a different list, so the old one goes.
    public func setSort(_ newSort: AlbumSort) async {
        guard newSort != sort else { return }
        sort = newSort
        state = .loading
        hasMore = false
        await load()
    }

    /// Called as each album appears on screen; fetches the next page near the end.
    public func loadMoreIfNeeded(after album: Album) async {
        guard loadMoreError == nil, let albums,
              let index = albums.firstIndex(where: { $0.id == album.id }),
              index >= albums.count - Self.prefetchDistance
        else { return }
        await loadMore()
    }

    /// Fetches the next page. Also the retry after `loadMoreError`.
    public func loadMore() async {
        guard hasMore, !isLoadingMore, albums != nil else { return }
        let thisLoad = generation
        isLoadingMore = true
        loadMoreError = nil
        do {
            let page = try await fetch(sort.listType, Self.pageSize, nextOffset)
            guard thisLoad == generation, let albums else { return }
            state = .loaded(albums + Self.withoutDuplicates(page, after: albums))
            nextOffset += page.count
            hasMore = page.count == Self.pageSize
            isLoadingMore = false
        } catch {
            guard thisLoad == generation else { return }
            isLoadingMore = false
            if !Task.isCancelled { loadMoreError = error.localizedDescription }
        }
    }

    /// The library can change between page requests, shifting albums across a
    /// page boundary; an album already shown must not appear twice.
    private static func withoutDuplicates(_ page: [Album], after shown: [Album]) -> [Album] {
        var seen = Set(shown.map(\.id))
        return page.filter { seen.insert($0.id).inserted }
    }
}
