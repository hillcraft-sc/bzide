import Foundation

/// What's known about a saved radio station beyond its name and address,
/// which is all the server keeps: its logo, country, genres and quality,
/// from Radio Browser.
public struct StationDetails: Codable, Equatable, Sendable {
    /// https only (see `StationLogo`).
    public var logoURL: URL?
    /// ISO 3166-1 alpha-2, e.g. "US".
    public var countryCode: String?
    public var tags: [String]
    public var codec: String?
    /// In kbps.
    public var bitrate: Int?

    public init(logoURL: URL? = nil, countryCode: String? = nil, tags: [String] = [], codec: String? = nil, bitrate: Int? = nil) {
        self.logoURL = logoURL
        self.countryCode = countryCode
        self.tags = tags
        self.codec = codec
        self.bitrate = bitrate
    }

    /// A line under a station's name, e.g. "US · MP3 128 kbps · jazz, smooth
    /// jazz": country, format and bitrate, and up to three genres.
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

    /// From a station found on Radio Browser.
    public init(_ station: RadioBrowserStation) {
        self.init(logoURL: station.logoURL, countryCode: station.countryCode, tags: station.tags, codec: station.codec, bitrate: station.bitrate)
    }
}

/// Remembers the details of saved stations, by stream address: those a
/// station had in Find Stations when it was added from there, and those
/// looked up on Radio Browser for stations added elsewhere. "Not on Radio
/// Browser" is remembered too, so a station is looked up only once. Also
/// remembers when each station was first seen (by id): when it was added, if
/// that was in Bzide; otherwise when Bzide first listed it, as the server
/// doesn't say.
///
/// Kept in a file, as part of the account's data (see `AccountScope`);
/// without a file (in tests) it lasts as long as the store. Logos remembered
/// by the earlier logo-only store are carried over, and looked up again once
/// for the other details.
public final class StationDetailsStore: @unchecked Sendable {
    nonisolated public static let fileName = "StationDetails.json"
    /// The earlier store, which kept logos only.
    nonisolated public static let oldLogosFileName = "StationLogos.json"

    /// What's known about a stream.
    public enum Entry: Equatable, Sendable {
        case details(StationDetails)
        /// Looked up: Radio Browser doesn't have it.
        case notListed
        /// Only a logo is known (carried over from the logo store), not yet
        /// looked up for the rest.
        case logoOnly(URL)
    }

    private struct Saved: Codable {
        var details: [String: StationDetails] = [:]
        var notListed: Set<String> = []
        var logoOnly: [String: URL] = [:]
        var firstSeen: [String: Date] = [:]
        /// `lookUpVersion` when `notListed` was last filled.
        var notListedVersion: Int?
    }

    /// Lookups since this version also search by name, so stations found
    /// "not listed" before it are asked about once more.
    static let lookUpVersion = 2

    private let fileURL: URL?
    private let lock = NSLock()
    private var saved: Saved

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let data = fileURL.flatMap({ try? Data(contentsOf: $0) }), var saved = try? JSONDecoder().decode(Saved.self, from: data) {
            if saved.notListedVersion != Self.lookUpVersion {
                saved.notListed = []
                saved.notListedVersion = Self.lookUpVersion
            }
            self.saved = saved
        } else {
            saved = Saved(notListedVersion: Self.lookUpVersion)
            carryOverOldLogos()
        }
    }

    /// `nil` if nothing is known about this stream yet.
    public func entry(for stream: URL) -> Entry? {
        lock.withLock {
            let key = stream.absoluteString
            if let details = saved.details[key] { return .details(details) }
            if saved.notListed.contains(key) { return .notListed }
            return saved.logoOnly[key].map(Entry.logoOnly)
        }
    }

    /// The details to show: all of them, or just the logo.
    public func details(for stream: URL) -> StationDetails? {
        switch entry(for: stream) {
        case .details(let details): details
        case .logoOnly(let logo): StationDetails(logoURL: logo)
        case .notListed, nil: nil
        }
    }

    /// Whether Radio Browser still has to be asked about this stream.
    public func needsLookUp(_ stream: URL) -> Bool {
        switch entry(for: stream) {
        case .details, .notListed: false
        case .logoOnly, nil: true
        }
    }

    public func set(_ details: StationDetails?, for stream: URL) {
        update { saved in
            let key = stream.absoluteString
            saved.logoOnly[key] = nil
            if let details {
                saved.details[key] = details
                saved.notListed.remove(key)
            } else {
                saved.details[key] = nil
                saved.notListed.insert(key)
            }
        }
    }

    // MARK: - First seen

    public func firstSeen(_ stationID: String) -> Date? {
        lock.withLock { saved.firstSeen[stationID] }
    }

    /// Records `date` for each station not seen before.
    public func noteSeen(_ stationIDs: [String], at date: Date) {
        let new = lock.withLock { stationIDs.filter { saved.firstSeen[$0] == nil } }
        guard !new.isEmpty else { return }
        update { saved in
            for id in new { saved.firstSeen[id] = date }
        }
    }

    // MARK: - Saving

    private func update(_ change: (inout Saved) -> Void) {
        let data: Data? = lock.withLock {
            change(&saved)
            return try? JSONEncoder().encode(saved)
        }
        guard let fileURL, let data else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// The logo-only store kept stream → logo address ("" for none) beside this file.
    private func carryOverOldLogos() {
        guard let old = fileURL?.deletingLastPathComponent().appending(path: Self.oldLogosFileName),
              let data = try? Data(contentsOf: old),
              let logos = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        for (stream, logo) in logos {
            if let url = StationLogo.usableURL(logo) { saved.logoOnly[stream] = url }
        }
        try? FileManager.default.removeItem(at: old)
    }
}
