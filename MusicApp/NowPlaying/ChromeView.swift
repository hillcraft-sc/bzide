import NavidromeCore
import SwiftUI

/// The Chrome visualizer: a liquid-metal blob, like the steel of the app
/// icon, reflecting the album cover (Chrome.metal draws it). Each frequency
/// band pushes out a bulge at its own angle, bass at the bottom and treble at
/// the top (`ChromeBlob` shapes it), beats swell it, ripple its surface and
/// splash droplets into the free space that melt back in (`ChromeSplash`),
/// and the edges catch the visualizer's colors. Without a cover it reflects
/// plain brushed steel.
struct ChromeView: View {
    let library: Library?
    let coverArtID: String?
    let levels: [Float]
    let beat: Float
    let date: Date
    /// Four colors for the light on its edges.
    let colors: [Color]
    let state: ChromeState

    @State private var cover: Image?

    var body: some View {
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
        let radii = ChromeBlob.radii(levels: levels, beat: beat, time: time)
        let rims = colors.count >= 4 ? colors : Array(repeating: colors.first ?? .white, count: 4)
        GeometryReader { geometry in
            // Room for the biggest bulges inside the space given.
            let radius = min(geometry.size.width, geometry.size.height) * 0.34
            let drops = state.update(
                beat: beat, at: date,
                room: (x: geometry.size.width / 2 / radius, y: geometry.size.height / 2 / radius)
            )
            Rectangle()
                .colorEffect(ShaderLibrary.chrome(
                    .float2(geometry.size), .float(radius),
                    .floatArray(radii),
                    .floatArray(drops),
                    .float(Float(time)), .float(beat),
                    .color(rims[0]), .color(rims[1]), .color(rims[2]), .color(rims[3]),
                    .image(cover ?? Self.brushedSteel)
                ))
        }
        .task(id: coverArtID) {
            cover = nil
            guard let library, let coverArtID else { return }
            let loaded = await library.artwork.image(for: coverArtID, pixels: 600)
            // The song changed while it loaded: this cover is for the old one.
            guard !Task.isCancelled, let loaded else { return }
            cover = Image(uiImage: loaded)
        }
    }

    /// What it reflects without a cover: light above, dark below, like a
    /// polished ball under a studio light.
    private static let brushedSteel: Image = {
        let size = CGSize(width: 64, height: 64)
        let rendered = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor(white: 0.95, alpha: 1), UIColor(white: 0.55, alpha: 1), UIColor(white: 0.15, alpha: 1)]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: [0, 0.5, 1]
            )
            if let gradient {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
        return Image(uiImage: rendered)
    }()
}

/// Keeps the droplets between frames. A class so the drawing can advance them
/// each frame without changing view state mid-update.
@MainActor
final class ChromeState {
    private var splash = ChromeSplash()
    private var lastFrame: Date?

    /// The droplets for the shader: x, y and size for each of a fixed number,
    /// empty ones with size 0.
    func update(beat: Float, at date: Date, room: (x: Double, y: Double)) -> [Float] {
        let elapsed = lastFrame.map { date.timeIntervalSince($0) } ?? 0
        lastFrame = date
        splash.update(beat: beat, elapsed: elapsed, room: room)
        var floats = [Float](repeating: 0, count: ChromeSplash.maxDroplets * 3)
        for (index, droplet) in splash.droplets.enumerated() {
            floats[index * 3] = Float(droplet.x)
            floats[index * 3 + 1] = Float(droplet.y)
            floats[index * 3 + 2] = Float(droplet.size)
        }
        return floats
    }
}
