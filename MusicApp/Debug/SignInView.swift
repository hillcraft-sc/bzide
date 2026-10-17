import SwiftUI

struct SignInView: View {
    let model: AppModel
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Group {
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
                .themedRows(grouped: true)
            }
            .themedList(grouped: true)
            .navigationTitle("Sign in")
            .confirmationDialog(
                "Sign In as a Different Account?",
                isPresented: Binding(get: { model.pendingSwitch != nil }, set: { if !$0 { model.cancelSwitch() } }),
                titleVisibility: .visible,
                presenting: model.pendingSwitch
            ) { _ in
                Button("Same Server, Keep Everything") { model.confirmSwitch(sameServer: true) }
                Button("Sign In and Remove Downloads", role: .destructive) { model.confirmSwitch(sameServer: false) }
                Button("Cancel", role: .cancel) { model.cancelSwitch() }
            } message: { pending in
                Text(Self.switchMessage(pending))
            }
        }
    }

    static func switchMessage(_ pending: AccountSwitch) -> String {
        let downloads = pending.downloadBytes > 0
            ? "the previous account's downloads (\(pending.downloadBytes.formatted(.byteCount(style: .file))))"
            : "the previous account's cached artwork"
        return "This iPhone has another account's music. Signing in removes \(downloads); its settings, history and queue are kept for when it signs in again.\n\nIf this is the same server at a different address (say, your local network instead of its domain), choose Same Server to keep everything."
    }
}
