import Foundation
import Testing
@testable import NavidromeCore

struct MarkdownBlocksTests {
    @Test func headingsParagraphsBulletsAndTables() {
        let markdown = """
        # Title

        First line
        continues here.

        ## Section

        - **One** thing
        - Another,
          wrapped
        Back to text? No: still the bullet.

        | Service | Gets |
        |---|---|
        | **LRCLIB** | A title |
        | Gravatar | A hash |

        *Footnote*
        """
        #expect(MarkdownBlock.parse(markdown) == [
            .heading(level: 1, text: "Title"),
            .paragraph("First line continues here."),
            .heading(level: 2, text: "Section"),
            .bullets(["**One** thing", "Another, wrapped Back to text? No: still the bullet."]),
            .table(header: ["Service", "Gets"], rows: [["**LRCLIB**", "A title"], ["Gravatar", "A hash"]]),
            .paragraph("*Footnote*"),
        ])
    }

    @Test func notHeadingsStayText() {
        #expect(MarkdownBlock.parse("#hashtag") == [.paragraph("#hashtag")])
        #expect(MarkdownBlock.parse("#### Deep") == [.paragraph("#### Deep")])
    }

    /// The real page parses into headings, bullets and the services table.
    @Test func thePrivacyPageParses() throws {
        let page = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/PRIVACY.md")
        let blocks = MarkdownBlock.parse(try String(contentsOf: page, encoding: .utf8))
        #expect(blocks.first == .heading(level: 1, text: "Bzide and your privacy"))
        let tables = blocks.compactMap { if case .table(let header, let rows) = $0 { (header, rows) } else { nil } }
        #expect(tables.count == 1)
        #expect(tables.first?.0 == ["Service", "What it's for", "Turned on in", "What it gets"])
        #expect((tables.first?.1.count ?? 0) >= 6)
    }
}
