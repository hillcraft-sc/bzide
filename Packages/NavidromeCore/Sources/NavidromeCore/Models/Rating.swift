/// The app's simplified three-level rating, stored on the server as
/// Subsonic's 1–5 stars. With Use Simplified Rating off, the stars themselves
/// are shown and chosen instead (see `Rating.stars(serverValue:)`); the mixes
/// read either the same way, so 1–2 stars are Meh.
public enum Rating: Int, Sendable, CaseIterable {
    case meh = 1
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

    /// A server rating as stars: 1–5, or `nil` for unrated (0, missing or out of range).
    public static func stars(serverValue: Int?) -> Int? {
        serverValue.flatMap { (1...5).contains($0) ? $0 : nil }
    }

    /// "1 Star", "4 Stars".
    public static func starsTitle(_ stars: Int) -> String {
        stars == 1 ? "1 Star" : "\(stars) Stars"
    }

    /// What a server rating is called in the chosen style: "Love", or "4 Stars".
    public static func title(serverValue: Int?, simplified: Bool) -> String? {
        simplified ? Rating(serverValue: serverValue)?.title : stars(serverValue: serverValue).map(starsTitle)
    }
}
