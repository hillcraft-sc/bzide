import Foundation
import Observation

/// Rating songs, albums and artists, shared by every screen so a rating set in
/// one place shows everywhere.
///
/// The rating changes at once and the server call follows; if the call fails,
/// it changes back and `error` says why. Choosing the current rating again
/// clears it.
@MainActor
@Observable
public final class RatingModel {
    /// `stars` is 1–5, or `nil` to clear.
    public typealias Send = @Sendable (_ target: StarTarget, _ stars: Int?) async throws(SubsonicError) -> Void

    public private(set) var error: String?

    /// Ratings changed in this session (`nil` inside means cleared). Lists
    /// fetched before the change still carry the old value, so this wins.
    private var overrides: [StarTarget: Rating?] = [:]
    @ObservationIgnored private var inFlight: Set<StarTarget> = []
    @ObservationIgnored private let send: Send

    public init(send: @escaping Send) {
        self.send = send
    }

    /// `fromServer` is the value on the item as fetched (e.g. `album.userRating`).
    public func rating(_ target: StarTarget, fromServer: Int?) -> Rating? {
        if let override = overrides[target] { return override }
        return Rating(serverValue: fromServer)
    }

    /// The user has seen the error.
    public func dismissError() {
        error = nil
    }

    /// Sets `rating`, or clears it if it's already the current one.
    public func choose(_ rating: Rating, for target: StarTarget, fromServer: Int?) async {
        // Same as starring: a second choice while the first is on its way is
        // ignored, so the server never receives the two out of order.
        guard !inFlight.contains(target) else { return }
        let previous = self.rating(target, fromServer: fromServer)
        let new: Rating? = previous == rating ? nil : rating
        overrides[target] = .some(new)
        error = nil
        inFlight.insert(target)
        defer { inFlight.remove(target) }
        do {
            try await send(target, new?.rawValue)
        } catch {
            overrides[target] = .some(previous)
            self.error = error.localizedDescription
        }
    }
}
