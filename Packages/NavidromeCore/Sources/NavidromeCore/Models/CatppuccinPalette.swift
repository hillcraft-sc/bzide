// Catppuccin palette, copied from https://github.com/catppuccin/palette (palette.json).
//
// MIT License. Copyright (c) 2021 Catppuccin.
// Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software and associated documentation files, to deal in the Software without
// restriction, provided the copyright notice and this permission notice are included in
// all copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS",
// WITHOUT WARRANTY OF ANY KIND. Full text: https://github.com/catppuccin/palette/blob/main/LICENSE

/// A colour as 0xRRGGBB. Kept free of UI frameworks so other clients can share it.
public struct RGBColor: Sendable, Equatable, Hashable {
    public let hex: UInt32

    public init(_ hex: UInt32) {
        self.hex = hex
    }

    /// 0–1 components, for building a platform colour.
    public var red: Double { Double((hex >> 16) & 0xFF) / 255 }
    public var green: Double { Double((hex >> 8) & 0xFF) / 255 }
    public var blue: Double { Double(hex & 0xFF) / 255 }
}

/// One Catppuccin flavour's colours. The neutrals run from `text` (foreground)
/// down to `crust` (the darkest background in dark flavours, lightest-but-one in Latte).
public struct CatppuccinPalette: Sendable, Equatable {
    public let text: RGBColor
    public let subtext1: RGBColor
    public let subtext0: RGBColor
    public let overlay2: RGBColor
    public let overlay1: RGBColor
    public let overlay0: RGBColor
    public let surface2: RGBColor
    public let surface1: RGBColor
    public let surface0: RGBColor
    public let base: RGBColor
    public let mantle: RGBColor
    public let crust: RGBColor
    let accents: [CatppuccinAccent: RGBColor]

    public func accent(_ accent: CatppuccinAccent) -> RGBColor {
        accents[accent] ?? RGBColor(0x000000)
    }
}

extension CatppuccinFlavor {
    public var palette: CatppuccinPalette {
        switch self {
        case .latte: .latte
        case .frappe: .frappe
        case .macchiato: .macchiato
        case .mocha: .mocha
        }
    }
}

extension CatppuccinPalette {
    public static let latte = CatppuccinPalette(
        text: RGBColor(0x4c4f69),
        subtext1: RGBColor(0x5c5f77),
        subtext0: RGBColor(0x6c6f85),
        overlay2: RGBColor(0x7c7f93),
        overlay1: RGBColor(0x8c8fa1),
        overlay0: RGBColor(0x9ca0b0),
        surface2: RGBColor(0xacb0be),
        surface1: RGBColor(0xbcc0cc),
        surface0: RGBColor(0xccd0da),
        base: RGBColor(0xeff1f5),
        mantle: RGBColor(0xe6e9ef),
        crust: RGBColor(0xdce0e8),
        accents: [
            .rosewater: RGBColor(0xdc8a78),
            .flamingo: RGBColor(0xdd7878),
            .pink: RGBColor(0xea76cb),
            .mauve: RGBColor(0x8839ef),
            .red: RGBColor(0xd20f39),
            .maroon: RGBColor(0xe64553),
            .peach: RGBColor(0xfe640b),
            .yellow: RGBColor(0xdf8e1d),
            .green: RGBColor(0x40a02b),
            .teal: RGBColor(0x179299),
            .sky: RGBColor(0x04a5e5),
            .sapphire: RGBColor(0x209fb5),
            .blue: RGBColor(0x1e66f5),
            .lavender: RGBColor(0x7287fd),
        ]
    )

    public static let frappe = CatppuccinPalette(
        text: RGBColor(0xc6d0f5),
        subtext1: RGBColor(0xb5bfe2),
        subtext0: RGBColor(0xa5adce),
        overlay2: RGBColor(0x949cbb),
        overlay1: RGBColor(0x838ba7),
        overlay0: RGBColor(0x737994),
        surface2: RGBColor(0x626880),
        surface1: RGBColor(0x51576d),
        surface0: RGBColor(0x414559),
        base: RGBColor(0x303446),
        mantle: RGBColor(0x292c3c),
        crust: RGBColor(0x232634),
        accents: [
            .rosewater: RGBColor(0xf2d5cf),
            .flamingo: RGBColor(0xeebebe),
            .pink: RGBColor(0xf4b8e4),
            .mauve: RGBColor(0xca9ee6),
            .red: RGBColor(0xe78284),
            .maroon: RGBColor(0xea999c),
            .peach: RGBColor(0xef9f76),
            .yellow: RGBColor(0xe5c890),
            .green: RGBColor(0xa6d189),
            .teal: RGBColor(0x81c8be),
            .sky: RGBColor(0x99d1db),
            .sapphire: RGBColor(0x85c1dc),
            .blue: RGBColor(0x8caaee),
            .lavender: RGBColor(0xbabbf1),
        ]
    )

    public static let macchiato = CatppuccinPalette(
        text: RGBColor(0xcad3f5),
        subtext1: RGBColor(0xb8c0e0),
        subtext0: RGBColor(0xa5adcb),
        overlay2: RGBColor(0x939ab7),
        overlay1: RGBColor(0x8087a2),
        overlay0: RGBColor(0x6e738d),
        surface2: RGBColor(0x5b6078),
        surface1: RGBColor(0x494d64),
        surface0: RGBColor(0x363a4f),
        base: RGBColor(0x24273a),
        mantle: RGBColor(0x1e2030),
        crust: RGBColor(0x181926),
        accents: [
            .rosewater: RGBColor(0xf4dbd6),
            .flamingo: RGBColor(0xf0c6c6),
            .pink: RGBColor(0xf5bde6),
            .mauve: RGBColor(0xc6a0f6),
            .red: RGBColor(0xed8796),
            .maroon: RGBColor(0xee99a0),
            .peach: RGBColor(0xf5a97f),
            .yellow: RGBColor(0xeed49f),
            .green: RGBColor(0xa6da95),
            .teal: RGBColor(0x8bd5ca),
            .sky: RGBColor(0x91d7e3),
            .sapphire: RGBColor(0x7dc4e4),
            .blue: RGBColor(0x8aadf4),
            .lavender: RGBColor(0xb7bdf8),
        ]
    )

    public static let mocha = CatppuccinPalette(
        text: RGBColor(0xcdd6f4),
        subtext1: RGBColor(0xbac2de),
        subtext0: RGBColor(0xa6adc8),
        overlay2: RGBColor(0x9399b2),
        overlay1: RGBColor(0x7f849c),
        overlay0: RGBColor(0x6c7086),
        surface2: RGBColor(0x585b70),
        surface1: RGBColor(0x45475a),
        surface0: RGBColor(0x313244),
        base: RGBColor(0x1e1e2e),
        mantle: RGBColor(0x181825),
        crust: RGBColor(0x11111b),
        accents: [
            .rosewater: RGBColor(0xf5e0dc),
            .flamingo: RGBColor(0xf2cdcd),
            .pink: RGBColor(0xf5c2e7),
            .mauve: RGBColor(0xcba6f7),
            .red: RGBColor(0xf38ba8),
            .maroon: RGBColor(0xeba0ac),
            .peach: RGBColor(0xfab387),
            .yellow: RGBColor(0xf9e2af),
            .green: RGBColor(0xa6e3a1),
            .teal: RGBColor(0x94e2d5),
            .sky: RGBColor(0x89dceb),
            .sapphire: RGBColor(0x74c7ec),
            .blue: RGBColor(0x89b4fa),
            .lavender: RGBColor(0xb4befe),
        ]
    )
}
