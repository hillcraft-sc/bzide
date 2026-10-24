import Foundation

/// What the server knows about an artist beyond the library (`getArtistInfo2`),
/// usually fetched from Last.fm. Every field may be missing.
public struct ArtistInfo: Sendable, Equatable, Decodable {
    /// Plain text, ready to show; `nil` when the server has none.
    public var biography: String?
    /// The artist's MusicBrainz id, if the server has it.
    public var musicBrainzID: String?
    /// Artists like this one (usually from Last.fm), in the server's order,
    /// including ones not in the library.
    public var similarArtists: [SimilarArtist]

    public init(biography: String? = nil, musicBrainzID: String? = nil, similarArtists: [SimilarArtist] = []) {
        self.biography = biography
        self.musicBrainzID = musicBrainzID
        self.similarArtists = similarArtists
    }

    private enum ServerKeys: String, CodingKey { case biography, musicBrainzId, similarArtist }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: ServerKeys.self)
        self.init(
            biography: c.lenientString(.biography).flatMap(Self.plainText),
            musicBrainzID: c.lenientString(.musicBrainzId).flatMap { $0.isEmpty ? nil : $0 },
            similarArtists: c.lossyArray(Artist.self, forKey: .similarArtist).compactMap(SimilarArtist.init)
        )
    }

    /// Last.fm biographies are HTML and end with a "Read more on Last.fm" link,
    /// which has nowhere to go in plain text, so it's dropped with the tags.
    static func plainText(fromHTML html: String) -> String? {
        var text = html.replacing(#/<a\b[^>]*>\s*Read more on Last\.fm\s*</a>\.?/#.ignoresCase(), with: "")
        text = text.replacing(#/<br\s*\/?>|<\/p>/#.ignoresCase(), with: "\n")
        text = text.replacing(#/<[^>]+>/#, with: "")
        for (entity, character) in entities {
            text = text.replacing(entity, with: character)
        }
        text = text.replacing(#/[ \t]+/#, with: " ")
        text = text.replacing(#/\s*\n\s*\n\s*/#, with: "\n\n")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // `&amp;` last, so "&amp;lt;" becomes "&lt;" and not "<".
    private static let entities: [(String, String)] = [
        ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#039;", "'"),
        ("&apos;", "'"), ("&nbsp;", " "), ("&amp;", "&"),
    ]
}

/// An artist the server says is like another (Gitea #32): in the library
/// (open their page), or not (look them up on MusicBrainz).
public struct SimilarArtist: Sendable, Equatable, Identifiable {
    public var name: String
    /// The library's id; `nil` when the artist isn't in the library.
    public var artistID: String?
    public var coverArtID: String?

    public var id: String { artistID ?? "name:" + name }
    public var isInLibrary: Bool { artistID != nil }

    public init(name: String, artistID: String? = nil, coverArtID: String? = nil) {
        self.name = name
        self.artistID = artistID
        self.coverArtID = coverArtID
    }

    /// Navidrome gives an artist that's not in the library the id "-1"
    /// (`includeNotPresent`); an empty id means the same. No name, no entry.
    init?(_ artist: Artist) {
        guard !artist.name.isEmpty else { return nil }
        let inLibrary = !artist.id.isEmpty && artist.id != "-1"
        self.init(name: artist.name, artistID: inLibrary ? artist.id : nil, coverArtID: inLibrary ? artist.coverArtID : nil)
    }

    /// A MusicBrainz search for the artist, opened by the user in Safari.
    public var musicBrainzSearch: URL? {
        var components = URLComponents(string: "https://musicbrainz.org/search")
        components?.queryItems = [.init(name: "query", value: name), .init(name: "type", value: "artist")]
        return components?.url
    }
}
