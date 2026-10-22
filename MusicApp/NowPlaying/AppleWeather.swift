import CoreLocation
import NavidromeCore
import WeatherKit

/// Apple Weather (WeatherKit) for Weather (Live): the weather now where the
/// user is, from observations and radar where Apple has them. Apple gets the
/// same rounded coordinates MET Norway would (about a kilometer). Apple's
/// terms ask for its mark and a link to its legal page wherever its data is
/// shown, so the attribution comes with it.
struct AppleWeather {
    struct Attribution: Equatable {
        /// The " Weather" mark for dark backgrounds.
        let markURL: URL
        let legalPageURL: URL
    }

    func weather(at place: SkyClock.Place) async throws -> (LiveWeather, Attribution) {
        let service = WeatherService.shared
        // Two decimals, as for MET Norway.
        let location = CLLocation(latitude: (place.latitude * 100).rounded() / 100, longitude: (place.longitude * 100).rounded() / 100)
        let current = try await service.weather(for: location, including: .current)
        let attribution = try await service.attribution
        let weather = LiveWeather(
            appleCondition: String(describing: current.condition),
            cloudCover: current.cloudCover,
            // A speed in WeatherKit; meters a second to millimeters an hour.
            precipitationRate: current.precipitationIntensity.converted(to: .metersPerSecond).value * 3_600_000,
            windSpeed: current.wind.speed.converted(to: .metersPerSecond).value
        )
        return (weather, Attribution(markURL: attribution.combinedMarkDarkURL, legalPageURL: attribution.legalPageURL))
    }
}
