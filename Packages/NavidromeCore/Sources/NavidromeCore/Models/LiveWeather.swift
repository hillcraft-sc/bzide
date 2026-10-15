import Foundation

/// The weather right now, for Weather (Live): what kind of sky, what's
/// falling and how hard, thunder, fog and wind. Read from MET Norway's
/// forecast (`METNorwayClient`), or forced in debug builds for testing.
public struct LiveWeather: Equatable, Sendable {
    public enum Precipitation: String, Sendable, CaseIterable {
        case none, rain, sleet, snow
    }

    /// 0 (clear) ... 1 (overcast).
    public var cloudCover: Double
    public var precipitation: Precipitation
    /// 0 (none) ... 1 (heavy): light 0.35, normal 0.65, heavy 1.
    public var intensity: Double
    /// Passing showers rather than steady rain or snow.
    public var isShowers: Bool
    public var isThunder: Bool
    public var isFog: Bool
    /// Meters per second.
    public var windSpeed: Double

    public init(
        cloudCover: Double, precipitation: Precipitation = .none, intensity: Double = 0,
        isShowers: Bool = false, isThunder: Bool = false, isFog: Bool = false, windSpeed: Double = 2
    ) {
        self.cloudCover = cloudCover
        self.precipitation = precipitation
        self.intensity = precipitation == .none ? 0 : intensity
        self.isShowers = isShowers
        self.isThunder = isThunder
        self.isFog = isFog
        self.windSpeed = windSpeed
    }

    /// A clear sky with a light breeze: before any weather is known, or with
    /// Live Weather off.
    public static let fair = LiveWeather(cloudCover: 0.2)

    /// From MET Norway's symbol code (e.g. "lightrainshowers_day",
    /// "heavysnowandthunder"), with its cloud cover (percent) and wind speed
    /// when given. Codes combine parts (clear sky, fair, partly cloudy,
    /// cloudy, fog; rain, sleet, snow; light, heavy; showers; thunder), so
    /// they're read by part, which also copes with codes added later and the
    /// "lightssleet" spelling MET uses.
    public init(symbolCode: String, cloudAreaFraction: Double?, windSpeed: Double?) {
        let code = symbolCode.split(separator: "_").first.map(String.init)?.lowercased() ?? ""
        let precipitation: Precipitation =
            code.contains("snow") ? .snow : code.contains("sleet") ? .sleet : code.contains("rain") ? .rain : .none
        let intensity = code.hasPrefix("light") ? 0.35 : code.hasPrefix("heavy") ? 1 : 0.65
        let cloudsFromCode: Double = switch code {
        case "clearsky": 0.05
        case "fair": 0.2
        case "partlycloudy": 0.5
        case "fog": 0.7
        default: precipitation == .none ? 0.9 : (code.contains("showers") ? 0.65 : 0.9)
        }
        self.init(
            cloudCover: cloudAreaFraction.map { min(max($0 / 100, 0), 1) } ?? cloudsFromCode,
            precipitation: precipitation,
            intensity: intensity,
            isShowers: code.contains("showers"),
            isThunder: code.contains("thunder"),
            isFog: code == "fog",
            windSpeed: windSpeed ?? 2
        )
    }
}
