import Foundation

/// Whether the user has all of an album (Gitea #31). Two ways to tell, both
/// used when available:
/// - **Gaps** in the owned songs' track numbers (tracks 1, 2 and 4 of a disc:
///   3 is missing). Always available, from the server alone, but blind to
///   tracks missing from the end.
/// - **The full count** from MusicBrainz (Look Up Artists Online): the
///   release the files are tagged with, else the smallest edition with the
///   same title, so a standard album isn't "missing" a deluxe edition's
///   bonus tracks.
public struct AlbumCompleteness: Equatable, Sendable {
    /// A track's place on the album.
    public struct Position: Hashable, Comparable, Sendable {
        public var disc: Int
        public var track: Int

        public init(disc: Int, track: Int) {
            self.disc = disc
            self.track = track
        }

        public static func < (lhs: Position, rhs: Position) -> Bool {
            (lhs.disc, lhs.track) < (rhs.disc, rhs.track)
        }
    }

    public var owned: Int
    /// How many tracks the album has, when MusicBrainz knows.
    public var total: Int?
    /// Track numbers missing between the owned ones.
    public var gaps: [Position]
    /// Whether the album has more than one disc, to say which disc a gap is on.
    public var isMultiDisc: Bool

    public init(owned: Int, total: Int? = nil, gaps: [Position] = [], isMultiDisc: Bool = false) {
        self.owned = owned
        self.total = total
        self.gaps = gaps
        self.isMultiDisc = isMultiDisc
    }

    public var isIncomplete: Bool {
        !gaps.isEmpty || (total.map { owned < $0 } ?? false)
    }

    /// The short mark in album lists: "9 of 12 tracks", or "Missing tracks"
    /// when only gaps are known; `nil` when nothing seems missing.
    public var badge: String? {
        guard isIncomplete else { return nil }
        if let total, owned < total { return "\(owned) of \(total) tracks" }
        return "Missing tracks"
    }

    /// The album page's line: the count when it's known ("You have 9 of 12
    /// tracks."), else just that some are missing. Never a list of track
    /// numbers: gaps only show what's missing between owned tracks, so a list
    /// would be incomplete (owning track 2 of 8 shows only track 1 missing).
    public var detail: String? {
        guard isIncomplete else { return nil }
        if let total, owned < total { return "You have \(owned) of \(total) tracks." }
        return "Some tracks are missing."
    }

    /// Works it out from what's known: the songs (for gaps), and the artist's
    /// releases from MusicBrainz (for the full count). Without the songs, the
    /// server's song count stands in for what's owned.
    public static func of(_ album: Album, songs: [Song]?, releases: [ReleaseTracks]) -> AlbumCompleteness {
        let owned = songs?.count ?? album.songCount ?? 0
        let discs = Set((songs ?? []).map { $0.discNumber ?? 1 })
        return AlbumCompleteness(
            owned: owned,
            total: expectedTracks(for: album, among: releases),
            gaps: songs.map(gaps(in:)) ?? [],
            isMultiDisc: discs.count > 1
        )
    }

    /// Missing track numbers within each disc the user has. Unknown (none)
    /// unless every song has a track number.
    public static func gaps(in songs: [Song]) -> [Position] {
        guard !songs.isEmpty, songs.allSatisfy({ ($0.track ?? 0) > 0 }) else { return [] }
        let byDisc = Dictionary(grouping: songs) { $0.discNumber ?? 1 }
        return byDisc.flatMap { disc, songs -> [Position] in
            let have = Set(songs.compactMap(\.track))
            guard let last = have.max() else { return [] }
            return (1...last).filter { !have.contains($0) }.map { Position(disc: disc, track: $0) }
        }
        .sorted()
    }

    /// The tagged release's count, else the smallest edition with the same title.
    static func expectedTracks(for album: Album, among releases: [ReleaseTracks]) -> Int? {
        release(for: album, among: releases)?.trackCount
    }

    /// The release the album is: the one its files are tagged with, else the
    /// smallest edition with the same title.
    public static func release(for album: Album, among releases: [ReleaseTracks]) -> ReleaseTracks? {
        if let id = album.musicBrainzID, let tagged = releases.first(where: { $0.id == id }) {
            return tagged
        }
        let key = Discography.matchKey(album.name)
        return releases.filter { Discography.matchKey($0.title) == key }.min { $0.trackCount < $1.trackCount }
    }

    /// The release's tracks the user doesn't have, matched by title (ignoring
    /// case, accents, punctuation and anything in brackets), in the release's order.
    public static func missingTitles(_ tracklist: [String], owned songs: [Song]) -> [String] {
        let have = Set(songs.map { Discography.matchKey($0.title) })
        return tracklist.filter { !have.contains(Discography.matchKey($0)) }
    }
}
