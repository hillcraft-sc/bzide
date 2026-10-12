@testable import NavidromeCore

@MainActor
final class FakeAudioSession: AudioSessionControlling {
    var onEvent: (@MainActor (AudioSessionEvent) -> Void)?
    var activationError: AudioSessionError?
    /// Off: activations wait for `finishActivation()`, as a slow system would.
    var completesImmediately = true
    private(set) var activationCount = 0
    private var pending: [@MainActor @Sendable (AudioSessionError?) -> Void] = []

    func activate(completion: @escaping @MainActor @Sendable (AudioSessionError?) -> Void) {
        activationCount += 1
        if completesImmediately {
            completion(activationError)
        } else {
            pending.append(completion)
        }
    }

    /// Completes the oldest waiting activation.
    func finishActivation(_ error: AudioSessionError? = nil) {
        guard !pending.isEmpty else { return }
        pending.removeFirst()(error)
    }

    func report(_ event: AudioSessionEvent) {
        onEvent?(event)
    }
}
