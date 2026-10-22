import CoreLocation
import MapKit
import NavidromeCore
import os

/// Feeds Weather (Live) its place and weather while it's open: the phone's
/// location (asked for once; approximate is enough) or the city typed in
/// Settings, then the weather there, checked every 10 minutes: from Apple
/// Weather, or MET Norway when that's the choice or Apple's can't be had
/// (MET's answer is reused until it expires). Nothing is asked with Live
/// Weather off, and nothing runs once the visualizer closes.
@MainActor
@Observable
final class LiveWeatherSource {
    enum Status: Equatable {
        /// Live Weather is off: time of day only.
        case off
        case locating
        /// No location allowed and no city (or the city wasn't found).
        case noPlace
        case live
        /// MET couldn't be reached and there's nothing to fall back on.
        case unavailable
    }

    private(set) var status = Status.off
    /// Apple's mark and legal page while its weather is shown; `nil` for MET Norway.
    private(set) var appleAttribution: AppleWeather.Attribution?
    @ObservationIgnored private let met: METNorwayClient
    @ObservationIgnored private let apple = AppleWeather()
    private static let logger = Logger(subsystem: "MusicApp", category: "LiveWeather")
    /// The place found for the current settings, so reopening doesn't ask again.
    @ObservationIgnored private var found: (key: String, place: SkyClock.Place)?

    static let refresh: Duration = .seconds(10 * 60)
    /// How long to wait for the phone's location before trying the city.
    static let locationTimeout: Duration = .seconds(30)

    init(met: METNorwayClient) {
        self.met = met
    }

    /// Keeps `state` up to date until cancelled (the visualizer closing, or
    /// the settings changing).
    func run(into state: LiveWeatherState, settings: StreamingSettings) async {
        guard settings.liveWeather else {
            status = .off
            state.place = .guess()
            state.weather = .fair
            return
        }
        status = .locating
        guard let place = await place(for: settings) else {
            status = .noPlace
            state.weather = .fair
            return
        }
        state.place = place
        while !Task.isCancelled {
            do {
                state.weather = try await weather(at: place, from: settings.liveWeatherSource)
                status = .live
            } catch {
                if Task.isCancelled { return }
                status = .unavailable
            }
            try? await Task.sleep(for: Self.refresh)
        }
    }

    private func weather(at place: SkyClock.Place, from source: LiveWeatherProvider) async throws -> LiveWeather {
        if source == .apple {
            do {
                let (weather, attribution) = try await apple.weather(at: place)
                appleAttribution = attribution
                return weather
            } catch {
                if Task.isCancelled { throw CancellationError() }
                // Not set up for WeatherKit, Apple's service down, or over its limit.
                Self.logger.error("Apple Weather failed, using MET Norway: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
        appleAttribution = nil
        return try await met.weather(at: place)
    }

    // MARK: - Finding the place

    private func place(for settings: StreamingSettings) async -> SkyClock.Place? {
        let city = settings.liveWeatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "\(settings.liveWeatherUsesLocation)|\(city)"
        if let found, found.key == key { return found.place }
        var place: SkyClock.Place?
        if settings.liveWeatherUsesLocation {
            place = await currentLocation()
        }
        if place == nil, !city.isEmpty {
            // The match Settings saved, else a lookup now.
            if let saved = settings.liveWeatherPlace, saved.matches(city) {
                place = saved.place
            } else {
                place = await Self.lookUp(city)?.place
            }
        }
        if let place { found = (key, place) }
        return place
    }

    /// One location from the phone, asking permission the first time.
    /// `nil` if it's not allowed, or none comes in time.
    private func currentLocation() async -> SkyClock.Place? {
        let lookup = Task { @MainActor () -> SkyClock.Place? in
            // Holding the session asks for when-in-use permission if needed.
            let session = CLServiceSession(authorization: .whenInUse)
            defer { session.invalidate() }
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                        return nil
                    }
                    if let location = update.location {
                        return SkyClock.Place(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                    }
                }
            } catch {}
            return nil
        }
        // Gives up after a while (no fix indoors, or the permission prompt left open).
        let timeout = Task {
            try? await Task.sleep(for: Self.locationTimeout)
            lookup.cancel()
        }
        defer { timeout.cancel() }
        return await withTaskCancellationHandler {
            await lookup.value
        } onCancel: {
            lookup.cancel()
        }
    }

    /// What Apple's geocoder makes of a typed place (a city and state, or a
    /// postal code): its best match, named like "Springfield, IL, United
    /// States", or `nil` if there's none.
    static func lookUp(_ typed: String) async -> LiveWeatherPlace? {
        let query = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let request = MKGeocodingRequest(addressString: query),
              let item = try? await request.mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        let name = item.addressRepresentations?.cityWithContext(.full)
            ?? item.address?.shortAddress
            ?? item.name
            ?? query
        return LiveWeatherPlace(query: query, name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
