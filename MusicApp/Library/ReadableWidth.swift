import SwiftUI

extension View {
    /// Keeps a list's or form's rows to a comfortable width on a wide screen
    /// (iPad), centered, with the background still filling it (Gitea #22).
    /// Narrower screens, every iPhone, are unchanged.
    func readableWidth(_ maxWidth: CGFloat = 640) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }
}

private struct ReadableWidth: ViewModifier {
    let maxWidth: CGFloat
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, max(0, (width - maxWidth) / 2), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
