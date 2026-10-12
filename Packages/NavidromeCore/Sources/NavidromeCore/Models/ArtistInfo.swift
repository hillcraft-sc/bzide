import Foundation

/// What the server knows about an artist beyond the library (`getArtistInfo2`),
/// usually fetched from Last.fm. Every field may be missing.
public struct ArtistInfo: Sendable, Equatable, Decodable {
    /// Plain text, ready to show; `nil` when the server has none.
    public var biography: String?

    public init(biography: String? = nil) {
        self.biography = biography
    }

    private enum ServerKeys: String, CodingKey { case biography }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: ServerKeys.self)
        self.init(biography: c.lenientString(.biography).flatMap(Self.plainText))
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
