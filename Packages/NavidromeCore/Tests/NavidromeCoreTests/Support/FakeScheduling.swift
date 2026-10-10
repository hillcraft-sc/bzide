@testable import NavidromeCore

/// Holds scheduled actions until a test fires them, so timing is deterministic.
@MainActor
final class FakeScheduler: Scheduling {
    private struct Pending {
        let id: Int
        let delay: Duration
        let action: @MainActor () -> Void
    }

    private var pending: [Pending] = []
    private var nextID = 0

    /// Delays of everything still waiting, in scheduling order.
    var pendingDelays: [Duration] { pending.map(\.delay) }

    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> ScheduledAction {
        let id = nextID
        nextID += 1
        pending.append(Pending(id: id, delay: delay, action: action))
        return ScheduledAction { [weak self] in self?.pending.removeAll { $0.id == id } }
    }

    /// Runs the oldest pending action.
    func fireNext() {
        guard !pending.isEmpty else { return }
        pending.removeFirst().action()
    }
}

@MainActor
final class FakeNetworkMonitor: NetworkMonitoring {
    var onNetworkAvailable: (@MainActor () -> Void)?

    func becomeAvailable() {
        onNetworkAvailable?()
    }
}
