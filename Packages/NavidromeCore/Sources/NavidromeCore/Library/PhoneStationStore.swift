import Foundation

/// Keeps the stations saved on this iPhone (My Stations) in a file. They
/// belong to the signed-in account like the rest of its data (see
/// `AccountScope`). Without a file (in tests) they last as long as the store.
public struct PhoneStationStore: Sendable {
    nonisolated public static let fileName = "RadioStations.json"

    private let fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    /// The saved stations; none if there's no file or it can't be read.
    public func load() -> [RadioStation] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode(LossyList<RadioStation>.self, from: data).items) ?? []
    }

    public func save(_ stations: [RadioStation]) {
        guard let fileURL, let data = try? JSONEncoder().encode(stations) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
