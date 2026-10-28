// Turns the screenshots from scripts/screenshots.sh into App Store images:
// a headline on Bzide Red, with the screenshot below it in a rounded
// rectangle that runs off the bottom edge. The Themes image stacks the
// themes-*.png shots, the most striking in front.
//
//   swift scripts/compose-screenshots.swift <screenshots folder>
//
// Saves upload-ready JPEGs in <screenshots folder>/upload, at the size taken
// (iPhone 6.9" 1320 x 2868, iPad 13" 2064 x 2752), plus 1206 x 2622 copies
// of the iPhone ones, the size App Store Connect requires; from the iPhone
// shots, also the search results (5244 x 2950) and product page header
// (3840 x 1646) images, as PNGs. Only Apple frameworks, so nothing to install.

import AppKit

/// The images in App Store order: the screenshot's file name (without .png)
/// and its headline. "themes" is the stacked Themes image.
let images: [(file: String, headline: String)] = [
    ("01-now-playing", "Your music,\nyour server"),
    ("02-library", "Your whole library,\nat a glance"),
    ("03-radio", "Live radio,\ndone right"),
    ("04-spectrum", "Watch\nthe music"),
    ("themes", "Make it\nyours"),
    ("06-lyrics", "Sing\nalong"),
    ("07-album", "Take it\noffline"),
]

/// Front to back.
let themes = ["tokyoNight", "latte", "gruvboxDark", "nord"]

// The oxblood of the icon, as Bzide Red in light mode, darkening downward.
let backgroundTop = NSColor(red: 0x9B / 255, green: 0x2D / 255, blue: 0x3F / 255, alpha: 1)
let backgroundBottom = NSColor(red: 0x5E / 255, green: 0x1A / 255, blue: 0x27 / 255, alpha: 1)

// MARK: - Drawing

func loadImage(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// A context with its origin at the top left, as the layout is measured.
func makeContext(width: Int, height: Int) -> CGContext? {
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    return context
}

func drawBackground(_ context: CGContext, size: CGSize) {
    let colors = [backgroundTop.cgColor, backgroundBottom.cgColor] as CFArray
    guard let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1]) else { return }
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
}

/// Text in a column `width` wide from `origin`; returns where it ends.
func drawText(
    _ text: String, context: CGContext, origin: CGPoint, width: CGFloat, fontSize: CGFloat,
    weight: NSFont.Weight = .heavy, alignment: NSTextAlignment = .center, color: NSColor = .white
) -> CGFloat {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineHeightMultiple = 0.95
    let attributed = NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph,
    ])
    let bounds = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
    let rect = CGRect(x: origin.x, y: origin.y, width: width, height: ceil(bounds.height))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    attributed.draw(with: rect, options: [.usesLineFragmentOrigin])
    NSGraphicsContext.restoreGraphicsState()
    return rect.maxY
}

/// Centered white headline from `top`; returns where it ends.
func drawHeadline(_ text: String, context: CGContext, size: CGSize, top: CGFloat) -> CGFloat {
    let width = size.width * 0.86
    return drawText(
        text, context: context, origin: CGPoint(x: (size.width - width) / 2, y: top), width: width,
        fontSize: min(size.width * 0.085, size.height * 0.042)
    )
}

/// The screenshot in a rounded rectangle with a soft shadow, its top left at
/// `origin`, turned by `degrees` around its center.
func drawShot(_ image: CGImage, context: CGContext, origin: CGPoint, width: CGFloat, degrees: CGFloat = 0) {
    let height = width * CGFloat(image.height) / CGFloat(image.width)
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    // About the corners of the device the screenshot came from: an iPad's
    // (wider screen) are much smaller for its size than an iPhone's.
    let radius = width * (image.width > image.height * 2 / 3 ? 0.035 : 0.11)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.translateBy(x: origin.x + width / 2, y: origin.y + height / 2)
    context.rotate(by: degrees * .pi / 180)
    context.translateBy(x: -width / 2, y: -height / 2)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: width * 0.02), blur: width * 0.08, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    context.addPath(path)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    context.addPath(path)
    context.clip()
    // Drawn upright in the flipped context.
    context.translateBy(x: 0, y: height)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: rect)
    context.restoreGState()
}

func compose(headline: String, shots: [CGImage], size: CGSize) -> CGImage? {
    guard let context = makeContext(width: Int(size.width), height: Int(size.height)) else { return nil }
    drawBackground(context, size: size)
    let textBottom = drawHeadline(headline, context: context, size: size, top: size.height * 0.065)
    let top = textBottom + size.height * 0.04
    if shots.count == 1, let shot = shots.first {
        let width = size.width * 0.82
        drawShot(shot, context: context, origin: CGPoint(x: (size.width - width) / 2, y: top), width: width)
    } else {
        // Staggered: each card behind is further left, higher and turned a
        // little more, so a strip of every theme shows. An iPhone's narrow
        // image gets smaller cards spread wider, or the strips are slivers.
        let isPhone = size.height > size.width * 1.5
        let width = size.width * (isPhone ? 0.56 : 0.64)
        let step = size.width * (isPhone ? 0.12 : 0.085)
        let rise = size.height * 0.035
        let turn: CGFloat = isPhone ? -2 : -3
        let frontX = size.width - width - size.width * (isPhone ? 0.04 : 0.06)
        for (index, shot) in shots.enumerated().reversed() {
            let origin = CGPoint(x: frontX - step * CGFloat(index), y: top + rise * CGFloat(shots.count - 1 - index))
            drawShot(shot, context: context, origin: origin, width: width, degrees: turn * CGFloat(index))
        }
    }
    return context.makeImage()
}

// MARK: - Header and search results

/// The App Store's search results image (iOS 27), as its 16:9 universal
/// size, which it shows whole there (trimmed a little at the sides). As the
/// product page header it doesn't work: on iPhone only about the middle 60%
/// of the width shows, under the back and share buttons, so that has its own
/// image (`header`).
let banner = (
    size: CGSize(width: 5244, height: 2950),
    headline: "Your music,\nyour server.",
    line: "Fast, private playback from\nyour own Navidrome server.",
    // Left, front (middle), right.
    shots: ["03-radio", "01-now-playing", "04-spectrum"]
)

/// The product page header: no text, as the name and Get button are just
/// below it; the phones fanned around the middle, where an iPhone shows it,
/// starting below the buttons over its top and running off the bottom edge.
/// An iPad shows more of the width, so the outer ones fill it out.
let header = (
    size: CGSize(width: 3840, height: 1646),
    // Left to right; the middle one in front.
    shots: ["03-radio", "02-library", "01-now-playing", "04-spectrum", "07-album"]
)

func composeHeader(shots: [CGImage]) -> CGImage? {
    let size = header.size
    guard let context = makeContext(width: Int(size.width), height: Int(size.height)) else { return nil }
    drawBackground(context, size: size)
    let width = size.width * 0.15
    let middle = shots.count / 2
    // Outermost first, so the middle one is drawn on top.
    let order = shots.indices.sorted { abs($0 - middle) > abs($1 - middle) }
    for index in order {
        let step = CGFloat(index - middle)
        let origin = CGPoint(
            x: size.width / 2 - width / 2 + step * size.width * 0.125,
            y: size.height * (0.24 + 0.05 * abs(step))
        )
        drawShot(shots[index], context: context, origin: origin, width: width, degrees: step * 6)
    }
    return context.makeImage()
}

func composeBanner(icon: CGImage?, shots: [CGImage]) -> CGImage? {
    let size = banner.size
    guard let context = makeContext(width: Int(size.width), height: Int(size.height)) else { return nil }
    drawBackground(context, size: size)

    // Text on the left, centered vertically as a block.
    let left = size.width * 0.15
    let column = size.width * 0.34
    let iconSize = size.height * 0.12
    let blockHeight = size.height * 0.5
    var y = (size.height - blockHeight) / 2
    if let icon {
        let rect = CGRect(x: left, y: y, width: iconSize, height: iconSize)
        context.saveGState()
        context.addPath(CGPath(roundedRect: rect, cornerWidth: iconSize * 0.2237, cornerHeight: iconSize * 0.2237, transform: nil))
        context.clip()
        context.translateBy(x: 0, y: rect.maxY + rect.minY)
        context.scaleBy(x: 1, y: -1)
        context.draw(icon, in: rect)
        context.restoreGState()
    }
    _ = drawText(
        "Bzide", context: context, origin: CGPoint(x: left + iconSize * 1.25, y: y + iconSize * 0.18), width: column,
        fontSize: iconSize * 0.5, weight: .bold, alignment: .left
    )
    y += iconSize * 1.45
    y = drawText(banner.headline, context: context, origin: CGPoint(x: left, y: y), width: column, fontSize: size.height * 0.095, alignment: .left)
    _ = drawText(
        banner.line, context: context, origin: CGPoint(x: left, y: y + size.height * 0.035), width: column,
        fontSize: size.height * 0.04, weight: .medium, alignment: .left, color: .white.withAlphaComponent(0.85)
    )

    // Three screenshots on the right, fanned around the front one.
    let width = size.width * 0.16
    guard let first = shots.first else { return context.makeImage() }
    let height = width * CGFloat(first.height) / CGFloat(first.width)
    let center = size.width * 0.665
    let top = (size.height - height) / 2
    let placements: [(index: Int, dx: CGFloat, dy: CGFloat, degrees: CGFloat)] = [
        (0, -0.115, 0.03, -7), (2, 0.115, 0.03, 7), (1, 0, 0, 0),
    ]
    for placement in placements where shots.indices.contains(placement.index) {
        let origin = CGPoint(x: center - width / 2 + size.width * placement.dx, y: top + size.height * placement.dy)
        drawShot(shots[placement.index], context: context, origin: origin, width: width, degrees: placement.degrees)
    }
    return context.makeImage()
}

func savePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("Couldn't encode \(url.lastPathComponent)")
        return
    }
    do { try data.write(to: url) } catch { print("Couldn't save \(url.path): \(error.localizedDescription)") }
}

func saveJPEG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else {
        print("Couldn't encode \(url.lastPathComponent)")
        return
    }
    do { try data.write(to: url) } catch { print("Couldn't save \(url.path): \(error.localizedDescription)") }
}

// MARK: - Main

guard CommandLine.arguments.count == 2 else {
    print("Usage: swift scripts/compose-screenshots.swift <screenshots folder>")
    exit(1)
}
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let upload = folder.appendingPathComponent("upload")
try? FileManager.default.createDirectory(at: upload, withIntermediateDirectories: true)

for (number, entry) in images.enumerated() {
    let names = entry.file == "themes" ? themes.map { "themes-\($0)" } : [entry.file]
    let shots = names.compactMap { loadImage(folder.appendingPathComponent("\($0).png")) }
    guard shots.count == names.count, let first = shots.first else {
        print("Skipped \(entry.file): missing \(names.map { "\($0).png" }.joined(separator: ", "))")
        continue
    }
    var sizes = [CGSize(width: first.width, height: first.height)]
    if first.width == 1320 { sizes.append(CGSize(width: 1206, height: 2622)) }
    let name = String(format: "%02d-", number + 1) + (entry.file == "themes" ? "themes" : String(entry.file.dropFirst(3)))
    for size in sizes {
        guard let image = compose(headline: entry.headline, shots: shots, size: size) else { continue }
        let suffix = size == sizes[0] ? "" : "-\(Int(size.width))x\(Int(size.height))"
        let url = upload.appendingPathComponent("\(name)\(suffix).jpg")
        saveJPEG(image, to: url)
        print(url.path)
    }
}

// The search results and header images, from the iPhone shots.
let bannerShots = banner.shots.compactMap { loadImage(folder.appendingPathComponent("\($0).png")) }
if bannerShots.count == banner.shots.count, bannerShots.allSatisfy({ $0.width == 1320 }) {
    let iconURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../MusicApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png").standardized
    if let image = composeBanner(icon: loadImage(iconURL), shots: bannerShots) {
        let url = upload.appendingPathComponent("search-results-5244x2950.png")
        savePNG(image, to: url)
        print(url.path)
    }
}
let headerShots = header.shots.compactMap { loadImage(folder.appendingPathComponent("\($0).png")) }
if headerShots.count == header.shots.count, headerShots.allSatisfy({ $0.width == 1320 }), let image = composeHeader(shots: headerShots) {
    let url = upload.appendingPathComponent("header-3840x1646.png")
    savePNG(image, to: url)
    print(url.path)
}
