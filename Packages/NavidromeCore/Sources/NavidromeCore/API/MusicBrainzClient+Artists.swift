import Foundation

/// Artists on MusicBrainz, for Look Up Artists Online: finding one by name
/// (when the server has no MusicBrainz id), their links (to Wikipedia), and
/// their release groups (albums, singles, live albums…). Only the artist's
/// name or id is sent.
extension MusicBrainzClient {
    /// Where an artist's biography can be found.
    public struct ArtistLinks: Equatable, Sendable {
        /// A Wikidata item ("Q11649"), which leads to Wikipedia in any language.
        public var wikidataID: String?
        /// A Wikipedia article linked directly (older entries).
        public var wikipediaURL: URL?
    }

    /// Browsing gives at most 100 a page; this many pages is plenty for
    /// almost anyone, and keeps a huge catalog from taking minutes.
    static let releaseGroupPageSize = 100
    static let releaseGroupPages = 4

    /// The id of the artist with exactly this name (ignoring case and
    /// accents), the best scored if there are several; `nil` if none.
    public func artistID(named name: String) async throws -> String? {
        guard !contact.isEmpty else { throw Failure.noContact }
        struct Search: Decodable {
            struct Found: Decodable {
                let id: String
                let name: String?
                let score: Int?
            }
            let artists: [Found]?
        }
        let url = try Self.url("artist", [
            .init(name: "query", value: "artist:\"\(Self.escaped(name))\""), .init(name: "limit", value: "10"),
        ])
        let found = try JSONDecoder().decode(Search.self, from: try await get(url, paced: true)).artists ?? []
        let wanted = Self.nameKey(name)
        return found
            .filter { ($0.score ?? 0) >= 90 && $0.name.map(Self.nameKey) == wanted }
            .max { ($0.score ?? 0) < ($1.score ?? 0) }?
            .id
    }

    public func links(artistID: String) async throws -> ArtistLinks {
        guard !contact.isEmpty else { throw Failure.noContact }
        struct Artist: Decodable {
            struct Relation: Decodable {
                struct Target: Decodable { let resource: String? }
                let type: String?
                let url: Target?
            }
            let relations: [Relation]?
        }
        let url = try Self.url("artist/\(artistID)", [.init(name: "inc", value: "url-rels")])
        let relations = try JSONDecoder().decode(Artist.self, from: try await get(url, paced: true)).relations ?? []
        func resource(_ type: String) -> URL? {
            relations.first { $0.type == type }?.url?.resource.flatMap(URL.init(string:))
        }
        let wikidata = resource("wikidata")?.lastPathComponent
        return ArtistLinks(wikidataID: wikidata?.hasPrefix("Q") == true ? wikidata : nil, wikipediaURL: resource("wikipedia"))
    }

    /// Everything MusicBrainz's own site shows for the artist (official
    /// releases; no bootlegs), up to `releaseGroupPages` pages.
    public func releaseGroups(artistID: String) async throws -> [DiscographyRelease] {
        guard !contact.isEmpty else { throw Failure.noContact }
        var releases: [DiscographyRelease] = []
        for page in 0..<Self.releaseGroupPages {
            let url = try Self.url("release-group", [
                .init(name: "artist", value: artistID),
                .init(name: "release-group-status", value: "website-default"),
                .init(name: "limit", value: String(Self.releaseGroupPageSize)),
                .init(name: "offset", value: String(page * Self.releaseGroupPageSize)),
            ])
            let browse = try JSONDecoder().decode(ReleaseGroupBrowse.self, from: try await get(url, paced: true))
            let groups = browse.groups ?? []
            releases += groups.compactMap(\.release)
            let total = browse.count ?? 0
            if groups.count < Self.releaseGroupPageSize || (page + 1) * Self.releaseGroupPageSize >= total { break }
        }
        return releases
    }

    /// The album on MusicBrainz's website: the exact release its files are
    /// tagged with, else a search for its title and artist. Only a link,
    /// opened by the user; nothing is sent until then.
    public static func albumPage(_ album: Album) -> URL? {
        if let id = album.musicBrainzID {
            return URL(string: "https://musicbrainz.org/release/\(id)")
        }
        var query = "release:\"\(escaped(album.name))\""
        if let artist = album.artist, !artist.isEmpty { query += " AND artist:\"\(escaped(artist))\"" }
        var components = URLComponents(string: "https://musicbrainz.org/search")
        components?.queryItems = [
            .init(name: "query", value: query), .init(name: "type", value: "release"), .init(name: "method", value: "advanced"),
        ]
        return components?.url
    }

    /// The artist's official releases (every edition of every album) with how
    /// many audio tracks each has, to tell whether an album the user owns is
    /// complete (`AlbumCompleteness`). Up to `releaseGroupPages` pages.
    public func releaseTracks(artistID: String) async throws -> [ReleaseTracks] {
        guard !contact.isEmpty else { throw Failure.noContact }
        var releases: [ReleaseTracks] = []
        for page in 0..<Self.releaseGroupPages {
            let url = try Self.url("release", [
                .init(name: "artist", value: artistID),
                .init(name: "status", value: "official"),
                .init(name: "inc", value: "media"),
                .init(name: "limit", value: String(Self.releaseGroupPageSize)),
                .init(name: "offset", value: String(page * Self.releaseGroupPageSize)),
            ])
            let browse = try JSONDecoder().decode(ReleaseBrowse.self, from: try await get(url, paced: true))
            let found = browse.releases ?? []
            releases += found.compactMap(\.tracks)
            let total = browse.count ?? 0
            if found.count < Self.releaseGroupPageSize || (page + 1) * Self.releaseGroupPageSize >= total { break }
        }
        return releases
    }

    struct ReleaseBrowse: Decodable {
        struct Release: Decodable {
            struct Medium: Decodable {
                let format: String?
                let trackCount: Int?
                private enum CodingKeys: String, CodingKey { case format, trackCount = "track-count" }
            }
            let id: String
            let title: String?
            let media: [Medium]?

            /// Audio tracks only: a deluxe edition's DVD isn't missing songs.
            var tracks: ReleaseTracks? {
                guard let title, !title.isEmpty else { return nil }
                let audio = (media ?? []).filter { medium in
                    let format = (medium.format ?? "").lowercased()
                    return !["dvd", "blu-ray", "vhs", "hd-dvd"].contains { format.contains($0) }
                }
                let count = audio.reduce(0) { $0 + ($1.trackCount ?? 0) }
                return count > 0 ? ReleaseTracks(id: id, title: title, trackCount: count) : nil
            }
        }
        let count: Int?
        let releases: [Release]?
        private enum CodingKeys: String, CodingKey { case count = "release-count", releases }
    }

    struct ReleaseGroupBrowse: Decodable {
        struct Group: Decodable {
            let id: String
            let title: String?
            let primaryType: String?
            let secondaryTypes: [String]?
            let firstReleaseDate: String?
            private enum CodingKeys: String, CodingKey {
                case id, title, primaryType = "primary-type", secondaryTypes = "secondary-types", firstReleaseDate = "first-release-date"
            }

            var release: DiscographyRelease? {
                guard let title, !title.isEmpty else { return nil }
                return DiscographyRelease(
                    id: id, title: title,
                    year: firstReleaseDate.flatMap { Int($0.prefix(4)) },
                    kind: MusicBrainzClient.kind(primary: primaryType, secondary: secondaryTypes ?? []),
                    coverURL: MusicBrainzClient.coverArtURL.appending(path: "release-group/\(id)/front-250"),
                    pageURL: URL(string: "https://musicbrainz.org/release-group/\(id)")
                )
            }
        }
        let count: Int?
        let groups: [Group]?
        private enum CodingKeys: String, CodingKey { case count = "release-group-count", groups = "release-groups" }
    }

    /// A live album is Live, not Albums; a compilation of singles is a Compilation.
    static func kind(primary: String?, secondary: [String]) -> DiscographyRelease.Kind {
        if secondary.contains("Live") { return .live }
        if secondary.contains("Compilation") { return .compilation }
        if secondary.contains("Soundtrack") { return .soundtrack }
        if secondary.contains("Remix") || secondary.contains("DJ-mix") { return .remix }
        guard secondary.isEmpty else { return .other }
        switch primary {
        case "Album": return .album
        case "EP": return .ep
        case "Single": return .single
        default: return .other
        }
    }

    private static func url(_ path: String, _ query: [URLQueryItem]) throws -> URL {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = query + [.init(name: "fmt", value: "json")]
        guard let url = components?.url else { throw URLError(.badURL) }
        return url
    }

    static func nameKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
