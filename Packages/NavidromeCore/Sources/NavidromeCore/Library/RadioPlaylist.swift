import Foundation

/// Finds the stream behind a station's address. Many stations publish a
/// `.pls` or `.m3u` file listing their streams rather than the stream itself;
/// the player can't play those, so the first stream in the file is used. HLS
/// (`.m3u8`) and anything else go to the player as they are.
public enum RadioPlaylist {
    public enum Kind: Sendable, Equatable {
        case pls, m3u
    }

    public enum ResolveError: Error, Equatable, LocalizedError {
        /// A plain-http playlist file: iOS only allows plain http for audio.
        case insecurePlaylist
        case noStreamInPlaylist
        case unreachable(String)

        public var errorDescription: String? {
            switch self {
            case .insecurePlaylist:
                "This station's address is a playlist file on an insecure (http) connection, which iOS doesn't allow. Use the station's direct stream address in Navidrome instead."
            case .noStreamInPlaylist:
                "This station's playlist file doesn't list a stream."
            case .unreachable(let message):
                "Couldn't read the station's playlist file (\(message))."
            }
        }
    }

    public typealias Fetch = @Sendable (URL) async throws -> Data

    static func kind(of url: URL) -> Kind? {
        switch url.pathExtension.lowercased() {
        case "pls": .pls
        case "m3u": .m3u
        default: nil
        }
    }

    /// The address to give the player.
    public static func streamURL(for station: RadioStation, fetch: Fetch) async throws(ResolveError) -> URL {
        let address = station.streamURL
        guard let kind = kind(of: address) else { return address }
        guard address.scheme?.lowercased() == "https" else { throw .insecurePlaylist }
        let data: Data
        do {
            data = try await fetch(address)
        } catch {
            throw .unreachable(error.localizedDescription)
        }
        guard let stream = firstStream(in: String(decoding: data, as: UTF8.self), kind: kind) else {
            throw .noStreamInPlaylist
        }
        return stream
    }

    /// `.pls`: `File1=…` lines, lowest number first. `.m3u`: the first line
    /// that isn't blank or a `#` comment.
    static func firstStream(in text: String, kind: Kind) -> URL? {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        switch kind {
        case .pls:
            let files = lines.compactMap { line -> (Int, URL)? in
                guard line.lowercased().hasPrefix("file"), let equals = line.firstIndex(of: "=") else { return nil }
                let number = Int(line[line.index(line.startIndex, offsetBy: 4)..<equals]) ?? Int.max
                return RadioStation.webURL(String(line[line.index(after: equals)...])).map { (number, $0) }
            }
            return files.min { $0.0 < $1.0 }?.1
        case .m3u:
            return lines.first { !$0.isEmpty && !$0.hasPrefix("#") }.flatMap(RadioStation.webURL)
        }
    }
}
