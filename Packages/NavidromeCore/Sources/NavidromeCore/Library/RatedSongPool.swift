import Foundation

/// The candidates for My Cuts (songs rated Rocks or Don't Hate It, and
/// favorites), and how many songs were looked through to find them (0 means
/// the server listed none at all). Which favorites count is decided when
/// playing (`qualifies`), since that's a setting.
public struct RatedSongs: Sendable, Equatable {
    public var songs: [Song]
    public var librarySize: Int

    public init(songs: [Song], librarySize: Int) {
        self.songs = songs
        self.librarySize = librarySize
    }
}

/// Finds every song that could be in My Cuts (Mix My Cuts): rated Rocks or
/// Don't Hate It, or a favorite. Subsonic has no way to ask for songs by
/// rating, so this pages through the whole library (each song comes with its
/// rating and favorite) and keeps those. The
/// answer is kept for a while, since looking through a large library takes a
/// few seconds; after that the next request looks again.
public actor RatedSongPool {
    public typealias FetchPage = @Sendable (_ count: Int, _ offset: Int) async throws -> [Song]

    public static let pageSize = PagedListing.pageSize
    /// How long a found list is used before looking again.
    public static let lifetime: TimeInterval = 30 * 60

    private let fetchPage: FetchPage
    private let now: @Sendable () -> Date
    private var found: (songs: RatedSongs, at: Date)?
    private var looking: Task<RatedSongs, Error>?

    public init(fetchPage: @escaping FetchPage, now: @escaping @Sendable () -> Date = { .now }) {
        self.fetchPage = fetchPage
        self.now = now
    }

    /// The rated songs, from the last look if it's recent enough.
    public func songs() async throws -> RatedSongs {
        if let found, now().timeIntervalSince(found.at) < Self.lifetime { return found.songs }
        // Two requests at once share one look through the library.
        if let looking { return try await looking.value }
        let task = Task { try await Self.lookThrough(fetchPage) }
        looking = task
        defer { looking = nil }
        let result = try await task.value
        found = (result, now())
        return result
    }

    /// A rating of Rocks or Don't Hate It (3 or more of the server's 5 stars).
    static func isRated(_ song: Song) -> Bool {
        guard let rating = Rating(serverValue: song.userRating) else { return false }
        return rating == .rocks || rating == .dontHateIt
    }

    /// Whether a song is in My Cuts: rated Rocks or Don't Hate It, or (when
    /// favorites are included) a favorite, unless it's rated Meh, the more
    /// specific verdict.
    public static func qualifies(_ song: Song, includeFavorites: Bool) -> Bool {
        if isRated(song) { return true }
        return includeFavorites && song.isStarred && Rating(serverValue: song.userRating) != .meh
    }

    /// The whole library, keeping songs rated Rocks or Don't Hate It, or favorites.
    private static func lookThrough(_ fetchPage: @escaping FetchPage) async throws -> RatedSongs {
        let all = try await PagedListing.all(fetchPage)
        var seen = Set<String>()
        let candidates = all.filter { (isRated($0) || $0.isStarred) && seen.insert($0.id).inserted }
        return RatedSongs(songs: candidates, librarySize: all.count)
    }
}
