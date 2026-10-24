import Foundation

/// Which albums `getAlbumList2` returns.
public enum AlbumListType: Sendable, Equatable {
    case random
    case newest
    case frequent
    case recent
    case starred
    /// The highest rated (the user's ratings).
    case highest
    case alphabeticalByName
    case alphabeticalByArtist
    case byYear(from: Int, to: Int)
    case byGenre(String)

    var queryItems: [URLQueryItem] {
        switch self {
        case .random: [.init(name: "type", value: "random")]
        case .newest: [.init(name: "type", value: "newest")]
        case .frequent: [.init(name: "type", value: "frequent")]
        case .recent: [.init(name: "type", value: "recent")]
        case .starred: [.init(name: "type", value: "starred")]
        case .highest: [.init(name: "type", value: "highest")]
        case .alphabeticalByName: [.init(name: "type", value: "alphabeticalByName")]
        case .alphabeticalByArtist: [.init(name: "type", value: "alphabeticalByArtist")]
        case .byYear(let from, let to):
            [.init(name: "type", value: "byYear"), .init(name: "fromYear", value: String(from)), .init(name: "toYear", value: String(to))]
        case .byGenre(let genre):
            [.init(name: "type", value: "byGenre"), .init(name: "genre", value: genre)]
        }
    }
}
