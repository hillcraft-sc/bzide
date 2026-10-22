import Foundation

/// A simple Markdown document as blocks, for showing the app's own pages
/// (the privacy page, `docs/PRIVACY.md`) natively. Handles what those pages
/// use: `#`/`##`/`###` headings, paragraphs (lines joined until a blank
/// line), `- ` bullet lists, and `|` tables. Inline styling (bold, italic,
/// code, links) is left in the text for the view to render. Anything else is
/// kept as a paragraph, so nothing is ever lost.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String])
    case table(header: [String], rows: [[String]])

    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var table: [[String]] = []

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            if !bullets.isEmpty { blocks.append(.bullets(bullets)) }
            if let header = table.first {
                // The second row is the |---|---| divider.
                let rows = table.dropFirst().filter { !isDivider($0) }
                blocks.append(.table(header: header, rows: Array(rows)))
            }
            paragraph = []
            bullets = []
            table = []
        }

        for raw in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if let level = headingLevel(line) {
                flush()
                blocks.append(.heading(level: level, text: String(line.dropFirst(level + 1)).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !paragraph.isEmpty || !table.isEmpty { flush() }
                bullets.append(String(line.dropFirst(2)))
            } else if line.hasPrefix("|") {
                if !paragraph.isEmpty || !bullets.isEmpty { flush() }
                table.append(cells(line))
            } else if !bullets.isEmpty {
                // A wrapped bullet line continues the bullet.
                bullets[bullets.count - 1] += " " + line
            } else {
                if !table.isEmpty { flush() }
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    /// 1 to 3 for `#`, `##`, `###` followed by a space.
    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...3).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func cells(_ line: String) -> [String] {
        var content = Substring(line)
        if content.hasPrefix("|") { content = content.dropFirst() }
        if content.hasSuffix("|") { content = content.dropLast() }
        return content.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isDivider(_ cells: [String]) -> Bool {
        cells.allSatisfy { cell in !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" } }
    }
}
