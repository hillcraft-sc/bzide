import Foundation

/// A genre in the library (`getGenres`). Its name is also its id: that's what
/// the server takes back to list its albums and songs.
public struct Genre: Sendable, Equatable, Identifiable, Decodable {
    public var name: String
    public var albumCount: Int?
    public var songCount: Int?

    public var id: String { name }

    public init(name: String, albumCount: Int? = nil, songCount: Int? = nil) {
        self.name = name
        self.albumCount = albumCount
        self.songCount = songCount
    }

    // Subsonic sends the name as `value`.
    private enum ServerKeys: String, CodingKey { case value, name, albumCount, songCount }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: ServerKeys.self)
        let name = (c.lenientString(.value) ?? c.lenientString(.name) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw DecodingError.keyNotFound(ServerKeys.value, .init(codingPath: c.codingPath, debugDescription: "No genre name"))
        }
        self.init(name: name, albumCount: c.lenientInt(.albumCount), songCount: c.lenientInt(.songCount))
    }

    /// For the genre grid: genres with albums, biggest first, then by name.
    /// A genre whose album count isn't known is kept, at the end.
    public static func forBrowsing(_ genres: [Genre]) -> [Genre] {
        genres
            .filter { ($0.albumCount ?? 1) > 0 }
            .sorted { a, b in
                let (x, y) = (a.albumCount ?? -1, b.albumCount ?? -1)
                if x != y { return x > y }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }
}
