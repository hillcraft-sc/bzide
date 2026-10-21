import Foundation
import os

/// An artist's biography from Wikipedia, for Look Up Artists Online: the
/// opening section of their article, in the iPhone's language when there's
/// an article in it, else English. Wikidata (which MusicBrainz links to)
/// says which article is theirs, so no name is searched. Only the Wikidata
/// item or article title is sent.
///
/// Wikimedia asks every app to name itself and a contact (`contact`, the
/// same one MusicBrainz gets). Wikipedia's text is CC BY-SA, so it's always
/// shown credited, with a link to the article.
public actor WikipediaClient {
    public static let wikidataURL = URL(string: "https://www.wikidata.org/w/api.php") ?? URL(filePath: "/")

    private let transport: any HTTPTransport
    private let contact: String
    /// "en", "de"…
    private let language: String
    private static let logger = Logger(subsystem: "MusicApp", category: "Wikipedia")

    public init(contact: String, language: String, transport: any HTTPTransport = URLSessionTransport()) {
        self.contact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = language.lowercased()
        self.transport = transport
    }

    /// The article's opening section, or `nil` if there's no article.
    public func biography(_ links: MusicBrainzClient.ArtistLinks) async throws -> ArtistBiography? {
        guard !contact.isEmpty else { throw MusicBrainzClient.Failure.noContact }
        let article: (language: String, title: String)?
        if let wikidataID = links.wikidataID {
            article = try await self.article(wikidataID: wikidataID)
        } else {
            article = links.wikipediaURL.flatMap(Self.article(at:))
        }
        guard let article else { return nil }
        return try await introduction(article.title, language: article.language)
    }

    // MARK: - Requests

    /// The article in `language`, else English.
    private func article(wikidataID: String) async throws -> (language: String, title: String)? {
        struct Entities: Decodable {
            struct Entity: Decodable {
                struct Link: Decodable { let title: String? }
                let sitelinks: [String: Link]?
            }
            let entities: [String: Entity]?
        }
        let languages = language == "en" ? ["en"] : [language, "en"]
        let url = try Self.url(Self.wikidataURL, [
            .init(name: "action", value: "wbgetentities"), .init(name: "ids", value: wikidataID),
            .init(name: "props", value: "sitelinks"),
            .init(name: "sitefilter", value: languages.map { "\($0)wiki" }.joined(separator: "|")),
        ])
        let links = try JSONDecoder().decode(Entities.self, from: try await get(url)).entities?[wikidataID]?.sitelinks ?? [:]
        for language in languages {
            if let title = links["\(language)wiki"]?.title, !title.isEmpty { return (language, title) }
        }
        return nil
    }

    private func introduction(_ title: String, language: String) async throws -> ArtistBiography? {
        struct Query: Decodable {
            struct Pages: Decodable {
                struct Page: Decodable {
                    let title: String?
                    let extract: String?
                }
                let pages: [Page]?
            }
            let query: Pages?
        }
        guard let api = URL(string: "https://\(language).wikipedia.org/w/api.php") else { return nil }
        let url = try Self.url(api, [
            .init(name: "action", value: "query"), .init(name: "prop", value: "extracts"),
            .init(name: "exintro", value: "1"), .init(name: "explaintext", value: "1"),
            .init(name: "redirects", value: "1"), .init(name: "titles", value: title),
        ])
        let page = try JSONDecoder().decode(Query.self, from: try await get(url)).query?.pages?.first
        guard let text = page?.extract.flatMap(Self.cleaned) else { return nil }
        let pageTitle = (page?.title ?? title).replacingOccurrences(of: " ", with: "_")
        return ArtistBiography(
            text: text, source: "Wikipedia",
            pageURL: URL(string: "https://\(language).wikipedia.org/wiki/")?.appending(path: pageTitle)
        )
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bzide/1.0 ( \(contact) )", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            Self.logger.error("GET \(url.host() ?? "", privacy: .public) failed: HTTP \(response.statusCode, privacy: .public)")
            throw MusicBrainzClient.Failure.badResponse(response.statusCode)
        }
        return data
    }

    private static func url(_ base: URL, _ query: [URLQueryItem]) throws -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = query + [.init(name: "format", value: "json"), .init(name: "formatversion", value: "2")]
        guard let url = components?.url else { throw URLError(.badURL) }
        return url
    }

    // MARK: - Reading

    /// "https://en.wikipedia.org/wiki/Nirvana_(band)" is English, "Nirvana (band)".
    static func article(at url: URL) -> (language: String, title: String)? {
        guard let host = url.host(), host.hasSuffix(".wikipedia.org"),
              let language = host.split(separator: ".").first.map(String.init),
              url.pathComponents.count >= 3, url.pathComponents[1] == "wiki" else { return nil }
        let title = url.pathComponents.dropFirst(2).joined(separator: "/").replacingOccurrences(of: "_", with: " ")
        return title.isEmpty ? nil : (language, title)
    }

    /// Paragraphs (one line each in the extract) a blank line apart; empty means none.
    static func cleaned(_ extract: String) -> String? {
        let text = extract
            .replacing(#/[ \t]*\n\s*/#, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
