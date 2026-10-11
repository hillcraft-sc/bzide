import Foundation
import Synchronization
import Testing
@testable import NavidromeCore

/// Answers fetches from a list set up by the test, one per call.
private final class ScriptedFetch: Sendable {
    private let results: Mutex<[Result<[String], SubsonicError>]>

    init(_ results: [Result<[String], SubsonicError>]) {
        self.results = Mutex(results)
    }

    func next() throws(SubsonicError) -> [String] {
        let result = results.withLock { $0.removeFirst() }
        return try result.get()
    }
}

@MainActor
struct LoadModelTests {
    private let offline = SubsonicError.network(.notConnectedToInternet)

    private func makeModel(_ fetch: ScriptedFetch) -> LoadModel<[String]> {
        LoadModel { () async throws(SubsonicError) -> [String] in try fetch.next() }
    }

    @Test func startsLoadingThenShowsTheResult() async {
        let model = makeModel(ScriptedFetch([.success(["A", "B"])]))
        #expect(model.state == .loading)
        await model.load()
        #expect(model.state == .loaded(["A", "B"]))
        #expect(model.value == ["A", "B"])
    }

    @Test func failureWithNothingShownIsAnError() async {
        let model = makeModel(ScriptedFetch([.failure(offline)]))
        await model.load()
        #expect(model.state == .failed(offline.localizedDescription))
        #expect(model.value == nil)
    }

    @Test func retryAfterAFailureLoads() async {
        let model = makeModel(ScriptedFetch([.failure(offline), .success(["A"])]))
        await model.load()
        await model.load()
        #expect(model.state == .loaded(["A"]))
    }

    @Test func refreshReplacesTheContent() async {
        let model = makeModel(ScriptedFetch([.success(["A"]), .success(["A", "B"])]))
        await model.load()
        await model.load()
        #expect(model.value == ["A", "B"])
        #expect(model.refreshError == nil)
    }

    @Test func failedRefreshKeepsTheContentAndReportsWhy() async {
        let model = makeModel(ScriptedFetch([.success(["A"]), .failure(offline)]))
        await model.load()
        await model.load()
        #expect(model.state == .loaded(["A"]))
        #expect(model.refreshError == offline.localizedDescription)
    }

    @Test func successfulRefreshClearsAnEarlierRefreshError() async {
        let model = makeModel(ScriptedFetch([.success(["A"]), .failure(offline), .success(["B"])]))
        await model.load()
        await model.load()
        await model.load()
        #expect(model.value == ["B"])
        #expect(model.refreshError == nil)
    }
}
