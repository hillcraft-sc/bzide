import Foundation
import os
import Synchronization

/// A scrobble waiting to be accepted by the server.
public struct PendingScrobble: Sendable, Equatable, Codable {
    public let songID: String
    public let playedAt: Date

    public init(songID: String, playedAt: Date) {
        self.songID = songID
        self.playedAt = playedAt
    }
}

/// What the engine tells the scrobbler. Kept separate from the network so the
/// engine stays synchronous and testable.
@MainActor
public protocol ScrobbleSubmitting: AnyObject {
    /// The play started: update the server's "now playing".
    func nowPlaying(songID: String)
    /// The play reached the threshold: record it.
    func submit(_ scrobble: PendingScrobble)
}

/// The server call. `SubsonicClient` conforms.
public protocol ScrobbleSending: Sendable {
    func scrobble(songID: String, playedAt: Date?, submission: Bool) async throws
}

extension SubsonicClient: ScrobbleSending {}

public protocol ScrobbleStore: Sendable {
    func load() -> [PendingScrobble]
    func save(_ pending: [PendingScrobble])
}

/// Delivers scrobbles. Each is saved before it is sent and removed only once the
/// server accepts it, so being offline or quitting the app never loses one. They
/// are sent oldest first, at the next submission and at launch.
///
/// With Send Plays to Server off (`isEnabled`), neither "now playing" nor new
/// plays are sent or saved; plays saved while it was on are still delivered.
@MainActor
public final class Scrobbler: ScrobbleSubmitting {
    public private(set) var pending: [PendingScrobble]

    private let sender: any ScrobbleSending
    private let store: any ScrobbleStore
    private let isEnabled: @MainActor () -> Bool
    /// The send in progress, if any. Cleared by the task itself when it ends.
    private var flushTask: Task<Void, Never>?
    private static let logger = Logger(subsystem: "MusicApp", category: "Scrobbler")

    public init(sender: any ScrobbleSending, store: any ScrobbleStore, isEnabled: @escaping @MainActor () -> Bool = { true }) {
        self.sender = sender
        self.store = store
        self.isEnabled = isEnabled
        pending = store.load()
    }

    public func nowPlaying(songID: String) {
        guard isEnabled() else { return }
        let sender = sender
        Task {
            // Best effort: a missed "now playing" doesn't matter, so no retry.
            try? await sender.scrobble(songID: songID, playedAt: nil, submission: false)
        }
    }

    public func submit(_ scrobble: PendingScrobble) {
        guard isEnabled() else { return }
        pending.append(scrobble)
        store.save(pending)
        Task { await flush() }
    }

    /// Sends pending scrobbles oldest first. Waits for any send already in
    /// progress, so sends never overlap and nothing is sent twice.
    public func flush() async {
        while let running = flushTask {
            await running.value
        }
        guard !pending.isEmpty else { return }
        let task = Task {
            await sendPending()
            flushTask = nil
        }
        flushTask = task
        await task.value
    }

    /// Stops at the first failure so order is kept and nothing is skipped.
    private func sendPending() async {
        while let next = pending.first {
            do {
                try await sender.scrobble(songID: next.songID, playedAt: next.playedAt, submission: true)
            } catch {
                Self.logger.notice("Scrobble not sent yet, will retry: \(String(describing: error), privacy: .public)")
                return
            }
            pending.removeFirst()
            store.save(pending)
        }
    }
}

/// Saves pending scrobbles as JSON, replaced atomically on each save.
public struct FileScrobbleStore: ScrobbleStore {
    private let fileURL: URL
    private static let logger = Logger(subsystem: "MusicApp", category: "FileScrobbleStore")
    static let fileName = "PendingScrobbles.json"

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `Application Support/PendingScrobbles.json`. `nil` if the directory can't be created.
    public static func applicationSupport() -> FileScrobbleStore? {
        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return FileScrobbleStore(fileURL: directory.appending(path: fileName))
    }

    public func load() -> [PendingScrobble] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode([PendingScrobble].self, from: data)
        } catch {
            Self.logger.error("Pending scrobbles unreadable, starting empty")
            return []
        }
    }

    public func save(_ pending: [PendingScrobble]) {
        do {
            // Written during locked-screen playback, like the queue.
            try JSONEncoder().encode(pending).write(
                to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            Self.logger.error("Couldn't save pending scrobbles: \(String(describing: error), privacy: .public)")
        }
    }
}

/// For tests, previews, and as a fallback when the file can't be used.
public final class InMemoryScrobbleStore: ScrobbleStore {
    private let stored: Mutex<[PendingScrobble]>

    public init(_ pending: [PendingScrobble] = []) {
        stored = Mutex(pending)
    }

    public func load() -> [PendingScrobble] { stored.withLock { $0 } }
    public func save(_ pending: [PendingScrobble]) { stored.withLock { $0 = pending } }
}
