/// How the app looks: the phone's own light or dark mode, one of them forced,
/// or a Catppuccin flavour.
public enum AppTheme: String, CaseIterable, Codable, Sendable {
    case system, light, dark
    case latte, frappe, macchiato, mocha

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .latte: "Catppuccin Latte"
        case .frappe: "Catppuccin Frappé"
        case .macchiato: "Catppuccin Macchiato"
        case .mocha: "Catppuccin Mocha"
        }
    }

    public var flavor: CatppuccinFlavor? {
        switch self {
        case .system, .light, .dark: nil
        case .latte: .latte
        case .frappe: .frappe
        case .macchiato: .macchiato
        case .mocha: .mocha
        }
    }

    /// `nil` follows the phone. Each flavour is made for one mode, so it forces it.
    public var isDark: Bool? {
        switch self {
        case .system: nil
        case .light: false
        case .dark: true
        default: flavor?.isDark
        }
    }
}

public enum CatppuccinFlavor: String, CaseIterable, Sendable {
    case latte, frappe, macchiato, mocha

    /// Latte is the light flavour; the others are dark.
    public var isDark: Bool { self != .latte }
}

/// Catppuccin's accent colours, in the palette's order.
public enum CatppuccinAccent: String, CaseIterable, Codable, Sendable {
    case rosewater, flamingo, pink, mauve, red, maroon, peach, yellow
    case green, teal, sky, sapphire, blue, lavender

    public var title: String { rawValue.capitalized }
}

public struct AppearanceSettings: Codable, Sendable, Equatable {
    public var theme: AppTheme
    /// Only used by the Catppuccin themes; kept when switching away and back.
    public var accent: CatppuccinAccent

    public init(theme: AppTheme = .system, accent: CatppuccinAccent = .mauve) {
        self.theme = theme
        self.accent = accent
    }

    private enum CodingKeys: String, CodingKey { case theme, accent }

    /// Each setting falls back to its default on its own if it's missing or
    /// unknown (say, saved by a newer version), keeping the other.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppearanceSettings()
        theme = (try? c.decodeIfPresent(AppTheme.self, forKey: .theme)) ?? defaults.theme
        accent = (try? c.decodeIfPresent(CatppuccinAccent.self, forKey: .accent)) ?? defaults.accent
    }
}
