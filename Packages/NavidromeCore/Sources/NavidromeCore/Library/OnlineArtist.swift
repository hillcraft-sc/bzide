import Foundation
import Observation

/// Which artist to look up online: their name, and their MusicBrainz id when
/// the server has one (which saves guessing by name).
public struct ArtistReference: Hashable, Sendable {
    public var name: String
    public var musicBrainzID: String?

    public init(name: String, musicBrainzID: String? = nil) {
        self.name = name
        self.musicBrainzID = musicBrainzID.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// A longer biography than the server's, from an outside source.
public struct ArtistBiography: Codable, Equatable, Sendable {
    public var text: String
    /// Who wrote it, for the credit ("Wikipedia").
    public var source: String
    /// Where to read the rest.
    public var pageURL: URL?

    public init(text: String, source: String, pageURL: URL? = nil) {
        self.text = text
        self.source = source
        self.pageURL = pageURL
    }
}

/// One of an artist's releases from an outside catalog (a MusicBrainz
/// release group today; Apple Music could be another source later).
public struct DiscographyRelease: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: Int, Codable, CaseIterable, Comparable, Sendable {
        case album, ep, single, live, compilation, soundtrack, remix, other

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }

        public var title: String {
            switch self {
            case .album: "Albums"
            case .ep: "EPs"
            case .single: "Singles"
            case .live: "Live"
            case .compilation: "Compilations"
            case .soundtrack: "Soundtracks"
            case .remix: "Remixes"
            case .other: "Other"
            }
        }
    }

    public var id: String
    public var title: String
    public var year: Int?
    public var kind: Kind
    public var coverURL: URL?
    /// Where to see it (the MusicBrainz page).
    public var pageURL: URL?

    public init(id: String, title: String, year: Int? = nil, kind: Kind, coverURL: URL? = nil, pageURL: URL? = nil) {
        self.id = id
        self.title = title
        self.year = year
        self.kind = kind
        self.coverURL = coverURL
        self.pageURL = pageURL
    }
}

/// Releases of one kind the user doesn't have, newest first.
public struct DiscographySection: Equatable, Identifiable, Sendable {
    public var kind: DiscographyRelease.Kind
    public var releases: [DiscographyRelease]
    public var id: DiscographyRelease.Kind { kind }
}

/// Where the artist page's online extras come from. The MusicBrainz and
/// Wikipedia version is `OnlineArtistLookup`; tests use fakes.
public protocol ArtistLookup: Sendable {
    /// `nil` when there's none.
    func biography(for artist: ArtistReference) async throws -> ArtistBiography?
    /// Empty when the artist can't be found.
    func discography(for artist: ArtistReference) async throws -> [DiscographyRelease]
    /// Every official release with its track count; empty when the artist
    /// can't be found. For `AlbumCompleteness`.
    func releaseTracks(for artist: ArtistReference) async throws -> [ReleaseTracks]
    /// A release's track titles, in order. For the Wishlist's missing songs.
    func tracklist(releaseID: String) async throws -> [String]
}

extension ArtistLookup {
    public func releaseTracks(for artist: ArtistReference) async throws -> [ReleaseTracks] { [] }
    public func tracklist(releaseID: String) async throws -> [String] { [] }
}

/// One release (an edition of an album) and how many audio tracks it has.
public struct ReleaseTracks: Codable, Equatable, Sendable {
    /// MusicBrainz's release id, as tagged in files by Picard.
    public var id: String
    public var title: String
    public var trackCount: Int

    public init(id: String, title: String, trackCount: Int) {
        self.id = id
        self.title = title
        self.trackCount = trackCount
    }
}

public enum Discography {
    /// The releases that aren't among the user's albums, by kind (in
    /// `Kind` order), each newest first. An album counts as owned when its
    /// title matches, ignoring case, accents, punctuation and anything in
    /// brackets ("Abbey Road (Remastered)" is "Abbey Road").
    public static func notOwned(_ releases: [DiscographyRelease], owned: [Album]) -> [DiscographySection] {
        let ownedTitles = Set(owned.map { matchKey($0.name) })
        let missing = releases.filter { !ownedTitles.contains(matchKey($0.title)) }
        return Dictionary(grouping: missing, by: \.kind)
            .sorted { $0.key < $1.key }
            .map { kind, releases in
                DiscographySection(kind: kind, releases: releases.sorted { lhs, rhs in
                    if lhs.year != rhs.year { return (lhs.year ?? .min) > (rhs.year ?? .min) }
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                })
            }
    }

    static func matchKey(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let unbracketed = folded.replacing(#/\s*[\(\[][^\)\]]*[\)\]]/#, with: "")
        let key = Self.letters(unbracketed.replacing("&", with: "and"))
        return key.isEmpty ? Self.letters(folded) : key
    }

    private static func letters(_ text: String) -> String {
        String(text.unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
    }
}

/// An artist page's online extras, while Look Up Artists Online is on: a
/// longer biography, and the releases the user doesn't have. Loaded after
/// the page's own data, so they never hold it up; a failed biography lookup
/// leaves the server's.
@MainActor
@Observable
public final class OnlineArtistModel {
    public enum State: Equatable, Sendable {
        case off
        case loading
        case loaded([DiscographySection])
        case failed
    }

    public private(set) var biography: ArtistBiography?
    public private(set) var discography: State = .off

    @ObservationIgnored private let lookup: any ArtistLookup

    /// MusicBrainz's id for Various Artists, whose "discography" is every
    /// compilation ever made.
    static let variousArtistsID = "89ad4ac3-39f7-470e-963a-56509c546377"

    public init(lookup: any ArtistLookup) {
        self.lookup = lookup
    }

    public func load(_ artist: Artist, info: ArtistInfo?, enabled: Bool) async {
        let reference = ArtistReference(name: artist.name, musicBrainzID: artist.musicBrainzID ?? info?.musicBrainzID)
        guard enabled, !reference.name.isEmpty, reference.musicBrainzID != Self.variousArtistsID else {
            biography = nil
            discography = .off
            return
        }
        if case .loaded = discography {} else { discography = .loading }
        if let found = try? await lookup.biography(for: reference) {
            biography = found
        }
        do {
            let releases = try await lookup.discography(for: reference)
            discography = .loaded(Discography.notOwned(releases, owned: artist.albums))
        } catch {
            // The page went away; it loads again when it comes back.
            if Task.isCancelled { return }
            if case .loaded = discography { return }
            discography = .failed
        }
    }
}
