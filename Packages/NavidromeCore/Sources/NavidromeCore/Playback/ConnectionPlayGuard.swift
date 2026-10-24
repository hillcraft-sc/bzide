import Foundation

/// Cars often send "play" by themselves as they connect, over CarPlay or
/// Bluetooth, so music would start the moment the user gets in (Gitea #27).
/// iOS doesn't say whether a play command came from a person or the car, so
/// for a few seconds after such a device connects, play commands are ignored,
/// unless Settings > CarPlay > Play When CarPlay Connects is on. Pause, next
/// and previous always work, and so does anything chosen in the app.
struct ConnectionPlayGuard {
    /// Long enough for the car's command to arrive, short enough that a person
    /// pressing play a moment later is heard.
    static let window: TimeInterval = 5

    private var connectedAt: Date?

    mutating func deviceConnected(at date: Date) {
        connectedAt = date
    }

    /// Whether a play command at `date` comes too soon after a connection.
    func blocksPlay(at date: Date) -> Bool {
        guard let connectedAt else { return false }
        let elapsed = date.timeIntervalSince(connectedAt)
        return elapsed >= 0 && elapsed < Self.window
    }
}
