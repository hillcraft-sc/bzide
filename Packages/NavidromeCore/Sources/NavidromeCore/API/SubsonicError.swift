import Foundation

public enum SubsonicError: Error, Equatable, Sendable {
    /// The base URL can't be turned into a request URL.
    case invalidBaseURL
    /// The request never got a response (offline, DNS, timeout, TLS...).
    case network(URLError.Code)
    /// The server answered with a non-2xx HTTP status.
    case httpStatus(Int)
    /// The server answered with `status: "failed"`. Codes are from the Subsonic spec.
    case server(code: Int, message: String)
    /// The response body wasn't the JSON we expected.
    case decoding(String)

    /// Subsonic code 40 is "wrong username or password"; 41 is "token auth
    /// not supported"; OpenSubsonic's API keys add 42 ("this way of signing in
    /// isn't supported"), 43 (conflicting logins sent) and 44 (invalid API key).
    public var isAuthenticationFailure: Bool {
        if case .server(let code, _) = self { return (40...44).contains(code) }
        return false
    }
}

extension SubsonicError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "The server address isn't a valid URL."
        case .network(let code):
            "Couldn't reach the server (\(URLError(code).localizedDescription))."
        case .httpStatus(let status):
            "The server returned HTTP \(status)."
        case .server(let code, let message):
            switch code {
            case 40: "Wrong username or password."
            case 41: "This server doesn't accept password sign-in for this account. Sign in with an API key instead, if your server offers them."
            case 42: "This server doesn't support this way of signing in."
            case 44: "That API key isn't valid. Check it in your server's settings."
            default: "Server error \(code): \(message)"
            }
        case .decoding:
            "The server sent a response this app couldn't read."
        }
    }
}
