import CoreLocation
import MapKit
import NavidromeCore

/// Feeds Weather (Live) its place and weather while it's open: the phone's
/// location (asked for once; approximate is enough) or the city typed in
/// Settings, then MET Norway's forecast for there, checked every 10 minutes
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
    @ObservationIgnored private let met: METNorwayClient
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
                state.weather = try await met.weather(at: place)
                status = .live
            } catch {
                if Task.isCancelled { return }
                status = .unavailable
            }
            try? await Task.sleep(for: Self.refresh)
        }
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
            place = await geocode(city)
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

    /// The city's coordinates, through Apple's geocoder.
    private func geocode(_ city: String) async -> SkyClock.Place? {
        guard let request = MKGeocodingRequest(addressString: city),
              let item = try? await request.mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        return SkyClock.Place(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
