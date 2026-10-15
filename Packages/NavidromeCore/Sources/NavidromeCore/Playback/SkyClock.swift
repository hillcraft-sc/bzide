import Foundation

/// Where the sun and moon are, worked out on the phone from a place and a
/// moment, for Weather (Live): no network needed. The sun's height gives the
/// time of day (night, dawn, golden hour, day, dusk); the moon's age gives its
/// phase. Accurate to about a minute for the sun and a day for the moon,
/// plenty for a sky.
///
/// The sun uses the standard low-precision formulas (the Astronomical
/// Almanac's, as in NOAA's calculator); the moon, the mean length of a lunar
/// month from a known new moon.
public enum SkyClock {
    /// A place on Earth, in degrees: north and east positive.
    public struct Place: Equatable, Sendable {
        public var latitude: Double
        public var longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }

        /// A rough place from the time zone alone, for when no location is
        /// known: the zone's offset gives the longitude (15° an hour), and
        /// the latitude is a middling guess. Sunrise and sunset come out
        /// within an hour or two, enough to tell night from day.
        public static func guess(from timeZone: TimeZone = .current, at date: Date = .now) -> Place {
            let offset = Double(timeZone.secondsFromGMT(for: date) - Int(timeZone.daylightSavingTimeOffset(for: date)))
            return Place(latitude: 40, longitude: offset / 3600 * 15)
        }
    }

    /// The time of day, by how high the sun is.
    public enum Phase: String, Sendable, CaseIterable {
        /// The sun more than 12° below the horizon.
        case night
        /// 12° below to the horizon, morning.
        case dawn
        /// On the horizon to 10° up, morning: warm, low light.
        case morningGold
        /// More than 10° up.
        case day
        /// 10° up to the horizon, evening.
        case eveningGold
        /// The horizon to 12° below, evening.
        case dusk
    }

    /// The sun's position: its height above the horizon (negative below),
    /// and its hour angle (negative before noon, positive after), in degrees.
    public struct Sun: Equatable, Sendable {
        public var altitude: Double
        public var hourAngle: Double

        public init(altitude: Double, hourAngle: Double) {
            self.altitude = altitude
            self.hourAngle = hourAngle
        }

        public var isRising: Bool { hourAngle < 0 }

        public var phase: Phase {
            switch altitude {
            case ..<(-12): .night
            case ..<0: isRising ? .dawn : .dusk
            case ..<10: isRising ? .morningGold : .eveningGold
            default: .day
            }
        }
    }

    public static func sun(at date: Date, place: Place) -> Sun {
        let n = julianDay(date) - 2_451_545.0
        let meanLongitude = normalized(280.460 + 0.985_647_4 * n)
        let meanAnomaly = radians(normalized(357.528 + 0.985_600_3 * n))
        let eclipticLongitude = radians(meanLongitude + 1.915 * sin(meanAnomaly) + 0.020 * sin(2 * meanAnomaly))
        let obliquity = radians(23.439 - 0.000_000_4 * n)
        let rightAscension = degrees(atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude)))
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))
        let siderealHours = (18.697_374_558 + 24.065_709_824_419_08 * n).truncatingRemainder(dividingBy: 24)
        var hourAngle = normalized(siderealHours * 15 + place.longitude - rightAscension)
        if hourAngle > 180 { hourAngle -= 360 }
        let latitude = radians(place.latitude)
        let altitude = asin(sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(radians(hourAngle)))
        return Sun(altitude: degrees(altitude), hourAngle: hourAngle)
    }

    /// The moon's age through its month, 0 (new) ... 0.5 (full) ... 1 (new).
    public static func moonPhase(at date: Date) -> Double {
        let age = (julianDay(date) - knownNewMoon) / synodicMonth
        let fraction = age - age.rounded(.down)
        return fraction
    }

    /// How much of the moon is lit, 0 (new) ... 1 (full).
    public static func moonIllumination(at date: Date) -> Double {
        (1 - cos(2 * .pi * moonPhase(at: date))) / 2
    }

    // MARK: - Helpers

    /// The new moon of 6 January 2000, 18:14 UTC, as a Julian day.
    static let knownNewMoon = 2_451_550.26
    /// The mean length of a lunar month, in days.
    static let synodicMonth = 29.530_588_853

    static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    private static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
