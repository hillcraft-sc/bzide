import Foundation

/// Everything needed to talk to one Navidrome server.
///
/// Signed in with a password, it's kept (in the Keychain) because token auth
/// needs it to compute a fresh token for every request; it is never sent over
/// the network. Signed in with an API key (OpenSubsonic `apiKeyAuthentication`),
/// the key is sent instead and nothing is derived from a password, which is
/// then empty; the username is the one the server gave for the key.
public struct ServerCredentials: Sendable, Equatable {
    /// Base URL as the user entered it, e.g. `https://music.example.com` or
    /// `http://192.168.1.10:4533/navidrome` behind a reverse proxy with a subpath.
    public var baseURL: URL
    public var username: String
    public var password: String
    public var apiKey: String?

    public init(baseURL: URL, username: String, password: String, apiKey: String? = nil) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.apiKey = apiKey.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Whether the login travels unencrypted: plain http to an address that
    /// isn't on this network or a private one (see `ServerAddress`).
    public var exposesLogin: Bool { ServerAddress.exposesLogin(baseURL) }
}

/// What a server address says about its privacy.
public enum ServerAddress {
    /// Plain http to a public address: the username and login token (or API
    /// key) in every request can be read on the way. Local and private
    /// addresses (this network, or a VPN such as Tailscale) are left alone:
    /// they don't cross the open internet.
    public static func exposesLogin(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http", let host = url.host()?.lowercased() else { return false }
        return !isPrivate(host: host)
    }

    static func isPrivate(host raw: String) -> Bool {
        let host = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".lan") || host.hasSuffix(".home.arpa") || host.hasSuffix(".internal") { return true }
        // A name without dots ("nas") is only resolvable on the local network.
        if !host.contains("."), !host.contains(":") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) {
            switch (parts[0], parts[1]) {
            case (10, _), (127, _), (192, 168), (169, 254): return true
            case (172, 16...31): return true
            // Carrier-grade NAT range, used by Tailscale and other VPNs.
            case (100, 64...127): return true
            default: return false
            }
        }
        if host.contains(":") {
            // IPv6: loopback, unique local (fc00::/7) and link-local (fe80::/10).
            return host == "::1" || host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe8") || host.hasPrefix("fe9") || host.hasPrefix("fea") || host.hasPrefix("feb")
        }
        return false
    }
}
