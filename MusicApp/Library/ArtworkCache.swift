import NavidromeCore
import UIKit

/// Cover art in memory, keyed by cover art id and size. Not by URL: every URL
/// carries a fresh auth salt, so no two URLs for the same image are alike.
/// Saving to disk comes with offline support (M4).
final class ArtworkCache {
    private let client: SubsonicClient
    private let images = NSCache<NSString, UIImage>()
    /// One download per image, however many rows ask for it at once.
    private var inFlight: [NSString: Task<UIImage?, Never>] = [:]

    /// Artwork URLs contain a reusable auth token, so responses must not land
    /// in the shared on-disk URL cache.
    private static let session = URLSession(configuration: .ephemeral)

    init(client: SubsonicClient) {
        self.client = client
    }

    /// `pixels` is the longest side wanted; the server scales the image down.
    func image(for coverArtID: String, pixels: Int) async -> UIImage? {
        let key = "\(coverArtID)@\(pixels)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        if let running = inFlight[key] { return await running.value }

        let task = Task { [client] in await Self.download(client: client, coverArtID: coverArtID, pixels: pixels) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { images.setObject(image, forKey: key) }
        return image
    }

    nonisolated private static func download(client: SubsonicClient, coverArtID: String, pixels: Int) async -> UIImage? {
        guard let url = try? client.coverArtURL(id: coverArtID, size: pixels),
              let (data, _) = try? await session.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}
