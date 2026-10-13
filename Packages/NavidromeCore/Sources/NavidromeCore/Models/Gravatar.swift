import CryptoKit
import Foundation

/// Gravatar (gravatar.com) addresses. An email is looked up by the SHA-256 of
/// its trimmed, lowercased form, so the address itself is never sent.
public enum Gravatar {
    /// The lookup hash, or `nil` if this doesn't look like an email address.
    public static func hash(of email: String) -> String? {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isPlausibleEmail(normalized) else { return nil }
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The picture for an email at `pixels` square. `d=404` makes Gravatar
    /// answer "not found" instead of sending a stand-in face, so the app only
    /// shows a real picture.
    public static func imageURL(forHash hash: String, pixels: Int) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "gravatar.com"
        components.path = "/avatar/\(hash)"
        components.queryItems = [
            URLQueryItem(name: "s", value: String(pixels)),
            URLQueryItem(name: "d", value: "404"),
        ]
        return components.url
    }

    /// Something@something.something, with no spaces.
    static func isPlausibleEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !text.contains(where: \.isWhitespace) else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }
}
