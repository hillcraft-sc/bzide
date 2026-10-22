import NavidromeCore
import SwiftUI

struct SignInView: View {
    let model: AppModel
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var method = Method.password
    @State private var apiKey = ""

    /// A password, or an API key from the server (OpenSubsonic), which keeps
    /// the password off the phone.
    private enum Method: Hashable {
        case password, apiKey
    }

    /// Plain http to a public address: the login can be read on the way.
    private var exposesLogin: Bool {
        URL(string: serverURL.trimmingCharacters(in: .whitespaces)).map(ServerAddress.exposesLogin) ?? false
    }

    private var canSignIn: Bool {
        guard !model.isSigningIn, !serverURL.isEmpty else { return false }
        return method == .apiKey ? !apiKey.isEmpty : !username.isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        TextField("https://music.example.com", text: $serverURL)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Picker("Sign In With", selection: $method) {
                            Text("Password").tag(Method.password)
                            Text("API Key").tag(Method.apiKey)
                        }
                        .pickerStyle(.segmented)
                        if method == .password {
                            TextField("Username", text: $username)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                        } else {
                            SecureField("API Key", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    } header: {
                        Text("Navidrome server")
                    } footer: {
                        VStack(alignment: .leading, spacing: 8) {
                            if exposesLogin {
                                Label("This address isn't encrypted (http), so your login can be read by anyone on the way to your server. Use https if your server supports it.", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                            if method == .apiKey {
                                Text("An API key from your server's settings signs you in without your password, which then never touches this iPhone. It needs a server that supports OpenSubsonic API keys.")
                            }
                        }
                    }
                    if let error = model.signInError {
                        Section {
                            Text(error).foregroundStyle(.red)
                        }
                    }
                    Section {
                        Button(model.isSigningIn ? "Signing in…" : "Sign in") {
                            Task {
                                await model.signIn(serverURL: serverURL, username: username, password: password, apiKey: method == .apiKey ? apiKey : nil)
                            }
                        }
                        .disabled(!canSignIn)
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
