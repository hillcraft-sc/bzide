import Foundation
import Observation

/// What a radio stream says about itself in its headers (Shoutcast and
/// Icecast send `icy-name`, `icy-description` and so on; Icecast also
/// `ice-audio-info`), for Station Info.
public struct StreamHeaders: Equatable, Sendable {
    public var name: String?
    public var description: String?
    public var genre: String?
    public var website: String?
    /// In kbps.
    public var bitrate: Int?
    /// In Hz.
    public var sampleRate: Int?
    public var contentType: String?
    public var server: String?

    public init(
        name: String? = nil, description: String? = nil, genre: String? = nil, website: String? = nil,
        bitrate: Int? = nil, sampleRate: Int? = nil, contentType: String? = nil, server: String? = nil
    ) {
        self.name = name
        self.description = description
        self.genre = genre
        self.website = website
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.contentType = contentType
        self.server = server
    }

    /// From a response's headers (any capitalization). Blank values are left out.
    public init(headers: [String: String]) {
        let lowered = Dictionary(headers.map { ($0.key.lowercased(), $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }, uniquingKeysWith: { first, _ in first })
        func value(_ key: String) -> String? { lowered[key].flatMap { $0.isEmpty ? nil : $0 } }
        // "bitrate=128;samplerate=44100;channels=2"
        let audioInfo = Dictionary(
            (value("ice-audio-info") ?? "").split(separator: ";").compactMap { part -> (String, String)? in
                let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
                return pair.count == 2 ? (pair[0].lowercased(), pair[1]) : nil
            },
            uniquingKeysWith: { first, _ in first }
        )
        self.init(
            name: value("icy-name"),
            description: value("icy-description"),
            genre: value("icy-genre"),
            website: value("icy-url"),
            bitrate: (value("icy-br")?.split(separator: ",").first).flatMap { Int($0) } ?? audioInfo["bitrate"].flatMap { Int($0) }
                ?? audioInfo["ice-bitrate"].flatMap { Int($0) },
            sampleRate: value("icy-sr").flatMap { Int($0) } ?? audioInfo["samplerate"].flatMap { Int($0) }
                ?? audioInfo["ice-samplerate"].flatMap { Int($0) },
            contentType: value("content-type"),
            server: value("server")
        )
    }

    /// The format, from the content type: "MP3", "AAC", "Ogg", "FLAC", "HLS".
    public var format: String? {
        guard let type = contentType?.lowercased().split(separator: ";").first.map(String.init) else { return nil }
        return switch type {
        case "audio/mpeg", "audio/mp3": "MP3"
        case "audio/aac", "audio/aacp", "audio/mp4", "audio/x-m4a": "AAC"
        case "audio/ogg", "application/ogg", "audio/opus": "Ogg"
        case "audio/flac", "audio/x-flac": "FLAC"
        case "application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl": "HLS"
        default: nil
        }
    }
}

/// Everything known about a radio station, for Station Info: from Bzide (where
/// it's saved, when it was first listed, its stream and what's on air), from
/// Radio Browser if it's listed there, and from the stream's own headers.
public struct StationInfoSubject: Equatable, Sendable {
    public enum Place: Equatable, Sendable {
        case server, phone
    }

    public var name: String
    /// The station's address as saved or found (may be a playlist file).
    public var stream: URL
    public var homePage: URL?
    public var coverArtID: String?
    /// Where it's saved, if it is.
    public var savedIn: Place?
    public var firstSeen: Date?
    /// What Bzide already knows (Find Stations, Spin the Dial, a lookup).
    public var details: StationDetails?
    /// The song it's announcing, if it's playing.
    public var announced: String?

    public init(
        name: String, stream: URL, homePage: URL? = nil, coverArtID: String? = nil, savedIn: Place? = nil,
        firstSeen: Date? = nil, details: StationDetails? = nil, announced: String? = nil
    ) {
        self.name = name
        self.stream = stream
        self.homePage = homePage
        self.coverArtID = coverArtID
        self.savedIn = savedIn
        self.firstSeen = firstSeen
        self.details = details
        self.announced = announced
    }

    /// From a saved station (Radio's list).
    public init(_ station: RadioStation, announced: String? = nil) {
        self.init(
            name: station.name, stream: station.streamURL, homePage: station.homePageURL, coverArtID: station.coverArtID,
            savedIn: station.isOnPhone ? .phone : .server, firstSeen: station.firstSeen, details: station.details, announced: announced
        )
    }
}

extension StationInfoSubject {
    /// The station a playing entry is: the saved station with its id (or,
    /// for one Spin the Dial found, its stream), else the station the dial
    /// last tuned to, else what the entry kept (name, stream, logo). `nil`
    /// for a song that isn't a station.
    public static func playing(
        _ song: Song, saved: [RadioStation], tuned: RadioBrowserStation?, announced: String?
    ) -> StationInfoSubject? {
        guard song.isLive else { return nil }
        if let station = saved.first(where: { $0.songID == song.id }) {
            return StationInfoSubject(station, announced: announced)
        }
        if let tuned, SpinTheDialModel.dialStation(tuned).songID == song.id {
            if let station = saved.first(where: { $0.streamURL == tuned.streamURL }) {
                var subject = StationInfoSubject(station, announced: announced)
                subject.details = StationDetails(tuned)
                return subject
            }
            return StationInfoSubject(
                name: tuned.name, stream: tuned.streamURL, homePage: tuned.homePageURL,
                coverArtID: song.coverArtID, details: StationDetails(tuned), announced: announced
            )
        }
        guard let stream = song.liveStreamURL else { return nil }
        let saved = saved.first { $0.streamURL == stream }
        if let saved { return StationInfoSubject(saved, announced: announced) }
        return StationInfoSubject(name: song.title, stream: stream, coverArtID: song.coverArtID, announced: announced)
    }
}

public enum StationInfo {
    /// The sheet's sections, each left out when there's nothing for it.
    /// Radio Browser's listing wins over what Bzide already knew, and the
    /// stream's headers fill what's still missing.
    public static func sections(
        for subject: StationInfoSubject, listing: RadioBrowserStation?, headers: StreamHeaders?,
        countryName: (String) -> String = { Locale.current.localizedString(forRegionCode: $0) ?? $0 }
    ) -> [InfoSection] {
        var sections: [InfoSection] = []
        func add(_ title: String, _ rows: [InfoRow?]) {
            let kept = rows.compactMap(\.self)
            if !kept.isEmpty { sections.append(InfoSection(title: title, rows: kept)) }
        }
        func row(_ label: String, _ value: String?) -> InfoRow? {
            value.flatMap { $0.isEmpty ? nil : InfoRow(label: label, value: $0) }
        }

        let details = listing.map(StationDetails.init) ?? subject.details
        let tags = details?.tags.isEmpty == false ? details?.tags.joined(separator: ", ") : headers?.genre
        let homePage = listing?.homePageURL ?? subject.homePage
        add("On Air", [row("Now Playing", subject.announced)])
        add("Station", [
            row("About", headers?.description),
            row("Country", details?.countryCode.map(countryName)),
            row("Region", listing?.state),
            row("Language", listing?.language.map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).capitalized }.joined(separator: ", ") }),
            row("Genres", tags),
            row("Homepage", homePage?.absoluteString ?? headers?.website),
        ])
        let format = listing?.isHLS == true ? "HLS" : details?.codec ?? headers?.format
        add("Stream", [
            row("Format", format),
            row("Bitrate", (details?.bitrate ?? headers?.bitrate).map { "\($0) kbps" }),
            row("Sample Rate", headers?.sampleRate.map { String(format: "%.1f kHz", locale: Locale(identifier: "en_US_POSIX"), Double($0) / 1000) }),
            row("Address", subject.stream.absoluteString),
            row("Server", headers?.server),
        ])
        if let listing {
            add("Radio Browser", [
                row("Votes", listing.votes.map { $0.formatted() }),
                row("Plays Today", listing.clickCount.map { $0.formatted() }),
                row("Last Check", listing.lastCheckOK.map { $0 ? "Working" : "Not working" }),
            ])
        }
        let saved = switch subject.savedIn {
        case .server: "On your server"
        case .phone: "On this iPhone"
        case nil: "Not saved"
        }
        add("In Bzide", [
            row("Saved", saved),
            row(subject.savedIn == nil ? "First Played" : "Added", subject.firstSeen.map { $0.formatted(date: .abbreviated, time: .omitted) }),
        ])
        return sections
    }
}

/// Station Info's lookups: Radio Browser's listing (while Find Stations
/// Online is on) and the stream's headers (https streams only: plain http is
/// allowed for audio playback, not for other requests). Both at once; either
/// may be missing.
@MainActor
@Observable
public final class StationInfoModel {
    public struct Sources: Sendable {
        /// A stream and the station's name.
        public var listing: @Sendable (URL, String) async throws -> RadioBrowserStation?
        public var headers: @Sendable (URL) async throws -> [String: String]?

        public init(
            listing: @escaping @Sendable (URL, String) async throws -> RadioBrowserStation?,
            headers: @escaping @Sendable (URL) async throws -> [String: String]?
        ) {
            self.listing = listing
            self.headers = headers
        }
    }

    public private(set) var listing: RadioBrowserStation?
    public private(set) var headers: StreamHeaders?
    public private(set) var isLoading = false

    @ObservationIgnored private let sources: Sources

    public init(sources: Sources) {
        self.sources = sources
    }

    /// `playing` is the address actually streamed (a playlist file resolved),
    /// for the headers; `lookUpOnline` is whether Find Stations Online is on.
    public func load(_ subject: StationInfoSubject, playing: URL?, lookUpOnline: Bool) async {
        isLoading = true
        defer { isLoading = false }
        let sources = sources
        let stream = playing ?? subject.stream
        async let listing: RadioBrowserStation? = lookUpOnline ? (try? await sources.listing(subject.stream, subject.name)) ?? nil : nil
        async let headers: [String: String]? = stream.scheme?.lowercased() == "https" ? (try? await sources.headers(stream)) ?? nil : nil
        let (found, heard) = await (listing, headers)
        self.listing = found
        self.headers = heard.map(StreamHeaders.init(headers:))
    }
}
