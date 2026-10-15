import NavidromeCore
import UIKit

/// The phone window's scene delegate, only for what SwiftUI has no hook for:
/// Home Screen quick actions, which arrive here when the app is launched by
/// one (`connectionOptions`) or brought back by one. They're handed to
/// `AppModel`, which runs them once the library is ready.
final class PhoneSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem {
            AppModel.shared.requestHomeScreenAction(type: item.type)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        AppModel.shared.requestHomeScreenAction(type: shortcutItem.type)
    }
}

/// Sets the app icon's quick actions from what's in the queue.
@MainActor
enum HomeScreenActions {
    static func update(current: Song?) {
        UIApplication.shared.shortcutItems = HomeScreenAction.available(current: current).map { action in
            UIApplicationShortcutItem(
                type: action.type,
                localizedTitle: action.title,
                localizedSubtitle: action == .resume ? current.map(HomeScreenAction.resumeSubtitle) : nil,
                icon: UIApplicationShortcutIcon(systemImageName: symbol(for: action))
            )
        }
    }

    /// Signed out: nothing to offer.
    static func clear() {
        UIApplication.shared.shortcutItems = []
    }

    private static func symbol(for action: HomeScreenAction) -> String {
        switch action {
        case .resume: "play.fill"
        case .randomMix: "shuffle"
        case .myCuts: "flame"
        case .search: "magnifyingglass"
        }
    }
}
