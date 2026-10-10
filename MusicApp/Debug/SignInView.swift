import SwiftUI

struct SignInView: View {
    let model: AppModel
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Navidrome server") {
                    TextField("https://music.example.com", text: $serverURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                if let error = model.signInError {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section {
                    Button(model.isSigningIn ? "Signing in…" : "Sign in") {
                        Task { await model.signIn(serverURL: serverURL, username: username, password: password) }
                    }
                    .disabled(model.isSigningIn || serverURL.isEmpty || username.isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("Sign in")
        }
    }
}
