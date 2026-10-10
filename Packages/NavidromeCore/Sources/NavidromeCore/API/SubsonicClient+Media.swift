import Foundation

// Media is loaded directly by the player or image loader, so these return signed
// URLs instead of fetching anything. The URLs contain a valid token: don't log or
// persist them. Build a fresh one when needed instead.

extension SubsonicClient {
    /// `maxBitRate` (kbps) and `format` (e.g. "mp3") ask the server to transcode.
    public func streamURL(songID: String, maxBitRate: Int? = nil, format: String? = nil) throws(SubsonicError) -> URL {
        var parameters: [URLQueryItem] = [.init(name: "id", value: songID)]
        if let maxBitRate { parameters.append(.init(name: "maxBitRate", value: String(maxBitRate))) }
        if let format { parameters.append(.init(name: "format", value: format)) }
        return try mediaURL("stream", parameters: parameters)
    }

    /// The original file, never transcoded. Used for offline downloads.
    public func downloadURL(songID: String) throws(SubsonicError) -> URL {
        try mediaURL("download", parameters: [.init(name: "id", value: songID)])
    }

    /// `size` is the longest edge in pixels; omit it for the original image.
    public func coverArtURL(id: String, size: Int? = nil) throws(SubsonicError) -> URL {
        var parameters: [URLQueryItem] = [.init(name: "id", value: id)]
        if let size { parameters.append(.init(name: "size", value: String(size))) }
        return try mediaURL("getCoverArt", parameters: parameters)
    }
}
