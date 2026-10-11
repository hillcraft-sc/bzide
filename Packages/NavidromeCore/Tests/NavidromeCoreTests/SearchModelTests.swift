import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct SearchModelTests {
    private let server = GatedFetch<String, SearchResult>()
    private let scheduler = FakeScheduler()
    private let offline = SubsonicError.network(.notConnectedToInternet)

    private func makeModel() -> SearchModel {
        SearchModel(scheduler: scheduler) { [server] query async throws(SubsonicError) -> SearchResult in
            try await server.fetch(query)
        }
    }

    private func result(_ name: String) -> SearchResult {
        SearchResult(albums: [Album(id: "al-\(name)", name: name)])
    }

    @Test func waitsForAPauseInTyping() async {
        let model = makeModel()
        model.updateQuery("b")
        model.updateQuery("be")
        model.updateQuery("bea")
        #expect(scheduler.pendingDelays == [SearchModel.typingPause])
        #expect(server.requests.isEmpty)

        scheduler.fireNext()
        #expect(model.isSearching)
        await server.waitForCalls(1)
        server.reply(to: 0, with: .success(result("Beach")))
        await model.searchTask?.value

        #expect(server.requests == ["bea"])
        #expect(model.results == result("Beach"))
        #expect(!model.isSearching)
    }

    @Test func aLateReplyForAnOlderQueryIsDropped() async {
        let model = makeModel()
        model.updateQuery("bea")
        scheduler.fireNext()
        await server.waitForCalls(1)
        let olderSearch = model.searchTask

        model.updateQuery("beat")
        scheduler.fireNext()
        await server.waitForCalls(2)
        server.reply(to: 1, with: .success(result("Beatles")))
        await model.searchTask?.value
        server.reply(to: 0, with: .success(result("Beach")))
        await olderSearch?.value

        #expect(model.results == result("Beatles"))
    }

    @Test func previousResultsStayWhileTheNextSearchRuns() async {
        let model = makeModel()
        model.updateQuery("bea")
        scheduler.fireNext()
        await server.waitForCalls(1)
        server.reply(to: 0, with: .success(result("Beach")))
        await model.searchTask?.value

        model.updateQuery("beat")
        scheduler.fireNext()
        #expect(model.isSearching)
        #expect(model.results == result("Beach"))
    }

    @Test func clearingTheQueryClearsResultsAndCancelsTheWait() async {
        let model = makeModel()
        model.updateQuery("bea")
        scheduler.fireNext()
        await server.waitForCalls(1)
        server.reply(to: 0, with: .success(result("Beach")))
        await model.searchTask?.value

        model.updateQuery("beat")
        model.updateQuery("  ")
        #expect(model.results == nil)
        #expect(!model.isSearching)
        #expect(scheduler.pendingDelays.isEmpty)
    }

    @Test func spacesAroundTheQueryAreIgnored() async {
        let model = makeModel()
        model.updateQuery("  bea ")
        scheduler.fireNext()
        await server.waitForCalls(1)
        #expect(server.requests == ["bea"])
        server.reply(to: 0, with: .success(result("Beach")))
        await model.searchTask?.value
    }

    @Test func failureIsShownAndRetryRunsItAgain() async {
        let model = makeModel()
        model.updateQuery("bea")
        scheduler.fireNext()
        await server.waitForCalls(1)
        server.reply(to: 0, with: .failure(offline))
        await model.searchTask?.value
        #expect(model.error == offline.localizedDescription)
        #expect(!model.isSearching)

        model.retry()
        #expect(model.error == nil)
        await server.waitForCalls(2)
        server.reply(to: 1, with: .success(result("Beach")))
        await model.searchTask?.value
        #expect(model.results == result("Beach"))
    }
}
