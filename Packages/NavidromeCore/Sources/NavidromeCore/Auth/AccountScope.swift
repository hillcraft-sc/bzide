import CryptoKit
import Foundation

/// Keeps one account's data from leaking into another's.
///
/// Everything on the iPhone belongs to the server and user it came from.
/// Signing out sets the account's settings and small files aside
/// (`setAside`), so the sign-in screen and whoever signs in next start from
/// the defaults; they come back when the same account signs in again. Its
/// downloads and caches stay where they are. When a different server or user signs in, the large,
/// re-fetchable data (downloads, cached cover art and Gravatar pictures) is
/// deleted, and the rest (settings, the queue, play history, unsent
/// scrobbles, the profile, saved stations, the Wishlist…) is set aside
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
    /// Set while the owner is signed out and its settings are set aside.
    static let setAsideKey = "accountSetAside"

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
        // It's the same account: what signing out set aside comes back.
        if defaults.bool(forKey: Self.setAsideKey), let owner = defaults.string(forKey: Self.fingerprintKey) {
            settings?.bringBack(owner)
            defaults.removeObject(forKey: Self.setAsideKey)
        }
        defaults.set(Self.fingerprint(of: credentials), forKey: Self.fingerprintKey)
    }

    /// Signing out: sets the owner's settings and small files aside, so
    /// everything reads its default until someone signs in. The owner's come
    /// back when it signs in again (`prepare`). Downloads and caches stay:
    /// they're still the owner's, and another account's sign-in removes them.
    public func setAside() {
        guard let settings, let owner = defaults.string(forKey: Self.fingerprintKey),
              !defaults.bool(forKey: Self.setAsideKey)
        else { return }
        settings.setAside(owner)
        defaults.set(true, forKey: Self.setAsideKey)
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
    /// records this one as the owner. The same account signing back in gets
    /// back what signing out set aside.
    /// Returns whether this account's settings were put in place (a switch, or
    /// a return after signing out), so loaded models should read them again.
    ///
    /// With no owner recorded (data from before this check existed), the data is
    /// assumed to be this account's and kept.
    @discardableResult
    public func prepare(for credentials: ServerCredentials) -> Bool {
        let fingerprint = Self.fingerprint(of: credentials)
        let isSetAside = defaults.bool(forKey: Self.setAsideKey)
        defer {
            defaults.set(fingerprint, forKey: Self.fingerprintKey)
            defaults.removeObject(forKey: Self.setAsideKey)
        }
        guard let owner = defaults.string(forKey: Self.fingerprintKey), owner != fingerprint else {
            // The same account: what signing out set aside comes back.
            guard isSetAside else { return false }
            settings?.bringBack(fingerprint)
            return true
        }
        // Already set aside when the owner signed out: nothing more to keep.
        settings?.switchAccount(from: isSetAside ? nil : owner, to: fingerprint)
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
