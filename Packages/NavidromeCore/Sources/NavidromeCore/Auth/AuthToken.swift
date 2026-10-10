import CryptoKit
import Foundation

/// Subsonic token auth: `t = md5(password + salt)`, sent with `s = salt`.
enum AuthToken {
    static func make(password: String, salt: String) -> String {
        // MD5 is what the Subsonic protocol specifies; it is not our choice of hash.
        let digest = Insecure.MD5.hash(data: Data((password + salt).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// A new random salt for each request, so a captured token can't be replayed
    /// with a different salt. `SystemRandomNumberGenerator` is cryptographically secure.
    static func randomSalt() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
    }
}
