import NavidromeCore
import SwiftUI

/// The Living Cover visualizer: the album cover cut into a grid of tiles that
/// move with the music (`LivingCover` works out how), over a blurred, darkened
/// copy of itself. Each album looks like itself. Without a cover, the tiles are
/// drawn in the visualizer's colors.
struct LivingCoverView: View {
    let library: Library?
    let coverArtID: String?
    let levels: [Float]
    let energy: SpectrumEnergy
    let beat: Float
    /// Edge sparkle colors, one per tile row: the accent, or the multicolor/custom sweep.
    let colors: [Color]
    /// Where the tiles may go, inside the screen; the blurred cover fills it all.
    let insets: EdgeInsets

    @State private var cover: UIImage?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - insets.leading - insets.trailing
            let height = geometry.size.height - insets.top - insets.bottom
            let side = max(min(width, height), 0) * 0.78
            let center = CGPoint(x: insets.leading + width / 2, y: insets.top + height / 2)
            ZStack {
                if let cover {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 40)
                        .overlay(.black.opacity(0.55))
                        .clipped()
                }
                Canvas { context, _ in
                    drawTiles(in: &context, side: side, center: center)
                }
            }
        }
        .ignoresSafeArea()
        .task(id: coverArtID) {
            cover = nil
            guard let library, let coverArtID else { return }
            let loaded = await library.artwork.image(for: coverArtID, pixels: 900)
            // The song changed while it loaded: this cover is for the old one.
            guard !Task.isCancelled else { return }
            cover = loaded
        }
    }

    private func drawTiles(in context: inout GraphicsContext, side: CGFloat, center: CGPoint) {
        let grid = LivingCover.gridSize
        let tile = side / CGFloat(grid)
        let origin = CGPoint(x: center.x - side / 2, y: center.y - side / 2)
        let image = cover.map { context.resolve(Image(uiImage: $0)) }
        let coverRect = CGRect(origin: origin, size: CGSize(width: side, height: side))

        for row in 0..<grid {
            for column in 0..<grid {
                let motion = LivingCover.motion(row: row, column: column, levels: levels, energy: energy, beat: beat)
                let home = CGRect(x: origin.x + CGFloat(column) * tile, y: origin.y + CGFloat(row) * tile, width: tile, height: tile)
                let middle = CGPoint(x: home.midX + CGFloat(motion.dx) * tile, y: home.midY + CGFloat(motion.dy) * tile)
                let color = colors.isEmpty ? Color.white : colors[row * colors.count / grid]

                context.drawLayer { layer in
                    // Move to the tile's new place, then turn and grow it about its middle.
                    layer.translateBy(x: middle.x, y: middle.y)
                    layer.rotate(by: .radians(motion.rotation))
                    layer.scaleBy(x: motion.scale, y: motion.scale)
                    let local = CGRect(x: -tile / 2, y: -tile / 2, width: tile, height: tile)
                    let shape = Path(roundedRect: local.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2)
                    if let image {
                        // The whole cover, placed so this tile's part lands in the tile.
                        var clipped = layer
                        clipped.clip(to: shape)
                        clipped.draw(image, in: coverRect.offsetBy(dx: -home.midX, dy: -home.midY))
                    } else {
                        layer.fill(shape, with: .color(color.opacity(0.35 + 0.65 * Double(motion.scale - 1) / 0.17)))
                    }
                    if motion.sparkle > 0.02 {
                        layer.stroke(shape, with: .color(color.opacity(motion.sparkle)), lineWidth: 1.5)
                    }
                }
            }
        }
    }
}
