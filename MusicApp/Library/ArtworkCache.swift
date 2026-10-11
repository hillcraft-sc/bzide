import NavidromeCore
import UIKit

/// Cover art for the screens and the lock screen: memory first, then disk
/// (`CoverArtStore`), then the server. Keyed by cover art id and size, not URL:
/// every URL carries a fresh auth salt.
///
/// Also keeps covers for downloaded music on disk, so it has artwork offline.
final class ArtworkCache: ArtworkPinning {
    private let client: SubsonicClient
    private let store: CoverArtStore
    private let images = NSCache<NSString, UIImage>()
    /// One load per image, however many rows ask for it at once.
    private var inFlight: [NSString: Task<UIImage?, Never>] = [:]
    /// Covers being fetched for pinning, so a second request doesn't fetch twice.
    private var pinning: Set<String> = []

    /// Pinned covers serve every size, so they're fetched big enough for Now Playing.
    private static let pinnedPixels = 900

    /// Artwork URLs contain a reusable auth token, so responses must not land
    /// in the shared on-disk URL cache.
    private static let session = URLSession(configuration: .ephemeral)

    init(client: SubsonicClient, store: CoverArtStore) {
        self.client = client
        self.store = store
    }

    /// `pixels` is the longest side wanted; the server scales the image down.
    func image(for coverArtID: String, pixels: Int) async -> UIImage? {
        let key = "\(coverArtID)@\(pixels)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        if let running = inFlight[key] { return await running.value }

        let task = Task { [client, store] in await Self.load(coverArtID, pixels: pixels, client: client, store: store) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { images.setObject(image, forKey: key) }
        return image
    }

    func keepOffline(coverArtIDs: Set<String>) {
        let wanted = coverArtIDs.subtracting(pinning)
        pinning.formUnion(wanted)
        Task { [client, store] in
            await Self.pin(wanted, unpinningAllBut: coverArtIDs, client: client, store: store)
            pinning.subtract(wanted)
        }
    }

    // MARK: - Off the main thread

    /// Disk, then server; if the server can't be reached, any size on disk.
    @concurrent
    private static func load(_ id: String, pixels: Int, client: SubsonicClient, store: CoverArtStore) async -> UIImage? {
        if let data = store.image(id: id, pixels: pixels), let image = UIImage(data: data) {
            return image
        }
        if let data = await fetch(id, pixels: pixels, client: client), let image = UIImage(data: data) {
            store.save(data, id: id, pixels: pixels)
            return image
        }
        return store.anyImage(id: id).flatMap(UIImage.init(data:))
    }

    @concurrent
    private static func pin(_ ids: Set<String>, unpinningAllBut keep: Set<String>, client: SubsonicClient, store: CoverArtStore) async {
        for id in store.pinnedIDs().subtracting(keep) {
            store.unpin(id: id)
        }
        // Not yet pinned: fetch. A failure is retried the next time downloads
        // change or the app launches.
        for id in ids.subtracting(store.pinnedIDs()) {
            if let data = await fetch(id, pixels: pinnedPixels, client: client), UIImage(data: data) != nil {
                store.pin(data, id: id)
            }
        }
    }

    @concurrent
    private static func fetch(_ id: String, pixels: Int, client: SubsonicClient) async -> Data? {
        guard let url = try? client.coverArtURL(id: id, size: pixels),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              response.mimeType?.hasPrefix("image/") == true
        else { return nil }
        return data
    }
}
