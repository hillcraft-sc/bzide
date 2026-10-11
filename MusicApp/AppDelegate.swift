import NavidromeCore
import UIKit

/// Only here for what SwiftUI has no hook for.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// iOS woke the app because background downloads finished. The completion
    /// handler is called once the download session has delivered everything.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundDownloadTransport.sessionIdentifier else {
            completionHandler()
            return
        }
        BackgroundDownloadTransport.handleBackgroundEvents(completion: Self.sendable(completionHandler))
    }

    /// The handler is called on the main thread, but crosses through a
    /// nonisolated store; built nonisolated so it isn't main-actor checked.
    nonisolated private static func sendable(_ handler: @escaping () -> Void) -> @Sendable () -> Void {
        nonisolated(unsafe) let handler = handler
        return { handler() }
    }
}
