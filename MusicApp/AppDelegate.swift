import NavidromeCore
import UIKit

/// Only here for what SwiftUI has no hook for.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Empties iOS's shared URL cache at each launch. Bzide's own requests no
    /// longer use it (see `URLSessionTransport.privateSession`), but earlier
    /// versions left server responses there on disk, under request URLs
    /// carrying the username and login token; and anything else using the
    /// shared session (a SwiftUI `AsyncImage`) shouldn't keep data either.
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        URLCache.shared.removeAllCachedResponses()
        return true
    }

    /// The phone window gets a scene delegate for Home Screen quick actions;
    /// CarPlay keeps the one named in Info.plist.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        guard connectingSceneSession.role == .windowApplication else { return connectingSceneSession.configuration }
        let configuration = UISceneConfiguration(name: "Phone", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = PhoneSceneDelegate.self
        return configuration
    }

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
