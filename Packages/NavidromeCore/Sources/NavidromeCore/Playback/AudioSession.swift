import AVFoundation
import os

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
    /// The system's audio services went down. The player is dead until
    /// `mediaServicesReset` arrives.
    case mediaServicesLost
    /// The system restarted its audio services. Every player is now dead and
    /// must be rebuilt, and the session set up again.
    case mediaServicesReset
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

    private static let logger = Logger(subsystem: "MusicApp", category: "AudioSession")

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
            let nsError = error as NSError
            Self.logger.error("Activation failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
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
            let source = context.map { String(describing: $0.source) } ?? "none"
            MainActor.assumeIsolated {
                Self.logger.notice("Raw: became inactive, source \(source, privacy: .public)")
                if let event { self?.deliver(event) }
            }
        })
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.resumptionRecommendationNotification, object: session, queue: .main
        ) { [weak self] notification in
            let context = notification.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext
            let event = Self.resumptionEvent(recommendation: context?.recommendation)
            let recommendation = context.map { String(describing: $0.recommendation) } ?? "none"
            MainActor.assumeIsolated {
                Self.logger.notice("Raw: resumption recommendation \(recommendation, privacy: .public)")
                self?.deliver(event)
            }
        })
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] notification in
            let event = Self.routeChangeEvent(from: notification.userInfo)
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).map(String.init) ?? "none"
            MainActor.assumeIsolated {
                Self.logger.notice("Raw: route change, reason \(reason, privacy: .public)")
                if let event { self?.deliver(event) }
            }
        })
        // Not acted on: the classic interruption notification, logged to compare
        // with the iOS 27 notifications above while diagnosing call handling.
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).map(String.init) ?? "none"
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(String.init) ?? "none"
            let reason = (notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt).map(String.init) ?? "none"
            MainActor.assumeIsolated {
                Self.logger.notice("Raw: classic interruption, type \(type, privacy: .public), options \(options, privacy: .public), reason \(reason, privacy: .public)")
            }
        })
        // Apple's docs say observers stay registered across a reset, so this
        // object survives it; only the player needs rebuilding. Filtered to our
        // session: with no filter, each notification arrived twice on device.
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereLostNotification, object: session, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.deliver(.mediaServicesLost) }
        })
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.deliver(.mediaServicesReset) }
        })
    }

    private func deliver(_ event: AudioSessionEvent) {
        Self.logger.notice("Session event: \(String(describing: event), privacy: .public)")
        onEvent?(event)
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
