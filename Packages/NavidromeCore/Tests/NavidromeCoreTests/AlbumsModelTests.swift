import Foundation
import Testing
@testable import NavidromeCore

struct AlbumRequest: Sendable, Equatable {
    let type: AlbumListType
    let size: Int
    let offset: Int
}

@MainActor
struct AlbumsModelTests {
    private let server = GatedFetch<AlbumRequest, [Album]>()
    private let offline = SubsonicError.network(.notConnectedToInternet)

    private func makeModel(sort: AlbumSort = .newest) -> AlbumsModel {
        AlbumsModel(sort: sort) { [server] type, size, offset async throws(SubsonicError) -> [Album] in
            try await server.fetch(AlbumRequest(type: type, size: size, offset: offset))
        }
    }

    private func albums(_ range: ClosedRange<Int>) -> [Album] {
        range.map { Album(id: "al-\($0)", name: "Album \($0)") }
    }

    private var fullPage: [Album] { albums(1...AlbumsModel.pageSize) }

    /// Runs `action`, answering each server call it makes with the next result.
    private func run(_ action: @escaping @MainActor () async -> Void, replies: [Result<[Album], SubsonicError>]) async {
        let callsBefore = server.requests.count
        let task = Task { @MainActor in await action() }
        for (offset, reply) in replies.enumerated() {
            await server.waitForCalls(callsBefore + offset + 1)
            server.reply(to: callsBefore + offset, with: reply)
        }
        await task.value
    }

    @Test func firstLoadFetchesThePageForTheSort() async {
        let model = makeModel(sort: .mostPlayed)
        await run({ await model.load() }, replies: [.success(albums(1...3))])
        #expect(server.requests == [AlbumRequest(type: .frequent, size: AlbumsModel.pageSize, offset: 0)])
        #expect(model.albums == albums(1...3))
    }

    @Test func scrollingNearTheEndFetchesTheNextPage() async {
        let model = makeModel()
        await run({ await model.load() }, replies: [.success(fullPage)])

        // Far from the end: nothing.
        await model.loadMoreIfNeeded(after: fullPage[0])
        #expect(server.requests.count == 1)

        let nextPage = albums(41...45)
        await run({ await model.loadMoreIfNeeded(after: fullPage[35]) }, replies: [.success(nextPage)])
        #expect(server.requests.last == AlbumRequest(type: .newest, size: AlbumsModel.pageSize, offset: 40))
        #expect(model.albums == fullPage + nextPage)
    }

    @Test func aShortPageMeansTheEnd() async {
        let model = makeModel()
        await run({ await model.load() }, replies: [.success(albums(1...10))])
        await model.loadMoreIfNeeded(after: albums(10...10)[0])
        #expect(server.requests.count == 1)
    }

    @Test func randomIsNeverPaged() async {
        let model = makeModel(sort: .random)
        await run({ await model.load() }, replies: [.success(fullPage)])
        await model.loadMoreIfNeeded(after: fullPage[39])
        #expect(server.requests.count == 1)
    }

    @Test func albumsAlreadyShownAreNotRepeated() async {
        let model = makeModel()
        await run({ await model.load() }, replies: [.success(fullPage)])
        // The library changed and album 40 slid into the next page.
        await run({ await model.loadMore() }, replies: [.success(albums(40...79))])
        #expect(model.albums == albums(1...79))
        // The server's offset counts what it sent, duplicate included.
        await run({ await model.loadMore() }, replies: [.success(albums(80...81))])
        #expect(server.requests.last?.offset == 80)
        #expect(model.albums == albums(1...81))
    }

    @Test func failedNextPageWaitsForAnExplicitRetry() async {
        let model = makeModel()
        await run({ await model.load() }, replies: [.success(fullPage)])
        await run({ await model.loadMore() }, replies: [.failure(offline)])
        #expect(model.loadMoreError == offline.localizedDescription)
        #expect(model.albums == fullPage)

        // Scrolling doesn't hammer the server after a failure...
        await model.loadMoreIfNeeded(after: fullPage[39])
        #expect(server.requests.count == 2)

        // ...the retry does.
        await run({ await model.loadMore() }, replies: [.success(albums(41...42))])
        #expect(model.loadMoreError == nil)
        #expect(model.albums?.count == 42)
    }

    @Test func changingTheSortReplacesTheList() async {
        let model = makeModel()
        await run({ await model.load() }, replies: [.success(albums(1...3))])

        await run({ await model.setSort(.name) }, replies: [.success(albums(7...8))])
        #expect(model.sort == .name)
        #expect(server.requests.last?.type == .alphabeticalByName)
        #expect(model.albums == albums(7...8))
    }

    @Test func aLateReplyForTheOldSortIsDropped() async {
        let model = makeModel()
        let firstLoad = Task { @MainActor in await model.load() }
        await server.waitForCalls(1)

        let sortChange = Task { @MainActor in await model.setSort(.name) }
        await server.waitForCalls(2)
        server.reply(to: 1, with: .success(albums(7...8)))
        await sortChange.value
        server.reply(to: 0, with: .success(albums(1...3)))
        await firstLoad.value

        #expect(model.albums == albums(7...8))
    }

    @Test func failedRefreshKeepsTheList() async {
        let model = makeModel()
        await run({ await model.load() }, replies: [.success(albums(1...3))])
        await run({ await model.load() }, replies: [.failure(offline)])
        #expect(model.albums == albums(1...3))
        #expect(model.refreshError == offline.localizedDescription)
    }

    @Test func failedFirstLoadIsAnError() async {
        let model = makeModel()
        await run({ await model.load() }, replies: [.failure(offline)])
        #expect(model.state == .failed(offline.localizedDescription))
    }
}
