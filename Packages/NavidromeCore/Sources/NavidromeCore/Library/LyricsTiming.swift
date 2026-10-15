import Foundation
import Observation

/// The user's timing fixes for synced lyrics, per song: how many seconds
/// earlier (positive) or later (negative) to show them, for lyrics that run
/// behind or ahead of the singing. Saved on this device, so a song fixed once
/// stays fixed.
@MainActor
@Observable
public final class LyricsTiming {
    /// Each tap moves the lyrics this much.
    public static let step: TimeInterval = 0.5
    /// The furthest either way.
    public static let limit: TimeInterval = 30
    /// Songs remembered; the oldest fixes go first beyond this.
    static let maximumSongs = 1_000

    public private(set) var offsets: [String: TimeInterval]
    @ObservationIgnored private var order: [String]
    @ObservationIgnored private let defaults: UserDefaults
    static let key = "lyricsTiming"

    private struct Saved: Codable {
        var offsets: [String: TimeInterval]
        var order: [String]
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        offsets = saved?.offsets ?? [:]
        order = saved?.order ?? []
    }

    /// Seconds earlier to show the song's lyrics (negative: later).
    public func offset(for songID: String) -> TimeInterval {
        offsets[songID] ?? 0
    }

    /// Shows the lyrics `step` earlier.
    public func earlier(_ songID: String) {
        set(offset(for: songID) + Self.step, for: songID)
    }

    /// Shows the lyrics `step` later.
    public func later(_ songID: String) {
        set(offset(for: songID) - Self.step, for: songID)
    }

    public func reset(_ songID: String) {
        set(0, for: songID)
    }

    /// e.g. "0.5 s earlier", "1.5 s later", or `nil` for no change.
    public static func describe(_ offset: TimeInterval) -> String? {
        guard offset != 0 else { return nil }
        let amount = abs(offset).formatted(.number.precision(.fractionLength(0...1)))
        return "\(amount) s \(offset > 0 ? "earlier" : "later")"
    }

    private func set(_ value: TimeInterval, for songID: String) {
        let clamped = min(max(value, -Self.limit), Self.limit)
        order.removeAll { $0 == songID }
        if clamped == 0 {
            offsets[songID] = nil
        } else {
            offsets[songID] = clamped
            order.append(songID)
            while order.count > Self.maximumSongs {
                offsets[order.removeFirst()] = nil
            }
        }
        if let data = try? JSONEncoder().encode(Saved(offsets: offsets, order: order)) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
