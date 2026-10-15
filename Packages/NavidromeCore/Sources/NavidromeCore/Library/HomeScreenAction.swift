import Foundation

/// The actions on the app icon's long-press menu (Home Screen quick actions).
/// Offered only while signed in; Continue only when there's something to
/// continue (the saved queue, or the last radio station).
public enum HomeScreenAction: String, CaseIterable, Sendable {
    case resume, randomMix, myCuts, search

    /// The system's identifier for each action. Internal names keep
    /// "musicapp", like the bundle identifier.
    static let typePrefix = "com.erichebert.musicapp.quickaction."

    public var type: String { Self.typePrefix + rawValue }

    public init?(type: String) {
        guard type.hasPrefix(Self.typePrefix) else { return nil }
        self.init(rawValue: String(type.dropFirst(Self.typePrefix.count)))
    }

    public var title: String {
        switch self {
        case .resume: "Continue"
        case .randomMix: "Random Mix"
        case .myCuts: "Mix My Cuts"
        case .search: "Search"
        }
    }

    /// The actions to offer, in menu order, given what's in the queue.
    public static func available(current: Song?) -> [HomeScreenAction] {
        current == nil ? [.randomMix, .myCuts, .search] : allCases
    }

    /// Under Continue: what it continues, e.g. "Paranoid Android · Radiohead",
    /// or a station's name.
    public static func resumeSubtitle(for song: Song) -> String {
        guard !song.isLive, let artist = song.artist, !artist.isEmpty else { return song.title }
        return "\(song.title) · \(artist)"
    }
}
