import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct AppearanceTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AppearanceTests-\(UUID())")!
    }

    @Test func defaultsToTheSystemThemeAndMauve() {
        let model = AppearanceModel(defaults: freshDefaults())
        #expect(model.settings == AppearanceSettings(theme: .system, accent: .mauve))
        #expect(model.palette == nil)
    }

    @Test func choiceSurvivesARestart() {
        let defaults = freshDefaults()
        let first = AppearanceModel(defaults: defaults)
        first.settings.theme = .mocha
        first.settings.accent = .peach

        let second = AppearanceModel(defaults: defaults)
        #expect(second.settings == AppearanceSettings(theme: .mocha, accent: .peach))
        #expect(second.palette == CatppuccinPalette.mocha.themePalette)
    }

    @Test func theSystemAccentDefaultsToBzideRedAndIsKept() {
        let defaults = freshDefaults()
        let first = AppearanceModel(defaults: defaults)
        #expect(first.settings.systemAccent == .bzide)
        #expect(SystemAccent.bzide.title == "Bzide Red")
        first.settings.systemAccent = .teal
        #expect(AppearanceModel(defaults: defaults).settings.systemAccent == .teal)
    }

    @Test func settingsSavedBeforeTheSystemAccentKeepTheirChoices() {
        let defaults = freshDefaults()
        defaults.set(Data("{\"theme\": \"dark\", \"accent\": \"peach\"}".utf8), forKey: AppearanceModel.key)
        #expect(AppearanceModel(defaults: defaults).settings == AppearanceSettings(theme: .dark, accent: .peach, systemAccent: .bzide))
    }

    @Test func unknownThemeFallsBackButKeepsTheAccent() {
        let defaults = freshDefaults()
        defaults.set(Data("{\"theme\": \"neon\", \"accent\": \"teal\"}".utf8), forKey: AppearanceModel.key)
        #expect(AppearanceModel(defaults: defaults).settings == AppearanceSettings(theme: .system, accent: .teal))
    }

    @Test func unreadableSettingsFallBackToDefaults() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: AppearanceModel.key)
        #expect(AppearanceModel(defaults: defaults).settings == AppearanceSettings())
    }

    @Test func eachThemeForcesItsModeExceptSystem() {
        #expect(AppTheme.system.isDark == nil)
        #expect(AppTheme.light.isDark == false)
        #expect(AppTheme.latte.isDark == false)
        #expect([AppTheme.dark, .frappe, .macchiato, .mocha].allSatisfy { $0.isDark == true })
    }

    @Test func onlyCatppuccinThemesHaveAFlavor() {
        #expect([AppTheme.system, .light, .dark].allSatisfy { $0.flavor == nil })
        #expect([AppTheme.latte, .frappe, .macchiato, .mocha].map(\.flavor) == [.latte, .frappe, .macchiato, .mocha])
    }

    @Test func paletteMatchesCatppuccinsPublishedValues() {
        // Spot checks against https://github.com/catppuccin/palette.
        #expect(CatppuccinPalette.mocha.base == RGBColor(0x1e1e2e))
        #expect(CatppuccinPalette.mocha.text == RGBColor(0xcdd6f4))
        #expect(CatppuccinPalette.mocha.accent(.mauve) == RGBColor(0xcba6f7))
        #expect(CatppuccinPalette.latte.base == RGBColor(0xeff1f5))
        #expect(CatppuccinPalette.latte.accent(.mauve) == RGBColor(0x8839ef))
        #expect(CatppuccinPalette.frappe.surface0 == RGBColor(0x414559))
        #expect(CatppuccinPalette.macchiato.accent(.lavender) == RGBColor(0xb7bdf8))
    }

    @Test func everyFlavorHasEveryAccent() {
        for flavor in CatppuccinFlavor.allCases {
            #expect(flavor.palette.accents.count == CatppuccinAccent.allCases.count)
        }
    }

    @Test func colorComponents() {
        let color = RGBColor(0xff8000)
        #expect(color.red == 1)
        #expect(abs(color.green - 128.0 / 255) < 0.0001)
        #expect(color.blue == 0)
    }
}

/// Gitea #13: more theme families.
struct ThemeFamilyTests {
    private let themed = AppTheme.allCases.filter { $0.family != nil }

    @Test func everyThemeHasAPaletteAndForcesItsMode() {
        for theme in themed {
            let palette = theme.palette
            #expect(palette != nil, "\(theme)")
            #expect(theme.isDark == palette.map { !$0.isLight }, "\(theme)")
            #expect((palette?.accents.count ?? 0) >= 7, "\(theme)")
            // The default accent is one of its own.
            #expect(palette.map { p in p.accents.contains { $0.id == p.defaultAccent } } ?? false, "\(theme)")
        }
        #expect(AppTheme.gruvboxLight.isDark == false)
        #expect(AppTheme.tokyoDay.isDark == false)
        #expect(AppTheme.nord.isDark == true)
        #expect(AppTheme.system.palette == nil)
    }

    @Test func familiesListTheirThemesInOrder() {
        #expect(ThemeFamily.catppuccin.themes == [.latte, .frappe, .macchiato, .mocha])
        #expect(ThemeFamily.gruvbox.themes == [.gruvboxDark, .gruvboxLight])
        #expect(ThemeFamily.tokyoNight.themes == [.tokyoNight, .tokyoStorm, .tokyoMoon, .tokyoDay])
        #expect(Set(themed.compactMap(\.family)) == Set(ThemeFamily.allCases))
    }

    @Test func catppuccinIsUnchanged() {
        let mocha = AppTheme.mocha.palette
        #expect(mocha?.accents.count == 14)
        #expect(mocha?.base == CatppuccinPalette.mocha.base)
        #expect(mocha?.accent("mauve").color == CatppuccinPalette.mocha.accent(.mauve))
        #expect(AppTheme.latte.palette?.isLight == true)
    }

    @Test func eachFamilyKeepsItsOwnAccent() {
        var settings = AppearanceSettings(theme: .nord)
        // Nothing chosen yet: the family's default.
        #expect(settings.themeAccent?.id == "frost2")
        settings.setAccent("green", for: .nord)
        settings.setAccent("pink", for: .catppuccin)
        settings.theme = .dracula
        #expect(settings.themeAccent?.id == "purple")
        settings.theme = .nord
        #expect(settings.themeAccent?.id == "green")
        settings.theme = .mocha
        #expect(settings.themeAccent?.id == "pink")
        #expect(settings.accent == .pink)
        // An unknown id falls back to the default.
        settings.theme = .gruvboxDark
        settings.setAccent("nonsense", for: .gruvbox)
        #expect(settings.themeAccent?.id == "orange")
    }

    @Test func olderSettingsStillLoad() throws {
        let old = try JSONDecoder().decode(AppearanceSettings.self, from: Data(#"{"theme":"mocha","accent":"teal"}"#.utf8))
        #expect(old.theme == .mocha)
        #expect(old.themeAccent?.id == "teal")
        #expect(old.familyAccents.isEmpty)
        let saved = try JSONDecoder().decode(AppearanceSettings.self, from: JSONEncoder().encode(AppearanceSettings(theme: .tokyoMoon, familyAccents: ["tokyoNight": "cyan"])))
        #expect(saved.themeAccent?.id == "cyan")
    }
}
