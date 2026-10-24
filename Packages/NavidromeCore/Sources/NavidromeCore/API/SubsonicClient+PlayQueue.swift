import Foundation

/// The play queue saved on the server, for continuing on another device
/// (Gitea #37): its songs, which one is playing and how far in.
public struct ServerPlayQueue: Sendable, Equatable {
    public var songs: [Song]
    /// 0-based, into `songs`.
    public var currentIndex: Int
    /// Seconds into the current song.
    public var position: TimeInterval
    /// When it was saved, by the server's clock.
    public var changed: Date?
    /// The app that saved it (its `c` name), e.g. "Bzide" or "Feishin".
    public var changedBy: String?

    public init(songs: [Song], currentIndex: Int, position: TimeInterval, changed: Date? = nil, changedBy: String? = nil) {
        self.songs = songs
        self.currentIndex = currentIndex
        self.position = position
        self.changed = changed
        self.changedBy = changedBy
    }

    public var current: Song? { songs.indices.contains(currentIndex) ? songs[currentIndex] : nil }
}

extension SubsonicClient {
    /// Saves the queue for this user, replacing what was there. `byIndex`
    /// uses OpenSubsonic `indexBasedQueue`, which keeps a song that's in the
    /// queue twice in its place; without it the current song is named by id.
    /// `post` sends it as a form POST (OpenSubsonic `formPost`), for long queues.
    public func savePlayQueue(
        songIDs: [String], currentIndex: Int, position: TimeInterval, byIndex: Bool, post: Bool
    ) async throws(SubsonicError) {
        guard songIDs.indices.contains(currentIndex) else { return }
        var parameters = songIDs.map { URLQueryItem(name: "id", value: $0) }
        parameters += byIndex
            ? [URLQueryItem(name: "currentIndex", value: String(currentIndex))]
            : [URLQueryItem(name: "current", value: songIDs[currentIndex])]
        parameters.append(URLQueryItem(name: "position", value: String(Int((max(position, 0) * 1000).rounded()))))
        _ = try await request(byIndex ? "savePlayQueueByIndex" : "savePlayQueue", parameters: parameters, post: post, as: EmptyPayload.self)
    }

    /// The saved queue, or `nil` when there's none (or it's empty).
    public func playQueue(byIndex: Bool) async throws(SubsonicError) -> ServerPlayQueue? {
        do {
            if byIndex {
                return try await request("getPlayQueueByIndex", as: OptionalItemPayload<PlayQueueByIndexResponse, PlayQueueByIndexKey>.self).item?.queue
            }
            return try await request("getPlayQueue", as: OptionalItemPayload<PlayQueueResponse, PlayQueueKey>.self).item?.queue
        } catch .server(code: 70, _) {
            // "Not found": nothing saved yet.
            return nil
        }
    }
}

enum PlayQueueKey: ItemKey { static let key = "playQueue" }
enum PlayQueueByIndexKey: ItemKey { static let key = "playQueueByIndex" }

/// `getPlayQueue`: the current song by id; the first with that id is taken.
struct PlayQueueResponse: Decodable {
    let queue: ServerPlayQueue?

    private enum Keys: String, CodingKey { case entry, current, position, changed, changedBy }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let songs = c.lossyArray(Song.self, forKey: .entry)
        let current = c.lenientString(.current)
        let index = songs.firstIndex { $0.id == current } ?? 0
        queue = songs.isEmpty ? nil : ServerPlayQueue(
            songs: songs, currentIndex: index, position: TimeInterval(c.lenientInt(.position) ?? 0) / 1000,
            changed: c.lenientDate(.changed), changedBy: c.nonEmptyString(.changedBy)
        )
    }
}

/// `getPlayQueueByIndex`: the current song by position.
struct PlayQueueByIndexResponse: Decodable {
    let queue: ServerPlayQueue?

    private enum Keys: String, CodingKey { case entry, currentIndex, position, changed, changedBy }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let songs = c.lossyArray(Song.self, forKey: .entry)
        let index = c.lenientInt(.currentIndex) ?? 0
        queue = songs.isEmpty ? nil : ServerPlayQueue(
            songs: songs, currentIndex: songs.indices.contains(index) ? index : 0,
            position: TimeInterval(c.lenientInt(.position) ?? 0) / 1000,
            changed: c.lenientDate(.changed), changedBy: c.nonEmptyString(.changedBy)
        )
    }
}
