import AVFoundation

/// System audio events the engine reacts to.
public enum AudioSessionEvent: Sendable, Equatable {
    /// Another audio source (call, Siri, alarm, another app) took over.
    case interruptionBegan
    /// The interruption is over. `shouldResume` is the system's hint that
    /// resuming playback now is appropriate.
    case interruptionEnded(shouldResume: Bool)
    /// The device we were playing through went away (headphones unplugged,
    /// Bluetooth disconnected).
    case outputDeviceLost
}

public struct AudioSessionError: Error, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// The audio session boundary. Production wraps `AVAudioSession`; tests use a fake.
@MainActor
public protocol AudioSessionControlling: AnyObject {
    var onEvent: (@MainActor (AudioSessionEvent) -> Void)? { get set }
    /// Claims audio output for music playback. Called before every play.
    func activate() throws(AudioSessionError)
}

/// `AudioSessionControlling` backed by the shared `AVAudioSession`.
/// Lives for the app's lifetime.
@MainActor
public final class SystemAudioSession: AudioSessionControlling {
    public var onEvent: (@MainActor (AudioSessionEvent) -> Void)?

    private let session = AVAudioSession.sharedInstance()
    private var notificationTokens: [any NSObjectProtocol] = []

    public init() {
        observeNotifications()
    }

    public func activate() throws(AudioSessionError) {
        do {
            // `.longFormAudio` is Apple's policy for music and podcast apps; it
            // routes playback to AirPlay and CarPlay like other music apps.
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            throw AudioSessionError(message: error.localizedDescription)
        }
    }

    private func observeNotifications() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.didBecomeInactiveNotification, object: session, queue: .main
        ) { [weak self] notification in
            let context = notification.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
            let event = context.flatMap { Self.deactivationEvent(source: $0.source) }
            MainActor.assumeIsolated {
                if let event { self?.onEvent?(event) }
            }
        })
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.resumptionRecommendationNotification, object: session, queue: .main
        ) { [weak self] notification in
            let context = notification.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext
            let event = Self.resumptionEvent(recommendation: context?.recommendation)
            MainActor.assumeIsolated { self?.onEvent?(event) }
        })
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] notification in
            let event = Self.routeChangeEvent(from: notification.userInfo)
            MainActor.assumeIsolated {
                if let event { self?.onEvent?(event) }
            }
        })
    }

    /// Only the system taking the session away is an interruption; our own
    /// deactivation is not.
    nonisolated static func deactivationEvent(source: AVAudioSession.DeactivationSource) -> AudioSessionEvent? {
        source == .system ? .interruptionBegan : nil
    }

    /// A missing recommendation is treated as "don't resume": never start
    /// playback without the system's go-ahead.
    nonisolated static func resumptionEvent(recommendation: AVAudioSession.ResumptionRecommendation?) -> AudioSessionEvent {
        .interruptionEnded(shouldResume: recommendation == .shouldResume)
    }

    nonisolated static func routeChangeEvent(from userInfo: [AnyHashable: Any]?) -> AudioSessionEvent? {
        guard
            let rawReason = userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable
        else { return nil }
        return .outputDeviceLost
    }
}
