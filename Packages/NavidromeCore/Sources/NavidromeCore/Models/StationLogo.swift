import Foundation

/// A radio station's logo, shown wherever cover art is (lists, Now Playing,
/// the lock screen). Logos come from Radio Browser and live on the stations'
/// own websites, so a logo's cover art id holds its address, and the artwork
/// cache fetches it from there instead of asking the server.
///
/// Only https logos are used: the app's one App Transport Security exception
/// covers audio only. An http logo is tried over https instead, which many
/// sites serve too; if they don't, the station shows no logo.
public enum StationLogo {
    static let prefix = "stationlogo:"

    /// The cover art id for a logo at `url`.
    public static func coverArtID(for url: URL) -> String {
        prefix + url.absoluteString
    }

    /// The logo's address, if `coverArtID` is a logo's (and https).
    public static func url(fromCoverArtID coverArtID: String) -> URL? {
        guard coverArtID.hasPrefix(prefix) else { return nil }
        return usableURL(String(coverArtID.dropFirst(prefix.count)))
    }

    /// The address to load a logo from: https as given, http moved to https,
    /// anything else nothing.
    public static func usableURL(_ string: String) -> URL? {
        guard var components = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              components.host?.isEmpty == false else { return nil }
        components.scheme = "https"
        if scheme == "http", components.port == 80 { components.port = nil }
        return components.url
    }
}
