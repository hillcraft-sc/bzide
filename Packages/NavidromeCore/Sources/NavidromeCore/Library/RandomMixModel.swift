import Foundation
import Observation

/// "Random Mix": asks the server for random songs and plays them as a new queue.
/// When the server can't be reached, mixes the downloaded songs instead.
@MainActor
@Observable
public final class RandomMixModel {
    public typealias Fetch = @Sendable (_ count: Int) async throws(SubsonicError) -> [Song]

    public private(set) var isLoading = false
    public private(set) var error: String?
    /// Set when the mix came from downloads, to say why it may be smaller.
    public private(set) var notice: String?

    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let downloadedSongs: () -> [Song]
    @ObservationIgnored private let play: ([Song]) -> Void

    /// Enough for a long session without a slow request.
    static let songCount = 50
    static let offlineNotice = "Couldn't reach the server, so this mix is from your downloads."

    public init(fetch: @escaping Fetch, downloadedSongs: @escaping () -> [Song] = { [] }, play: @escaping ([Song]) -> Void) {
        self.fetch = fetch
        self.downloadedSongs = downloadedSongs
        self.play = play
    }

    public func start() async {
        // A second tap while one is loading would replace the queue twice.
        guard !isLoading else { return }
        isLoading = true
        error = nil
        notice = nil
        defer { isLoading = false }
        do {
            let songs = try await fetch(Self.songCount)
            if songs.isEmpty {
                error = "The server returned no songs."
            } else {
                play(songs)
            }
        } catch {
            if Task.isCancelled { return }
            let offline = Array(downloadedSongs().shuffled().prefix(Self.songCount))
            if offline.isEmpty {
                self.error = error.localizedDescription
            } else {
                play(offline)
                notice = Self.offlineNotice
            }
        }
    }
}
