import Foundation
import os

/// What MusicBrainz knows about a song a station is playing, for Song Info
/// and the cover on Now Playing.
public struct OnAirDetails: Equatable, Sendable {
    public var title: String
    public var artist: String
    /// The earliest official studio album it's on, if any.
    public var album: String?
    public var year: Int?
    /// Seconds.
    public var length: Int?
    public var recordingID: String
    public var releaseGroupID: String?
    /// The album's front cover (Cover Art Archive), once it's known to exist.
    public var coverURL: URL?

    public init(
        title: String, artist: String, album: String? = nil, year: Int? = nil, length: Int? = nil,
        recordingID: String, releaseGroupID: String? = nil, coverURL: URL? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.year = year
        self.length = length
        self.recordingID = recordingID
        self.releaseGroupID = releaseGroupID
        self.coverURL = coverURL
    }

    public var musicBrainzURL: URL? { URL(string: "https://musicbrainz.org/recording/\(recordingID)") }
}

/// Looks songs up on MusicBrainz (musicbrainz.org), the free, open music
/// database, and their covers on the Cover Art Archive, for a song a radio
/// station announces. Only used while the user has Look Up Songs Online on;
/// only the artist and title are sent. It also finds artists for Look Up
/// Artists Online (see `MusicBrainzClient+Artists.swift`).
///
/// MusicBrainz's rules, followed here: every request names the app and a
/// contact (`contact`, from Info.plist; with none, nothing is asked), and at
/// most one request a second (`minimumGap`, kept by this actor, so the app
/// shares one).
///
/// A song is searched among official studio albums first (so a live bootleg
/// doesn't win), taking the earliest; with none, the best match on any
/// release. A recording counts only if its title and artist match the
/// announced ones (see `OnAirSong.matches`).
public actor MusicBrainzClient {
    public enum Failure: Error, Equatable, Sendable {
        case noContact
        case badResponse(Int)
    }

    public static let baseURL = URL(string: "https://musicbrainz.org/ws/2/") ?? URL(filePath: "/")
    public static let coverArtURL = URL(string: "https://coverartarchive.org/") ?? URL(filePath: "/")
    /// MusicBrainz allows one request a second; a little more, to be safe.
    static let minimumGap: TimeInterval = 1.1
    /// When it says it's busy (503), it's asked again after this, up to `busyRetries` times.
    static let busyWait: TimeInterval = 2
    static let busyRetries = 2

    private let transport: any HTTPTransport
    let contact: String
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var lastRequest: Date?
    private static let logger = Logger(subsystem: "MusicApp", category: "MusicBrainz")

    public init(
        contact: String, transport: any HTTPTransport = URLSessionTransport(),
        now: @escaping @Sendable () -> Date = { .now },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.contact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
        self.now = now
        self.sleep = sleep
    }

    var userAgent: String { "Bzide/1.0 ( \(contact) )" }

    /// The song, if MusicBrainz has it.
    public func details(for song: OnAirSong) async throws -> OnAirDetails? {
        guard !contact.isEmpty else { throw Failure.noContact }
        let phrase = "recording:\"\(Self.escaped(song.title))\" AND artist:\"\(Self.escaped(song.artist))\""
        let studio = try await recordings(phrase + " AND status:official AND primarytype:album")
        var found = Self.pick(studio, for: song, studioOnly: true)
        if found == nil {
            found = Self.pick(try await recordings(phrase), for: song, studioOnly: false)
        }
        if let group = found?.releaseGroupID {
            found?.coverURL = (try? await cover(releaseGroup: group)) ?? nil
        }
        return found
    }

    // MARK: - Reading

    private struct Search: Decodable {
        let recordings: [Recording]?
    }

    struct Recording: Decodable {
        struct Credit: Decodable { let name: String? }
        struct Release: Decodable {
            struct Group: Decodable {
                let id: String?
                let primaryType: String?
                let secondaryTypes: [String]?
                private enum CodingKeys: String, CodingKey { case id, primaryType = "primary-type", secondaryTypes = "secondary-types" }
            }
            let title: String?
            let date: String?
            let status: String?
            let releaseGroup: Group?
            private enum CodingKeys: String, CodingKey { case title, date, status, releaseGroup = "release-group" }

            var isStudioAlbum: Bool {
                status == "Official" && releaseGroup?.primaryType == "Album" && (releaseGroup?.secondaryTypes ?? []).isEmpty
            }

            var year: Int? { date.flatMap { Int($0.prefix(4)) } }
        }
        let id: String
        let title: String?
        let length: Int?
        let score: Int?
        let artistCredit: [Credit]?
        let releases: [Release]?
        private enum CodingKeys: String, CodingKey { case id, title, length, score, artistCredit = "artist-credit", releases }

        var artist: String { (artistCredit ?? []).compactMap(\.name).joined(separator: " & ") }
    }

    /// The best match among recordings: for `studioOnly`, the one on the
    /// earliest studio album; otherwise the highest scored, on its earliest
    /// official release (else any).
    static func pick(_ recordings: [Recording], for song: OnAirSong, studioOnly: Bool) -> OnAirDetails? {
        let matching = recordings.filter { recording in
            (recording.score ?? 0) >= 80
                && song.matches(Song(id: recording.id, title: recording.title ?? "", artist: recording.artist))
        }
        var best: (recording: Recording, release: Recording.Release?)?
        var bestKey: (Int, Int) = (Int.max, Int.max)
        for recording in matching {
            let releases = recording.releases ?? []
            let candidates = studioOnly ? releases.filter(\.isStudioAlbum) : releases
            guard studioOnly ? !candidates.isEmpty : true else { continue }
            let release = candidates.filter { $0.status == "Official" }.min { ($0.year ?? .max) < ($1.year ?? .max) }
                ?? candidates.min { ($0.year ?? .max) < ($1.year ?? .max) }
            // Studio: the earliest album. Otherwise: the best score, then the earliest.
            let key = studioOnly ? (release?.year ?? .max, -(recording.score ?? 0)) : (-(recording.score ?? 0), release?.year ?? .max)
            if key < bestKey {
                bestKey = key
                best = (recording, release)
            }
        }
        guard let best else { return nil }
        return OnAirDetails(
            title: best.recording.title ?? song.title,
            artist: best.recording.artist.isEmpty ? song.artist : best.recording.artist,
            album: best.release?.title,
            year: best.release?.year,
            length: best.recording.length.map { $0 / 1000 },
            recordingID: best.recording.id,
            releaseGroupID: best.release?.releaseGroup?.id
        )
    }

    // MARK: - Requests

    private func recordings(_ query: String) async throws -> [Recording] {
        var components = URLComponents(url: Self.baseURL.appending(path: "recording"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "query", value: query), .init(name: "fmt", value: "json"), .init(name: "limit", value: "25")]
        guard let url = components?.url else { throw URLError(.badURL) }
        let data = try await get(url, paced: true)
        return (try JSONDecoder().decode(Search.self, from: data)).recordings ?? []
    }

    /// The album's front cover, if the Cover Art Archive has one (`nil` if not).
    private func cover(releaseGroup id: String) async throws -> URL? {
        struct Covers: Decodable {
            struct Image: Decodable {
                let front: Bool?
                let image: String?
                let thumbnails: [String: String]?
            }
            let images: [Image]?
        }
        let url = Self.coverArtURL.appending(path: "release-group/\(id)")
        guard let data = try? await get(url, paced: false),
              let covers = try? JSONDecoder().decode(Covers.self, from: data),
              let front = covers.images?.first(where: { $0.front == true }) ?? covers.images?.first else { return nil }
        let address = front.thumbnails?["500"] ?? front.thumbnails?["large"] ?? front.image
        return address.flatMap(StationLogo.usableURL)
    }

    /// `paced`: MusicBrainz itself, kept to one request a second and asked
    /// again when busy. The Cover Art Archive isn't limited that way.
    func get(_ url: URL, paced: Bool) async throws -> Data {
        var attempt = 0
        while true {
            do {
                return try await getOnce(url, paced: paced)
            } catch Failure.badResponse(503) where paced && attempt < Self.busyRetries {
                attempt += 1
                try await sleep(Self.busyWait)
            }
        }
    }

    private func getOnce(_ url: URL, paced: Bool) async throws -> Data {
        if paced {
            if let lastRequest {
                let wait = Self.minimumGap - now().timeIntervalSince(lastRequest)
                if wait > 0 { try await sleep(wait) }
            }
            lastRequest = now()
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            Self.logger.error("GET \(url.path(), privacy: .public) failed: HTTP \(response.statusCode, privacy: .public)")
            throw Failure.badResponse(response.statusCode)
        }
        return data
    }

    /// For inside a quoted phrase of MusicBrainz's search syntax.
    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// MusicBrainz's details for the song a station is playing, while Look Up
/// Songs Online is on: each announced song once (remembered for the session,
/// found or not; failures aren't), the newest always winning.
@MainActor
@Observable
public final class OnAirInfoModel {
    public typealias Lookup = @Sendable (OnAirSong) async throws -> OnAirDetails?

    /// For the song on air, if found.
    public private(set) var details: OnAirDetails?

    @ObservationIgnored private let lookup: Lookup
    @ObservationIgnored private var answers: [OnAirSong: OnAirDetails?] = [:]
    @ObservationIgnored private var latest: OnAirSong?

    public init(lookup: @escaping Lookup) {
        self.lookup = lookup
    }

    public func update(_ song: OnAirSong?, enabled: Bool) async {
        latest = song
        guard enabled, let song else {
            details = nil
            return
        }
        if let known = answers[song] {
            details = known
            return
        }
        details = nil
        do {
            let found = try await lookup(song)
            guard latest == song, !Task.isCancelled else { return }
            answers[song] = found
            details = found
        } catch {
            // Asked again if the song comes round again.
        }
    }
}


extension OnAirSong {
    /// Song Info's sections when nothing more is known: what the station said.
    public var sections: [InfoSection] {
        [InfoSection(title: "Song", rows: [InfoRow(label: "Title", value: title), InfoRow(label: "Artist", value: artist)])]
    }
}

extension OnAirDetails {
    /// Song Info's sections for a song on air.
    public var sections: [InfoSection] {
        var song = [InfoRow(label: "Title", value: title), InfoRow(label: "Artist", value: artist)]
        if let album { song.append(InfoRow(label: "Album", value: album)) }
        if let year { song.append(InfoRow(label: "Year", value: String(year))) }
        if let length { song.append(InfoRow(label: "Length", value: Duration.seconds(length).formatted(.time(pattern: .minuteSecond)))) }
        var sections = [InfoSection(title: "Song", rows: song)]
        if let musicBrainzURL {
            sections.append(InfoSection(title: "MusicBrainz", rows: [InfoRow(label: "Page", value: musicBrainzURL.absoluteString)]))
        }
        return sections
    }
}
