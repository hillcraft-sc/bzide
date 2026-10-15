import Foundation
import Testing
@testable import NavidromeCore

struct LiveWeatherCodeTests {
    private func weather(_ code: String) -> LiveWeather {
        LiveWeather(symbolCode: code, cloudAreaFraction: nil, windSpeed: nil)
    }

    @Test func skiesAreReadFromTheCode() {
        #expect(weather("clearsky_day").cloudCover < 0.1)
        #expect(weather("fair_night").cloudCover == 0.2)
        #expect(weather("partlycloudy_polartwilight").cloudCover == 0.5)
        #expect(weather("cloudy").cloudCover == 0.9)
        #expect(weather("clearsky_day").precipitation == .none)
        #expect(weather("fog").isFog)
    }

    @Test func precipitationKindStrengthShowersAndThunder() {
        let light = weather("lightrainshowers_day")
        #expect(light.precipitation == .rain)
        #expect(light.intensity == 0.35)
        #expect(light.isShowers)
        #expect(!light.isThunder)

        let storm = weather("heavyrainandthunder")
        #expect(storm.precipitation == .rain)
        #expect(storm.intensity == 1)
        #expect(storm.isThunder)
        #expect(!storm.isShowers)

        #expect(weather("sleet").precipitation == .sleet)
        #expect(weather("sleet").intensity == 0.65)
        #expect(weather("heavysnowshowers_night").precipitation == .snow)
        // MET's own spelling of light sleet showers with thunder.
        let odd = weather("lightssleetshowersandthunder_day")
        #expect(odd.precipitation == .sleet)
        #expect(odd.isThunder)
    }

    @Test func measuredCloudsAndWindWin() {
        let measured = LiveWeather(symbolCode: "partlycloudy_day", cloudAreaFraction: 64.5, windSpeed: 7.2)
        #expect(abs(measured.cloudCover - 0.645) < 0.0001)
        #expect(measured.windSpeed == 7.2)
    }
}

struct LiveWeatherSettingsTests {
    @Test func liveWeatherIsOffByDefault() throws {
        let fresh = StreamingSettings()
        #expect(fresh.liveWeather == false)
        #expect(fresh.liveWeatherUsesLocation)
        #expect(fresh.liveWeatherCity.isEmpty)
        let older = try JSONDecoder().decode(StreamingSettings.self, from: Data(#"{"wifiQuality":0,"cellularQuality":192}"#.utf8))
        #expect(older.liveWeather == false)
        #expect(older.liveWeatherUsesLocation)
    }
}

struct METNorwayClientTests {
    private static let oslo = SkyClock.Place(latitude: 59.913_868, longitude: 10.752_245)

    /// A forecast with entries for 22:00 and 23:00 UTC.
    private static let forecast = #"""
    {"properties":{"meta":{"updated_at":"2026-10-15T22:29:57Z"},"timeseries":[
      {"time":"2026-10-15T22:00:00Z","data":{"instant":{"details":{"cloud_area_fraction":10.0,"wind_speed":1.0}},"next_1_hours":{"summary":{"symbol_code":"clearsky_night"},"details":{"precipitation_amount":0.0}}}},
      {"time":"2026-10-15T23:00:00Z","data":{"instant":{"details":{"cloud_area_fraction":95.0,"wind_speed":9.0}},"next_1_hours":{"summary":{"symbol_code":"heavyrainandthunder"},"details":{"precipitation_amount":4.2}}}}
    ]}}
    """#

    private static func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    private final class Clock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private func client(_ transport: FakeTransport, clock: Clock, contact: String = "https://example.test") -> METNorwayClient {
        METNorwayClient(contact: contact, transport: transport, now: { clock.now })
    }

    private static let headers = ["Expires": "Thu, 15 Oct 2026 23:30:00 GMT", "Last-Modified": "Thu, 15 Oct 2026 23:00:01 GMT"]

    @Test func asksWithRoundedCoordinatesAndItsName() async throws {
        let transport = FakeTransport(.json(Self.forecast, headers: Self.headers))
        let weather = try await client(transport, clock: Clock(Self.at("2026-10-15T23:10:00Z"))).weather(at: Self.oslo)
        // The 23:00 hour: a thunderstorm.
        #expect(weather.isThunder)
        #expect(weather.precipitation == .rain)
        #expect(abs(weather.cloudCover - 0.95) < 0.0001)
        let request = try #require(await transport.requests.first)
        #expect(request.url?.queryParameters["lat"] == "59.91")
        #expect(request.url?.queryParameters["lon"] == "10.75")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Bzide/1.0 https://example.test")
    }

    @Test func picksTheHourItIsNow() throws {
        let earlier = try METNorwayClient.current(in: Data(Self.forecast.utf8), at: Self.at("2026-10-15T22:40:00Z"))
        #expect(earlier.precipitation == .none)
        #expect(earlier.cloudCover == 0.1)
        // Before the first entry: the first.
        let before = try METNorwayClient.current(in: Data(Self.forecast.utf8), at: Self.at("2026-10-15T20:00:00Z"))
        #expect(before.precipitation == .none)
    }

    @Test func aForecastIsKeptUntilItExpiresThenChecked() async throws {
        let transport = FakeTransport(
            .json(Self.forecast, headers: Self.headers),
            .json("", status: 304, headers: ["Expires": "Fri, 16 Oct 2026 00:00:00 GMT"])
        )
        let clock = Clock(Self.at("2026-10-15T23:10:00Z"))
        let met = client(transport, clock: clock)
        _ = try await met.weather(at: Self.oslo)
        clock.now = Self.at("2026-10-15T23:20:00Z")
        _ = try await met.weather(at: Self.oslo)
        #expect(await transport.requests.count == 1)

        // Expired: asked again, saying what it has; "not modified" keeps it.
        clock.now = Self.at("2026-10-15T23:40:00Z")
        let checked = try await met.weather(at: Self.oslo)
        #expect(checked.isThunder)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[1].value(forHTTPHeaderField: "If-Modified-Since") == "Thu, 15 Oct 2026 23:00:01 GMT")
        // And the new expiry holds.
        clock.now = Self.at("2026-10-15T23:50:00Z")
        _ = try await met.weather(at: Self.oslo)
        #expect(await transport.requests.count == 2)
    }

    @Test func offlineTheLastForecastStands() async throws {
        let transport = FakeTransport(.json(Self.forecast, headers: Self.headers), .failure(.notConnectedToInternet))
        let clock = Clock(Self.at("2026-10-15T23:10:00Z"))
        let met = client(transport, clock: clock)
        _ = try await met.weather(at: Self.oslo)
        clock.now = Self.at("2026-10-16T01:00:00Z")
        #expect(try await met.weather(at: Self.oslo).isThunder)
        // With nothing to fall back on, the failure shows.
        let fresh = client(FakeTransport(.failure(.notConnectedToInternet)), clock: clock)
        await #expect(throws: URLError.self) { try await fresh.weather(at: Self.oslo) }
    }

    @Test func withoutAContactNothingIsAsked() async {
        let transport = FakeTransport()
        let met = client(transport, clock: Clock(.now), contact: "  ")
        await #expect(throws: METNorwayClient.Failure.noContact) { try await met.weather(at: Self.oslo) }
        #expect(await transport.requests.isEmpty)
    }
}
