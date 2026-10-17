import Foundation
import Observation

/// The user's appearance settings, saved to `UserDefaults` on every change.
/// Each account has its own (see `AccountSettings`); they stay across sign-outs.
@MainActor
@Observable
public final class AppearanceModel {
    public var settings: AppearanceSettings {
        didSet { save() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    static let key = "appearanceSettings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = Self.load(defaults)
    }

    /// Reads them again, after another account's settings were put in place.
    public func reload() {
        settings = Self.load(defaults)
    }

    private static func load(_ defaults: UserDefaults) -> AppearanceSettings {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(AppearanceSettings.self, from: $0) } ?? AppearanceSettings()
    }

    /// The Catppuccin colors in use, or `nil` for the system themes.
    public var palette: CatppuccinPalette? {
        settings.theme.flavor?.palette
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
