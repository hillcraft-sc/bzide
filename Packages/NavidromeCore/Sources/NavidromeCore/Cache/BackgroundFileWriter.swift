import Foundation
import os
import Synchronization

/// Saves a value as JSON in a file off the main thread, so a large one (a
/// year of play history, a long queue) never stalls the screen. Saves are
/// done in order, and one that's already outdated by a newer save is
/// skipped. The file is replaced atomically, so it's never half-written,
/// and stays writable while the device is locked (saves happen during
/// locked-screen playback).
///
/// `FileWriters.drainAll()` waits for every writer's pending saves: before
/// the files are moved (switching accounts, restoring a backup), so a late
/// save can't land in the wrong account's place.
final class BackgroundFileWriter<Value: Encodable & Sendable>: Sendable {
    private let fileURL: URL
    private let queue: DispatchQueue
    /// Bumped by each save; a queued save that isn't the latest is skipped.
    private let generation = Mutex(0)
    /// The newest value asked to be saved, until it's written: what reading
    /// the file back would give.
    private let pending = Mutex<Value?>(nil)
    private static var logger: Logger { Logger(subsystem: "MusicApp", category: "BackgroundFileWriter") }

    init(fileURL: URL) {
        self.fileURL = fileURL
        queue = DispatchQueue(label: "MusicApp.writer.\(fileURL.lastPathComponent)", qos: .utility)
        FileWriters.add(queue)
    }

    func save(_ value: Value) {
        let mine = generation.withLock { count in
            count += 1
            return count
        }
        pending.withLock { $0 = value }
        queue.async { [self] in
            guard generation.withLock({ $0 }) == mine else { return }
            do {
                let data = try JSONEncoder().encode(value)
                try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                let name = fileURL.lastPathComponent
                Self.logger.error("Couldn't save \(name, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            if generation.withLock({ $0 }) == mine { pending.withLock { $0 = nil } }
        }
    }

    /// The value waiting to be written, if any.
    var unwritten: Value? { pending.withLock { $0 } }

    /// Waits until this writer's saves are on disk.
    func drain() {
        queue.sync {}
    }
}

/// Every writer's queue, to wait for them all.
enum FileWriters {
    private static let queues = Mutex<[DispatchQueue]>([])

    static func add(_ queue: DispatchQueue) {
        queues.withLock { $0.append(queue) }
    }

    /// Waits until every writer's saves are on disk. Only a moment: saves
    /// take milliseconds, and this is only before files are moved.
    static func drainAll() {
        for queue in queues.withLock({ $0 }) { queue.sync {} }
    }
}
