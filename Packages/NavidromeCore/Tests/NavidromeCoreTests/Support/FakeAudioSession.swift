@testable import NavidromeCore

@MainActor
final class FakeAudioSession: AudioSessionControlling {
    var onEvent: (@MainActor (AudioSessionEvent) -> Void)?
    var activationError: AudioSessionError?
    private(set) var activationCount = 0

    func activate() throws(AudioSessionError) {
        activationCount += 1
        if let activationError { throw activationError }
    }

    func report(_ event: AudioSessionEvent) {
        onEvent?(event)
    }
}
