import NavidromeCore
import SwiftUI

/// Signed out: the sign-in form. Signed in: the library.
struct ContentView: View {
    let model: AppModel

    var body: some View {
        Group {
            if let library = model.library {
                RootView(model: model, library: library)
            } else {
                SignInView(model: model)
            }
        }
        // The widgets draw in the app's theme.
        .onChange(of: model.appearance.settings, initial: true) { _, settings in
            WidgetBridge.shareTheme(settings)
        }
    }
}
