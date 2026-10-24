import Foundation
import Observation

/// Something the user wants to remember, and maybe get (Gitea #33): a song
/// heard on the radio, a song missing from an album they partly have, an
/// album, or an artist.
public struct WishlistEntry: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case radioSong, missingSong, album, artist

        /// The Wishlist's section for it.
        public var sectionTitle: String {
            switch self {
            case .radioSong: "Found on Radio"
            case .missingSong: "Missing Songs"
            case .album: "Albums"
            case .artist: "Artists"
            }
        }
    }

    public var id: UUID
    /// Saved lists from before there were kinds hold radio songs.
    public var kind: Kind
    /// The artist (for an artist entry, its name, as `title` is).
    public var artist: String
    /// The song's or album's title; an artist entry's name.
    public var title: String
    /// The station it was heard on.
    public var station: String?
    /// When it was added (for a radio song, when it was heard).
    public var heardAt: Date
    /// A song's album, if known.
    public var album: String?
    public var year: Int?
    public var coverURL: URL?
    public var musicBrainzURL: URL?
    /// When it was first found in the library (cleared if it's gone again),
    /// which Remove Found Items counts from.
    public var foundAt: Date?

    public init(
        id: UUID = UUID(), kind: Kind = .radioSong, artist: String, title: String, station: String? = nil, heardAt: Date,
        album: String? = nil, year: Int? = nil, coverURL: URL? = nil, musicBrainzURL: URL? = nil, foundAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
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

    private enum CodingKeys: String, CodingKey {
        case id, kind, artist, title, station, heardAt, album, year, coverURL, musicBrainzURL, foundAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            kind: (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .radioSong,
            artist: try c.decode(String.self, forKey: .artist),
            title: try c.decode(String.self, forKey: .title),
            station: try c.decodeIfPresent(String.self, forKey: .station),
            heardAt: try c.decode(Date.self, forKey: .heardAt),
            album: try c.decodeIfPresent(String.self, forKey: .album),
            year: try c.decodeIfPresent(Int.self, forKey: .year),
            coverURL: try c.decodeIfPresent(URL.self, forKey: .coverURL),
            musicBrainzURL: try c.decodeIfPresent(URL.self, forKey: .musicBrainzURL),
            foundAt: try c.decodeIfPresent(Date.self, forKey: .foundAt)
        )
    }

    public var isSong: Bool { kind == .radioSong || kind == .missingSong }

    var song: OnAirSong { OnAirSong(artist: artist, title: title) }

    /// "Paul McCartney - Band on the Run", for copying; an artist's name alone.
    public var text: String { kind == .artist ? artist : "\(artist) - \(title)" }
}

/// What a found entry is in the library.
public enum WishlistMatch: Equatable, Sendable {
    case song(Song)
    case album(Album)
    case artist(Artist)
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

/// The Wishlist (Gitea #33; once "Tagged Radio Songs"): things to remember,
/// and maybe get, in four sections (`sections`, only those with something
/// in them): songs heard on the radio (Now Playing's Tag Song), songs missing
/// from albums the user partly has (an album page's Add Missing Songs), and
/// albums and artists they don't have (Not Owned, Similar Artists). Kept on
/// this iPhone only, in a file, and never sent anywhere; each account has
/// its own list, set aside with its settings when another signs in (see
/// `AccountSettings`). Newest first.
///
/// Opening the list checks the user's server for each entry (a song as Now
/// Playing's "In Your Library" does; an album by title and artist; an artist
/// by name); one found there is marked, with the library's copy to open. It
/// stays until the user removes it, or, with Remove Found Items on (off by
/// default), until `removeFoundAfter` has passed since it was found. The
/// settings are kept in UserDefaults, with the account's other settings.
@MainActor
@Observable
public final class Wishlist {
    nonisolated public static let fileName = "Wishlist.json"

    public private(set) var entries: [WishlistEntry]
    /// Entries found in the library since, with the library's copy.
    public private(set) var found: [UUID: WishlistMatch] = [:]
    /// What the last addition did, e.g. "Added 7 songs to your Wishlist."
    public private(set) var notice: String?
    /// Remove entries once they're in the library.
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

    /// The long-press menu's Buy menu; on by default.
    public var showsBuyMenu: Bool {
        didSet { defaults.set(!showsBuyMenu, forKey: Self.hidesBuyMenuKey) }
    }
    /// Stores turned off, so a store added later shows until it's turned off.
    public var hiddenStores: Set<String> {
        didSet { defaults.set(hiddenStores.sorted(), forKey: Self.hiddenStoresKey) }
    }

    static let removesFoundKey = "wishlistRemovesFound"
    static let removeFoundAfterKey = "wishlistRemoveFoundAfter"
    static let hidesBuyMenuKey = "wishlistHidesBuyMenu"
    static let hiddenStoresKey = "wishlistHiddenStores"

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let defaults: UserDefaults
    /// One check at a time (launch and opening the list can overlap).
    @ObservationIgnored private var isChecking = false
    @ObservationIgnored private let search: OnAirMatchModel.Search
    /// Albums and artists; without it they're never marked found.
    @ObservationIgnored private let searchLibrary: (@Sendable (String) async throws(SubsonicError) -> SearchResult)?
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(
        fileURL: URL?, defaults: UserDefaults = .standard,
        search: @escaping OnAirMatchModel.Search,
        searchLibrary: (@Sendable (String) async throws(SubsonicError) -> SearchResult)? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.fileURL = fileURL
        self.defaults = defaults
        removesFound = defaults.bool(forKey: Self.removesFoundKey)
        removeFoundAfter = defaults.object(forKey: Self.removeFoundAfterKey).flatMap { $0 as? Int }.flatMap(FoundSongRemoval.init) ?? .week
        showsBuyMenu = !defaults.bool(forKey: Self.hidesBuyMenuKey)
        hiddenStores = Set(defaults.stringArray(forKey: Self.hiddenStoresKey) ?? [])
        self.search = search
        self.searchLibrary = searchLibrary
        self.now = now
        entries = fileURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(LossyList<WishlistEntry>.self, from: $0).items }
            ?? []
    }

    /// The entries by kind, in the sections' order, leaving out empty ones.
    public var sections: [(kind: WishlistEntry.Kind, entries: [WishlistEntry])] {
        WishlistEntry.Kind.allCases.compactMap { kind in
            let inKind = entries.filter { $0.kind == kind }
            return inKind.isEmpty ? nil : (kind, inKind)
        }
    }

    /// Songs found in the library, for playing.
    public var owned: [UUID: Song] {
        found.compactMapValues { if case .song(let song) = $0 { song } else { nil } }
    }

    /// Reads its settings again, after they were restored to the defaults.
    /// Reads the list and its settings again: a backup was restored.
    public func reload() {
        entries = fileURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(LossyList<WishlistEntry>.self, from: $0).items }
            ?? []
        found = [:]
        reloadSettings()
    }

    public func reloadSettings() {
        removesFound = defaults.bool(forKey: Self.removesFoundKey)
        removeFoundAfter = defaults.object(forKey: Self.removeFoundAfterKey).flatMap { $0 as? Int }.flatMap(FoundSongRemoval.init) ?? .week
        showsBuyMenu = !defaults.bool(forKey: Self.hidesBuyMenuKey)
        hiddenStores = Set(defaults.stringArray(forKey: Self.hiddenStoresKey) ?? [])
    }

    public func dismissNotice() {
        notice = nil
    }

    /// Says why something couldn't be added (e.g. MusicBrainz didn't answer).
    public func explain(_ message: String) {
        notice = message
    }

    // MARK: - Adding

    /// Whether the song is on the list already, from the radio or an album
    /// (the same title and artist, as Now Playing's matching goes).
    public func contains(_ song: OnAirSong) -> Bool {
        entries.contains { $0.isSong && song.matches(Song(id: $0.id.uuidString, title: $0.title, artist: $0.artist)) }
    }

    /// Adds the song heard on the radio (once), with what MusicBrainz found, if anything.
    public func add(_ song: OnAirSong, station: String?, details: OnAirDetails?) {
        guard !contains(song) else { return }
        let entry = WishlistEntry(
            artist: details?.artist ?? song.artist, title: details?.title ?? song.title, station: station, heardAt: now(),
            album: details?.album, year: details?.year, coverURL: details?.coverURL, musicBrainzURL: details?.musicBrainzURL
        )
        entries.insert(entry, at: 0)
        save()
    }

    /// Adds an album's missing songs (those not on the list already), in the
    /// album's order, and says how many. Returns how many were added.
    @discardableResult
    public func addMissingSongs(
        _ titles: [String], album: String, artist: String, year: Int?, coverURL: URL?, musicBrainzURL: URL?
    ) -> Int {
        var added: [WishlistEntry] = []
        for title in titles where !title.isEmpty {
            let song = OnAirSong(artist: artist, title: title)
            guard !contains(song), !added.contains(where: { song.matches(Song(id: "", title: $0.title, artist: $0.artist)) }) else { continue }
            added.append(WishlistEntry(
                kind: .missingSong, artist: artist, title: title, heardAt: now(),
                album: album, year: year, coverURL: coverURL, musicBrainzURL: musicBrainzURL
            ))
        }
        notice = switch added.count {
        case 0: "Those songs are already on your Wishlist."
        case 1: "Added 1 song to your Wishlist."
        default: "Added \(added.count) songs to your Wishlist."
        }
        guard !added.isEmpty else { return 0 }
        entries.insert(contentsOf: added, at: 0)
        save()
        return added.count
    }

    /// The same, for songs missing from the user's copy of an album, with the
    /// MusicBrainz release they're from for the cover and the link.
    @discardableResult
    public func addMissingSongs(_ titles: [String], from album: Album, release: ReleaseTracks) -> Int {
        addMissingSongs(
            titles, album: album.name, artist: album.artist ?? "", year: album.year,
            coverURL: MusicBrainzClient.coverArtURL.appending(path: "release/\(release.id)/front-250"),
            musicBrainzURL: URL(string: "https://musicbrainz.org/release/\(release.id)")
        )
    }

    public func containsAlbum(titled title: String, by artist: String) -> Bool {
        entries.contains { $0.kind == .album && Self.sameAlbum($0.title, title) && Self.sameName($0.artist, artist) }
    }

    public func addAlbum(titled title: String, by artist: String, year: Int?, coverURL: URL?, musicBrainzURL: URL?) {
        guard !containsAlbum(titled: title, by: artist) else { return }
        entries.insert(WishlistEntry(
            kind: .album, artist: artist, title: title, heardAt: now(), year: year, coverURL: coverURL, musicBrainzURL: musicBrainzURL
        ), at: 0)
        notice = "Added “\(title)” to your Wishlist."
        save()
    }

    public func containsArtist(named name: String) -> Bool {
        entries.contains { $0.kind == .artist && Self.sameName($0.artist, name) }
    }

    public func addArtist(named name: String, musicBrainzURL: URL?) {
        guard !containsArtist(named: name) else { return }
        entries.insert(WishlistEntry(kind: .artist, artist: name, title: name, heardAt: now(), musicBrainzURL: musicBrainzURL), at: 0)
        notice = "Added \(name) to your Wishlist."
        save()
    }

    public func remove(_ id: WishlistEntry.ID) {
        entries.removeAll { $0.id == id }
        found[id] = nil
        save()
    }

    // MARK: - In the library

    /// Looks each entry up on the user's server and marks those found (noting
    /// the day it was first found), then removes found ones that are due. A
    /// search that fails leaves that entry as it was; one that no longer finds
    /// it starts its count again next time it's found.
    public func checkLibrary() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        var changed = false
        for entry in entries where found[entry.id] == nil {
            guard let result = await find(entry) else { continue }
            // Removed while searching.
            guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { continue }
            found[entry.id] = result
            let foundAt = result == nil ? nil : entries[index].foundAt ?? now()
            if entries[index].foundAt != foundAt {
                entries[index].foundAt = foundAt
                changed = true
            }
        }
        if changed { save() }
        removeExpired()
    }

    /// The library's copy (`.some(nil)` if it isn't there), or `nil` if a
    /// search failed or can't be made.
    private func find(_ entry: WishlistEntry) async -> WishlistMatch?? {
        switch entry.kind {
        case .radioSong, .missingSong:
            let song = entry.song
            for query in ["\(song.artist) \(song.title)", song.title, song.artist] {
                guard let results = try? await search(query) else { return nil }
                if let match = results.first(where: song.matches) { return .some(.song(match)) }
            }
            return .some(nil)
        case .album:
            guard let searchLibrary, let results = try? await searchLibrary(entry.title) else { return nil }
            let match = results.albums.first { Self.sameAlbum($0.name, entry.title) && Self.sameName($0.artist ?? "", entry.artist) }
            return .some(match.map(WishlistMatch.album))
        case .artist:
            guard let searchLibrary, let results = try? await searchLibrary(entry.artist) else { return nil }
            return .some(results.artists.first { Self.sameName($0.name, entry.artist) }.map(WishlistMatch.artist))
        }
    }

    /// With Remove Found Items on, removes entries found at least
    /// `removeFoundAfter` days ago.
    private func removeExpired() {
        guard removesFound else { return }
        let cutoff = now().addingTimeInterval(-Double(removeFoundAfter.rawValue) * 86_400)
        let expired = Set(entries.filter { $0.foundAt.map { $0 <= cutoff } ?? false }.map(\.id))
        guard !expired.isEmpty else { return }
        entries.removeAll { expired.contains($0.id) }
        for id in expired { found[id] = nil }
        save()
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Titles match as Not Owned's do: ignoring case, accents, punctuation
    /// and anything in brackets ("Abbey Road (Remastered)" is "Abbey Road").
    static func sameAlbum(_ a: String, _ b: String) -> Bool {
        Discography.matchKey(a) == Discography.matchKey(b)
    }

    static func sameName(_ a: String, _ b: String) -> Bool {
        MusicBrainzClient.nameKey(a) == MusicBrainzClient.nameKey(b)
    }
}
