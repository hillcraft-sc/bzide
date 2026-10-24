import CarPlay
import NavidromeCore

/// Entry point for the CarPlay screen, named in Info.plist's scene manifest.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var controller: CarPlayController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        // The car may send play by itself as it connects; give the engine a
        // moment to tell that from the user (Settings > CarPlay).
        AppModel.shared.engine?.carPlayConnected()
        let controller = CarPlayController(interfaceController: interfaceController, model: AppModel.shared)
        self.controller = controller
        controller.start()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        controller = nil
    }
}
