// The themes' colors. Catppuccin's are in CatppuccinPalette.swift. The others
// are copied from each project's published palette, all MIT licensed:
// - Gruvbox: https://github.com/morhetz/gruvbox (c) 2012 Pavel Pertsev
// - Nord: https://www.nordtheme.com (c) 2016 Sven Greb (Arctic Ice Studio)
// - Dracula: https://draculatheme.com (c) 2016 Dracula Theme
// - Tokyo Night: https://github.com/folke/tokyonight.nvim (c) 2021 Folke Lemaitre
// Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software and associated documentation files, to deal in the Software without
// restriction, provided the copyright notice and this permission notice are included in
// all copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS",
// WITHOUT WARRANTY OF ANY KIND.

/// One of a theme's accent colors, with its name in that theme ("Mauve",
/// "Aqua", "Frost"…). `id` is what's saved.
public struct ThemeAccentColor: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let color: RGBColor

    public init(_ id: String, _ title: String, _ color: RGBColor) {
        self.id = id
        self.title = title
        self.color = color
    }
}

/// The colors a theme draws with: light or dark, its backgrounds, text, and
/// its own accents, in the theme's order.
public struct ThemePalette: Sendable, Equatable {
    public let isLight: Bool
    /// The main background.
    public let base: RGBColor
    /// A shade between `base` and `crust`.
    public let mantle: RGBColor
    /// The darkest background in dark themes; in light ones, the shade behind
    /// grouped rows (darker than `base`).
    public let crust: RGBColor
    /// Rows in dark themes' grouped lists: a shade lighter than `base`.
    public let surface0: RGBColor
    public let text: RGBColor
    public let accents: [ThemeAccentColor]
    /// The accent chosen until the user picks one.
    public let defaultAccent: String

    public init(
        isLight: Bool, base: RGBColor, mantle: RGBColor, crust: RGBColor, surface0: RGBColor, text: RGBColor,
        accents: [ThemeAccentColor], defaultAccent: String
    ) {
        self.isLight = isLight
        self.base = base
        self.mantle = mantle
        self.crust = crust
        self.surface0 = surface0
        self.text = text
        self.accents = accents
        self.defaultAccent = defaultAccent
    }

    /// The accent with this id, else the default, else the first.
    public func accent(_ id: String) -> ThemeAccentColor {
        accents.first { $0.id == id } ?? accents.first { $0.id == defaultAccent } ?? accents[0]
    }
}

/// A family of themes, for grouping in the picker and its credit.
public enum ThemeFamily: String, CaseIterable, Codable, Sendable {
    case catppuccin, gruvbox, nord, dracula, tokyoNight

    public var title: String {
        switch self {
        case .catppuccin: "Catppuccin"
        case .gruvbox: "Gruvbox"
        case .nord: "Nord"
        case .dracula: "Dracula"
        case .tokyoNight: "Tokyo Night"
        }
    }

    /// Where its colors come from, for the credit under the picker.
    public var source: String {
        switch self {
        case .catppuccin: "catppuccin.com"
        case .gruvbox: "github.com/morhetz/gruvbox"
        case .nord: "nordtheme.com"
        case .dracula: "draculatheme.com"
        case .tokyoNight: "github.com/folke/tokyonight.nvim"
        }
    }

    /// Its themes, in the picker's order.
    public var themes: [AppTheme] {
        AppTheme.allCases.filter { $0.family == self }
    }
}

extension CatppuccinPalette {
    /// As a theme palette: Catppuccin's 14 accents, Mauve first chosen.
    public var themePalette: ThemePalette {
        ThemePalette(
            isLight: self == .latte, base: base, mantle: mantle, crust: crust, surface0: surface0, text: text,
            accents: CatppuccinAccent.allCases.map { ThemeAccentColor($0.rawValue, $0.title, accent($0)) },
            defaultAccent: CatppuccinAccent.mauve.rawValue
        )
    }
}

extension ThemePalette {
    // MARK: Gruvbox (dark uses the bright accents, light the faded ones, as Gruvbox does)

    public static let gruvboxDark = ThemePalette(
        isLight: false,
        base: RGBColor(0x282828), mantle: RGBColor(0x1d2021), crust: RGBColor(0x1d2021),
        surface0: RGBColor(0x3c3836), text: RGBColor(0xebdbb2),
        accents: [
            ThemeAccentColor("red", "Red", RGBColor(0xfb4934)),
            ThemeAccentColor("orange", "Orange", RGBColor(0xfe8019)),
            ThemeAccentColor("yellow", "Yellow", RGBColor(0xfabd2f)),
            ThemeAccentColor("green", "Green", RGBColor(0xb8bb26)),
            ThemeAccentColor("aqua", "Aqua", RGBColor(0x8ec07c)),
            ThemeAccentColor("blue", "Blue", RGBColor(0x83a598)),
            ThemeAccentColor("purple", "Purple", RGBColor(0xd3869b)),
        ],
        defaultAccent: "orange"
    )

    public static let gruvboxLight = ThemePalette(
        isLight: true,
        base: RGBColor(0xfbf1c7), mantle: RGBColor(0xf2e5bc), crust: RGBColor(0xebdbb2),
        surface0: RGBColor(0xd5c4a1), text: RGBColor(0x3c3836),
        accents: [
            ThemeAccentColor("red", "Red", RGBColor(0x9d0006)),
            ThemeAccentColor("orange", "Orange", RGBColor(0xaf3a03)),
            ThemeAccentColor("yellow", "Yellow", RGBColor(0xb57614)),
            ThemeAccentColor("green", "Green", RGBColor(0x79740e)),
            ThemeAccentColor("aqua", "Aqua", RGBColor(0x427b58)),
            ThemeAccentColor("blue", "Blue", RGBColor(0x076678)),
            ThemeAccentColor("purple", "Purple", RGBColor(0x8f3f71)),
        ],
        defaultAccent: "orange"
    )

    // MARK: Nord (Polar Night backgrounds, Snow Storm text, Frost and Aurora accents)

    public static let nord = ThemePalette(
        isLight: false,
        base: RGBColor(0x2e3440), mantle: RGBColor(0x2e3440), crust: RGBColor(0x2e3440),
        surface0: RGBColor(0x3b4252), text: RGBColor(0xeceff4),
        accents: [
            ThemeAccentColor("frost1", "Frost Teal", RGBColor(0x8fbcbb)),
            ThemeAccentColor("frost2", "Frost Cyan", RGBColor(0x88c0d0)),
            ThemeAccentColor("frost3", "Frost Blue", RGBColor(0x81a1c1)),
            ThemeAccentColor("frost4", "Frost Deep", RGBColor(0x5e81ac)),
            ThemeAccentColor("red", "Aurora Red", RGBColor(0xbf616a)),
            ThemeAccentColor("orange", "Aurora Orange", RGBColor(0xd08770)),
            ThemeAccentColor("yellow", "Aurora Yellow", RGBColor(0xebcb8b)),
            ThemeAccentColor("green", "Aurora Green", RGBColor(0xa3be8c)),
            ThemeAccentColor("purple", "Aurora Purple", RGBColor(0xb48ead)),
        ],
        defaultAccent: "frost2"
    )

    // MARK: Dracula

    public static let dracula = ThemePalette(
        isLight: false,
        base: RGBColor(0x282a36), mantle: RGBColor(0x21222c), crust: RGBColor(0x191a21),
        surface0: RGBColor(0x44475a), text: RGBColor(0xf8f8f2),
        accents: [
            ThemeAccentColor("cyan", "Cyan", RGBColor(0x8be9fd)),
            ThemeAccentColor("green", "Green", RGBColor(0x50fa7b)),
            ThemeAccentColor("orange", "Orange", RGBColor(0xffb86c)),
            ThemeAccentColor("pink", "Pink", RGBColor(0xff79c6)),
            ThemeAccentColor("purple", "Purple", RGBColor(0xbd93f9)),
            ThemeAccentColor("red", "Red", RGBColor(0xff5555)),
            ThemeAccentColor("yellow", "Yellow", RGBColor(0xf1fa8c)),
        ],
        defaultAccent: "purple"
    )

    // MARK: Tokyo Night

    private static func tokyoAccents(
        blue: UInt32, cyan: UInt32, teal: UInt32, green: UInt32, yellow: UInt32, orange: UInt32, red: UInt32, magenta: UInt32
    ) -> [ThemeAccentColor] {
        [
            ThemeAccentColor("blue", "Blue", RGBColor(blue)),
            ThemeAccentColor("cyan", "Cyan", RGBColor(cyan)),
            ThemeAccentColor("teal", "Teal", RGBColor(teal)),
            ThemeAccentColor("green", "Green", RGBColor(green)),
            ThemeAccentColor("yellow", "Yellow", RGBColor(yellow)),
            ThemeAccentColor("orange", "Orange", RGBColor(orange)),
            ThemeAccentColor("red", "Red", RGBColor(red)),
            ThemeAccentColor("magenta", "Magenta", RGBColor(magenta)),
        ]
    }

    public static let tokyoNight = ThemePalette(
        isLight: false,
        base: RGBColor(0x1a1b26), mantle: RGBColor(0x16161e), crust: RGBColor(0x16161e),
        surface0: RGBColor(0x292e42), text: RGBColor(0xc0caf5),
        accents: tokyoAccents(blue: 0x7aa2f7, cyan: 0x7dcfff, teal: 0x1abc9c, green: 0x9ece6a, yellow: 0xe0af68, orange: 0xff9e64, red: 0xf7768e, magenta: 0xbb9af7),
        defaultAccent: "blue"
    )

    public static let tokyoStorm = ThemePalette(
        isLight: false,
        base: RGBColor(0x24283b), mantle: RGBColor(0x1f2335), crust: RGBColor(0x1f2335),
        surface0: RGBColor(0x292e42), text: RGBColor(0xc0caf5),
        accents: tokyoAccents(blue: 0x7aa2f7, cyan: 0x7dcfff, teal: 0x1abc9c, green: 0x9ece6a, yellow: 0xe0af68, orange: 0xff9e64, red: 0xf7768e, magenta: 0xbb9af7),
        defaultAccent: "blue"
    )

    public static let tokyoMoon = ThemePalette(
        isLight: false,
        base: RGBColor(0x222436), mantle: RGBColor(0x1e2030), crust: RGBColor(0x1e2030),
        surface0: RGBColor(0x2f334d), text: RGBColor(0xc8d3f5),
        accents: tokyoAccents(blue: 0x82aaff, cyan: 0x86e1fc, teal: 0x4fd6be, green: 0xc3e88d, yellow: 0xffc777, orange: 0xff966c, red: 0xff757f, magenta: 0xc099ff),
        defaultAccent: "blue"
    )

    public static let tokyoDay = ThemePalette(
        isLight: true,
        base: RGBColor(0xe1e2e7), mantle: RGBColor(0xd0d5e3), crust: RGBColor(0xd0d5e3),
        surface0: RGBColor(0xc4c8da), text: RGBColor(0x3760bf),
        accents: tokyoAccents(blue: 0x2e7de9, cyan: 0x007197, teal: 0x118c74, green: 0x587539, yellow: 0x8c6c3e, orange: 0xb15c00, red: 0xf52a65, magenta: 0x9854f1),
        defaultAccent: "blue"
    )
}
