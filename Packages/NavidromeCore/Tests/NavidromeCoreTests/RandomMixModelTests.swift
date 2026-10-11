import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct RandomMixModelTests {
    private let server = GatedFetch<Int, [Song]>()

    private final class Played {
        var queues: [[Song]] = []
    }

    private func makeModel(_ played: Played, downloaded: [Song] = []) -> RandomMixModel {
        RandomMixModel(
            fetch: { [server] count async throws(SubsonicError) in try await server.fetch(count) },
            downloadedSongs: { downloaded },
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

    @Test func offlineItMixesTheDownloads() async {
        let played = Played()
        let downloaded = (1...80).map { Song(id: "dl-\($0)", title: "Downloaded \($0)") }
        let model = makeModel(played, downloaded: downloaded)
        let task = Task { @MainActor in await model.start() }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .failure(.network(.notConnectedToInternet)))
        await task.value

        let queue = played.queues.first ?? []
        #expect(queue.count == RandomMixModel.songCount)
        #expect(Set(queue.map(\.id)).count == queue.count)
        #expect(Set(queue.map(\.id)).isSubset(of: Set(downloaded.map(\.id))))
        #expect(model.error == nil)
        #expect(model.notice == RandomMixModel.offlineNotice)
    }

    @Test func aSmallDownloadLibraryIsPlayedWhole() async {
        let played = Played()
        let model = makeModel(played, downloaded: songs)
        let task = Task { @MainActor in await model.start() }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .failure(.httpStatus(502)))
        await task.value
        #expect(Set((played.queues.first ?? []).map(\.id)) == Set(songs.map(\.id)))
    }

    @Test func theOfflineNoticeClearsWhenTheServerIsBack() async {
        let played = Played()
        let model = makeModel(played, downloaded: songs)
        let first = Task { @MainActor in await model.start() }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .failure(.network(.notConnectedToInternet)))
        await first.value

        let second = Task { @MainActor in await model.start() }
        await server.waitForCalls(2)
        server.reply(to: 1, with: .success(songs))
        await second.value
        #expect(model.notice == nil)
        #expect(played.queues.count == 2)
    }
}
