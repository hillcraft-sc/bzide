import Foundation

/// Everything needed to talk to one Navidrome server.
///
/// The plain password is kept (in the Keychain) because token auth needs it to
/// compute a fresh token for every request. It is never sent over the network.
public struct ServerCredentials: Sendable, Equatable {
    /// Base URL as the user entered it, e.g. `https://music.example.com` or
    /// `http://192.168.1.10:4533/navidrome` behind a reverse proxy with a subpath.
    public var baseURL: URL
    public var username: String
    public var password: String

    public init(baseURL: URL, username: String, password: String) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
    }
}
