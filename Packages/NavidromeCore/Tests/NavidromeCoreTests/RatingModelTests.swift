import Foundation
import Testing
@testable import NavidromeCore

struct RatingRequest: Sendable, Equatable {
    let target: StarTarget
    let stars: Int?
}

struct RatingTests {
    @Test func levelsAreSentAsTwoThreeAndFiveStars() {
        #expect(Rating.allCases.map(\.rawValue) == [2, 3, 5])
    }

    @Test func serverRatingsRoundToTheNearestLevel() {
        #expect([1, 2, 3, 4, 5].map { Rating(serverValue: $0) } == [.meh, .meh, .like, .love, .love])
    }

    @Test func zeroMissingOrOutOfRangeIsUnrated() {
        #expect(Rating(serverValue: 0) == nil)
        #expect(Rating(serverValue: nil) == nil)
        #expect(Rating(serverValue: 6) == nil)
        #expect(Rating(serverValue: -1) == nil)
    }
}

@MainActor
struct RatingModelTests {
    private let server = GatedFetch<RatingRequest, Void>()
    private let album = StarTarget.album(id: "al-1")

    private func makeModel() -> RatingModel {
        RatingModel { [server] target, stars async throws(SubsonicError) in
            try await server.fetch(RatingRequest(target: target, stars: stars))
        }
    }

    @Test func followsTheServerUntilChanged() {
        let model = makeModel()
        #expect(model.rating(album, fromServer: 4) == .love)
        #expect(model.rating(album, fromServer: nil) == nil)
    }

    @Test func ratingChangesAtOnceAndIsSent() async {
        let model = makeModel()
        let choose = Task { @MainActor in await model.choose(.meh, for: album, fromServer: nil) }
        await server.waitForCalls(1)
        // Shown before the server answers, even where the list still says otherwise.
        #expect(model.rating(album, fromServer: nil) == .meh)

        server.reply(to: 0, with: .success(()))
        await choose.value
        #expect(server.requests == [RatingRequest(target: album, stars: 2)])
        #expect(model.rating(album, fromServer: nil) == .meh)
        #expect(model.error == nil)
    }

    @Test func choosingTheCurrentRatingClearsIt() async {
        let model = makeModel()
        // 4 stars from the web UI shows as Love; choosing Love clears it.
        let choose = Task { @MainActor in await model.choose(.love, for: album, fromServer: 4) }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .success(()))
        await choose.value
        #expect(server.requests == [RatingRequest(target: album, stars: nil)])
        #expect(model.rating(album, fromServer: 4) == nil)
    }

    @Test func choosingAnotherLevelReplacesIt() async {
        let model = makeModel()
        let choose = Task { @MainActor in await model.choose(.like, for: album, fromServer: 5) }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .success(()))
        await choose.value
        #expect(server.requests == [RatingRequest(target: album, stars: 3)])
        #expect(model.rating(album, fromServer: 5) == .like)
    }

    @Test func failureChangesBackAndSaysWhy() async {
        let model = makeModel()
        let offline = SubsonicError.network(.notConnectedToInternet)
        let choose = Task { @MainActor in await model.choose(.love, for: album, fromServer: 3) }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .failure(offline))
        await choose.value
        #expect(model.rating(album, fromServer: 3) == .like)
        #expect(model.error == offline.localizedDescription)

        model.dismissError()
        #expect(model.error == nil)
    }

    @Test func choiceWhileSendingIsIgnored() async {
        let model = makeModel()
        let first = Task { @MainActor in await model.choose(.like, for: album, fromServer: nil) }
        await server.waitForCalls(1)
        await model.choose(.love, for: album, fromServer: nil)
        server.reply(to: 0, with: .success(()))
        await first.value
        #expect(server.requests.count == 1)
        #expect(model.rating(album, fromServer: nil) == .like)
    }

    @Test func eachItemKeepsItsOwnRating() async {
        let model = makeModel()
        let song = StarTarget.song(id: "so-1")
        let choose = Task { @MainActor in await model.choose(.like, for: song, fromServer: nil) }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .success(()))
        await choose.value
        #expect(model.rating(album, fromServer: nil) == nil)
        #expect(model.rating(song, fromServer: nil) == .like)
    }
}
