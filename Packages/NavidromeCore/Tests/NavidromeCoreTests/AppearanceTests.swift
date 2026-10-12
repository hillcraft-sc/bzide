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
        #expect(second.palette == .mocha)
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

    @Test func colourComponents() {
        let color = RGBColor(0xff8000)
        #expect(color.red == 1)
        #expect(abs(color.green - 128.0 / 255) < 0.0001)
        #expect(color.blue == 0)
    }
}
