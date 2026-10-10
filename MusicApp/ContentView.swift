import SwiftUI

/// Signed out: the sign-in form. Signed in: the debug player.
struct ContentView: View {
    let model: AppModel

    var body: some View {
        if let engine = model.engine {
            DebugPlayerView(model: model, engine: engine)
        } else {
            SignInView(model: model)
        }
    }
}
