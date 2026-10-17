import CryptoKit
import Foundation

/// Keeps one account's data from leaking into another's.
///
/// Everything on the iPhone belongs to the server and user it came from.
/// Signing out leaves it in place, so signing back in to the same account
/// keeps everything. When a different server or user signs in, the large,
/// re-fetchable data (downloads, cached cover art and Gravatar pictures) is
/// deleted, and the rest (settings, the queue, play history, unsent
/// scrobbles, the profile, saved stations, Tagged Radio Songs…) is set aside
/// for that account by `AccountSettings`, and comes back when it signs in
/// again. The app warns before a switch (`isDifferentAccount`) and offers
/// `adopt` for the same server reached at a new address.
///
/// The owning account is remembered as a fingerprint (a hash of server address
/// and username), so neither is stored outside the Keychain.
public struct AccountScope {
    private let defaults: UserDefaults
    private let dataLocations: [URL]
    private let settings: AccountSettings?

    static let fingerprintKey = "accountFingerprint"

    public init(defaults: UserDefaults = .standard, dataLocations: [URL], settings: AccountSettings? = nil) {
        self.defaults = defaults
        self.dataLocations = dataLocations
        self.settings = settings
    }

    /// The data deleted on a switch, in its standard places: downloads and
    /// caches, which can be fetched again. (Everything else is set aside; see
    /// `AccountSettings.standard()`.)
    public static func standardDataLocations() throws -> [URL] {
        let fileManager = FileManager.default
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let caches = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return [
            support.appending(path: DownloadManager.directoryName),
            caches.appending(path: CoverArtStore.directoryName),
            caches.appending(path: ProfileModel.cacheDirectoryName),
        ]
    }

    /// Whether signing in with these would switch accounts: the data here
    /// belongs to another (and isn't from before accounts were tracked).
    public func isDifferentAccount(_ credentials: ServerCredentials) -> Bool {
        guard let owner = defaults.string(forKey: Self.fingerprintKey) else { return false }
        return owner != Self.fingerprint(of: credentials)
    }

    /// Makes these the owner of everything here, without switching: for the
    /// same server reached at a different address (say, the local network
    /// instead of the domain), which counts as a different account otherwise.
    public func adopt(_ credentials: ServerCredentials) {
        defaults.set(Self.fingerprint(of: credentials), forKey: Self.fingerprintKey)
    }

    /// Bytes in a folder and everything in it (0 if it's missing), for the
    /// warning before a switch.
    public static func size(of folder: URL) -> Int64 {
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in items {
            total += Int64((try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    /// Call before any account data or settings are loaded. If the data on the
    /// device belongs to a different account, sets its settings and data aside,
    /// brings back this account's, and deletes the downloads and caches; then
    /// records this one as the owner.
    /// Returns whether it switched.
    ///
    /// With no owner recorded (data from before this check existed), the data is
    /// assumed to be this account's and kept.
    @discardableResult
    public func prepare(for credentials: ServerCredentials) -> Bool {
        let fingerprint = Self.fingerprint(of: credentials)
        defer { defaults.set(fingerprint, forKey: Self.fingerprintKey) }
        guard let owner = defaults.string(forKey: Self.fingerprintKey), owner != fingerprint else { return false }
        settings?.switchAccount(from: owner, to: fingerprint)
        for location in dataLocations {
            try? FileManager.default.removeItem(at: location)
        }
        return true
    }

    /// The same server written differently (`HTTPS://Music.example.com/`) is the
    /// same account; the username is compared exactly.
    static func fingerprint(of credentials: ServerCredentials) -> String {
        var server = credentials.baseURL.absoluteString
        if var components = URLComponents(url: credentials.baseURL, resolvingAgainstBaseURL: false) {
            components.scheme = components.scheme?.lowercased()
            components.host = components.host?.lowercased()
            while components.path.hasSuffix("/") { components.path.removeLast() }
            server = components.string ?? server
        }
        let digest = SHA256.hash(data: Data("\(server)\n\(credentials.username)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
