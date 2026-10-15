import Foundation

/// A station as typed into the Add or Edit Station form, checked before it's
/// saved. The stream address must be http or https (plain http is common for
/// radio and allowed for audio); a blank name becomes the stream's host.
public struct RadioStationDraft: Equatable, Sendable {
    public var name: String
    public var streamURL: String
    public var homePageURL: String

    public init(name: String = "", streamURL: String = "", homePageURL: String = "") {
        self.name = name
        self.streamURL = streamURL
        self.homePageURL = homePageURL
    }

    /// The form filled in from an existing station, for editing.
    public init(_ station: RadioStation) {
        self.init(name: station.name, streamURL: station.streamURL.absoluteString, homePageURL: station.homePageURL?.absoluteString ?? "")
    }

    /// A draft that passed its checks, ready to save.
    public struct Valid: Equatable, Sendable {
        public var name: String
        public var streamURL: URL
        public var homePageURL: URL?
    }

    public enum Problem: Error, Equatable, Sendable {
        case missingStream
        case invalidStream
        case invalidHomePage

        public var message: String {
            switch self {
            case .missingStream: "Enter the station's stream address."
            case .invalidStream: "The stream address must start with http:// or https://."
            case .invalidHomePage: "The homepage must start with http:// or https://, or be left blank."
            }
        }
    }

    public func validated() -> Result<Valid, Problem> {
        let stream = streamURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stream.isEmpty else { return .failure(.missingStream) }
        guard let streamURL = RadioStation.webURL(stream) else { return .failure(.invalidStream) }
        let page = homePageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var homePage: URL?
        if !page.isEmpty {
            guard let url = RadioStation.webURL(page) else { return .failure(.invalidHomePage) }
            homePage = url
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(Valid(name: trimmed.isEmpty ? (streamURL.host() ?? "Radio") : trimmed, streamURL: streamURL, homePageURL: homePage))
    }
}
