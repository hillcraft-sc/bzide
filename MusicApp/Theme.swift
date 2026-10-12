import NavidromeCore
import SwiftUI

// The chosen theme is applied once at the root (`appTheme`). It sets light or
// dark mode and, for Catppuccin, the accent. Text keeps iOS's label colours:
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
    /// The Catppuccin colours in use, or `nil` for the system themes.
    @Entry var catppuccin: CatppuccinPalette?
}

extension View {
    func appTheme(_ appearance: AppearanceModel) -> some View {
        modifier(AppTheme(appearance: appearance))
    }

    /// A Catppuccin background behind a `List` or `Form`. `grouped` is for the
    /// inset-grouped style (forms), whose rows sit on a contrasting background.
    func themedList(grouped: Bool = false) -> some View {
        modifier(ThemedList(grouped: grouped))
    }

    /// Catppuccin backgrounds for the rows inside a list's section or `ForEach`.
    func themedRows(grouped: Bool = false) -> some View {
        modifier(ThemedRows(grouped: grouped))
    }
}

// Always the same modifiers, with nil values for the system themes:
// an `if` here would rebuild the whole app when the theme changes, losing the
// navigation stack and every screen's state.
private struct AppTheme: ViewModifier {
    let appearance: AppearanceModel

    func body(content: Content) -> some View {
        let palette = appearance.palette
        content
            .preferredColorScheme(appearance.settings.theme.isDark.map { $0 ? .dark : .light })
            .tint(palette.map { Color($0.accent(appearance.settings.accent)) })
            .environment(\.catppuccin, palette)
    }
}

private struct ThemedList: ViewModifier {
    let grouped: Bool
    @Environment(\.catppuccin) private var palette

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(palette == nil ? .automatic : .hidden)
            .background(palette.map { $0.listBackground(grouped: grouped) } ?? .clear)
    }
}

private struct ThemedRows: ViewModifier {
    let grouped: Bool
    @Environment(\.catppuccin) private var palette

    func body(content: Content) -> some View {
        content.listRowBackground(palette.map { $0.rowBackground(grouped: grouped) })
    }
}

private extension CatppuccinPalette {
    /// Light Latte: rows a shade lighter than the background, like iOS's light
    /// grouped style. Dark flavours: rows a shade lighter than `base`.
    var isLight: Bool { self == .latte }

    func listBackground(grouped: Bool) -> Color {
        Color(grouped && isLight ? crust : base)
    }

    func rowBackground(grouped: Bool) -> Color {
        guard grouped else { return Color(base) }
        return Color(isLight ? base : surface0)
    }
}
