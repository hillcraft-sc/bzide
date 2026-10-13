import NavidromeCore
import SwiftUI
import UIKit

/// The Typeset visualizer: the song's title, big, in heavy rounded type, with
/// the artist below, moving with the feel of the track
/// (`TypesetMotion` moves them): every letter plays its own band, bass on the
/// first and treble on the last; the bass thumps the title, treble tilts it,
/// drum hits make the letters jump out, and soft passages float them.
struct TypesetView: View {
    let title: String
    let artist: String?
    let levels: [Float]
    let energy: SpectrumEnergy
    let beat: Float
    let date: Date
    /// The colors to set the letters in, across the words: the accent, or the sweep.
    let colors: [Color]
    /// Where the words go, inside the canvas. The canvas itself is bigger, so
    /// letters lifting, stretching, glowing or knocked loose past the edges of
    /// the words aren't cut off.
    let insets: EdgeInsets
    let state: TypesetState

    var body: some View {
        Canvas { context, size in
            let area = CGRect(
                x: insets.leading, y: insets.top,
                width: max(size.width - insets.leading - insets.trailing, 1),
                height: max(size.height - insets.top - insets.bottom, 1)
            )
            let layout = state.layout(title: title, artist: artist, area: area)
            let motion = state.update(layout: layout, levels: levels, energy: energy, beat: beat, at: date)
            for (index, letter) in layout.letters.enumerated() where index < motion.count {
                draw(letter, motion: motion[index], index: index, count: layout.letters.count, in: &context)
            }
        }
    }

    private func draw(_ letter: TypesetLayout.Letter, motion: TypesetMotion.Letter, index: Int, count: Int, in context: inout GraphicsContext) {
        // The artist moves half as much, so the title leads.
        let amount = letter.isArtist ? 0.5 : 1.0
        let color = colors.isEmpty ? Color.white : colors[min(index * colors.count / max(count, 1), colors.count - 1)]
        let text = Text(letter.character)
            .font(.system(size: letter.fontSize, weight: letter.isArtist ? .semibold : .black, design: .rounded))
            .foregroundStyle(color)
        var layer = context
        layer.opacity = letter.isArtist ? 0.6 + 0.4 * motion.brightness : 0.7 + 0.3 * motion.brightness
        layer.translateBy(
            x: letter.baseline.x + CGFloat(motion.dx * amount) * letter.fontSize,
            y: letter.baseline.y + CGFloat(motion.dy * amount) * letter.fontSize
        )
        layer.rotate(by: .radians(motion.rotation * amount))
        // Grown and stretched up from the baseline, so letters still stand on it.
        let scale = CGFloat(1 + (motion.scale - 1) * amount)
        layer.scaleBy(x: scale, y: scale * CGFloat(1 + (motion.stretch - 1) * amount))
        if motion.brightness > 0.6, !letter.isArtist {
            // A glow behind the loudest letters.
            var glow = layer
            glow.addFilter(.blur(radius: letter.fontSize * 0.12))
            glow.opacity = (motion.brightness - 0.6) * 1.5
            glow.draw(text, at: .zero, anchor: .bottom)
        }
        layer.draw(text, at: .zero, anchor: .bottom)
    }
}

/// Where each letter sits: the title as large as fits in up to three lines,
/// the artist below in up to two, the whole block centered.
struct TypesetLayout {
    struct Letter {
        let character: String
        /// The middle of the letter's baseline.
        let baseline: CGPoint
        let fontSize: CGFloat
        let isArtist: Bool
        /// 0 for the first letter of its line of words ... 1 for the last, across title and artist separately.
        let position: Double
    }

    let letters: [Letter]

    static let maxTitleSize: CGFloat = 76
    static let minTitleSize: CGFloat = 26

    /// A margin either side of the words, a share of the width, for letters to move into.
    static let sideMargin: CGFloat = 0.06

    init(title: String, artist: String?, area: CGRect) {
        let margin = area.width * Self.sideMargin
        let size = CGSize(width: area.width - margin * 2, height: area.height)
        var titleSize = Self.maxTitleSize
        var titleLines: [[String]] = []
        var artistSize: CGFloat = 0
        var artistLines: [[String]] = []
        // Shrink until the title fits in three lines and the whole block fits
        // the height, with a quarter spare for letters lifting and scattering.
        while true {
            artistSize = max(titleSize * 0.38, 16)
            titleLines = Self.wrap(title, width: size.width, font: Self.titleFont(titleSize))
            artistLines = artist.map { Self.wrap($0, width: size.width, font: Self.artistFont(artistSize)) } ?? []
            let height = CGFloat(titleLines.count) * titleSize * 1.15 + CGFloat(artistLines.count) * artistSize * 1.3 + titleSize * 0.4
            let fits = titleLines.count <= 3 && artistLines.count <= 2 && height <= size.height * 0.75
            if fits || titleSize <= Self.minTitleSize { break }
            titleSize *= 0.92
        }

        let titleHeight = CGFloat(titleLines.count) * titleSize * 1.15
        let artistHeight = CGFloat(artistLines.count) * artistSize * 1.3
        let gap = artistLines.isEmpty ? 0 : titleSize * 0.4
        var y = (size.height - titleHeight - gap - artistHeight) / 2
        var letters: [Letter] = []
        for line in titleLines {
            y += titleSize * 1.15
            letters += Self.place(line, baselineY: y - titleSize * 0.22, width: size.width, font: Self.titleFont(titleSize), isArtist: false)
        }
        y += gap
        for line in artistLines {
            y += artistSize * 1.3
            letters += Self.place(line, baselineY: y - artistSize * 0.25, width: size.width, font: Self.artistFont(artistSize), isArtist: true)
        }
        self.letters = Self.spread(letters, offset: CGPoint(x: area.minX + margin, y: area.minY))
    }

    /// The same faces the letters are drawn in, for measuring.
    private static func titleFont(_ size: CGFloat) -> UIFont {
        rounded(UIFont.systemFont(ofSize: size, weight: .black))
    }

    private static func artistFont(_ size: CGFloat) -> UIFont {
        rounded(UIFont.systemFont(ofSize: size, weight: .semibold))
    }

    private static func rounded(_ font: UIFont) -> UIFont {
        font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
    }

    private static func width(of text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// Words into lines no wider than `width`, as lists of characters.
    private static func wrap(_ text: String, width: CGFloat, font: UIFont) -> [[String]] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ").map(String.init) {
            let candidate = current.isEmpty ? word : current + " " + word
            if current.isEmpty || Self.width(of: candidate, font: font) <= width {
                current = candidate
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        // A single word wider than the screen counts as an extra line, so the font shrinks.
        let tooWide = lines.contains { Self.width(of: $0, font: font) > width }
        return lines.map { $0.map(String.init) } + (tooWide ? [[]] : [])
    }

    /// One line's letters, centered, each at the middle of its own width.
    private static func place(_ line: [String], baselineY: CGFloat, width: CGFloat, font: UIFont, isArtist: Bool) -> [Letter] {
        guard !line.isEmpty else { return [] }
        let widths = line.map { Self.width(of: $0, font: font) }
        var x = (width - widths.reduce(0, +)) / 2
        var letters: [Letter] = []
        for (character, letterWidth) in zip(line, widths) {
            if character != " " {
                letters.append(Letter(
                    character: character, baseline: CGPoint(x: x + letterWidth / 2, y: baselineY),
                    fontSize: font.pointSize, isArtist: isArtist, position: 0
                ))
            }
            x += letterWidth
        }
        return letters
    }

    /// Spreads the title's letters, then the artist's, across the spectrum,
    /// and moves them from the words' own space to the canvas's.
    private static func spread(_ letters: [Letter], offset: CGPoint) -> [Letter] {
        let titleCount = letters.filter { !$0.isArtist }.count
        let artistCount = letters.count - titleCount
        var titleIndex = 0
        var artistIndex = 0
        return letters.map { letter in
            let position: Double
            if letter.isArtist {
                position = artistCount > 1 ? Double(artistIndex) / Double(artistCount - 1) : 0
                artistIndex += 1
            } else {
                position = titleCount > 1 ? Double(titleIndex) / Double(titleCount - 1) : 0
                titleIndex += 1
            }
            let baseline = CGPoint(x: letter.baseline.x + offset.x, y: letter.baseline.y + offset.y)
            return Letter(character: letter.character, baseline: baseline, fontSize: letter.fontSize, isArtist: letter.isArtist, position: position)
        }
    }
}

/// Keeps the letter motion between frames, and the layout until the words or
/// the space change. A class so the drawing can advance it each frame without
/// changing view state mid-update.
@MainActor
final class TypesetState {
    private var motion = TypesetMotion()
    private var lastFrame: Date?
    private var cached: (key: String, layout: TypesetLayout)?

    func layout(title: String, artist: String?, area: CGRect) -> TypesetLayout {
        let key = "\(title)\n\(artist ?? "")\n\(area.debugDescription)"
        if let cached, cached.key == key { return cached.layout }
        let layout = TypesetLayout(title: title, artist: artist, area: area)
        cached = (key, layout)
        return layout
    }

    func update(layout: TypesetLayout, levels: [Float], energy: SpectrumEnergy, beat: Float, at date: Date) -> [TypesetMotion.Letter] {
        let elapsed = lastFrame.map { date.timeIntervalSince($0) } ?? 0
        lastFrame = date
        motion.update(positions: layout.letters.map(\.position), levels: levels, energy: energy, beat: beat, elapsed: elapsed)
        return motion.letters
    }
}
