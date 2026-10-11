import SwiftUI

@main
struct MusicAppApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
