import Foundation
import Observation

/// What a screen shows while it fetches something from the server.
public enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)
}

extension LoadState: Equatable where Value: Equatable {}
extension LoadState: Sendable where Value: Sendable {}

/// Fetches one thing for a screen (the artist index, an album, a playlist) and
/// keeps it. Screens call `load()` when they appear, to retry, and to refresh.
///
/// A refresh keeps the current content on screen. If it fails, the content stays
/// and `refreshError` says why, rather than replacing a working screen with an error.
@MainActor
@Observable
public final class LoadModel<Value: Sendable> {
    public private(set) var state: LoadState<Value> = .loading
    public private(set) var refreshError: String?

    @ObservationIgnored private let fetch: @Sendable () async throws(SubsonicError) -> Value
    @ObservationIgnored private var isFetching = false

    public init(fetch: @escaping @Sendable () async throws(SubsonicError) -> Value) {
        self.fetch = fetch
    }

    public var value: Value? {
        if case .loaded(let value) = state { value } else { nil }
    }

    public func load() async {
        // A second call while one is in flight (appear + pull to refresh) adds nothing.
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        refreshError = nil
        if value == nil { state = .loading }
        do {
            state = .loaded(try await fetch())
        } catch {
            // The screen went away mid-load; it loads again when it comes back.
            if Task.isCancelled { return }
            if value == nil {
                state = .failed(error.localizedDescription)
            } else {
                refreshError = error.localizedDescription
            }
        }
    }
}
