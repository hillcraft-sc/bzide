import Foundation
import Synchronization
@testable import NavidromeCore

@MainActor
final class FakeScrobbler: ScrobbleSubmitting {
    private(set) var nowPlayingSongIDs: [String] = []
    private(set) var submitted: [PendingScrobble] = []

    func nowPlaying(songID: String) {
        nowPlayingSongIDs.append(songID)
    }

    func submit(_ scrobble: PendingScrobble) {
        submitted.append(scrobble)
    }
}

/// Records server calls; fails while `isOffline` is set.
final class FakeScrobbleSender: ScrobbleSending {
    struct Call: Equatable {
        let songID: String
        let playedAt: Date?
        let submission: Bool
    }

    private let state = Mutex<(calls: [Call], isOffline: Bool)>(([], false))

    var calls: [Call] { state.withLock { $0.calls } }

    func setOffline(_ offline: Bool) {
        state.withLock { $0.isOffline = offline }
    }

    func scrobble(songID: String, playedAt: Date?, submission: Bool) async throws {
        let offline = state.withLock { state in
            if !state.isOffline {
                state.calls.append(Call(songID: songID, playedAt: playedAt, submission: submission))
            }
            return state.isOffline
        }
        if offline { throw URLError(.notConnectedToInternet) }
    }
}
