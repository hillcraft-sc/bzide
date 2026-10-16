/// The app's three-level rating, stored on the server as Subsonic's 1–5 stars.
public enum Rating: Int, Sendable, CaseIterable {
    case meh = 2
    case like = 3
    case love = 5

    public var title: String {
        switch self {
        case .meh: "Meh"
        case .like: "Like"
        case .love: "Love"
        }
    }

    /// Whether a song belongs in a mix the app picks for the user (Random Mix,
    /// Spin Off, Keep Spinning): songs rated Meh are left out unless the user
    /// chose to include them. Unrated songs, and servers without ratings,
    /// always count.
    public static func suitsMix(_ song: Song, includeMeh: Bool) -> Bool {
        includeMeh || Rating(serverValue: song.userRating) != .meh
    }

    /// The level shown for a server rating, which may have been set to any
    /// 1–5 elsewhere (e.g. Navidrome's web UI). 0, missing or out of range
    /// means unrated.
    public init?(serverValue: Int?) {
        switch serverValue {
        case 1, 2: self = .meh
        case 3: self = .like
        case 4, 5: self = .love
        default: return nil
        }
    }
}
