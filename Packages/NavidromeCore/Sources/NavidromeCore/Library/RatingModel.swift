import Foundation
import Observation

/// Rating songs, albums and artists, shared by every screen so a rating set in
/// one place shows everywhere.
///
/// Ratings are kept as the server's 1–5 stars, so they show exactly as set in
/// either style: Meh, Like or Love (`choose(_:for:fromServer:)`) or stars
/// (`choose(stars:for:fromServer:)`).
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

    /// Stars changed in this session (`nil` inside means cleared). Lists
    /// fetched before the change still carry the old value, so this wins.
    private var overrides: [StarTarget: Int?] = [:]
    @ObservationIgnored private var inFlight: Set<StarTarget> = []
    @ObservationIgnored private let send: Send

    public init(send: @escaping Send) {
        self.send = send
    }

    /// 1–5, or `nil` if unrated. `fromServer` is the value on the item as
    /// fetched (e.g. `album.userRating`).
    public func stars(_ target: StarTarget, fromServer: Int?) -> Int? {
        if let override = overrides[target] { return override }
        return Rating.stars(serverValue: fromServer)
    }

    /// The simplified rating those stars show as.
    public func rating(_ target: StarTarget, fromServer: Int?) -> Rating? {
        Rating(serverValue: stars(target, fromServer: fromServer))
    }

    /// The user has seen the error.
    public func dismissError() {
        error = nil
    }

    /// Sets `rating`, or clears it if it's already the current one.
    public func choose(_ rating: Rating, for target: StarTarget, fromServer: Int?) async {
        let current = self.rating(target, fromServer: fromServer)
        await set(current == rating ? nil : rating.rawValue, for: target, fromServer: fromServer)
    }

    /// Sets 1–5 stars, or clears them if they're already the current ones.
    public func choose(stars: Int, for target: StarTarget, fromServer: Int?) async {
        guard (1...5).contains(stars) else { return }
        let current = self.stars(target, fromServer: fromServer)
        await set(current == stars ? nil : stars, for: target, fromServer: fromServer)
    }

    public func clear(_ target: StarTarget, fromServer: Int?) async {
        await set(nil, for: target, fromServer: fromServer)
    }

    private func set(_ new: Int?, for target: StarTarget, fromServer: Int?) async {
        // Same as starring: a second choice while the first is on its way is
        // ignored, so the server never receives the two out of order.
        guard !inFlight.contains(target) else { return }
        let previous = stars(target, fromServer: fromServer)
        guard new != previous else { return }
        overrides[target] = .some(new)
        error = nil
        inFlight.insert(target)
        defer { inFlight.remove(target) }
        do {
            try await send(target, new)
        } catch {
            overrides[target] = .some(previous)
            self.error = error.localizedDescription
        }
    }
}
