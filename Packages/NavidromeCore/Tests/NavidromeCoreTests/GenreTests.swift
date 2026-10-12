import Foundation
import Testing
@testable import NavidromeCore

struct GenreTests {
    @Test func decodesGenresAndDropsNamelessOnes() async throws {
        let transport = try FakeTransport(fixture: "getGenres")
        let genres = try await TestServer.client(transport).genres()
        #expect(genres.map(\.name) == ["Jazz", "Rock", "Spoken Word", "Ambient", "Blues"])
        #expect(genres[1].albumCount == 80)
        #expect(genres[3].albumCount == nil)
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path() == "/rest/getGenres")
    }

    @Test func browsingShowsBiggestFirstWithoutEmptyGenres() async throws {
        let genres = try await TestServer.client(FakeTransport(fixture: "getGenres")).genres()
        // Jazz and Blues tie on 12 albums: by name. Unknown count goes last; 0 albums is dropped.
        #expect(Genre.forBrowsing(genres).map(\.name) == ["Rock", "Blues", "Jazz", "Ambient"])
    }

    @Test func noGenresIsAnEmptyList() async throws {
        #expect(try await TestServer.client(FakeTransport(.json(TestServer.ok))).genres().isEmpty)
    }

    @Test func songsByGenreSendsTheGenreAndCount() async throws {
        let transport = try FakeTransport(fixture: "getSongsByGenre")
        let songs = try await TestServer.client(transport).songs(inGenre: "Rock & Roll")
        #expect(songs.map(\.id) == ["so-1", "so-2"])
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path() == "/rest/getSongsByGenre")
        #expect(url.queryParameters["genre"] == "Rock & Roll")
        #expect(url.queryParameters["count"] == "500")
        #expect(url.queryParameters["offset"] == "0")
    }

    @Test func genreAlbumsAskForTheGenre() async throws {
        let transport = FakeTransport(.json(TestServer.ok))
        _ = try await TestServer.client(transport).albumList(.byGenre("Jazz"), size: 1)
        let url = try #require(await transport.requests.first?.url)
        #expect(url.queryParameters["type"] == "byGenre")
        #expect(url.queryParameters["genre"] == "Jazz")
        #expect(url.queryParameters["size"] == "1")
    }
}

@MainActor
struct GenreCoversTests {
    private let server = GatedFetch<String, String?>()

    private func makeCovers() -> GenreCovers {
        GenreCovers { [server] genre async throws(SubsonicError) in try await server.fetch(genre) }
    }

    @Test func fetchesEachGenresCoverOnce() async {
        let covers = makeCovers()
        let first = Task { @MainActor in await covers.load("Jazz") }
        await server.waitForCalls(1)
        // Appearing again while it loads asks nothing more.
        await covers.load("Jazz")
        server.reply(to: 0, with: .success("al-9"))
        await first.value
        #expect(covers.coverArtID(for: "Jazz") == "al-9")

        await covers.load("Jazz")
        #expect(server.requests == ["Jazz"])
    }

    @Test func aGenreWithoutACoverIsNotAskedAgain() async {
        let covers = makeCovers()
        let first = Task { @MainActor in await covers.load("Noise") }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .success(nil))
        await first.value
        await covers.load("Noise")
        #expect(covers.coverArtID(for: "Noise") == nil)
        #expect(server.requests.count == 1)
    }

    @Test func aFailedFetchIsTriedAgainLater() async {
        let covers = makeCovers()
        let first = Task { @MainActor in await covers.load("Jazz") }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .failure(.network(.notConnectedToInternet)))
        await first.value

        let second = Task { @MainActor in await covers.load("Jazz") }
        await server.waitForCalls(2)
        server.reply(to: 1, with: .success("al-9"))
        await second.value
        #expect(covers.coverArtID(for: "Jazz") == "al-9")
    }
}

@MainActor
struct GenreAlbumsTests {
    @Test func aFixedListPagesThroughTheGenre() async {
        let server = GatedFetch<String, [Album]>()
        let model = AlbumsModel(listType: .byGenre("Jazz")) { [server] type, size, offset async throws(SubsonicError) in
            #expect(type == .byGenre("Jazz"))
            return try await server.fetch("\(size)@\(offset)")
        }
        let page = (1...AlbumsModel.pageSize).map { Album(id: "al-\($0)", name: "Album \($0)") }

        let load = Task { @MainActor in await model.load() }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .success(page))
        await load.value
        #expect(model.albums?.count == AlbumsModel.pageSize)

        let more = Task { @MainActor in await model.loadMore() }
        await server.waitForCalls(2)
        server.reply(to: 1, with: .success([Album(id: "al-99", name: "Last")]))
        await more.value
        #expect(server.requests == ["\(AlbumsModel.pageSize)@0", "\(AlbumsModel.pageSize)@\(AlbumsModel.pageSize)"])
        #expect(model.albums?.last?.id == "al-99")
    }
}
