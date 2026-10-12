import Foundation
import Observation

/// Starts a radio station: finds its stream (reading a playlist file if
/// that's what the station's address is), then plays it as the whole queue.
@MainActor
@Observable
public final class RadioPlayer {
    /// The station being started, for a spinner on its row.
    public private(set) var startingStationID: String?
    public private(set) var error: String?

    @ObservationIgnored private let fetch: RadioPlaylist.Fetch
    @ObservationIgnored private let play: (Song) -> Void

    public init(fetchPlaylist: @escaping RadioPlaylist.Fetch, play: @escaping (Song) -> Void) {
        fetch = fetchPlaylist
        self.play = play
    }

    public func start(_ station: RadioStation) async {
        // One at a time: a second tap while the first resolves is ignored.
        guard startingStationID == nil else { return }
        startingStationID = station.id
        error = nil
        defer { startingStationID = nil }
        do {
            let stream = try await RadioPlaylist.streamURL(for: station, fetch: fetch)
            play(Song(station: station, stream: stream))
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
        }
    }

    public func dismissError() {
        error = nil
    }
}
