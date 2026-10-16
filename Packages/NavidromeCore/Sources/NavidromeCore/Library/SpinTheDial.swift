import Foundation
import Observation

/// Spin the Dial's settings (Settings > Spin the Dial).
public struct DialSettings: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// Genres from the user's listening: play history (recent plays
        /// count more) and favorites.
        case myTaste
        /// Genres from the library itself, not from listening.
        case myLibrary
        /// Any working station, anywhere.
        case surpriseMe
        /// Genres outside the user's library and listening, and stations
        /// they haven't saved or dialed before.
        case somethingNew

        public var title: String {
            switch self {
            case .myTaste: "My Taste"
            case .myLibrary: "My Library"
            case .surpriseMe: "Surprise Me"
            case .somethingNew: "Something New"
            }
        }
    }

    public var mode = Mode.myTaste
    /// Only stations from the phone's region.
    public var myCountryOnly = false
    /// Only these genres (Radio Browser tags); none means any.
    public var genres: [String] = []
    /// In kbps.
    public var minimumBitrate: Int?

    public init(mode: Mode = .myTaste, myCountryOnly: Bool = false, genres: [String] = [], minimumBitrate: Int? = nil) {
        self.mode = mode
        self.myCountryOnly = myCountryOnly
        self.genres = genres
        self.minimumBitrate = minimumBitrate
    }

    private enum CodingKeys: String, CodingKey { case mode, myCountryOnly, genres, minimumBitrate }

    /// Anything missing or unknown takes its default.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decodeIfPresent(Mode.self, forKey: .mode)) ?? .myTaste
        myCountryOnly = (try? c.decodeIfPresent(Bool.self, forKey: .myCountryOnly)) ?? false
        genres = (try? c.decodeIfPresent([String].self, forKey: .genres)) ?? []
        minimumBitrate = (try? c.decodeIfPresent(Int.self, forKey: .minimumBitrate)) ?? nil
    }
}

/// Turning the library's genres into Radio Browser's tags, which are
/// lowercase words: "Hip-Hop/Rap; R&B" becomes "hip hop", "rap" and "r&b".
public enum GenreTags {
    /// The tags a genre (as the server names it) stands for.
    public static func tags(fromGenre genre: String) -> [String] {
        genre.split(whereSeparator: { ";/,|".contains($0) })
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// Lowercase, hyphens and underscores as spaces, single-spaced.
    public static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ").joined(separator: " ")
    }

    /// Whether two tags are about the same music: equal, or one is part of
    /// the other ("rock" and "classic rock").
    public static func related(_ a: String, _ b: String) -> Bool {
        let a = normalize(a), b = normalize(b)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.contains(b) || b.contains(a)
    }

    /// Popular tags that aren't genres, left out of Something New.
    static let notGenres: Set<String> = [
        "music", "radio", "fm", "am", "station", "online", "internet", "web", "various", "variety",
        "hits", "top 40", "top40", "news", "talk", "local", "community", "public radio", "college",
        "entertainment", "information", "culture", "public", "free", "live", "mp3", "aac", "hd",
    ]
}

/// What the user listens to, as weights on genre tags.
public struct TasteProfile: Equatable, Sendable {
    public private(set) var weights: [String: Double]

    public init(weights: [String: Double]) {
        self.weights = weights.filter { $0.value > 0 }
    }

    public var isEmpty: Bool { weights.isEmpty }

    /// How long until a play counts half as much.
    public static let halfLife: TimeInterval = 30 * 24 * 60 * 60
    /// What a favorite counts, against a play just now.
    static let favoriteWeight = 0.5

    /// From play history (recent plays count more) and favorites.
    public static func fromListening(history: [PlayHistoryEntry], favorites: [Song], now: Date) -> TasteProfile {
        var weights: [String: Double] = [:]
        for entry in history {
            let age = max(now.timeIntervalSince(entry.playedAt), 0)
            let weight = pow(0.5, age / halfLife)
            for tag in entry.song.genre.map(GenreTags.tags) ?? [] { weights[tag, default: 0] += weight }
        }
        for song in favorites {
            for tag in song.genre.map(GenreTags.tags) ?? [] { weights[tag, default: 0] += favoriteWeight }
        }
        return TasteProfile(weights: weights)
    }

    /// From the library's genres, by how many songs (else albums) each has.
    public static func fromLibrary(_ genres: [Genre]) -> TasteProfile {
        var weights: [String: Double] = [:]
        for genre in genres {
            let size = Double(genre.songCount ?? genre.albumCount ?? 1)
            for tag in GenreTags.tags(fromGenre: genre.name) { weights[tag, default: 0] += size }
        }
        return TasteProfile(weights: weights)
    }

    /// Only the listed genres: their weights here, or, if none of them is
    /// here, all of them equally.
    public func restricted(to tags: [String]) -> TasteProfile {
        let kept = weights.filter { entry in tags.contains { GenreTags.related($0, entry.key) } }
        return kept.isEmpty ? .equal(tags) : TasteProfile(weights: kept)
    }

    public static func equal(_ tags: [String]) -> TasteProfile {
        TasteProfile(weights: Dictionary(tags.map { (GenreTags.normalize($0), 1.0) }, uniquingKeysWith: +))
    }

    /// Whether this taste covers `tag` (or something related to it).
    public func knows(_ tag: String) -> Bool {
        weights.keys.contains { GenreTags.related($0, tag) }
    }

    /// A genre, at random, weighted by the profile but flattened a little,
    /// so the long tail comes up too, not only the favorite.
    public func pick(using random: inout some RandomNumberGenerator) -> String? {
        let entries = weights.sorted { $0.key < $1.key }.map { ($0.key, pow($0.value, 0.6)) }
        let total = entries.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var point = Double.random(in: 0..<total, using: &random)
        for (tag, weight) in entries {
            if point < weight { return tag }
            point -= weight
        }
        return entries.last?.0
    }
}

/// The stations Spin the Dial has played, newest last, so it can avoid
/// repeats and know what's new to the user. Kept in a file, as part of the
/// account's data (see `AccountScope`).
public final class DialLog: @unchecked Sendable {
    nonisolated public static let fileName = "DialLog.json"
    /// How many are remembered.
    static let capacity = 500

    private let fileURL: URL?
    private let lock = NSLock()
    private var ids: [String]

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        ids = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    }

    /// The last `count` dialed, by Radio Browser id.
    public func recent(_ count: Int) -> Set<String> {
        lock.withLock { Set(ids.suffix(count)) }
    }

    public var all: Set<String> { lock.withLock { Set(ids) } }

    public func record(_ id: String) {
        let data: Data? = lock.withLock {
            ids.removeAll { $0 == id }
            ids.append(id)
            if ids.count > Self.capacity { ids.removeFirst(ids.count - Self.capacity) }
            return try? JSONEncoder().encode(ids)
        }
        guard let fileURL, let data else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Spin the Dial: finds a radio station on Radio Browser and plays it,
/// picked by the settings' mode (see `DialSettings.Mode`) within their
/// restrictions (country, genres, quality).
///
/// A spin picks a genre at random, weighted by the taste it's working from
/// (none for Surprise Me), asks Radio Browser for working stations with that
/// tag (best voted first; a random order for Surprise Me), leaves out the
/// last 30 dialed (and, for Something New, every station saved or dialed
/// before), and plays one of the top 40 left at random. If a genre has
/// nothing, it tries others, then any genre (unless the user limited the
/// genres). My Taste falls back to My Library, then to Surprise Me, when
/// there's no history or no genres to go on.
///
/// Only the chosen genre and restrictions go to Radio Browser, never the
/// listening history. Radio plays aren't in play history, so the dial never
/// feeds on itself.
@MainActor
@Observable
public final class SpinTheDialModel {
    public struct Sources: Sendable {
        /// A page of stations for a query (Radio Browser).
        public var stations: @Sendable (RadioBrowserClient.Query) async throws -> [RadioBrowserStation]
        public var history: @MainActor () -> [PlayHistoryEntry]
        public var favorites: @Sendable () async throws -> [Song]
        public var libraryGenres: @Sendable () async throws -> [Genre]
        /// Radio Browser's most common tags, for Something New.
        public var popularTags: @Sendable () async throws -> [RadioBrowserClient.Tag]
        /// The stream addresses of saved stations (server and this iPhone).
        public var savedStreams: @Sendable () async -> Set<URL>
        public var play: @MainActor (RadioStation) async -> Void
        public var countPlay: @Sendable (String) async throws -> Void

        public init(
            stations: @escaping @Sendable (RadioBrowserClient.Query) async throws -> [RadioBrowserStation],
            history: @escaping @MainActor () -> [PlayHistoryEntry],
            favorites: @escaping @Sendable () async throws -> [Song],
            libraryGenres: @escaping @Sendable () async throws -> [Genre],
            popularTags: @escaping @Sendable () async throws -> [RadioBrowserClient.Tag],
            savedStreams: @escaping @Sendable () async -> Set<URL>,
            play: @escaping @MainActor (RadioStation) async -> Void,
            countPlay: @escaping @Sendable (String) async throws -> Void
        ) {
            self.stations = stations
            self.history = history
            self.favorites = favorites
            self.libraryGenres = libraryGenres
            self.popularTags = popularTags
            self.savedStreams = savedStreams
            self.play = play
            self.countPlay = countPlay
        }
    }

    /// What was tuned to, for the banner.
    public struct Tuned: Equatable, Sendable {
        public var station: RadioBrowserStation
        /// The genre it was picked for, if one.
        public var genre: String?

        /// "Tuned to WWOZ · jazz · US".
        public var message: String {
            ["Tuned to \(station.name)", genre, station.countryCode].compactMap(\.self).joined(separator: " · ")
        }
    }

    public private(set) var isSpinning = false
    /// The station last tuned to, kept for Save Station.
    public private(set) var tuned: Tuned?
    /// The banner after a spin; dismissing it keeps `tuned`.
    public private(set) var notice: String?
    public private(set) var error: String?

    /// Station ids for dialed stations start with this, so Next knows to spin again.
    nonisolated public static let stationPrefix = "dial:"
    /// How many recent stations a spin avoids.
    static let avoidRecent = 30
    /// How far down the list a spin picks from.
    static let pickFrom = 40
    static let attempts = 4
    /// How long the listening profile is reused (favorites come from the server).
    static let profileLifetime: TimeInterval = 10 * 60

    @ObservationIgnored private let sources: Sources
    @ObservationIgnored private let log: DialLog
    @ObservationIgnored private var random: DialRandom
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var listening: (made: Date, profile: TasteProfile)?
    @ObservationIgnored private var library: TasteProfile?

    public init(
        sources: Sources, log: DialLog,
        random: some RandomNumberGenerator = SystemRandomNumberGenerator(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.sources = sources
        self.log = log
        self.random = DialRandom(random)
        self.now = now
    }

    /// Whether a song is a station Spin the Dial played.
    nonisolated public static func isDialed(_ song: Song) -> Bool {
        song.id.hasPrefix("radio:" + stationPrefix)
    }

    public func dismissNotice() {
        notice = nil
    }

    public func dismissError() {
        error = nil
    }

    /// Finds a station and plays it. `countryCode` is the phone's region,
    /// used with My Country Only.
    public func spin(_ settings: DialSettings, countryCode: String?) async {
        guard !isSpinning else { return }
        isSpinning = true
        error = nil
        defer { isSpinning = false }
        do {
            let (taste, excluded) = try await plan(settings)
            guard let found = try await find(settings, taste: taste, countryCode: countryCode, excluded: excluded) else {
                error = settings.genres.isEmpty && !settings.myCountryOnly && settings.minimumBitrate == nil
                    ? "Couldn't find a station. Try spinning again."
                    : "Couldn't find a station with these settings. Try fewer restrictions in Settings > Spin the Dial."
                return
            }
            log.record(found.station.id)
            tuned = found
            notice = found.message
            await sources.play(Self.dialStation(found.station))
            let countPlay = sources.countPlay
            let id = found.station.id
            Task { try? await countPlay(id) }
        } catch is URLError {
            error = "Couldn't reach Radio Browser. Check your connection and try again."
        } catch {
            if !Task.isCancelled { self.error = "Couldn't find a station. Try again." }
        }
    }

    /// A dialed station, ready to save (Now Playing's Save Station).
    public struct Savable: Equatable, Sendable {
        public var draft: RadioStationDraft
        public var details: StationDetails?
        /// Its stream address, to tell whether it's saved already.
        public var stream: URL
    }

    /// What Save Station would save for `song`, if it's a dialed station: the
    /// station as the dial found it, if it's the one last tuned to (name,
    /// addresses, logo, country, genres, quality); otherwise (after a
    /// relaunch) what the queue entry kept: its name, stream and logo.
    public func savable(_ song: Song) -> Savable? {
        guard Self.isDialed(song) else { return nil }
        if let tuned, song.id == Self.dialStation(tuned.station).songID {
            let station = tuned.station
            return Savable(draft: station.draft, details: StationDetails(station), stream: station.streamURL)
        }
        guard let stream = song.liveStreamURL else { return nil }
        let logo = song.coverArtID.flatMap(StationLogo.url(fromCoverArtID:))
        return Savable(
            draft: RadioStationDraft(name: song.title, streamURL: stream.absoluteString),
            details: logo.map { StationDetails(logoURL: $0) },
            stream: stream
        )
    }

    /// The station as one to play, marked as dialed.
    nonisolated static func dialStation(_ station: RadioBrowserStation) -> RadioStation {
        var radio = station.radioStation
        radio.id = stationPrefix + station.id
        return radio
    }

    // MARK: - Choosing

    /// The taste to pick genres from (`nil`: any genre), and stations to leave out.
    private func plan(_ settings: DialSettings) async throws -> (TasteProfile?, Set<String>) {
        var excluded = log.recent(Self.avoidRecent)
        var taste: TasteProfile?
        switch settings.mode {
        case .myTaste:
            let listened = try await listeningProfile()
            taste = listened.isEmpty ? try await libraryProfile() : listened
        case .myLibrary:
            taste = try await libraryProfile()
        case .surpriseMe:
            taste = nil
        case .somethingNew:
            excluded.formUnion(log.all)
            if settings.genres.isEmpty {
                taste = try await newGenres()
            }
        }
        if taste?.isEmpty == true { taste = nil }
        if !settings.genres.isEmpty {
            taste = taste.map { $0.restricted(to: settings.genres) } ?? .equal(settings.genres)
        }
        return (taste, excluded)
    }

    /// Up to `attempts` genres, then any genre unless the user limited them.
    private func find(_ settings: DialSettings, taste: TasteProfile?, countryCode: String?, excluded: Set<String>) async throws -> Tuned? {
        let saved = settings.mode == .somethingNew ? await sources.savedStreams() : []
        var tried = Set<String>()
        var remaining = taste
        for _ in 0..<Self.attempts {
            let genre = remaining?.pick(using: &random)
            if let genre {
                tried.insert(genre)
                remaining = remaining.map { TasteProfile(weights: $0.weights.filter { $0.key != genre }) }
            }
            if let found = try await search(settings, genre: genre, countryCode: countryCode, excluded: excluded, saved: saved) {
                return found
            }
            if genre == nil || remaining?.isEmpty != false { break }
        }
        guard taste != nil, settings.genres.isEmpty else { return nil }
        return try await search(settings, genre: nil, countryCode: countryCode, excluded: excluded, saved: saved)
    }

    private func search(_ settings: DialSettings, genre: String?, countryCode: String?, excluded: Set<String>, saved: Set<URL>) async throws -> Tuned? {
        let query = RadioBrowserClient.Query(
            countryCode: settings.myCountryOnly ? countryCode : nil,
            tag: genre, tagIsLoose: true,
            minimumBitrate: settings.minimumBitrate,
            order: genre == nil ? .random : .topRated
        )
        var seenStreams = Set<URL>()
        let candidates = try await sources.stations(query).filter { station in
            !excluded.contains(station.id) && !saved.contains(station.streamURL) && seenStreams.insert(station.streamURL).inserted
        }
        let pool = candidates.prefix(Self.pickFrom)
        guard !pool.isEmpty else { return nil }
        let index = Int.random(in: 0..<pool.count, using: &random)
        return Tuned(station: pool[pool.startIndex + index], genre: genre)
    }

    // MARK: - Profiles

    private func listeningProfile() async throws -> TasteProfile {
        if let listening, now().timeIntervalSince(listening.made) < Self.profileLifetime { return listening.profile }
        // Favorites are a bonus: without the server, history alone.
        let favorites = (try? await sources.favorites()) ?? []
        let profile = TasteProfile.fromListening(history: sources.history(), favorites: favorites, now: now())
        listening = (now(), profile)
        return profile
    }

    private func libraryProfile() async throws -> TasteProfile {
        if let library { return library }
        let profile = TasteProfile.fromLibrary(try await sources.libraryGenres())
        library = profile
        return profile
    }

    /// Popular genres on Radio Browser that the user's listening and library
    /// don't cover.
    private func newGenres() async throws -> TasteProfile {
        let known = try await listeningProfile()
        let owned = (try? await libraryProfile()) ?? TasteProfile(weights: [:])
        let fresh = try await sources.popularTags()
            .map { GenreTags.normalize($0.name) }
            .filter { !GenreTags.notGenres.contains($0) && !known.knows($0) && !owned.knows($0) }
        return .equal(Array(fresh.prefix(80)))
    }
}

/// Any random number generator, held so it can be passed `inout` (tests use
/// a seeded one, so spins are predictable).
struct DialRandom: RandomNumberGenerator {
    private final class Box {
        var base: any RandomNumberGenerator
        init(_ base: any RandomNumberGenerator) { self.base = base }
    }

    private let box: Box

    init(_ base: some RandomNumberGenerator) {
        box = Box(base)
    }

    mutating func next() -> UInt64 {
        box.base.next()
    }
}
