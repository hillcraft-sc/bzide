import Foundation
import Testing
@testable import NavidromeCore

/// Hand-written MusicBrainz, Wikidata and Wikipedia replies, shaped like the
/// real ones; ids invented.
private enum Sample {
    static func group(_ id: String, _ title: String, type: String = "Album", secondary: [String] = [], date: String = "1997-05-21") -> String {
        let secondaryJSON = secondary.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"id":"\#(id)","title":"\#(title)","primary-type":"\#(type)","secondary-types":[\#(secondaryJSON)],"first-release-date":"\#(date)"}"#
    }

    static func browse(count: Int, _ groups: [String]) -> String {
        #"{"release-group-count":\#(count),"release-group-offset":0,"release-groups":[\#(groups.joined(separator: ","))]}"#
    }

    static let artistSearch = #"{"artists":[{"id":"ar-tribute","name":"Radiohead Tribute","score":95},{"id":"ar-other","name":"radiohéad","score":91},{"id":"ar-rh","name":"Radiohead","score":100}]}"#
    static let links = #"{"id":"ar-rh","relations":[{"type":"official homepage","url":{"resource":"https://radiohead.example"}},{"type":"wikidata","url":{"resource":"https://www.wikidata.org/wiki/Q44190"}}]}"#
    static let sitelinks = #"{"entities":{"Q44190":{"sitelinks":{"enwiki":{"site":"enwiki","title":"Radiohead"}}}}}"#
    static let extract = #"{"query":{"pages":[{"pageid":1,"title":"Radiohead","extract":"Radiohead are an English rock band.  \nThey formed in 1985.\n\n\nTheir debut was Pablo Honey."}]}}"#
}

private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000)
}

private func musicBrainz(_ transport: FakeTransport, clock: Clock = Clock()) -> MusicBrainzClient {
    MusicBrainzClient(contact: "https://example.test", transport: transport, now: { clock.now }, sleep: { clock.now = clock.now.addingTimeInterval($0) })
}

struct MusicBrainzArtistTests {
    @Test func findsTheArtistWithExactlyThatName() async throws {
        let transport = FakeTransport(.json(Sample.artistSearch))
        // Accents and case don't matter; the best scored wins.
        #expect(try await musicBrainz(transport).artistID(named: "Radiohead") == "ar-rh")
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path() == "/ws/2/artist")
        #expect(url.queryParameters["query"] == #"artist:"Radiohead""#)
    }

    @Test func noExactNameIsNoArtist() async throws {
        let transport = FakeTransport(.json(#"{"artists":[{"id":"x","name":"Radiohead Tribute","score":100}]}"#))
        #expect(try await musicBrainz(transport).artistID(named: "Radiohead") == nil)
    }

    @Test func readsTheWikidataLink() async throws {
        let transport = FakeTransport(.json(Sample.links))
        let links = try await musicBrainz(transport).links(artistID: "ar-rh")
        #expect(links.wikidataID == "Q44190")
        #expect(links.wikipediaURL == nil)
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path() == "/ws/2/artist/ar-rh")
        #expect(url.queryParameters["inc"] == "url-rels")
    }

    @Test func releaseGroupsArePagedLikeTheWebsite() async throws {
        let first = (0..<100).map { Sample.group("rg-\($0)", "Album \($0)") }
        let transport = FakeTransport(
            .json(Sample.browse(count: 101, first)),
            .json(Sample.browse(count: 101, [Sample.group("rg-live", "Live at Somewhere", secondary: ["Live"], date: "")]))
        )
        let releases = try await musicBrainz(transport).releaseGroups(artistID: "ar-rh")
        #expect(releases.count == 101)
        let live = try #require(releases.last)
        #expect(live.kind == .live)
        #expect(live.year == nil)
        #expect(live.coverURL?.absoluteString == "https://coverartarchive.org/release-group/rg-live/front-250")
        #expect(live.pageURL?.absoluteString == "https://musicbrainz.org/release-group/rg-live")
        let requests = await transport.requests.compactMap(\.url)
        #expect(requests.count == 2)
        #expect(requests[0].queryParameters["release-group-status"] == "website-default")
        #expect(requests[0].queryParameters["artist"] == "ar-rh")
        #expect(requests[1].queryParameters["offset"] == "100")
    }

    @Test func stopsAfterTheLastPage() async throws {
        let transport = FakeTransport(.json(Sample.browse(count: 1, [Sample.group("rg-1", "OK Computer")])))
        let releases = try await musicBrainz(transport).releaseGroups(artistID: "ar-rh")
        #expect(releases.map(\.title) == ["OK Computer"])
        #expect(await transport.requests.count == 1)
    }

    @Test func kinds() {
        #expect(MusicBrainzClient.kind(primary: "Album", secondary: []) == .album)
        #expect(MusicBrainzClient.kind(primary: "EP", secondary: []) == .ep)
        #expect(MusicBrainzClient.kind(primary: "Single", secondary: []) == .single)
        #expect(MusicBrainzClient.kind(primary: "Album", secondary: ["Live"]) == .live)
        #expect(MusicBrainzClient.kind(primary: "Album", secondary: ["Compilation"]) == .compilation)
        #expect(MusicBrainzClient.kind(primary: "Album", secondary: ["Soundtrack"]) == .soundtrack)
        #expect(MusicBrainzClient.kind(primary: "Single", secondary: ["Remix"]) == .remix)
        #expect(MusicBrainzClient.kind(primary: "Album", secondary: ["Demo"]) == .other)
        #expect(MusicBrainzClient.kind(primary: "Broadcast", secondary: []) == .other)
        #expect(MusicBrainzClient.kind(primary: nil, secondary: []) == .other)
    }
}

struct WikipediaClientTests {
    @Test func theIntroductionOfTheLinkedArticle() async throws {
        let transport = FakeTransport(.json(Sample.sitelinks), .json(Sample.extract))
        let client = WikipediaClient(contact: "https://example.test", language: "en", transport: transport)
        let biography = try #require(try await client.biography(.init(wikidataID: "Q44190")))
        // One blank line between paragraphs.
        #expect(biography.text == "Radiohead are an English rock band.\n\nThey formed in 1985.\n\nTheir debut was Pablo Honey.")
        #expect(biography.source == "Wikipedia")
        #expect(biography.pageURL?.absoluteString == "https://en.wikipedia.org/wiki/Radiohead")

        let requests = await transport.requests
        let wikidata = try #require(requests.first?.url)
        #expect(wikidata.host() == "www.wikidata.org")
        #expect(wikidata.queryParameters["ids"] == "Q44190")
        #expect(wikidata.queryParameters["sitefilter"] == "enwiki")
        let article = try #require(requests.last?.url)
        #expect(article.host() == "en.wikipedia.org")
        #expect(article.queryParameters["titles"] == "Radiohead")
        #expect(article.queryParameters["exintro"] == "1")
        #expect(article.queryParameters["explaintext"] == "1")
        #expect(requests.first?.value(forHTTPHeaderField: "User-Agent") == "Bzide/1.0 ( https://example.test )")
    }

    @Test func theIPhonesLanguageFirstThenEnglish() async throws {
        let transport = FakeTransport(.json(Sample.sitelinks), .json(Sample.extract))
        let client = WikipediaClient(contact: "https://example.test", language: "de", transport: transport)
        let biography = try await client.biography(.init(wikidataID: "Q44190"))
        let wikidata = try #require(await transport.requests.first?.url)
        #expect(wikidata.queryParameters["sitefilter"] == "dewiki|enwiki")
        // No German article here, so English.
        #expect(biography?.pageURL?.host() == "en.wikipedia.org")
    }

    @Test func noArticleIsNoBiography() async throws {
        let transport = FakeTransport(.json(#"{"entities":{"Q1":{"sitelinks":{}}}}"#))
        let client = WikipediaClient(contact: "https://example.test", language: "en", transport: transport)
        #expect(try await client.biography(.init(wikidataID: "Q1")) == nil)
        #expect(try await client.biography(.init()) == nil)
        #expect(await transport.requests.count == 1)
    }

    @Test func aDirectWikipediaLink() {
        let article = WikipediaClient.article(at: URL(string: "https://fr.wikipedia.org/wiki/Nirvana_(groupe)")!)
        #expect(article?.language == "fr")
        #expect(article?.title == "Nirvana (groupe)")
        #expect(WikipediaClient.article(at: URL(string: "https://example.org/wiki/Nirvana")!) == nil)
    }
}

struct DiscographyTests {
    @Test func ownedAlbumsAreLeftOutAndTheRestGroupedNewestFirst() {
        let releases = [
            DiscographyRelease(id: "1", title: "OK Computer", year: 1997, kind: .album),
            DiscographyRelease(id: "2", title: "Kid A", year: 2000, kind: .album),
            DiscographyRelease(id: "3", title: "Amnesiac", year: 2001, kind: .album),
            DiscographyRelease(id: "4", title: "Creep", year: 1992, kind: .single),
            DiscographyRelease(id: "5", title: "I Might Be Wrong", year: 2001, kind: .live),
            DiscographyRelease(id: "6", title: "Hail to the Thief", kind: .album),
        ]
        let owned = [Album(id: "a", name: "OK Computer (Collector's Edition)"), Album(id: "b", name: "kid a")]
        let sections = Discography.notOwned(releases, owned: owned)
        #expect(sections.map(\.kind) == [.album, .single, .live])
        // No year last.
        #expect(sections[0].releases.map(\.title) == ["Amnesiac", "Hail to the Thief"])
    }

    @Test func titlesMatchLooselyButNotTooLoosely() {
        #expect(Discography.matchKey("Sgt. Pepper's Lonely Hearts Club Band") == Discography.matchKey("Sgt Peppers Lonely Hearts Club Band (Remastered 2009)"))
        #expect(Discography.matchKey("Simon & Garfunkel's Greatest Hits") == Discography.matchKey("Simon and Garfunkel’s Greatest Hits"))
        #expect(Discography.matchKey("Déjà Vu") == Discography.matchKey("deja vu [Deluxe]"))
        #expect(Discography.matchKey("Help!") != Discography.matchKey("Help Me"))
        // All in brackets: the whole title.
        #expect(Discography.matchKey("(What's the Story) Morning Glory?") == Discography.matchKey("(Whats the Story) Morning Glory"))
        #expect(Discography.matchKey("[Untitled]") == "untitled")
    }
}

/// Answers from memory, counting what's asked.
private actor FakeLookup: ArtistLookup {
    var biography: ArtistBiography?
    var releases: [DiscographyRelease] = []
    var fails = false
    private(set) var asked: [ArtistReference] = []

    func set(biography: ArtistBiography?, releases: [DiscographyRelease], fails: Bool = false) {
        self.biography = biography
        self.releases = releases
        self.fails = fails
    }

    func biography(for artist: ArtistReference) async throws -> ArtistBiography? {
        asked.append(artist)
        if fails { throw URLError(.notConnectedToInternet) }
        return biography
    }

    func discography(for artist: ArtistReference) async throws -> [DiscographyRelease] {
        if fails { throw URLError(.notConnectedToInternet) }
        return releases
    }
}

@MainActor
struct OnlineArtistModelTests {
    private let artist = Artist(id: "ar-1", name: "Radiohead", albums: [Album(id: "a", name: "OK Computer")])
    private let bio = ArtistBiography(text: "An English rock band.", source: "Wikipedia")

    @Test func offAsksNothing() async {
        let lookup = FakeLookup()
        let model = OnlineArtistModel(lookup: lookup)
        await model.load(artist, info: nil, enabled: false)
        #expect(model.discography == .off)
        #expect(model.biography == nil)
        #expect(await lookup.asked.isEmpty)
    }

    @Test func theBiographyAndWhatIsNotOwned() async {
        let lookup = FakeLookup()
        await lookup.set(biography: bio, releases: [
            DiscographyRelease(id: "1", title: "OK Computer", kind: .album),
            DiscographyRelease(id: "2", title: "Kid A", kind: .album),
        ])
        let model = OnlineArtistModel(lookup: lookup)
        await model.load(artist, info: ArtistInfo(musicBrainzID: "mb-rh"), enabled: true)
        #expect(model.biography == bio)
        #expect(model.discography == .loaded([DiscographySection(kind: .album, releases: [DiscographyRelease(id: "2", title: "Kid A", kind: .album)])]))
        // The server's id, from the artist info.
        #expect(await lookup.asked == [ArtistReference(name: "Radiohead", musicBrainzID: "mb-rh")])
    }

    @Test func aFailureSaysSoUnlessThereIsSomethingToKeep() async {
        let lookup = FakeLookup()
        await lookup.set(biography: nil, releases: [], fails: true)
        let model = OnlineArtistModel(lookup: lookup)
        await model.load(artist, info: nil, enabled: true)
        #expect(model.discography == .failed)
        #expect(model.biography == nil)

        await lookup.set(biography: bio, releases: [DiscographyRelease(id: "2", title: "Kid A", kind: .album)])
        await model.load(artist, info: nil, enabled: true)
        await lookup.set(biography: nil, releases: [], fails: true)
        await model.load(artist, info: nil, enabled: true)
        // A failed refresh keeps what was found.
        #expect(model.biography == bio)
        #expect(model.discography == .loaded([DiscographySection(kind: .album, releases: [DiscographyRelease(id: "2", title: "Kid A", kind: .album)])]))
    }

    @Test func variousArtistsIsNotLookedUp() async {
        let lookup = FakeLookup()
        let model = OnlineArtistModel(lookup: lookup)
        var various = artist
        various.musicBrainzID = OnlineArtistModel.variousArtistsID
        await model.load(various, info: nil, enabled: true)
        #expect(model.discography == .off)
        #expect(await lookup.asked.isEmpty)
    }
}

struct OnlineArtistLookupTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "ArtistLookups-\(UUID().uuidString)")
    }

    private func lookup(_ transport: FakeTransport, directory: URL, clock: Clock = Clock()) -> OnlineArtistLookup {
        OnlineArtistLookup(
            musicBrainz: musicBrainz(transport, clock: clock),
            wikipedia: WikipediaClient(contact: "https://example.test", language: "en", transport: transport),
            directory: directory, now: { clock.now }
        )
    }

    @Test func searchesTheNameOnceAndKeepsTheAnswers() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let transport = FakeTransport(
            .json(Sample.artistSearch), .json(Sample.links), .json(Sample.sitelinks), .json(Sample.extract),
            .json(Sample.browse(count: 1, [Sample.group("rg-1", "OK Computer")]))
        )
        let artist = ArtistReference(name: "Radiohead")
        let first = lookup(transport, directory: folder)
        #expect(try await first.biography(for: artist)?.source == "Wikipedia")
        #expect(try await first.discography(for: artist).map(\.title) == ["OK Computer"])
        #expect(await transport.requests.count == 5)

        // Another session asks nothing.
        let second = lookup(transport, directory: folder)
        #expect(try await second.biography(for: artist)?.source == "Wikipedia")
        #expect(try await second.discography(for: artist).map(\.title) == ["OK Computer"])
        #expect(await transport.requests.count == 5)
    }

    @Test func notFoundIsKeptTooAndEverythingExpires() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let transport = FakeTransport(.json(#"{"artists":[]}"#), .json(#"{"artists":[]}"#))
        let clock = Clock()
        let artist = ArtistReference(name: "Nobody Knows")
        let lookup = lookup(transport, directory: folder, clock: clock)
        #expect(try await lookup.discography(for: artist).isEmpty)
        #expect(try await lookup.biography(for: artist) == nil)
        #expect(await transport.requests.count == 1)

        clock.now = clock.now.addingTimeInterval(OnlineArtistLookup.cacheLifetime + 1)
        let later = self.lookup(transport, directory: folder, clock: clock)
        #expect(try await later.discography(for: artist).isEmpty)
        #expect(await transport.requests.count == 2)
    }

    @Test func aFailureIsNotKept() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let transport = FakeTransport(.failure(.notConnectedToInternet), .json(Sample.browse(count: 1, [Sample.group("rg-1", "Kid A")])))
        let artist = ArtistReference(name: "Radiohead", musicBrainzID: "ar-rh")
        let lookup = lookup(transport, directory: folder)
        await #expect(throws: (any Error).self) { try await lookup.discography(for: artist) }
        #expect(try await lookup.discography(for: artist).map(\.title) == ["Kid A"])
    }
}

struct ArtistMusicBrainzIDTests {
    @Test func decodedFromTheServer() throws {
        let artist = try JSONDecoder().decode(Artist.self, from: Data(#"{"id":"ar-1","name":"A","musicBrainzId":"mb-1"}"#.utf8))
        #expect(artist.musicBrainzID == "mb-1")
        let blank = try JSONDecoder().decode(Artist.self, from: Data(#"{"id":"ar-1","name":"A","musicBrainzId":""}"#.utf8))
        #expect(blank.musicBrainzID == nil)
        let info = try JSONDecoder().decode(ArtistInfo.self, from: Data(#"{"musicBrainzId":"mb-2"}"#.utf8))
        #expect(info.musicBrainzID == "mb-2")
    }

    @Test func theSettingIsOffByDefaultAndForOlderSettings() throws {
        #expect(StreamingSettings().lookUpArtistsOnline == false)
        let old = try JSONDecoder().decode(StreamingSettings.self, from: Data(#"{"lookUpSongsOnline":true}"#.utf8))
        #expect(old.lookUpArtistsOnline == false)
        #expect(old.lookUpSongsOnline)
    }
}
