import UIKit

/// A little background time from iOS for work that must finish as the app
/// leaves. Ended once, by whichever comes first: `end()`, or iOS saying time
/// is up (an app that leaves a task running past that is ended by iOS).
final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: Self.expiration(for: self))
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }

    /// Called on the main thread; built nonisolated, as the handler isn't
    /// main-actor isolated (see `SystemNowPlaying.makeArtwork`). The task is
    /// main-actor isolated, so it can be captured here and used only there.
    nonisolated private static func expiration(for task: BackgroundTask) -> @Sendable () -> Void {
        return { MainActor.assumeIsolated { task.end() } }
    }
}
