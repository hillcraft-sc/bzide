import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct AlbumQueueModelTests {
    private let server = GatedFetch<String, [Song]>()

    private final class Performed {
        var calls: [(AlbumQueueModel.Action, [Song])] = []
    }

    private func makeModel(_ performed: Performed) -> AlbumQueueModel {
        AlbumQueueModel(
            fetch: { [server] id async throws(SubsonicError) in try await server.fetch(id) },
            perform: { performed.calls.append(($0, $1)) }
        )
    }

    private let songs = (1...3).map { Song(id: "so-\($0)", title: "Song \($0)") }

    @Test func fetchesTheAlbumThenPerformsTheAction() async {
        let performed = Performed()
        let model = makeModel(performed)
        let task = Task { @MainActor in await model.perform(.playNext, albumID: "al-1") }
        await server.waitForCalls(1)
        #expect(performed.calls.isEmpty)
        server.reply(to: 0, with: .success(songs))
        await task.value

        #expect(server.requests == ["al-1"])
        #expect(performed.calls.map(\.0) == [.playNext])
        #expect(performed.calls.map(\.1) == [songs])
        #expect(model.error == nil)
    }

    @Test func aSecondChoiceForTheSameAlbumWhileLoadingIsIgnored() async {
        let performed = Performed()
        let model = makeModel(performed)
        let first = Task { @MainActor in await model.perform(.addToQueue, albumID: "al-1") }
        await server.waitForCalls(1)
        await model.perform(.addToQueue, albumID: "al-1")
        server.reply(to: 0, with: .success(songs))
        await first.value
        #expect(server.requests.count == 1)
        #expect(performed.calls.count == 1)
    }

    @Test func failureIsShownAndNothingHappens() async {
        let performed = Performed()
        let model = makeModel(performed)
        let offline = SubsonicError.network(.notConnectedToInternet)
        let task = Task { @MainActor in await model.perform(.play, albumID: "al-1") }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .failure(offline))
        await task.value
        #expect(performed.calls.isEmpty)
        #expect(model.error == offline.localizedDescription)

        model.dismissError()
        #expect(model.error == nil)
    }

    @Test func anEmptyAlbumSaysSo() async {
        let performed = Performed()
        let model = makeModel(performed)
        let task = Task { @MainActor in await model.perform(.play, albumID: "al-1") }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .success([]))
        await task.value
        #expect(performed.calls.isEmpty)
        #expect(model.error == "This album has no songs.")
    }
}
