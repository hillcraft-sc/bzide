import Foundation
import Observation

/// Follows what a radio station is playing, whether or not any screen is
/// open (the lock screen needs it with the app in the background): each time
/// the station or its announced title changes, or Look Up Songs Online is
/// turned on or off, it looks the song up in the library (`OnAirMatchModel`)
/// and, with lookups on, on MusicBrainz (`OnAirInfoModel`), and sets the
/// engine's on-air cover: the library's own, else MusicBrainz's, else none
/// (the station's logo).
@MainActor
public final class OnAirTracker {
    private let engine: PlaybackEngine
    private let match: OnAirMatchModel
    private let info: OnAirInfoModel
    private let lookUpOnline: @MainActor () -> Bool
    private var refreshing: Task<Void, Never>?

    public init(engine: PlaybackEngine, match: OnAirMatchModel, info: OnAirInfoModel, lookUpOnline: @escaping @MainActor () -> Bool) {
        self.engine = engine
        self.match = match
        self.info = info
        self.lookUpOnline = lookUpOnline
    }

    /// Starts following, and catches up with what's playing now.
    public func start() {
        observe()
        changed()
    }

    private func observe() {
        withObservationTracking {
            _ = engine.queue.current?.id
            _ = engine.streamTitle
            _ = lookUpOnline()
        } onChange: { [weak self] in
            // Called before the change lands: act once it has.
            Task { @MainActor in
                self?.observe()
                self?.changed()
            }
        }
    }

    private func changed() {
        refreshing?.cancel()
        refreshing = Task { await refresh() }
    }

    /// Looks the song up and sets the cover. Exposed for tests.
    func refresh() async {
        let current = engine.queue.current?.song
        let live = current?.isLive == true
        await match.update(announced: live ? engine.streamTitle : nil, stationName: current?.title)
        await info.update(match.onAir, enabled: live && lookUpOnline())
        guard !Task.isCancelled else { return }
        engine.onAirCoverArtID = live
            ? match.match?.coverArtID ?? info.details?.coverURL.map(StationLogo.coverArtID)
            : nil
    }
}
