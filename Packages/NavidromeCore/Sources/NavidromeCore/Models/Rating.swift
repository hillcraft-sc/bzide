/// The app's three-level rating, stored on the server as Subsonic's 1–5 stars.
public enum Rating: Int, Sendable, CaseIterable {
    case meh = 2
    case good = 3
    case great = 5

    public var title: String {
        switch self {
        case .meh: "Meh"
        case .good: "Good"
        case .great: "Great"
        }
    }

    /// The level shown for a server rating, which may have been set to any
    /// 1–5 elsewhere (e.g. Navidrome's web UI). 0, missing or out of range
    /// means unrated.
    public init?(serverValue: Int?) {
        switch serverValue {
        case 1, 2: self = .meh
        case 3: self = .good
        case 4, 5: self = .great
        default: return nil
        }
    }
}
