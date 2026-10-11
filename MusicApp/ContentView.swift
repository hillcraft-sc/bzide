import SwiftUI

/// Signed out: the sign-in form. Signed in: the library.
struct ContentView: View {
    let model: AppModel

    var body: some View {
        if let library = model.library {
            RootView(model: model, library: library)
        } else {
            SignInView(model: model)
        }
    }
}
