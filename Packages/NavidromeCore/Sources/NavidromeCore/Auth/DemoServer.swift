import Foundation

/// The public demo library run by the Navidrome project, for trying the app
/// without a server of your own. Its login is published on navidrome.org for
/// exactly this, so it isn't a secret. If the project changes it, this is the
/// one place to update.
public enum DemoServer {
    public static let baseURL: URL = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "demo.navidrome.org"
        // Can't fail for a fixed scheme and host; the fallback only avoids a force unwrap.
        return components.url ?? URL(fileURLWithPath: "/")
    }()
    public static let username = "demo"
    public static let password = "demo"

    public static var credentials: ServerCredentials {
        ServerCredentials(baseURL: baseURL, username: username, password: password)
    }

    /// Whether these credentials are the demo's. Compares the host only, so a
    /// trailing slash or a different scheme in the saved address still counts.
    public static func isDemo(_ credentials: ServerCredentials) -> Bool {
        credentials.baseURL.host()?.lowercased() == baseURL.host()
    }

    /// Everyone on the demo shares one account, so the app keeps its writes
    /// to the shared server small: no saved queue (which would offer one
    /// someone else left) and no plays sent (which would fill the shared
    /// history). Favorites, ratings and playlists still work.
    public static func adjusting(_ settings: StreamingSettings) -> StreamingSettings {
        var adjusted = settings
        adjusted.syncQueueWithServer = false
        adjusted.sendPlaysToServer = false
        return adjusted
    }
}
