import Foundation

/// What to star or unstar. Subsonic uses a different parameter name for each kind.
public enum StarTarget: Sendable, Equatable {
    case song(id: String)
    case album(id: String)
    case artist(id: String)

    var queryItem: URLQueryItem {
        switch self {
        case .song(let id): URLQueryItem(name: "id", value: id)
        case .album(let id): URLQueryItem(name: "albumId", value: id)
        case .artist(let id): URLQueryItem(name: "artistId", value: id)
        }
    }
}
