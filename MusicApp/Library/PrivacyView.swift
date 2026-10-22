import NavidromeCore
import SwiftUI

/// Settings > Privacy: the app's privacy page, `docs/PRIVACY.md`, bundled
/// with the app and drawn natively, so the page in the repo and the one in
/// the app are always the same.
struct PrivacyView: View {
    private let blocks: [MarkdownBlock] = {
        guard let url = Bundle.main.url(forResource: "PRIVACY", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return MarkdownBlock.parse(text)
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if blocks.isEmpty {
                    Text("The privacy page couldn't be loaded.").foregroundStyle(.secondary)
                }
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    BlockView(block: block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .themedList()
    }
}

private struct BlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Inline(text)
                .font(level == 1 ? .title.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, level == 1 ? 0 : 10)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Inline(text)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").accessibilityHidden(true)
                        Inline(item)
                    }
                }
            }
        case .table(let header, let rows):
            // A card per row, too wide for a phone as a grid: the first column
            // as its title, the rest labeled with their headers.
            VStack(spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 6) {
                        Inline(row.first ?? "").font(.headline)
                        ForEach(Array(zip(header.dropFirst(), row.dropFirst()).enumerated()), id: \.offset) { _, pair in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pair.0).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Inline(pair.1).font(.subheadline)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                }
            }
        }
    }
}

/// Bold, italic, code and links within a line.
private struct Inline: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        let styled = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        Text(styled).fixedSize(horizontal: false, vertical: true)
    }
}
