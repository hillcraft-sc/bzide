import Foundation
import Observation

/// Plays or queues an album from a menu without opening it (e.g. long-pressing
/// a Recently Added cover): fetches the album's songs, then hands them on.
@MainActor
@Observable
public final class AlbumQueueModel {
    public enum Action: Sendable, Equatable {
        case play, playNext, addToQueue
    }

    public typealias Fetch = @Sendable (_ albumID: String) async throws(SubsonicError) -> [Song]

    public private(set) var error: String?

    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let perform: (Action, [Song]) -> Void
    @ObservationIgnored private var inFlight: Set<String> = []

    public init(fetch: @escaping Fetch, perform: @escaping (Action, [Song]) -> Void) {
        self.fetch = fetch
        self.perform = perform
    }

    public func perform(_ action: Action, albumID: String) async {
        // A second choice for the same album while it loads would queue it twice.
        guard !inFlight.contains(albumID) else { return }
        inFlight.insert(albumID)
        defer { inFlight.remove(albumID) }
        error = nil
        do {
            let songs = try await fetch(albumID)
            if songs.isEmpty {
                error = "This album has no songs."
            } else {
                perform(action, songs)
            }
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
        }
    }

    /// The user has seen the error.
    public func dismissError() {
        error = nil
    }
}
