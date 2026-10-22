/// How the app looks: the phone's own light or dark mode, one of them forced,
/// or a theme from one of the families (Catppuccin, Gruvbox, Nord, Dracula,
/// Tokyo Night). Each theme is made for one mode, so it forces it.
public enum AppTheme: String, CaseIterable, Codable, Sendable {
    case system, light, dark
    case latte, frappe, macchiato, mocha
    case gruvboxDark, gruvboxLight
    case nord
    case dracula
    case tokyoNight, tokyoStorm, tokyoMoon, tokyoDay

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .latte: "Catppuccin Latte"
        case .frappe: "Catppuccin Frappé"
        case .macchiato: "Catppuccin Macchiato"
        case .mocha: "Catppuccin Mocha"
        case .gruvboxDark: "Gruvbox Dark"
        case .gruvboxLight: "Gruvbox Light"
        case .nord: "Nord"
        case .dracula: "Dracula"
        case .tokyoNight: "Tokyo Night"
        case .tokyoStorm: "Tokyo Night Storm"
        case .tokyoMoon: "Tokyo Night Moon"
        case .tokyoDay: "Tokyo Night Day"
        }
    }

    public var family: ThemeFamily? {
        switch self {
        case .system, .light, .dark: nil
        case .latte, .frappe, .macchiato, .mocha: .catppuccin
        case .gruvboxDark, .gruvboxLight: .gruvbox
        case .nord: .nord
        case .dracula: .dracula
        case .tokyoNight, .tokyoStorm, .tokyoMoon, .tokyoDay: .tokyoNight
        }
    }

    public var flavor: CatppuccinFlavor? {
        switch self {
        case .latte: .latte
        case .frappe: .frappe
        case .macchiato: .macchiato
        case .mocha: .mocha
        default: nil
        }
    }

    /// The theme's colors; `nil` for System, Light and Dark.
    public var palette: ThemePalette? {
        if let flavor { return flavor.palette.themePalette }
        return switch self {
        case .gruvboxDark: .gruvboxDark
        case .gruvboxLight: .gruvboxLight
        case .nord: .nord
        case .dracula: .dracula
        case .tokyoNight: .tokyoNight
        case .tokyoStorm: .tokyoStorm
        case .tokyoMoon: .tokyoMoon
        case .tokyoDay: .tokyoDay
        default: nil
        }
    }

    /// `nil` follows the phone. Each theme is made for one mode, so it forces it.
    public var isDark: Bool? {
        switch self {
        case .system: nil
        case .light: false
        case .dark: true
        default: palette.map { !$0.isLight }
        }
    }
}

public enum CatppuccinFlavor: String, CaseIterable, Sendable {
    case latte, frappe, macchiato, mocha

    /// Latte is the light flavor; the others are dark.
    public var isDark: Bool { self != .latte }
}

/// Catppuccin's accent colors, in the palette's order.
public enum CatppuccinAccent: String, CaseIterable, Codable, Sendable {
    case rosewater, flamingo, pink, mauve, red, maroon, peach, yellow
    case green, teal, sky, sapphire, blue, lavender

    public var title: String { rawValue.capitalized }
}

/// The accent for the System, Light and Dark themes: the red from the app's
/// icon by default, or one of iOS's standard colors. The app turns these into
/// colors; Bzide Red's are in the app target.
public enum SystemAccent: String, CaseIterable, Codable, Sendable {
    case bzide
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown

    public var title: String {
        self == .bzide ? "Bzide Red" : rawValue.capitalized
    }
}

public struct AppearanceSettings: Codable, Sendable, Equatable {
    public var theme: AppTheme
    /// Only used by the Catppuccin themes; kept when switching away and back.
    public var accent: CatppuccinAccent
    /// Only used by the System, Light and Dark themes; kept likewise.
    public var systemAccent: SystemAccent
    /// The other families' accents, by family (`ThemeFamily` raw value) to
    /// the accent's id; a family without one uses its default. Kept likewise.
    public var familyAccents: [String: String]

    public init(theme: AppTheme = .system, accent: CatppuccinAccent = .mauve, systemAccent: SystemAccent = .bzide, familyAccents: [String: String] = [:]) {
        self.theme = theme
        self.accent = accent
        self.systemAccent = systemAccent
        self.familyAccents = familyAccents
    }

    /// The current theme's accent, if it has a palette.
    public var themeAccent: ThemeAccentColor? {
        guard let family = theme.family, let palette = theme.palette else { return nil }
        return palette.accent(accentID(for: family))
    }

    /// The accent chosen for a family (Catppuccin's is kept in `accent`, as before).
    public func accentID(for family: ThemeFamily) -> String {
        family == .catppuccin ? accent.rawValue : familyAccents[family.rawValue] ?? ""
    }

    public mutating func setAccent(_ id: String, for family: ThemeFamily) {
        if family == .catppuccin {
            if let catppuccin = CatppuccinAccent(rawValue: id) { accent = catppuccin }
        } else {
            familyAccents[family.rawValue] = id
        }
    }

    private enum CodingKeys: String, CodingKey { case theme, accent, systemAccent, familyAccents }

    /// Each setting falls back to its default on its own if it's missing or
    /// unknown (say, saved by a newer version), keeping the other.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppearanceSettings()
        theme = (try? c.decodeIfPresent(AppTheme.self, forKey: .theme)) ?? defaults.theme
        accent = (try? c.decodeIfPresent(CatppuccinAccent.self, forKey: .accent)) ?? defaults.accent
        systemAccent = (try? c.decodeIfPresent(SystemAccent.self, forKey: .systemAccent)) ?? defaults.systemAccent
        familyAccents = (try? c.decodeIfPresent([String: String].self, forKey: .familyAccents)) ?? defaults.familyAccents
    }
}
