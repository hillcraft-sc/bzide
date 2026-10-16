import Foundation

/// Recently Played: albums played in the last week, from any app (the
/// server's recently played list), most recent first.
public enum RecentlyPlayed {
    public static let days = 7
    /// Shown when the server doesn't say when albums were played.
    public static let fallbackCount = 15

    /// The albums played within `days` of `now`. A server that doesn't give
    /// play dates gets its most recent `fallbackCount` instead.
    public static func albums(from recent: [Album], now: Date) -> [Album] {
        guard recent.contains(where: { $0.details.lastPlayed != nil }) else {
            return Array(recent.prefix(fallbackCount))
        }
        let since = now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        return recent
            .filter { ($0.details.lastPlayed ?? .distantPast) >= since }
            .sorted { ($0.details.lastPlayed ?? .distantPast) > ($1.details.lastPlayed ?? .distantPast) }
    }
}

/// Spin It Back: albums worth hearing again. Favors music the user clearly
/// likes (ratings, favorites, plays) that they haven't played in a while,
/// never anything rated Meh, at most two per artist, with a daily shuffle so
/// it changes each day but holds still within one.
public enum SpinItBack {
    public static let count = 15
    static let perArtist = 2

    /// The picks from the whole album list.
    public static func picks(from albums: [Album], now: Date, calendar: Calendar = .current) -> [Album] {
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        let scored = albums.compactMap { album -> (Album, Double)? in
            guard let score = score(album, now: now) else { return nil }
            return (album, score * jitter(album.id, day: day))
        }
        var byArtist: [String: Int] = [:]
        var picks: [Album] = []
        for (album, _) in scored.sorted(by: { $0.1 > $1.1 }) {
            let artist = album.artistID ?? album.artist ?? album.id
            guard byArtist[artist, default: 0] < perArtist else { continue }
            byArtist[artist, default: 0] += 1
            picks.append(album)
            if picks.count == count { break }
        }
        return picks
    }

    /// For a server without play counts, dates or ratings in its album list:
    /// its most played albums, less any played recently.
    public static func fallback(frequent: [Album], recent: [Album]) -> [Album] {
        let recentIDs = Set(recent.prefix(30).map(\.id))
        return Array(frequent.filter { !recentIDs.contains($0.id) }.prefix(count))
    }

    /// How much an album deserves a re-listen, or `nil` if it doesn't: it must
    /// be liked (rated Love or Like, a favorite, or played a few
    /// times), and not rated Meh.
    static func score(_ album: Album, now: Date) -> Double? {
        let rating = Rating(serverValue: album.userRating)
        if rating == .meh { return nil }
        let plays = album.details.playCount ?? 0
        guard rating != nil || album.isStarred || plays >= 2 else { return nil }
        let liking = (rating == .love ? 1.0 : rating == .like ? 0.7 : 0.35)
            + (album.isStarred ? 0.4 : 0)
            + min(log2(1 + Double(plays)) / 6, 0.6)
        return liking * timeAway(album.details.lastPlayed, now: now)
    }

    /// Played in the last two weeks barely counts; then the longer since, the
    /// more, up to a year. Never played (as far as the server says): modest.
    static func timeAway(_ lastPlayed: Date?, now: Date) -> Double {
        guard let lastPlayed else { return 0.4 }
        let days = now.timeIntervalSince(lastPlayed) / (24 * 60 * 60)
        if days < 14 { return 0.05 }
        if days >= 365 { return 1 }
        return 0.3 + 0.7 * (days - 14) / (365 - 14)
    }

    /// 0.85…1.15, the same for an album all day (stable across launches).
    static func jitter(_ id: String, day: Int) -> Double {
        // FNV-1a: Swift's own hashes change every launch.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(id)|\(day)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return 0.85 + 0.3 * Double(hash % 10_000) / 10_000
    }
}
