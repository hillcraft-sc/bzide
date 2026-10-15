import Foundation

/// A station from Radio Browser (radio-browser.info), the free community
/// directory of internet radio. Decoded leniently: a station without a usable
/// stream address is dropped, and anything else missing is left out.
public struct RadioBrowserStation: Sendable, Equatable, Identifiable, Decodable {
    /// Radio Browser's `stationuuid`.
    public var id: String
    public var name: String
    /// The direct stream (Radio Browser's `url_resolved`, which has playlist
    /// files and redirects already followed), else the address as entered.
    public var streamURL: URL
    public var homePageURL: URL?
    public var faviconURL: URL?
    public var tags: [String]
    /// ISO 3166-1 alpha-2, e.g. "US".
    public var countryCode: String?
    public var codec: String?
    /// In kbps.
    public var bitrate: Int?

    public init(
        id: String, name: String, streamURL: URL, homePageURL: URL? = nil, faviconURL: URL? = nil,
        tags: [String] = [], countryCode: String? = nil, codec: String? = nil, bitrate: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.homePageURL = homePageURL
        self.faviconURL = faviconURL
        self.tags = tags
        self.countryCode = countryCode
        self.codec = codec
        self.bitrate = bitrate
    }

    private enum Keys: String, CodingKey {
        case stationuuid, name, url, url_resolved, homepage, favicon, tags, countrycode, codec, bitrate
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let id = try c.requiredID(.stationuuid)
        let resolved = c.lenientString(.url_resolved).flatMap(RadioStation.webURL)
        guard let stream = resolved ?? c.lenientString(.url).flatMap(RadioStation.webURL) else {
            throw DecodingError.keyNotFound(Keys.url, .init(codingPath: c.codingPath, debugDescription: "No stream URL"))
        }
        let name = (c.lenientString(.name) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let codec = c.lenientString(.codec)?.trimmingCharacters(in: .whitespaces)
        let bitrate = c.lenientInt(.bitrate)
        let country = c.lenientString(.countrycode)?.trimmingCharacters(in: .whitespaces).uppercased()
        self.init(
            id: id,
            name: name.isEmpty ? (stream.host() ?? "Radio") : name,
            streamURL: stream,
            homePageURL: c.lenientString(.homepage).flatMap(RadioStation.webURL),
            faviconURL: c.lenientString(.favicon).flatMap(RadioStation.webURL),
            tags: (c.lenientString(.tags) ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            countryCode: country?.count == 2 ? country : nil,
            codec: codec.flatMap { $0.isEmpty || $0.uppercased() == "UNKNOWN" ? nil : $0.uppercased() },
            bitrate: bitrate.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    /// The station as one to play. Its id can't collide with a server station's.
    public var radioStation: RadioStation {
        RadioStation(id: "radiobrowser:\(id)", name: name, streamURL: streamURL, homePageURL: homePageURL, logoURL: logoURL)
    }

    /// The logo to show: the favicon over https (see `StationLogo`).
    public var logoURL: URL? {
        faviconURL.flatMap { StationLogo.usableURL($0.absoluteString) }
    }

    /// The station for saving: Add Station's form, filled in.
    public var draft: RadioStationDraft {
        RadioStationDraft(name: name, streamURL: streamURL.absoluteString, homePageURL: homePageURL?.absoluteString ?? "")
    }

    /// A line under the name, e.g. "US · MP3 128 kbps · jazz, smooth jazz".
    public var summary: String {
        var parts: [String] = []
        if let countryCode { parts.append(countryCode) }
        switch (codec, bitrate) {
        case let (codec?, bitrate?): parts.append("\(codec) \(bitrate) kbps")
        case let (codec?, nil): parts.append(codec)
        case let (nil, bitrate?): parts.append("\(bitrate) kbps")
        case (nil, nil): break
        }
        if !tags.isEmpty { parts.append(tags.prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}
