import NavidromeCore
import SwiftUI

/// The Groove visualizer: a record turning under a steel tonearm, its groove
/// cut as the song plays. Loud moments engrave a jagged wiggle, quiet ones a
/// smooth line, and the spiral runs from the edge to the label over the length
/// of the song, so the finished record shows the whole song's shape. The album
/// cover is the label. Moments played before the visualizer opened show as a
/// plain groove (they weren't heard); what's still to come is blank vinyl.
struct GrooveView: View {
    let engine: PlaybackEngine
    let library: Library?
    let feed: SpectrumFeed
    let date: Date
    /// Groove colors from the edge inward: one for Accent, several for Multicolor and Custom.
    let colors: [Color]
    let state: GrooveState

    var body: some View {
        let groove = state.update(engine: engine, feed: feed, at: date)
        GeometryReader { geometry in
            let layout = GrooveLayout(size: geometry.size)
            let duration = max(engine.duration ?? 240, 1)
            ZStack {
                Canvas { context, _ in
                    drawDisc(in: &context, layout: layout)
                    drawGroove(groove, duration: duration, in: &context, layout: layout)
                }
                if let library {
                    ArtworkView(library: library, coverArtID: engine.queue.current?.song.coverArtID, side: layout.labelRadius * 2)
                        .clipShape(.circle)
                        .overlay { Circle().fill(.black).frame(width: 6, height: 6) }
                        .rotationEffect(.radians(GrooveLayout.turnRate * groove.songTime))
                        .position(layout.center)
                }
                Canvas { context, _ in
                    drawTonearm(in: &context, layout: layout, groove: groove, duration: duration)
                }
            }
        }
    }

    // MARK: - Drawing

    private func drawDisc(in context: inout GraphicsContext, layout: GrooveLayout) {
        let disc = Path(ellipseIn: layout.circle(radius: layout.outerRadius))
        context.fill(disc, with: .color(Color(white: 0.07)))
        // Fine concentric rings, for the vinyl's sheen.
        var rings = Path()
        var radius = layout.labelRadius * 1.05
        while radius < layout.outerRadius * 0.99 {
            rings.addEllipse(in: layout.circle(radius: radius))
            radius += 2.5
        }
        context.stroke(rings, with: .color(.white.opacity(0.035)), lineWidth: 0.6)
        context.stroke(disc, with: .color(.white.opacity(0.12)), lineWidth: 1)
    }

    /// The groove so far, one point per recorded moment. Heard moments are
    /// engraved in the groove colors with a wiggle as big as the level; unheard
    /// ones are a plain gray line.
    private func drawGroove(_ groove: GrooveRecorder, duration: TimeInterval, in context: inout GraphicsContext, layout: GrooveLayout) {
        guard !groove.levels.isEmpty else { return }
        let pitch = layout.groovePitch(duration: duration)
        var heard = [Path](repeating: Path(), count: colors.count)
        var unheard = Path()
        var previous: (point: CGPoint, wasHeard: Bool, colorIndex: Int)?

        for (index, level) in groove.levels.enumerated() {
            let time = Double(index) / Double(GrooveRecorder.samplesPerSecond)
            // Squared, so loud moments cut deep and moderate ones much less;
            // at most a third of the gap, so neighboring turns don't cross.
            let depth = CGFloat(pow(level ?? 0, 2))
            let wiggle = depth * pitch * 0.33 * (index.isMultiple(of: 2) ? 1 : -1)
            let point = layout.groovePoint(time: time, now: groove.songTime, duration: duration, offset: wiggle)
            let isHeard = level != nil
            let progress = min(time / duration, 1)
            let colorIndex = min(Int(progress * Double(colors.count)), colors.count - 1)

            if isHeard {
                if let previous, previous.wasHeard, previous.colorIndex == colorIndex {
                    heard[colorIndex].addLine(to: point)
                } else {
                    heard[colorIndex].move(to: previous?.point ?? point)
                    heard[colorIndex].addLine(to: point)
                }
            } else {
                if let previous, !previous.wasHeard {
                    unheard.addLine(to: point)
                } else {
                    unheard.move(to: previous?.point ?? point)
                    unheard.addLine(to: point)
                }
            }
            previous = (point, isHeard, colorIndex)
        }
        context.stroke(unheard, with: .color(.white.opacity(0.18)), lineWidth: 0.8)
        for (index, path) in heard.enumerated() {
            context.stroke(path, with: .color(colors[index]), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        }
    }

    /// A steel arm from a ball pivot at the top right to the stylus, which sits
    /// on the groove being cut.
    private func drawTonearm(in context: inout GraphicsContext, layout: GrooveLayout, groove: GrooveRecorder, duration: TimeInterval) {
        let stylus = layout.groovePoint(time: groove.songTime, now: groove.songTime, duration: duration, offset: 0)
        let pivot = layout.pivot
        let steel = Gradient(colors: [Color(white: 0.85), Color(white: 0.55), Color(white: 0.9)])
        var arm = Path()
        arm.move(to: pivot)
        arm.addLine(to: stylus)
        context.stroke(arm, with: .linearGradient(steel, startPoint: pivot, endPoint: stylus), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        // The headshell: a short, thicker piece at the stylus end.
        let direction = CGPoint(x: stylus.x - pivot.x, y: stylus.y - pivot.y)
        let length = max(hypot(direction.x, direction.y), 1)
        let back = CGPoint(x: stylus.x - direction.x / length * 18, y: stylus.y - direction.y / length * 18)
        var head = Path()
        head.move(to: back)
        head.addLine(to: stylus)
        context.stroke(head, with: .color(Color(white: 0.75)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
        // The ball at the pivot, like the icon's.
        let ball = Path(ellipseIn: CGRect(x: pivot.x - 13, y: pivot.y - 13, width: 26, height: 26))
        context.fill(ball, with: .radialGradient(
            Gradient(colors: [.white, Color(white: 0.6), Color(white: 0.3)]),
            center: CGPoint(x: pivot.x - 4, y: pivot.y - 4), startRadius: 1, endRadius: 15
        ))
    }
}

/// Where everything sits, shared by the canvases and the label.
struct GrooveLayout {
    let center: CGPoint
    let outerRadius: CGFloat

    /// How fast the record turns: about one turn every seven seconds, slow
    /// enough to see the groove form.
    static let turnRate = 2 * Double.pi * 0.15
    /// Where the stylus sits on the record, in screen angle (radians, clockwise from 3 o'clock).
    static let stylusAngle = -0.12 * Double.pi

    /// Centered in the space it's given (between the menu and the controls).
    init(size: CGSize) {
        outerRadius = min(size.width, size.height) * 0.46
        center = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    var labelRadius: CGFloat { outerRadius * 0.33 }
    private var grooveStart: CGFloat { outerRadius * 0.96 }
    private var grooveEnd: CGFloat { labelRadius * 1.1 }
    var pivot: CGPoint { CGPoint(x: center.x + outerRadius * 0.92, y: center.y - outerRadius * 1.08) }

    func circle(radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    /// The gap between turns of the groove, so the whole song fits from edge to label.
    func groovePitch(duration: TimeInterval) -> CGFloat {
        let turns = max(duration * Self.turnRate / (2 * .pi), 1)
        return (grooveStart - grooveEnd) / CGFloat(turns)
    }

    /// Where the groove cut at `time` is now: it was under the stylus then, and
    /// the record has turned since.
    func groovePoint(time: TimeInterval, now: TimeInterval, duration: TimeInterval, offset: CGFloat) -> CGPoint {
        let progress = CGFloat(min(max(time / duration, 0), 1))
        let radius = grooveStart - (grooveStart - grooveEnd) * progress + offset
        let angle = Self.stylusAngle + Self.turnRate * (now - time)
        return CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
    }
}

/// Keeps the recorder between frames. A class so the drawing can advance it
/// each frame without changing view state mid-update.
@MainActor
final class GrooveState {
    private var recorder = GrooveRecorder()
    private var lastFrame: Date?

    func update(engine: PlaybackEngine, feed: SpectrumFeed, at date: Date) -> GrooveRecorder {
        let elapsed = lastFrame.map { min(date.timeIntervalSince($0), 0.1) } ?? 0
        lastFrame = date
        let energy = feed.energy
        let loudness = (energy.bass * 0.5 + energy.mid * 0.3 + energy.treble * 0.2) * 1.4 + feed.beat * 0.4
        recorder.update(
            entryID: engine.queue.current?.id,
            position: engine.position,
            isPlaying: engine.status == .playing,
            level: loudness,
            elapsed: elapsed
        )
        return recorder
    }
}
