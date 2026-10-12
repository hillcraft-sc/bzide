import Foundation

/// An internet radio station saved on the server (`getInternetRadioStations`).
/// The stream is somewhere else on the internet, not on the server.
public struct RadioStation: Sendable, Equatable, Identifiable, Decodable {
    public var id: String
    public var name: String
    /// A direct stream, an HLS playlist, or a `.pls`/`.m3u` file listing streams.
    public var streamURL: URL
    public var homePageURL: URL?

    public init(id: String, name: String, streamURL: URL, homePageURL: URL? = nil) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.homePageURL = homePageURL
    }

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
