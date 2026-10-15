import Foundation

/// An internet radio station, saved on the server (`getInternetRadioStations`)
/// or on this iPhone (My Stations, for users who can't change the server's).
/// The stream is somewhere else on the internet, not on the server.
public struct RadioStation: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var name: String
    /// A direct stream, an HLS playlist, or a `.pls`/`.m3u` file listing streams.
    public var streamURL: URL
    public var homePageURL: URL?
    /// Its logo (https), if known. Not from the server or saved with the
    /// station: it's added from `StationLogoStore` when the list is shown.
    public var logoURL: URL?

    public init(id: String, name: String, streamURL: URL, homePageURL: URL? = nil, logoURL: URL? = nil) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.homePageURL = homePageURL
        self.logoURL = logoURL
    }

    /// The logo as cover art, for lists, Now Playing and the lock screen.
    public var coverArtID: String? { logoURL.map(StationLogo.coverArtID) }

    private enum ServerKeys: String, CodingKey {
        case id, name, streamUrl, homePageUrl
    }

    /// A station without a usable stream address can't be played, so it's
    /// dropped from the list (the surrounding `lossyArray` skips it).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: ServerKeys.self)
        guard let stream = c.lenientString(.streamUrl).flatMap(Self.webURL) else {
            throw DecodingError.keyNotFound(ServerKeys.streamUrl, .init(codingPath: c.codingPath, debugDescription: "No stream URL"))
        }
        let name = c.lenientString(.name) ?? ""
        self.init(
            id: try c.requiredID(.id),
            name: name.isEmpty ? (stream.host() ?? "Radio") : name,
            streamURL: stream,
            homePageURL: c.lenientString(.homePageUrl).flatMap(Self.webURL)
        )
    }

    /// Stations saved on this iPhone have ids starting with this.
    public static let phonePrefix = "phone:"

    /// Saved on this iPhone rather than on the server.
    public var isOnPhone: Bool { id.hasPrefix(Self.phonePrefix) }

    /// Written with the server's names, so it reads back the same way.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: ServerKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(streamURL.absoluteString, forKey: .streamUrl)
        try c.encodeIfPresent(homePageURL?.absoluteString, forKey: .homePageUrl)
    }

    /// The id the station has as a queue entry (see `Song(station:stream:)`);
    /// it can't collide with a server song's.
    public var songID: String { "radio:\(id)" }

    /// Only http(s) addresses; anything else can't be streamed or opened.
    static func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host() != nil else { return nil }
        return url
    }
}
