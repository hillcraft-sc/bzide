@testable import NavidromeCore

@MainActor
final class FakeNowPlaying: NowPlayingControlling {
    var onCommand: (@MainActor (RemoteCommand) -> Void)?
    private(set) var updates: [NowPlayingInfo?] = []

    var latest: NowPlayingInfo? { updates.last ?? nil }

    func update(_ info: NowPlayingInfo?) {
        updates.append(info)
    }

    func send(_ command: RemoteCommand) {
        onCommand?(command)
    }
}
