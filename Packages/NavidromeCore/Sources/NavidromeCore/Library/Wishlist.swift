import Foundation
import Observation

/// A song heard on the radio that the user wants to remember (and maybe get).
public struct WishlistEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var artist: String
    public var title: String
    /// The station it was heard on.
    public var station: String?
    public var heardAt: Date
    /// From MusicBrainz, if it was looked up.
    public var album: String?
    public var year: Int?
    public var coverURL: URL?
    public var musicBrainzURL: URL?
    /// When it was first found in the library (cleared if it's gone again),
    /// which Remove Found Songs counts from.
    public var foundAt: Date?

    public init(
        id: UUID = UUID(), artist: String, title: String, station: String? = nil, heardAt: Date,
        album: String? = nil, year: Int? = nil, coverURL: URL? = nil, musicBrainzURL: URL? = nil, foundAt: Date? = nil
    ) {
        self.id = id
        self.artist = artist
        self.title = title
        self.station = station
        self.heardAt = heardAt
        self.album = album
        self.year = year
        self.coverURL = coverURL
        self.musicBrainzURL = musicBrainzURL
        self.foundAt = foundAt
    }

    var song: OnAirSong { OnAirSong(artist: artist, title: title) }

    /// "Paul McCartney - Band on the Run", for copying.
    public var text: String { "\(artist) - \(title)" }
}

/// When songs on the list that turn up in the library are removed, counted
/// from the day they're found.
public enum FoundSongRemoval: Int, CaseIterable, Sendable {
    case immediately = 0
    case week = 7
    case month = 30

    public var title: String {
        switch self {
        case .immediately: "Immediately"
        case .week: "After 7 Days"
        case .month: "After 30 Days"
        }
    }
}

/// Songs heard on the radio to remember, shown to users as "Tagged Radio
/// Songs" (Wishlist is its name in code and in the saved file): added from Now Playing while a
/// station plays a song that isn't in the library. Kept on this iPhone only,
/// in a file, whichever account is signed in (it's about music heard, not a
/// server's library), and never sent anywhere. Newest first.
///
/// Opening the list checks the user's server for each song (as Now Playing's
/// "In Your Library" does); one found there is marked, with the library's
/// copy to play. It stays until the user removes it, or, with Remove Found
/// Songs on (off by default), until `removeFoundAfter` has passed since it
/// was found. The settings are kept in UserDefaults, on this iPhone like the
/// list.
@MainActor
@Observable
public final class Wishlist {
    nonisolated public static let fileName = "Wishlist.json"

    public private(set) var entries: [WishlistEntry]
    /// Entries found in the library since, with the library's song.
    public private(set) var owned: [UUID: Song] = [:]
    /// Remove songs once they're in the library.
    public var removesFound: Bool {
        didSet {
            defaults.set(removesFound, forKey: Self.removesFoundKey)
            removeExpired()
        }
    }
    public var removeFoundAfter: FoundSongRemoval {
        didSet {
            defaults.set(removeFoundAfter.rawValue, forKey: Self.removeFoundAfterKey)
            removeExpired()
        }
    }

    static let removesFoundKey = "wishlistRemovesFound"
    static let removeFoundAfterKey = "wishlistRemoveFoundAfter"

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let defaults: UserDefaults
    /// One check at a time (launch and opening the list can overlap).
    @ObservationIgnored private var isChecking = false
    @ObservationIgnored private let search: OnAirMatchModel.Search
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(
        fileURL: URL?, defaults: UserDefaults = .standard,
        search: @escaping OnAirMatchModel.Search, now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.fileURL = fileURL
        self.defaults = defaults
        removesFound = defaults.bool(forKey: Self.removesFoundKey)
        removeFoundAfter = defaults.object(forKey: Self.removeFoundAfterKey).flatMap { $0 as? Int }.flatMap(FoundSongRemoval.init) ?? .week
        self.search = search
        self.now = now
        entries = fileURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(LossyList<WishlistEntry>.self, from: $0).items }
            ?? []
    }

    /// Whether the song is on the list already (the same title and artist,
    /// as Now Playing's matching goes).
    public func contains(_ song: OnAirSong) -> Bool {
        entries.contains { song.matches(Song(id: $0.id.uuidString, title: $0.title, artist: $0.artist)) }
    }

    /// Adds the song (once), with what MusicBrainz found, if anything.
    public func add(_ song: OnAirSong, station: String?, details: OnAirDetails?) {
        guard !contains(song) else { return }
        let entry = WishlistEntry(
            artist: details?.artist ?? song.artist, title: details?.title ?? song.title, station: station, heardAt: now(),
            album: details?.album, year: details?.year, coverURL: details?.coverURL, musicBrainzURL: details?.musicBrainzURL
        )
        entries.insert(entry, at: 0)
        save()
    }

    public func remove(_ id: WishlistEntry.ID) {
        entries.removeAll { $0.id == id }
        owned[id] = nil
        save()
    }

    /// Looks each song up on the user's server and marks those found (noting
    /// the day it was first found), then removes found songs that are due. A
    /// search that fails leaves that song as it was; one that no longer finds
    /// it starts its count again next time it's found.
    public func checkLibrary() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        var changed = false
        for entry in entries where owned[entry.id] == nil {
            guard let result = await find(entry.song) else { continue }
            // Removed while searching.
            guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { continue }
            owned[entry.id] = result
            let foundAt = result == nil ? nil : entries[index].foundAt ?? now()
            if entries[index].foundAt != foundAt {
                entries[index].foundAt = foundAt
                changed = true
            }
        }
        if changed { save() }
        removeExpired()
    }

    /// The library's copy (`.some(nil)` if it isn't there), or `nil` if a search failed.
    private func find(_ song: OnAirSong) async -> Song?? {
        for query in ["\(song.artist) \(song.title)", song.title, song.artist] {
            guard let results = try? await search(query) else { return nil }
            if let found = results.first(where: song.matches) { return .some(found) }
        }
        return .some(nil)
    }

    /// With Remove Found Songs on, removes songs found at least
    /// `removeFoundAfter` days ago.
    private func removeExpired() {
        guard removesFound else { return }
        let cutoff = now().addingTimeInterval(-Double(removeFoundAfter.rawValue) * 86_400)
        let expired = Set(entries.filter { $0.foundAt.map { $0 <= cutoff } ?? false }.map(\.id))
        guard !expired.isEmpty else { return }
        entries.removeAll { expired.contains($0.id) }
        for id in expired { owned[id] = nil }
        save()
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
