import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct RandomMixModelTests {
    private let server = GatedFetch<Int, [Song]>()

    private final class Played {
        var queues: [[Song]] = []
    }

    private func makeModel(_ played: Played) -> RandomMixModel {
        RandomMixModel(
            fetch: { [server] count async throws(SubsonicError) in try await server.fetch(count) },
            play: { played.queues.append($0) }
        )
    }

    private let songs = (1...3).map { Song(id: "so-\($0)", title: "Song \($0)") }

    @Test func fetchesAndPlaysTheSongs() async {
        let played = Played()
        let model = makeModel(played)
        let task = Task { @MainActor in await model.start() }
        await server.waitForCalls(1)
        #expect(model.isLoading)
        server.reply(to: 0, with: .success(songs))
        await task.value

        #expect(server.requests == [RandomMixModel.songCount])
        #expect(played.queues == [songs])
        #expect(!model.isLoading)
        #expect(model.error == nil)
    }

    @Test func aSecondTapWhileLoadingIsIgnored() async {
        let played = Played()
        let model = makeModel(played)
        let task = Task { @MainActor in await model.start() }
        await server.waitForCalls(1)
        await model.start()
        server.reply(to: 0, with: .success(songs))
        await task.value
        #expect(server.requests.count == 1)
        #expect(played.queues.count == 1)
    }

    @Test func failureIsShownAndNothingPlays() async {
        let played = Played()
        let model = makeModel(played)
        let offline = SubsonicError.network(.notConnectedToInternet)
        let task = Task { @MainActor in await model.start() }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .failure(offline))
        await task.value
        #expect(model.error == offline.localizedDescription)
        #expect(played.queues.isEmpty)
    }

    @Test func anEmptyLibraryIsReported() async {
        let played = Played()
        let model = makeModel(played)
        let task = Task { @MainActor in await model.start() }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .success([]))
        await task.value
        #expect(model.error == "The server returned no songs.")
        #expect(played.queues.isEmpty)
    }
}
