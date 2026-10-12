import Foundation
import Observation

/// One album cover per genre, for the genre tiles. Each genre's cover is
/// fetched the first time its tile appears and then kept for the session, so
/// scrolling the grid doesn't fetch again. A genre with no cover is remembered
/// as such.
@MainActor
@Observable
public final class GenreCovers {
    public typealias Fetch = @Sendable (_ genre: String) async throws(SubsonicError) -> String?

    private var covers: [String: String] = [:]
    @ObservationIgnored private var settled: Set<String> = []
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private let fetch: Fetch

    public init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    public func coverArtID(for genre: String) -> String? {
        covers[genre]
    }

    public func load(_ genre: String) async {
        guard !settled.contains(genre), inFlight.insert(genre).inserted else { return }
        defer { inFlight.remove(genre) }
        do {
            covers[genre] = try await fetch(genre)
            settled.insert(genre)
        } catch {
            // Left unsettled: the tile tries again next time it appears.
        }
    }
}
