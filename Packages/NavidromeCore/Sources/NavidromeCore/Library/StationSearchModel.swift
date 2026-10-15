import Foundation
import Observation

/// Finding stations on Radio Browser for the Find Stations screen: a name to
/// search for, Country and Genre filters, and an order. With none of them
/// set it shows what's popular right now. Typing searches once the user
/// pauses; a newer search always wins, so a slow answer for older text is
/// dropped. Results come a page at a time, the next when the list reaches
/// its end. Only used once the user has turned on Find Stations Online.
@MainActor
@Observable
public final class StationSearchModel {
    public struct Sources: Sendable {
        public var stations: @Sendable (RadioBrowserClient.Query, Int) async throws -> [RadioBrowserStation]
        public var countries: @Sendable () async throws -> [RadioBrowserClient.Country]
        public var tags: @Sendable () async throws -> [RadioBrowserClient.Tag]
        public var countPlay: @Sendable (String) async throws -> Void

        /// `stations` gets the query and the offset of the page.
        public init(
            stations: @escaping @Sendable (RadioBrowserClient.Query, Int) async throws -> [RadioBrowserStation],
            countries: @escaping @Sendable () async throws -> [RadioBrowserClient.Country],
            tags: @escaping @Sendable () async throws -> [RadioBrowserClient.Tag],
            countPlay: @escaping @Sendable (String) async throws -> Void
        ) {
            self.stations = stations
            self.countries = countries
            self.tags = tags
            self.countPlay = countPlay
        }
    }

    public var query = RadioBrowserClient.Query()
    public private(set) var state: LoadState<[RadioBrowserStation]> = .loading
    /// Whether another page may follow the stations shown.
    public private(set) var hasMore = false
    public private(set) var isLoadingMore = false
    /// Why the next page didn't load; scrolling to the end again retries.
    public private(set) var moreError: String?

    /// For the filter pickers, fetched when first opened.
    public private(set) var countries: LoadState<[RadioBrowserClient.Country]> = .loading
    public private(set) var tags: LoadState<[RadioBrowserClient.Tag]> = .loading

    @ObservationIgnored private let pause: Duration
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private let sources: Sources
    @ObservationIgnored private var generation = 0
    /// What the shown stations are for, and how many Radio Browser returned
    /// for it (before duplicates were removed): the next page's offset.
    @ObservationIgnored private var shownQuery: RadioBrowserClient.Query?
    @ObservationIgnored private var fetchedCount = 0

    public init(sources: Sources, pause: Duration = .milliseconds(400), pageSize: Int = RadioBrowserClient.pageSize) {
        self.sources = sources
        self.pause = pause
        self.pageSize = pageSize
    }

    public var isShowingPopular: Bool { query.isPopular }

    /// Searches for the current query from the first page. Call it whenever
    /// the query changes; after a change to the name it waits for typing to
    /// pause, so most calls end early.
    public func update() async {
        generation += 1
        let mine = generation
        let query = query
        if query == shownQuery, case .loaded = state { return }
        if query.name != shownQuery?.name, !query.name.isEmpty {
            try? await Task.sleep(for: pause)
            guard mine == generation, !Task.isCancelled else { return }
        }
        state = .loading
        hasMore = false
        moreError = nil
        do {
            let page = try await sources.stations(query, 0)
            guard mine == generation, !Task.isCancelled else { return }
            shownQuery = query
            fetchedCount = page.count
            hasMore = page.count >= pageSize
            state = .loaded(Self.unique(page))
        } catch {
            guard mine == generation, !Task.isCancelled else { return }
            shownQuery = nil
            state = .failed(Self.message(for: error))
        }
    }

    /// Fetches the next page, when the list reaches its end.
    public func loadMore() async {
        guard hasMore, !isLoadingMore, let shownQuery, case .loaded(let shown) = state else { return }
        let mine = generation
        isLoadingMore = true
        moreError = nil
        defer { if mine == generation { isLoadingMore = false } }
        do {
            let page = try await sources.stations(shownQuery, fetchedCount)
            // A new search started meanwhile: this page belongs to the old one.
            guard mine == generation, case .loaded(let current) = state, current == shown else { return }
            fetchedCount += page.count
            hasMore = page.count >= pageSize
            state = .loaded(Self.unique(shown + page))
        } catch {
            guard mine == generation, !Task.isCancelled else { return }
            moreError = Self.message(for: error)
        }
    }

    /// Fetches the countries for the Country filter, once.
    public func loadCountries() async {
        if case .loaded = countries { return }
        countries = .loading
        do {
            countries = .loaded(try await sources.countries())
        } catch {
            if !Task.isCancelled { countries = .failed(Self.message(for: error)) }
        }
    }

    /// Fetches the genres for the Genre filter, once.
    public func loadTags() async {
        if case .loaded = tags { return }
        tags = .loading
        do {
            tags = .loaded(try await sources.tags())
        } catch {
            if !Task.isCancelled { tags = .failed(Self.message(for: error)) }
        }
    }

    /// Tells Radio Browser a station found there was played. A failure
    /// doesn't matter to the user, so it's ignored.
    public func played(_ station: RadioBrowserStation) {
        let countPlay = sources.countPlay
        Task { try? await countPlay(station.id) }
    }

    /// Radio Browser lists some stations more than once; one per stream.
    static func unique(_ stations: [RadioBrowserStation]) -> [RadioBrowserStation] {
        var seen = Set<URL>()
        return stations.filter { seen.insert($0.streamURL).inserted }
    }

    static func message(for error: any Error) -> String {
        if error is URLError { return "Couldn't reach Radio Browser. Check your connection and try again." }
        return "Radio Browser's answer couldn't be read. Try again later."
    }
}
