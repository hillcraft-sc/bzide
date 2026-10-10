import Foundation
@testable import NavidromeCore

/// Records what the engine asks for and lets tests play the player's role:
/// finishing tracks, reporting time, failing.
@MainActor
final class FakeAudioPlayer: AudioPlayer {
    var onEvent: (@MainActor (PlayerEvent) -> Void)?

    private(set) var loaded: [PlayerItem] = []
    private(set) var setItemsCalls: [(items: [PlayerItem], startPosition: TimeInterval)] = []
    private(set) var isPlaying = false
    private(set) var seeks: [TimeInterval] = []

    var loadedEntryIDs: [QueueEntry.ID] { loaded.map(\.entryID) }

    func setItems(_ items: [PlayerItem], startPosition: TimeInterval) {
        loaded = items
        setItemsCalls.append((items, startPosition))
    }

    func append(_ item: PlayerItem) {
        loaded.append(item)
    }

    private(set) var replacedUpcoming: [PlayerItem] = []

    func replaceUpcoming(with item: PlayerItem) {
        loaded = Array(loaded.prefix(1)) + [item]
        replacedUpcoming.append(item)
    }

    func skipToNextItem() {
        finishCurrentItem()
    }

    func play() {
        isPlaying = true
        onEvent?(.statusChanged(.playing))
    }

    func pause() {
        isPlaying = false
        onEvent?(.statusChanged(.paused))
    }

    func seek(to position: TimeInterval) {
        seeks.append(position)
    }

    // MARK: - Simulating the real player

    /// What AVQueuePlayer does when a track ends or is skipped.
    func finishCurrentItem() {
        guard !loaded.isEmpty else { return }
        loaded.removeFirst()
        if let next = loaded.first {
            onEvent?(.currentItemChanged(next.entryID))
        } else {
            isPlaying = false
            onEvent?(.reachedEnd)
            onEvent?(.currentItemChanged(nil))
        }
    }

    func report(_ event: PlayerEvent) {
        onEvent?(event)
    }
}

struct FakeStreamURLs: StreamURLProviding {
    var failingSongIDs: Set<String> = []

    struct NoURL: Error {}

    func streamURL(for song: Song) throws -> URL {
        if failingSongIDs.contains(song.id) { throw NoURL() }
        return URL(string: "https://music.example.test/rest/stream?id=\(song.id)")!
    }
}
