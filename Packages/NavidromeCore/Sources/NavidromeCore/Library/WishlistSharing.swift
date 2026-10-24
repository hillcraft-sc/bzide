import Foundation

/// A store's search for a Wishlist entry, to buy it (Gitea #29). Only a link,
/// opened by the user; nothing is sent until then.
public struct StoreLink: Equatable, Sendable, Identifiable {
    public var store: String
    public var url: URL
    public var id: String { store }
}

extension WishlistEntry {
    /// What to search for: the artist and title, an album's artist and title,
    /// or an artist's name.
    var searchText: String {
        kind == .artist ? artist : "\(artist) \(title)"
    }

    /// Stores that sell downloads, searched for this song, album or artist.
    /// Qobuz and Amazon are per country, from the iPhone's region (the US
    /// store when it isn't one they have); Apple Music picks the country itself.
    public func storeLinks(region: String? = Locale.current.region?.identifier) -> [StoreLink] {
        let text = searchText
        let region = region?.uppercased() ?? "US"
        let bandcampKind = switch kind {
        case .radioSong, .missingSong: "t"
        case .album: "a"
        case .artist: "b"
        }
        let links: [(String, String, [URLQueryItem])] = [
            ("Apple Music", "https://music.apple.com/search", [.init(name: "term", value: text)]),
            ("Bandcamp", "https://bandcamp.com/search", [.init(name: "q", value: text), .init(name: "item_type", value: bandcampKind)]),
            ("Qobuz", "https://www.qobuz.com/\(Self.qobuzStores[region] ?? "us-en")/search", [.init(name: "q", value: text)]),
            ("Amazon", "https://www.\(Self.amazonStores[region] ?? "amazon.com")/s", [.init(name: "k", value: text), .init(name: "i", value: "digital-music")]),
        ]
        return links.compactMap { store, address, query in
            var components = URLComponents(string: address)
            components?.queryItems = query
            return components?.url.map { StoreLink(store: store, url: $0) }
        }
    }

    static let qobuzStores = [
        "US": "us-en", "GB": "gb-en", "IE": "ie-en", "AU": "au-en", "NZ": "nz-en", "FR": "fr-fr", "DE": "de-de",
        "AT": "at-de", "IT": "it-it", "ES": "es-es", "NL": "nl-nl", "BE": "be-nl", "CH": "ch-de", "LU": "lu-fr",
    ]

    static let amazonStores = [
        "US": "amazon.com", "GB": "amazon.co.uk", "CA": "amazon.ca", "AU": "amazon.com.au", "DE": "amazon.de",
        "FR": "amazon.fr", "IT": "amazon.it", "ES": "amazon.es", "JP": "amazon.co.jp",
    ]
}

extension Wishlist {
    /// The list as plain text, by section, for sharing: "Artist - Title"
    /// (or an artist's name) per line, with the album or station when known.
    public func exportText() -> String {
        sections.map { section in
            let lines = section.entries.map { entry -> String in
                var line = "- " + entry.text
                switch entry.kind {
                case .radioSong: if let station = entry.station { line += " (heard on \(station))" }
                case .missingSong: if let album = entry.album { line += " (from \(album))" }
                case .album: if let year = entry.year { line += " (\(year))" }
                case .artist: break
                }
                return line
            }
            return ([section.kind.sectionTitle] + lines).joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    /// The list as CSV, one entry a row, for a spreadsheet or a script.
    public func exportCSV() -> String {
        let header = "Kind,Artist,Title,Album,Year,Station,Added,MusicBrainz"
        let added = ISO8601DateFormatter()
        added.formatOptions = [.withFullDate]
        let rows = sections.flatMap(\.entries).map { entry in
            [
                entry.kind.sectionTitle, entry.artist, entry.kind == .artist ? "" : entry.title,
                entry.album ?? "", entry.year.map(String.init) ?? "", entry.station ?? "",
                added.string(from: entry.heardAt), entry.musicBrainzURL?.absoluteString ?? "",
            ]
            .map(Self.csvField)
            .joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    /// Quoted when it holds a comma, quote or line break; quotes doubled.
    static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacing("\"", with: "\"\"") + "\""
    }
}
