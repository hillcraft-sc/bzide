import NavidromeCore
import SwiftUI

/// The Tapestry visualizer: a loom weaving the song into cloth, one row every
/// half second from the top down. Each frequency band is a thread (bass on the
/// left); the louder it was, the thicker and brighter it's woven, so the
/// finished cloth shows the whole song's shape. Rows played before the
/// visualizer opened are bare threads; below the loom, the warp waits.
struct TapestryView: View {
    let engine: PlaybackEngine
    let feed: SpectrumFeed
    let date: Date
    /// One color per thread, bass first.
    let colors: [Color]
    let state: TapestryState

    /// Opacity for each step of loudness, so the cloth is drawn in a few fills.
    private static let shades: [Double] = [0.3, 0.5, 0.75, 1]

    var body: some View {
        let tapestry = state.update(engine: engine, feed: feed, at: date)
        Canvas { context, size in
            let layout = TapestryLayout(size: size, duration: engine.duration ?? 240, rowCount: tapestry.rows.count)
            drawWarp(in: &context, layout: layout)
            drawCloth(tapestry, in: &context, layout: layout)
            drawLoom(at: tapestry.songTime, in: &context, layout: layout)
        }
    }

    // MARK: - Drawing

    /// The bare vertical threads the cloth is woven on, top to bottom.
    private func drawWarp(in context: inout GraphicsContext, layout: TapestryLayout) {
        var warp = Path()
        for thread in 0..<TapestryRecorder.threadCount {
            let x = layout.threadCenter(thread)
            warp.move(to: CGPoint(x: x, y: 0))
            warp.addLine(to: CGPoint(x: x, y: layout.size.height))
        }
        context.stroke(warp, with: .color(.white.opacity(0.12)), lineWidth: 1)
    }

    /// Each woven row as a short piece of each thread, as wide and bright as
    /// the band was loud. Pieces are gathered by thread and shade so the whole
    /// cloth takes a few dozen fills, not thousands.
    private func drawCloth(_ tapestry: TapestryRecorder, in context: inout GraphicsContext, layout: TapestryLayout) {
        guard !colors.isEmpty, !tapestry.rows.isEmpty else { return }
        let threadCount = TapestryRecorder.threadCount
        var pieces = [[Path]](repeating: [Path](repeating: Path(), count: Self.shades.count), count: threadCount)
        var unheard = Path()
        // A touch taller than a row, so neighboring rows meet without seams.
        let height = layout.rowHeight + 0.5

        for (index, row) in tapestry.rows.enumerated() {
            let top = CGFloat(index) * layout.rowHeight
            guard let row else {
                for thread in 0..<threadCount {
                    unheard.addRect(layout.piece(thread: thread, top: top, height: height, level: 0))
                }
                continue
            }
            for (thread, level) in row.enumerated() where thread < threadCount {
                let shade = min(Int(level * Float(Self.shades.count)), Self.shades.count - 1)
                pieces[thread][shade].addRect(layout.piece(thread: thread, top: top, height: height, level: level))
            }
        }
        context.fill(unheard, with: .color(.white.opacity(0.25)))
        for thread in 0..<threadCount {
            let color = colors[thread * colors.count / threadCount]
            for (shade, path) in pieces[thread].enumerated() {
                context.fill(path, with: .color(color.opacity(Self.shades[shade])))
            }
        }
        // Faint crosswise lines over the woven part, for the weave's texture.
        let wovenHeight = min(CGFloat(tapestry.rows.count) * layout.rowHeight, layout.size.height)
        var weft = Path()
        var y: CGFloat = 2
        while y < wovenHeight {
            weft.move(to: CGPoint(x: 0, y: y))
            weft.addLine(to: CGPoint(x: layout.size.width, y: y))
            y += 3
        }
        context.stroke(weft, with: .color(.black.opacity(0.2)), lineWidth: 1)
    }

    /// A steel beam across the cloth at the row being woven, with the shuttle
    /// crossing once per row and drawing its thread behind it.
    private func drawLoom(at songTime: TimeInterval, in context: inout GraphicsContext, layout: TapestryLayout) {
        let rows = songTime * Double(TapestryRecorder.rowsPerSecond)
        let y = min(CGFloat(rows) * layout.rowHeight, layout.size.height)
        // Left to right on even rows, back on odd ones.
        let along = CGFloat(rows - rows.rounded(.down))
        let goingRight = Int(rows).isMultiple(of: 2)
        let x = layout.size.width * (goingRight ? along : 1 - along)

        var weft = Path()
        weft.move(to: CGPoint(x: goingRight ? 0 : layout.size.width, y: y))
        weft.addLine(to: CGPoint(x: x, y: y))
        context.stroke(weft, with: .color(.white.opacity(0.7)), lineWidth: 1.5)

        let beam = CGRect(x: -6, y: y + 3, width: layout.size.width + 12, height: 7)
        let steel = Gradient(colors: [Color(white: 0.9), Color(white: 0.55), Color(white: 0.35)])
        context.fill(Path(roundedRect: beam, cornerRadius: 3.5), with: .linearGradient(
            steel, startPoint: CGPoint(x: 0, y: beam.minY), endPoint: CGPoint(x: 0, y: beam.maxY)
        ))

        let shuttle = CGRect(x: x - 16, y: y - 4, width: 32, height: 8)
        context.fill(Path(roundedRect: shuttle, cornerRadius: 4), with: .linearGradient(
            Gradient(colors: [Color(white: 0.95), Color(white: 0.6)]),
            startPoint: CGPoint(x: 0, y: shuttle.minY), endPoint: CGPoint(x: 0, y: shuttle.maxY)
        ))
    }
}

/// Where the cloth's threads and rows sit in the space given.
struct TapestryLayout {
    let size: CGSize
    /// The whole song's rows fit the height, so the cloth is finished at the end.
    let rowHeight: CGFloat

    init(size: CGSize, duration: TimeInterval, rowCount: Int) {
        self.size = size
        let songRows = Int((max(duration, 1) * Double(TapestryRecorder.rowsPerSecond)).rounded(.up))
        // A song that runs past its stated length squeezes up to keep fitting.
        rowHeight = size.height / CGFloat(max(songRows, rowCount, 1))
    }

    private var threadWidth: CGFloat { size.width / CGFloat(TapestryRecorder.threadCount) }

    func threadCenter(_ thread: Int) -> CGFloat {
        (CGFloat(thread) + 0.5) * threadWidth
    }

    /// One row's piece of a thread: a third of its width when silent, nearly
    /// all of it when loudest (a sliver of gap keeps the threads apart).
    func piece(thread: Int, top: CGFloat, height: CGFloat, level: Float) -> CGRect {
        let width = threadWidth * (0.33 + 0.6 * CGFloat(min(max(level, 0), 1)))
        return CGRect(x: threadCenter(thread) - width / 2, y: top, width: width, height: height)
    }
}

/// Keeps the recorder between frames. A class so the drawing can advance it
/// each frame without changing view state mid-update.
@MainActor
final class TapestryState {
    private var recorder = TapestryRecorder()
    private var lastFrame: Date?

    func update(engine: PlaybackEngine, feed: SpectrumFeed, at date: Date) -> TapestryRecorder {
        let elapsed = lastFrame.map { min(date.timeIntervalSince($0), 0.1) } ?? 0
        lastFrame = date
        recorder.update(
            entryID: engine.queue.current?.id,
            position: engine.position,
            isPlaying: engine.status == .playing,
            levels: feed.levels,
            elapsed: elapsed
        )
        return recorder
    }
}
