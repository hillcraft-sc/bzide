import Foundation
import Network

/// How hard the engine tries to keep playing through network trouble.
public struct RecoveryPolicy: Sendable, Equatable {
    /// Wait before each retry; its length is the number of retries.
    public var retryDelays: [Duration]
    /// How long a stalled player gets to recover by itself before a reload.
    public var stallGracePeriod: Duration
    /// Seconds of uninterrupted playback after a retry before the retry budget
    /// resets. A stream that plays for a moment and drops again must not be
    /// retried forever.
    public var playbackNeededToReset: TimeInterval

    public init(
        retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)],
        stallGracePeriod: Duration = .seconds(10),
        playbackNeededToReset: TimeInterval = 10
    ) {
        self.retryDelays = retryDelays
        self.stallGracePeriod = stallGracePeriod
        self.playbackNeededToReset = playbackNeededToReset
    }
}

/// Runs an action later. Tests substitute a scheduler they fire by hand.
@MainActor
public protocol Scheduling: AnyObject {
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> ScheduledAction
}

/// A pending scheduled action that can be called off.
@MainActor
public final class ScheduledAction {
    private let onCancel: @MainActor () -> Void

    public init(onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        onCancel()
    }
}

@MainActor
public final class TaskScheduler: Scheduling {
    public init() {}

    public func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> ScheduledAction {
        let task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
        return ScheduledAction { task.cancel() }
    }
}

/// Reports when the device regains a usable network connection.
@MainActor
public protocol NetworkMonitoring: AnyObject {
    var onNetworkAvailable: (@MainActor () -> Void)? { get set }
}

/// Whether the current connection costs the user: cellular, a personal hotspot,
/// or Low Data Mode. Streaming quality follows it.
@MainActor
public protocol NetworkCostMonitoring: AnyObject {
    var isExpensive: Bool { get }
}

/// `NetworkMonitoring` backed by `NWPathMonitor`. Reports both "back online" and
/// "switched interface while online" (e.g. Wi-Fi to cellular), since either can
/// leave a broken stream that is worth retrying right away.
@MainActor
public final class SystemNetworkMonitor: NetworkMonitoring, NetworkCostMonitoring {
    public var onNetworkAvailable: (@MainActor () -> Void)?
    public private(set) var isExpensive = false

    private let monitor = NWPathMonitor()
    private var lastPath: (satisfied: Bool, interfaces: [NWInterface.InterfaceType])?

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            let interfaces = path.availableInterfaces.map(\.type)
            let expensive = path.isExpensive || path.isConstrained
            Task { @MainActor in
                self?.isExpensive = expensive
                self?.pathChanged(satisfied: satisfied, interfaces: interfaces)
            }
        }
        monitor.start(queue: DispatchQueue(label: "MusicApp.NetworkMonitor"))
    }

    private func pathChanged(satisfied: Bool, interfaces: [NWInterface.InterfaceType]) {
        defer { lastPath = (satisfied, interfaces) }
        guard satisfied, let lastPath else { return }
        if !lastPath.satisfied || lastPath.interfaces != interfaces {
            onNetworkAvailable?()
        }
    }
}
