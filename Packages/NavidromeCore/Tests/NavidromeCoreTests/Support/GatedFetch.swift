import Synchronization
@testable import NavidromeCore

/// A fake server call that waits until the test answers it, so tests can control
/// the order replies arrive in.
final class GatedFetch<Request: Sendable, Response: Sendable>: Sendable {
    private struct Call {
        let request: Request
        var continuation: CheckedContinuation<Result<Response, SubsonicError>, Never>?
    }

    private let calls = Mutex<[Call]>([])

    var requests: [Request] { calls.withLock { $0.map(\.request) } }

    func fetch(_ request: Request) async throws(SubsonicError) -> Response {
        let result = await withCheckedContinuation { continuation in
            calls.withLock { $0.append(Call(request: request, continuation: continuation)) }
        }
        return try result.get()
    }

    /// Waits until `count` calls have been made.
    func waitForCalls(_ count: Int) async {
        while calls.withLock({ $0.count }) < count {
            await Task.yield()
        }
    }

    func reply(to index: Int, with result: Result<Response, SubsonicError>) {
        let continuation = calls.withLock { calls in
            defer { calls[index].continuation = nil }
            return calls[index].continuation
        }
        continuation?.resume(returning: result)
    }
}
