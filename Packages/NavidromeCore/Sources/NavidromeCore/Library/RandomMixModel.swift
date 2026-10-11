import Foundation
import Observation

/// "Random Mix": asks the server for random songs and plays them as a new queue.
@MainActor
@Observable
public final class RandomMixModel {
    public typealias Fetch = @Sendable (_ count: Int) async throws(SubsonicError) -> [Song]

    public private(set) var isLoading = false
    public private(set) var error: String?

    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let play: ([Song]) -> Void

    /// Enough for a long session without a slow request.
    static let songCount = 50

    public init(fetch: @escaping Fetch, play: @escaping ([Song]) -> Void) {
        self.fetch = fetch
        self.play = play
    }

    public func start() async {
        // A second tap while one is loading would replace the queue twice.
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let songs = try await fetch(Self.songCount)
            if songs.isEmpty {
                error = "The server returned no songs."
            } else {
                play(songs)
            }
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
