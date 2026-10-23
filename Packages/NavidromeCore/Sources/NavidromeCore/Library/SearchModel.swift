import Foundation
import Observation

/// What Search asks for: the text (empty when browsing), and how many of
/// each kind of result.
public struct SearchRequest: Equatable, Sendable {
    public var query: String
    public var artistCount: Int
    public var albumCount: Int
    public var songCount: Int
    /// Nothing typed but a filter on: everything in the scope, from the
    /// whole library (see `LibraryCatalog`).
    public var isBrowse: Bool
    public var scope: SearchFilters.Scope
}

/// Search as you type. Waits for a pause in typing before asking the server,
/// keeps the previous results on screen while a new search runs, and drops any
/// reply that arrives after a newer search started.
///
/// Filters (`filters`) narrow the results: a scope (one kind of result) and
/// rating, favorites and downloaded filters. Changing them searches again at
/// once. With nothing typed and a filter on, it browses the whole library.
@MainActor
@Observable
public final class SearchModel {
    public typealias Fetch = @Sendable (_ query: String) async throws(SubsonicError) -> SearchResult
    public typealias Run = @Sendable (_ request: SearchRequest) async throws(SubsonicError) -> SearchResult

    public private(set) var query = ""
    /// `nil` until the first search finishes, and again when the query is cleared.
    public private(set) var results: SearchResult? {
        didSet { updateVisibleResults() }
    }
    public private(set) var isSearching = false
    public private(set) var error: String?

    /// The scope and filters. Setting them searches again.
    public var filters = SearchFilters() {
        didSet {
            guard filters != oldValue else { return }
            updateVisibleResults()
            filtersChanged()
        }
    }

    /// The results that pass the scope and filters. Worked out when the
    /// results, filters or downloads change, not each time it's read: browsing
    /// can hold the whole library, and a list rebuilt on every redraw makes
    /// SwiftUI compare every song again each time (which froze the app).
    public private(set) var visibleResults: SearchResult?

    /// Nothing typed, but a filter on: showing everything that matches.
    public var isBrowsing: Bool {
        trimmedQuery.isEmpty && filters.isFiltering
    }

    @ObservationIgnored private let run: Run
    @ObservationIgnored private let isSongDownloaded: (String) -> Bool
    @ObservationIgnored private let isAlbumDownloaded: (String) -> Bool
    @ObservationIgnored private let scheduler: any Scheduling
    @ObservationIgnored private var pendingSearch: ScheduledAction?
    @ObservationIgnored private(set) var searchTask: Task<Void, Never>?
    /// Bumped by every change of query; a reply for an older query is dropped.
    @ObservationIgnored private var generation = 0

    /// How long typing must pause before a search is sent.
    static let typingPause: Duration = .milliseconds(300)

    public init(
        scheduler: any Scheduling,
        isSongDownloaded: @escaping (String) -> Bool = { _ in false },
        isAlbumDownloaded: @escaping (String) -> Bool = { _ in false },
        run: @escaping Run
    ) {
        self.scheduler = scheduler
        self.isSongDownloaded = isSongDownloaded
        self.isAlbumDownloaded = isAlbumDownloaded
        self.run = run
    }

    /// A search by text alone (no counts or browsing).
    public convenience init(scheduler: any Scheduling, fetch: @escaping Fetch) {
        self.init(scheduler: scheduler, run: { request async throws(SubsonicError) in try await fetch(request.query) })
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func updateQuery(_ newQuery: String) {
        guard newQuery != query else { return }
        query = newQuery
        generation += 1
        pendingSearch?.cancel()
        pendingSearch = nil
        searchTask?.cancel()
        searchTask = nil

        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showNothingOrBrowse()
            return
        }
        let thisSearch = generation
        pendingSearch = scheduler.schedule(after: Self.typingPause) { [weak self] in
            self?.startSearch(trimmed, generation: thisSearch)
        }
    }

    /// Downloads changed, which Downloaded Only depends on.
    public func downloadsChanged() {
        updateVisibleResults()
    }

    private func updateVisibleResults() {
        visibleResults = results.map { filters.apply(to: $0, isSongDownloaded: isSongDownloaded, isAlbumDownloaded: isAlbumDownloaded) }
    }

    /// Runs the current query again right away, e.g. after an error.
    public func retry() {
        let trimmed = trimmedQuery
        guard !trimmed.isEmpty || filters.isFiltering else { return }
        generation += 1
        pendingSearch?.cancel()
        pendingSearch = nil
        startSearch(trimmed, generation: generation)
    }

    private func filtersChanged() {
        generation += 1
        pendingSearch?.cancel()
        pendingSearch = nil
        searchTask?.cancel()
        searchTask = nil
        if trimmedQuery.isEmpty {
            showNothingOrBrowse()
        } else {
            startSearch(trimmedQuery, generation: generation)
        }
    }

    /// Nothing typed: browse if a filter is on, otherwise show nothing (the
    /// genre grid).
    private func showNothingOrBrowse() {
        guard filters.isFiltering else {
            results = nil
            isSearching = false
            error = nil
            return
        }
        startSearch("", generation: generation)
    }

    private func startSearch(_ query: String, generation thisSearch: Int) {
        pendingSearch = nil
        searchTask?.cancel()
        isSearching = true
        error = nil
        let counts = filters.requestCounts
        let request = SearchRequest(
            query: query, artistCount: counts.artists, albumCount: counts.albums, songCount: counts.songs,
            isBrowse: query.isEmpty, scope: filters.scope
        )
        searchTask = Task { [weak self, run] in
            let result: Result<SearchResult, SubsonicError>
            do throws(SubsonicError) {
                result = .success(try await run(request))
            } catch {
                result = .failure(error)
            }
            self?.finishSearch(result, generation: thisSearch)
        }
    }

    private func finishSearch(_ result: Result<SearchResult, SubsonicError>, generation thisSearch: Int) {
        guard thisSearch == generation else { return }
        isSearching = false
        switch result {
        case .success(let found):
            results = found
        case .failure(let failure):
            error = failure.localizedDescription
        }
    }
}
