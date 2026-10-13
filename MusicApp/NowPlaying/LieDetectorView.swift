import NavidromeCore
import SwiftUI

/// The Lie Detector visualizer: a polygraph. Chart paper fills the screen,
/// running past four steel needles that swing with the music
/// (`PolygraphChart` moves them): bass, mid-range and treble as wandering
/// lines, loudness as dense hatching. In portrait the needles reach down from
/// above the top edge and the paper runs down; sideways they reach in from
/// the left and it runs right, away from the controls panel. The controls
/// float over the paper in dark ink.
struct LieDetectorView: View {
    let engine: PlaybackEngine
    let feed: SpectrumFeed
    let levels: [Float]
    let date: Date
    /// One ink per pen.
    let colors: [Color]
    /// The space between the menu and the controls, where the pens' lanes go.
    let insets: EdgeInsets
    let landscape: Bool
    let state: LieDetectorState

    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    private static let gridLine = Color(red: 0.62, green: 0.7, blue: 0.78)
    /// Points of paper per second.
    private static let paperSpeed: CGFloat = 70
    private static let gridSpacing: CGFloat = 16

    var body: some View {
        let chart = state.update(engine: engine, feed: feed, levels: levels, at: date)
        Canvas { context, size in
            let layout = PolygraphLayout(size: size, insets: insets, landscape: landscape)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.paper))
            drawGrid(travel: chart.travel, in: &context, layout: layout)
            drawInk(chart, in: &context, layout: layout)
            drawNeedles(chart, in: &context, layout: layout)
        }
        .ignoresSafeArea()
    }

    /// The colors darkened a little, so pale ones still read on white paper.
    private var inks: [Color] {
        let chosen = colors.count >= 4 ? colors : Array(repeating: colors.first ?? .blue, count: 4)
        return chosen.map { $0.mix(with: .black, by: 0.3) }
    }

    // MARK: - Drawing

    /// Fine lines over the whole sheet, every fifth darker. The ones across
    /// the paper's run move with it, so the grid and ink travel together.
    private func drawGrid(travel: TimeInterval, in context: inout GraphicsContext, layout: PolygraphLayout) {
        let spacing = Self.gridSpacing
        let moved = CGFloat(travel) * Self.paperSpeed
        var fine = Path()
        var bold = Path()
        // Lines across the run: placed by their distance from the needles,
        // from before the tips (behind the needles) to the far edge.
        let shift = moved.truncatingRemainder(dividingBy: spacing)
        let passed = Int((moved / spacing).rounded(.down))
        var index = -Int((layout.behindTips / spacing).rounded(.up)) - 1
        while CGFloat(index) * spacing + shift < layout.runLength {
            let along = CGFloat(index) * spacing + shift
            let (a, b) = layout.lineAcross(along: along)
            // Numbered as the paper moves, so the darker lines travel with it.
            if (index - passed).isMultiple(of: 5) {
                bold.move(to: a)
                bold.addLine(to: b)
            } else {
                fine.move(to: a)
                fine.addLine(to: b)
            }
            index += 1
        }
        // Lines along the run, fixed, across the whole sheet.
        var across: CGFloat = 0
        var count = 0
        while across < layout.sheetWidth {
            let (a, b) = layout.lineAlong(at: across)
            if count.isMultiple(of: 5) {
                bold.move(to: a)
                bold.addLine(to: b)
            } else {
                fine.move(to: a)
                fine.addLine(to: b)
            }
            across += spacing
            count += 1
        }
        context.stroke(fine, with: .color(Self.gridLine.opacity(0.3)), lineWidth: 0.5)
        context.stroke(bold, with: .color(Self.gridLine.opacity(0.6)), lineWidth: 1)
    }

    /// Each pen's trace, newest at its needle, carried away by the paper.
    private func drawInk(_ chart: PolygraphChart, in context: inout GraphicsContext, layout: PolygraphLayout) {
        let samples = chart.samples
        guard !samples.isEmpty else { return }
        let gap = Self.paperSpeed / CGFloat(PolygraphChart.samplesPerSecond)
        let visible = min(samples.count, Int(layout.runLength / gap) + 2)
        for pen in 0..<PolygraphChart.penCount {
            var path = Path()
            // Hatching uses every third point, so its strokes stand apart.
            let stride = pen == 3 ? 3 : 1
            for back in Swift.stride(from: 0, to: visible, by: stride) {
                let sample = samples[samples.count - 1 - back]
                var offset = CGFloat(sample[pen])
                if pen == 3 {
                    // Hatching: a stroke to each side in turn, as tall as it's loud.
                    offset *= (back / stride).isMultiple(of: 2) ? 1 : -1
                }
                let point = layout.point(along: CGFloat(back) * gap, across: layout.laneCenter(pen) + offset * layout.laneReach)
                back == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            context.stroke(path, with: .color(inks[pen]), style: StrokeStyle(lineWidth: pen == 3 ? 1 : 1.8, lineJoin: .round))
        }
    }

    /// Steel needles reaching in from pivots past the edge to their tips.
    private func drawNeedles(_ chart: PolygraphChart, in context: inout GraphicsContext, layout: PolygraphLayout) {
        for pen in 0..<PolygraphChart.penCount {
            let side: Double = chart.samples.count.isMultiple(of: 2) ? 1 : -1
            let value = pen == 3 ? side * chart.pens[pen] : chart.pens[pen]
            let tip = layout.point(along: 0, across: layout.laneCenter(pen) + CGFloat(value) * layout.laneReach)
            let pivot = layout.pivot(pen)
            var needle = Path()
            needle.move(to: pivot)
            needle.addLine(to: tip)
            // Its shadow on the paper, then the steel.
            var shadow = context
            shadow.translateBy(x: 3, y: 4)
            shadow.addFilter(.blur(radius: 2))
            shadow.stroke(needle, with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            context.stroke(needle, with: .color(Color(white: 0.35)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            context.stroke(needle, with: .linearGradient(
                Gradient(colors: [Color(white: 0.95), Color(white: 0.6)]), startPoint: pivot, endPoint: tip
            ), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            // The pen's tip, in its ink.
            context.fill(Path(ellipseIn: CGRect(x: tip.x - 3, y: tip.y - 3, width: 6, height: 6)), with: .color(inks[pen]))
        }
    }
}

/// Where the needles and lanes sit on the full-screen sheet. Drawing works in
/// paper terms (`along`: distance past the needle tips as the paper runs
/// away; `across`: from the first lane's side), and `point` turns those into
/// the screen for each orientation.
struct PolygraphLayout {
    let size: CGSize
    let landscape: Bool
    /// Where the tips sit along the run, from the screen's edge.
    let tipLine: CGFloat
    /// Where the lanes start and how wide they are together.
    let lanesStart: CGFloat
    let lanesWidth: CGFloat

    init(size: CGSize, insets: EdgeInsets, landscape: Bool) {
        self.size = size
        self.landscape = landscape
        if landscape {
            // Needles in from the left; lanes top to bottom between the top bar and the bottom.
            tipLine = insets.leading + 70
            lanesStart = insets.top
            lanesWidth = size.height - insets.top - insets.bottom
        } else {
            // Needles down from the top, the tips just below the menu; lanes across the width.
            tipLine = insets.top + 20
            lanesStart = insets.leading + 8
            lanesWidth = size.width - insets.leading - insets.trailing - 16
        }
    }

    /// How far the paper runs past the tips before leaving the screen.
    var runLength: CGFloat { (landscape ? size.width : size.height) - tipLine }
    /// The paper between the edge the needles come from and the tips.
    var behindTips: CGFloat { tipLine }
    /// The sheet's size across the run.
    var sheetWidth: CGFloat { landscape ? size.height : size.width }

    private var laneWidth: CGFloat { lanesWidth / CGFloat(PolygraphChart.penCount) }
    func laneCenter(_ pen: Int) -> CGFloat { (CGFloat(pen) + 0.5) * laneWidth }
    /// How far a pen swings either way: most of its lane.
    var laneReach: CGFloat { laneWidth * 0.42 }

    func point(along: CGFloat, across: CGFloat) -> CGPoint {
        landscape
            ? CGPoint(x: tipLine + along, y: lanesStart + across)
            : CGPoint(x: lanesStart + across, y: tipLine + along)
    }

    /// A grid line across the whole sheet at `along` past the tips.
    func lineAcross(along: CGFloat) -> (CGPoint, CGPoint) {
        landscape
            ? (CGPoint(x: tipLine + along, y: 0), CGPoint(x: tipLine + along, y: size.height))
            : (CGPoint(x: 0, y: tipLine + along), CGPoint(x: size.width, y: tipLine + along))
    }

    /// A grid line along the whole run, `across` from the sheet's side.
    func lineAlong(at across: CGFloat) -> (CGPoint, CGPoint) {
        landscape
            ? (CGPoint(x: 0, y: across), CGPoint(x: size.width, y: across))
            : (CGPoint(x: across, y: 0), CGPoint(x: across, y: size.height))
    }

    /// Each needle's pivot, past the screen's edge and a little to one side
    /// of its lane, so the needle reaches in at an angle.
    func pivot(_ pen: Int) -> CGPoint {
        let across = lanesStart + laneCenter(pen) + laneWidth * 0.3
        return landscape ? CGPoint(x: -30, y: across) : CGPoint(x: across, y: -30)
    }
}

/// Keeps the chart between frames. A class so the drawing can advance it each
/// frame without changing view state mid-update.
@MainActor
final class LieDetectorState {
    private var chart = PolygraphChart()
    private var lastFrame: Date?

    func update(engine: PlaybackEngine, feed: SpectrumFeed, levels: [Float], at date: Date) -> PolygraphChart {
        let elapsed = lastFrame.map { date.timeIntervalSince($0) } ?? 0
        lastFrame = date
        let loudness = levels.isEmpty ? 0 : levels.reduce(0, +) / Float(levels.count)
        chart.update(energy: feed.energy, loudness: loudness, beat: feed.beat, isPlaying: engine.status == .playing, elapsed: elapsed)
        return chart
    }
}
