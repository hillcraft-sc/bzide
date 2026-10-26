import NavidromeCore
import SwiftUI

// The chosen theme is applied once at the root (`appTheme`). It sets light or
// dark mode and the accent: the theme's chosen accent, or for the System, Light and
// Dark themes the chosen system accent (Bzide Red by default). Text keeps iOS's label colors:
// setting a foreground style for the whole app would also override the tint
// on buttons and icons, so they'd stop following the accent. Lists and forms
// also need their backgrounds replaced, which each screen asks for with
// `themedList` and `themedRows`. Bars, menus, alerts and the keyboard stay iOS's own.

extension Color {
    init(_ rgb: RGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension EnvironmentValues {
    /// The theme's colors (Catppuccin, Gruvbox, Nord, Dracula, Tokyo Night),
    /// or `nil` for the system themes.
    @Entry var themePalette: ThemePalette?
    /// The accent in use (the theme's or the system themes'). For UIKit views,
    /// which don't pick up SwiftUI's `tint`.
    @Entry var themeAccent: Color?
}

extension View {
    func appTheme(_ appearance: AppearanceModel) -> some View {
        modifier(AppTheme(appearance: appearance))
    }

    /// The theme's background behind a `List` or `Form`. `grouped` is for the
    /// inset-grouped style (forms), whose rows sit on a contrasting background.
    func themedList(grouped: Bool = false) -> some View {
        modifier(ThemedList(grouped: grouped))
    }

    /// The theme's backgrounds for the rows inside a list's section or `ForEach`.
    func themedRows(grouped: Bool = false) -> some View {
        modifier(ThemedRows(grouped: grouped))
    }
}

// Always the same modifiers, with nil values where a theme has none: an `if`
// here would rebuild the whole app when the theme changes, losing the
// navigation stack and every screen's state.
private struct AppTheme: ViewModifier {
    let appearance: AppearanceModel

    func body(content: Content) -> some View {
        let palette = appearance.palette
        let accent = appearance.settings.themeAccent.map { Color($0.color) } ?? appearance.settings.systemAccent.color
        content
            .preferredColorScheme(appearance.settings.theme.isDark.map { $0 ? .dark : .light })
            .tint(accent)
            .environment(\.themePalette, palette)
            .environment(\.themeAccent, accent)
    }
}

extension SystemAccent {
    var color: Color {
        switch self {
        case .bzide: Color(uiColor: Self.bzideRed)
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        }
    }

    /// The deep oxblood of the icon's leather (about #4F2F33), lifted so it
    /// reads as an accent: richer in light mode, brighter in dark mode.
    ///
    /// Built outside the main actor: SwiftUI also resolves colors on its
    /// background render thread (during animations), and a main-actor
    /// closure called there stops the app (seen on device, 2026-10-26).
    nonisolated private static let bzideRed = UIColor { @Sendable traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xE0 / 255, green: 0x60 / 255, blue: 0x6F / 255, alpha: 1)
            : UIColor(red: 0x9B / 255, green: 0x2D / 255, blue: 0x3F / 255, alpha: 1)
    }
}

private struct ThemedList: ViewModifier {
    let grouped: Bool
    @Environment(\.themePalette) private var palette

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(palette == nil ? .automatic : .hidden)
            .background(palette.map { $0.listBackground(grouped: grouped) } ?? .clear)
    }
}

private struct ThemedRows: ViewModifier {
    let grouped: Bool
    @Environment(\.themePalette) private var palette

    /// Always a color, never nil (the system default) for the system themes:
    /// a list caches its rows' backgrounds, and a row switching from none to
    /// a color while its list was hidden (behind Settings, where the theme is
    /// changed) kept showing none until relaunch. The system colors here are
    /// what a list draws by default.
    func body(content: Content) -> some View {
        content.listRowBackground(
            palette.map { $0.rowBackground(grouped: grouped) }
                ?? Color(uiColor: grouped ? .secondarySystemGroupedBackground : .systemBackground)
        )
    }
}

private extension ThemePalette {
    /// Light themes: rows a shade lighter than the background, like iOS's light
    /// grouped style. Dark themes: rows a shade lighter than `base`.
    func listBackground(grouped: Bool) -> Color {
        Color(grouped && isLight ? crust : base)
    }

    func rowBackground(grouped: Bool) -> Color {
        guard grouped else { return Color(base) }
        return Color(isLight ? base : surface0)
    }
}
