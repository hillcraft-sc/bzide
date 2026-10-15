import Foundation
import os

/// Asks MET Norway (api.met.no, the Norwegian Meteorological Institute's
/// free forecast service) for the weather where the user is, for Weather
/// (Live). Only used once the user turns Live Weather on.
///
/// MET's terms, followed here: every request names the app and a contact
/// (`contact`, from the app's Info.plist; with none, nothing is asked);
/// coordinates are cut to 2 decimals (about a kilometer, within their limit
/// of 4); answers are kept until their `Expires` time and then checked with
/// `If-Modified-Since`; nothing is fetched while the visualizer is closed.
/// The data is CC BY 4.0 and credited in the app. MET logs the IP address of
/// apps that call it directly; `baseURL` can point at a caching proxy
/// instead, which MET asks apps with many users to use.
public actor METNorwayClient {
    public enum Failure: Error, Equatable, Sendable {
        /// No contact configured: MET requires one.
        case noContact
        case badResponse(Int)
        case noForecast
    }

    public static let defaultBaseURL = URL(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact") ?? URL(filePath: "/")

    private let transport: any HTTPTransport
    private let baseURL: URL
    private let contact: String
    private let now: @Sendable () -> Date
    private var cached: [String: Cached] = [:]
    private static let logger = Logger(subsystem: "MusicApp", category: "METNorway")

    private struct Cached {
        var weather: LiveWeather
        var expires: Date
        var lastModified: String?
    }

    public init(
        contact: String, transport: any HTTPTransport = URLSessionTransport(), baseURL: URL = METNorwayClient.defaultBaseURL,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.contact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
        self.baseURL = baseURL
        self.now = now
    }

    /// "Bzide/1.0 https://example.com": the app and how to reach its maker.
    var userAgent: String { "Bzide/1.0 \(contact)" }

    /// The weather now at `place`. A forecast is reused until it expires; if
    /// a new one can't be fetched, the last one stands (and the error is
    /// thrown only when there's none).
    public func weather(at place: SkyClock.Place) async throws -> LiveWeather {
        guard !contact.isEmpty else { throw Failure.noContact }
        let (latitude, longitude) = Self.rounded(place)
        let key = "\(latitude),\(longitude)"
        let date = now()
        if let entry = cached[key], entry.expires > date { return entry.weather }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "lat", value: latitude), .init(name: "lon", value: longitude)]
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let lastModified = cached[key]?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        do {
            let (data, response) = try await transport.data(for: request)
            let expires = Self.httpDate(response.value(forHTTPHeaderField: "Expires")) ?? date.addingTimeInterval(30 * 60)
            if response.statusCode == 304, var entry = cached[key] {
                entry.expires = expires
                cached[key] = entry
                return entry.weather
            }
            guard (200..<300).contains(response.statusCode) else {
                Self.logger.error("Forecast failed: HTTP \(response.statusCode, privacy: .public)")
                throw Failure.badResponse(response.statusCode)
            }
            let weather = try Self.current(in: data, at: date)
            cached[key] = Cached(weather: weather, expires: expires, lastModified: response.value(forHTTPHeaderField: "Last-Modified"))
            return weather
        } catch {
            if let stale = cached[key]?.weather { return stale }
            throw error
        }
    }

    // MARK: - Reading the forecast

    private struct Forecast: Decodable {
        struct Properties: Decodable { let timeseries: [Entry] }
        struct Entry: Decodable {
            let time: Date
            let data: EntryData
        }
        struct EntryData: Decodable {
            let instant: Instant?
            let next_1_hours: Period?
            let next_6_hours: Period?
        }
        struct Instant: Decodable { let details: Details? }
        struct Details: Decodable {
            let cloud_area_fraction: Double?
            let wind_speed: Double?
        }
        struct Period: Decodable {
            struct Summary: Decodable { let symbol_code: String? }
            let summary: Summary?
        }
        let properties: Properties
    }

    /// The entry for the hour that `date` is in (the latest one starting at
    /// or before it), else the first.
    static func current(in data: Data, at date: Date) throws -> LiveWeather {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode(Forecast.self, from: data).properties.timeseries
        guard let first = entries.first else { throw Failure.noForecast }
        let entry = entries.last { $0.time <= date } ?? first
        let code = entry.data.next_1_hours?.summary?.symbol_code ?? entry.data.next_6_hours?.summary?.symbol_code
        guard let code else { throw Failure.noForecast }
        return LiveWeather(
            symbolCode: code,
            cloudAreaFraction: entry.data.instant?.details?.cloud_area_fraction,
            windSpeed: entry.data.instant?.details?.wind_speed
        )
    }

    /// To 2 decimals, written with a dot whatever the phone's language.
    static func rounded(_ place: SkyClock.Place) -> (String, String) {
        func format(_ value: Double) -> String {
            String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        return (format(place.latitude), format(place.longitude))
    }

    private static func httpDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}
