import Foundation
import Observation

/// Starring and unstarring, shared by every screen so an album starred in one
/// place shows as starred everywhere.
///
/// The star flips at once and the server call follows; if the call fails, the
/// star flips back and `error` says why.
@MainActor
@Observable
public final class StarModel {
    public typealias Send = @Sendable (_ target: StarTarget, _ starred: Bool) async throws(SubsonicError) -> Void

    public private(set) var error: String?

    /// Stars changed in this session. Lists fetched before the change still
    /// carry the old flag, so this wins over what the server sent.
    private var overrides: [StarTarget: Bool] = [:]
    @ObservationIgnored private var inFlight: Set<StarTarget> = []
    @ObservationIgnored private let send: Send

    public init(send: @escaping Send) {
        self.send = send
    }

    /// `fromServer` is the flag on the item as fetched (e.g. `album.isStarred`).
    public func isStarred(_ target: StarTarget, fromServer: Bool) -> Bool {
        overrides[target] ?? fromServer
    }

    /// The user has seen the error.
    public func dismissError() {
        error = nil
    }

    public func toggle(_ target: StarTarget, fromServer: Bool) async {
        await set(target, starred: !isStarred(target, fromServer: fromServer), fromServer: fromServer)
    }

    /// Stars or unstars, whatever it was: for "favorite this" from Siri or the
    /// lock screen, where a second press mustn't undo the first. Returns
    /// whether the server took it; already as asked counts as taken, and isn't
    /// sent again.
    @discardableResult
    public func set(_ target: StarTarget, starred: Bool, fromServer: Bool) async -> Bool {
        // A second tap while the first is still on its way is ignored, so the
        // server never receives the two out of order.
        guard !inFlight.contains(target) else { return false }
        let wasStarred = isStarred(target, fromServer: fromServer)
        guard wasStarred != starred else { return true }
        overrides[target] = starred
        error = nil
        inFlight.insert(target)
        defer { inFlight.remove(target) }
        do {
            try await send(target, starred)
            return true
        } catch {
            overrides[target] = wasStarred
            self.error = error.localizedDescription
            return false
        }
    }
}
