import NavidromeCore
import SwiftUI
import WidgetKit

// The widgets draw in the app's theme (`WidgetTheme`, shared by the app):
// its background, text and tiles, and its accent on the buttons. Only in
// full color: on the Lock Screen and in the Home Screen's tinted and clear
// modes, iOS draws every widget in its own style, as Apple asks widgets to
// allow. With the System, Light and Dark themes (no colors), the widgets keep
// iOS's look and the phone's mode, with the system accent.

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension EnvironmentValues {
    /// The theme's tile and placeholder color; `nil` for iOS's own fill.
    @Entry var widgetSurface: Color?
}

extension View {
    func themedWidget(_ theme: WidgetTheme?) -> some View {
        modifier(ThemedWidget(theme: theme))
    }
}

private struct ThemedWidget: ViewModifier {
    let theme: WidgetTheme?
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isFullColor = renderingMode == .fullColor
        let colors = isFullColor ? theme?.colors : nil
        // A theme's accent is the same either way; a system accent has a
        // light and a dark shade.
        let accent = isFullColor ? theme.map { Color(hex: colorScheme == .dark ? $0.accentDark : $0.accentLight) } : nil
        content
            .foregroundStyle(colors.map { AnyShapeStyle(Color(hex: $0.text)) } ?? AnyShapeStyle(.primary))
            .tint(accent)
            .environment(\.widgetSurface, colors.map { Color(hex: $0.surface) })
            .containerBackground(for: .widget) {
                if let colors {
                    Color(hex: colors.base)
                } else {
                    Rectangle().fill(.fill.tertiary)
                }
            }
    }
}
