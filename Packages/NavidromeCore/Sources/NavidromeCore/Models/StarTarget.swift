import Foundation

/// What to favourite (star) or rate. Subsonic's star call uses a different
/// parameter name for each kind; its rating call takes the plain id.
public enum StarTarget: Sendable, Hashable {
    case song(id: String)
    case album(id: String)
    case artist(id: String)

    public var id: String {
        switch self {
        case .song(let id), .album(let id), .artist(let id): id
        }
    }

    var queryItem: URLQueryItem {
        switch self {
        case .song(let id): URLQueryItem(name: "id", value: id)
        case .album(let id): URLQueryItem(name: "albumId", value: id)
        case .artist(let id): URLQueryItem(name: "artistId", value: id)
        }
    }
}
