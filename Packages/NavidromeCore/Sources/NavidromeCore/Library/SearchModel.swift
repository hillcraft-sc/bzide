import Foundation
import Observation

/// Search as you type. Waits for a pause in typing before asking the server,
/// keeps the previous results on screen while a new search runs, and drops any
/// reply that arrives after a newer search started.
@MainActor
@Observable
public final class SearchModel {
    public typealias Fetch = @Sendable (_ query: String) async throws(SubsonicError) -> SearchResult

    public private(set) var query = ""
    /// `nil` until the first search finishes, and again when the query is cleared.
    public private(set) var results: SearchResult?
    public private(set) var isSearching = false
    public private(set) var error: String?

    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let scheduler: any Scheduling
    @ObservationIgnored private var pendingSearch: ScheduledAction?
    @ObservationIgnored private(set) var searchTask: Task<Void, Never>?
    /// Bumped by every change of query; a reply for an older query is dropped.
    @ObservationIgnored private var generation = 0

    /// How long typing must pause before a search is sent.
    static let typingPause: Duration = .milliseconds(300)

    public init(scheduler: any Scheduling, fetch: @escaping Fetch) {
        self.scheduler = scheduler
        self.fetch = fetch
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
            results = nil
            isSearching = false
            error = nil
            return
        }
        let thisSearch = generation
        pendingSearch = scheduler.schedule(after: Self.typingPause) { [weak self] in
            self?.startSearch(trimmed, generation: thisSearch)
        }
    }

    /// Runs the current query again right away, e.g. after an error.
    public func retry() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        generation += 1
        pendingSearch?.cancel()
        pendingSearch = nil
        startSearch(trimmed, generation: generation)
    }

    private func startSearch(_ query: String, generation thisSearch: Int) {
        pendingSearch = nil
        searchTask?.cancel()
        isSearching = true
        error = nil
        searchTask = Task { [weak self, fetch] in
            let result: Result<SearchResult, SubsonicError>
            do throws(SubsonicError) {
                result = .success(try await fetch(query))
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
