import Foundation

/// Reads a radio stream's response headers (`icy-name`, `icy-description`…)
/// for Station Info, then stops: the stream itself would never end. Asks the
/// station's server only, which is already being streamed from.
enum StreamHeaderReader {
    /// Its own session, keeping nothing.
    private static let session = URLSession(configuration: .ephemeral)

    static func headers(_ url: URL) async throws -> [String: String]? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        // Asks Shoutcast and Icecast servers to describe the station.
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        let (bytes, response) = try await session.bytes(for: request)
        bytes.task.cancel()
        guard let http = response as? HTTPURLResponse else { return nil }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return headers
    }
}
