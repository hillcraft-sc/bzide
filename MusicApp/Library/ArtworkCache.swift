import NavidromeCore
import UIKit

/// Cover art for the screens and the lock screen: memory first, then disk
/// (`CoverArtStore`), then the server. Keyed by cover art id and size, not URL:
/// every URL carries a fresh auth salt.
///
/// Also keeps covers for downloaded music on disk, so it has artwork offline.
///
/// A radio station's logo has its own kind of id (`StationLogo`): it's fetched
/// from the station's website, not the server, and scaled down here.
final class ArtworkCache: ArtworkPinning {
    private let client: SubsonicClient
    private let store: CoverArtStore
    /// Decoded images, by their memory (width × height × 4 bytes), so a
    /// long scroll can't grow it without bound; iOS also empties it under
    /// memory pressure.
    private let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 80 * 1024 * 1024
        return cache
    }()
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
        if let image { images.setObject(image, forKey: key, cost: Self.cost(of: image)) }
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
            return prepared(image)
        }
        if let data = await fetch(id, pixels: pixels, client: client), let image = UIImage(data: data) {
            store.save(data, id: id, pixels: pixels)
            return prepared(image)
        }
        return store.anyImage(id: id).flatMap(UIImage.init(data:)).map(prepared)
    }

    /// Decoded here, off the main thread, rather than on it the first time
    /// it's drawn, which would hitch scrolling.
    nonisolated private static func prepared(_ image: UIImage) -> UIImage {
        image.preparingForDisplay() ?? image
    }

    nonisolated private static func cost(of image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale) * 4
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
        if let logo = StationLogo.url(fromCoverArtID: id) { return await fetchLogo(logo, pixels: pixels) }
        guard let url = try? client.coverArtURL(id: id, size: pixels),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              response.mimeType?.hasPrefix("image/") == true
        else { return nil }
        return data
    }

    /// A logo as an image no bigger than asked for. Sites send favicons of
    /// every size and type, often without an image type, so it's checked by
    /// decoding it.
    @concurrent
    private static func fetchLogo(_ url: URL, pixels: Int) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data)
        else { return nil }
        let longest = max(image.size.width * image.scale, image.size.height * image.scale)
        guard longest > CGFloat(pixels), longest > 0 else { return data }
        let scale = CGFloat(pixels) / longest
        let size = CGSize(width: image.size.width * image.scale * scale, height: image.size.height * image.scale * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.pngData()
    }
}
