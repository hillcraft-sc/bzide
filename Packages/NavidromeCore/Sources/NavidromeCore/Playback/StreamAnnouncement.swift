import Foundation

/// What a live stream says it's playing, as one line. Shoutcast and Icecast
/// send "Artist - Title" in one field; HLS streams (ID3 tags in each chunk)
/// usually send the title and artist separately, and these are joined the
/// same way, so everything after (On Air, Song Info, the Wishlist)
/// reads both alike.
public enum StreamAnnouncement {
    /// "Artist - Title"; just the title when there's no artist or the title
    /// names it already, and just the artist when there's no title.
    public static func combined(title: String?, artist: String?) -> String? {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if artist.isEmpty { return title.isEmpty ? nil : title }
        if title.isEmpty { return artist }
        if title.localizedCaseInsensitiveContains(artist) { return title }
        return "\(artist) - \(title)"
    }
}
