import Foundation
import NavidromeCore

/// The server calls Siri's entity queries need: by id, and by name.
struct SiriLookup: Sendable {
    var artist: @Sendable (_ id: String) async throws(SubsonicError) -> Artist
    var album: @Sendable (_ id: String) async throws(SubsonicError) -> Album
    var playlist: @Sendable (_ id: String) async throws(SubsonicError) -> Playlist
    var song: @Sendable (_ id: String) async throws(SubsonicError) -> Song
    var playlists: @Sendable () async throws(SubsonicError) -> [Playlist]
    var search: @Sendable (_ query: String) async throws(SubsonicError) -> SearchResult
}

/// Siri runs intents and queries in the app's process. They reach the
/// signed-in library through the shared `AppModel`; signed out, there's
/// nothing to find or play.
enum SiriAccess {
    @MainActor
    static func library() throws -> Library {
        guard let library = AppModel.shared.library else { throw SiriError.signedOut }
        return library
    }

    static func lookup() async throws -> SiriLookup {
        try await MainActor.run { try library().siriLookup }
    }

    /// Looks up each id, skipping any the server no longer has rather than
    /// failing them all.
    static func each<Item: Sendable>(
        _ ids: [String], _ fetch: @escaping @Sendable (String) async throws(SubsonicError) -> Item
    ) async -> [Item] {
        var items: [Item] = []
        for id in ids {
            if let item = try? await fetch(id) { items.append(item) }
        }
        return items
    }
}

enum SiriError: Error, CustomLocalizedStringResourceConvertible {
    case signedOut
    case notFound
    case nothingPlaying
    case radio
    case server(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut: "Sign in to your Navidrome server in Bzide first."
        case .notFound: "Bzide couldn't find that in your library."
        case .nothingPlaying: "Nothing is playing in Bzide."
        case .radio: "A radio station can't be a favorite."
        case .server(let message): "\(message)"
        }
    }
}
