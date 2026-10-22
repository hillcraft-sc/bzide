import Foundation

/// Which LRCLIB lyrics the user picked for a song with "Wrong lyrics?": a
/// particular entry (by LRCLIB's id), or none at all. Saved on this device,
/// with the account's other settings, so a song fixed once stays fixed.
/// Songs without a choice get LRCLIB's best match.
public final class LyricsChoices: @unchecked Sendable {
    public enum Choice: Codable, Equatable, Sendable {
        case lrclib(id: Int)
        /// Don't use LRCLIB for this song. (Not `none`, which Swift would
        /// read as an optional's "no choice".)
        case turnedDown
    }

    /// Songs remembered; the oldest choices go first beyond this.
    static let maximumSongs = 1_000
    nonisolated static let key = "lyricsChoices"

    private struct Saved: Codable {
        var choices: [String: Choice] = [:]
        var order: [String] = []
    }

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var saved: Saved

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) } ?? Saved()
    }

    public func choice(for songID: String) -> Choice? {
        lock.withLock { saved.choices[songID] }
    }

    /// `nil` forgets the choice: back to LRCLIB's best match.
    public func set(_ choice: Choice?, for songID: String) {
        lock.withLock {
            saved.order.removeAll { $0 == songID }
            saved.choices[songID] = choice
            if choice != nil {
                saved.order.append(songID)
                while saved.order.count > Self.maximumSongs {
                    saved.choices[saved.order.removeFirst()] = nil
                }
            }
            if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.key) }
        }
    }
}
