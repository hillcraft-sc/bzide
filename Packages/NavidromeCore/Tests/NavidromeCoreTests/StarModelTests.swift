import Foundation
import Testing
@testable import NavidromeCore

struct StarRequest: Sendable, Equatable {
    let target: StarTarget
    let starred: Bool
}

@MainActor
struct StarModelTests {
    private let server = GatedFetch<StarRequest, Void>()
    private let album = StarTarget.album(id: "al-1")

    private func makeModel() -> StarModel {
        StarModel { [server] target, starred async throws(SubsonicError) in
            try await server.fetch(StarRequest(target: target, starred: starred))
        }
    }

    @Test func followsTheServerUntilChanged() {
        let model = makeModel()
        #expect(model.isStarred(album, fromServer: true))
        #expect(!model.isStarred(album, fromServer: false))
    }

    @Test func starFlipsAtOnceAndIsSent() async {
        let model = makeModel()
        let toggle = Task { @MainActor in await model.toggle(album, fromServer: false) }
        await server.waitForCalls(1)
        // Shown starred before the server answers, even where the list still says otherwise.
        #expect(model.isStarred(album, fromServer: false))

        server.reply(to: 0, with: .success(()))
        await toggle.value
        #expect(server.requests == [StarRequest(target: album, starred: true)])
        #expect(model.isStarred(album, fromServer: false))
        #expect(model.error == nil)
    }

    @Test func unstarSendsUnstar() async {
        let model = makeModel()
        let toggle = Task { @MainActor in await model.toggle(album, fromServer: true) }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .success(()))
        await toggle.value
        #expect(server.requests == [StarRequest(target: album, starred: false)])
        #expect(!model.isStarred(album, fromServer: true))
    }

    @Test func failureFlipsBackAndSaysWhy() async {
        let model = makeModel()
        let offline = SubsonicError.network(.notConnectedToInternet)
        let toggle = Task { @MainActor in await model.toggle(album, fromServer: false) }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .failure(offline))
        await toggle.value
        #expect(!model.isStarred(album, fromServer: false))
        #expect(model.error == offline.localizedDescription)

        model.dismissError()
        #expect(model.error == nil)
    }

    @Test func tapWhileSendingIsIgnored() async {
        let model = makeModel()
        let first = Task { @MainActor in await model.toggle(album, fromServer: false) }
        await server.waitForCalls(1)
        await model.toggle(album, fromServer: false)
        server.reply(to: 0, with: .success(()))
        await first.value
        #expect(server.requests.count == 1)
        #expect(model.isStarred(album, fromServer: false))
    }

    @Test func favoritingSetsRatherThanFlips() async {
        let model = makeModel()
        // Already a favorite: nothing is sent, and it counts as done.
        #expect(await model.set(album, starred: true, fromServer: true))
        #expect(server.requests.isEmpty)

        let favorite = Task { @MainActor in await model.set(album, starred: true, fromServer: false) }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .success(()))
        #expect(await favorite.value)
        #expect(server.requests == [StarRequest(target: album, starred: true)])
        // A second press doesn't undo it.
        #expect(await model.set(album, starred: true, fromServer: false))
        #expect(server.requests.count == 1)
        #expect(model.isStarred(album, fromServer: false))
    }

    @Test func aFailedFavoriteSaysSo() async {
        let model = makeModel()
        let favorite = Task { @MainActor in await model.set(album, starred: true, fromServer: false) }
        await server.waitForCalls(1)
        server.reply(to: 0, with: .failure(.network(.notConnectedToInternet)))
        #expect(await favorite.value == false)
        #expect(!model.isStarred(album, fromServer: false))
    }
}
