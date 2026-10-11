import Foundation
import Synchronization

/// The queue plus where we were in the current song. This is what survives
/// app termination.
public struct QueueSnapshot: Sendable, Equatable, Codable {
    public var queue: PlaybackQueue
    /// Seconds into the current entry.
    public var position: TimeInterval
    public var repeatMode: RepeatMode

    public init(queue: PlaybackQueue, position: TimeInterval, repeatMode: RepeatMode = .off) {
        self.queue = queue
        self.position = position
        self.repeatMode = repeatMode
    }

    private enum CodingKeys: String, CodingKey { case queue, position, repeatMode }

    /// Queues saved before repeat existed have no mode: off.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        queue = try c.decode(PlaybackQueue.self, forKey: .queue)
        position = try c.decode(TimeInterval.self, forKey: .position)
        repeatMode = (try? c.decodeIfPresent(RepeatMode.self, forKey: .repeatMode)) ?? .off
    }
}

public protocol QueueStore: Sendable {
    /// `nil` when nothing has been saved.
    func load() throws(QueueStoreError) -> QueueSnapshot?
    func save(_ snapshot: QueueSnapshot) throws(QueueStoreError)
}

public enum QueueStoreError: Error, Equatable, Sendable {
    /// The saved file exists but couldn't be decoded (e.g. written by a different version).
    case unreadable
    /// The file couldn't be read or written.
    case io(String)
}

/// Saves the queue as JSON in one file, replaced atomically on each save so a crash
/// mid-write never leaves a half-written queue behind.
public struct FileQueueStore: QueueStore {
    private let fileURL: URL
    static let fileName = "PlaybackQueue.json"

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `Application Support/PlaybackQueue.json` in the app's container.
    public static func applicationSupport() throws(QueueStoreError) -> FileQueueStore {
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            return FileQueueStore(fileURL: directory.appending(path: fileName))
        } catch {
            throw .io(String(describing: error))
        }
    }

    public func load() throws(QueueStoreError) -> QueueSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw .io(String(describing: error))
        }
        guard let snapshot = try? JSONDecoder().decode(QueueSnapshot.self, from: data) else {
            throw .unreadable
        }
        return snapshot
    }

    public func save(_ snapshot: QueueSnapshot) throws(QueueStoreError) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            // Saves happen during locked-screen playback, so the file must stay writable
            // while the device is locked (after the first unlock since boot).
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw .io(String(describing: error))
        }
    }
}

public final class InMemoryQueueStore: QueueStore {
    private let stored: Mutex<QueueSnapshot?>

    public init(_ snapshot: QueueSnapshot? = nil) {
        stored = Mutex(snapshot)
    }

    public func load() -> QueueSnapshot? {
        stored.withLock { $0 }
    }

    public func save(_ snapshot: QueueSnapshot) {
        stored.withLock { $0 = snapshot }
    }
}
