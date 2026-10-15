import Foundation
import Testing
@testable import NavidromeCore

struct SkyClockTests {
    private static func utc(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text)!
    }

    private let london = SkyClock.Place(latitude: 51.5074, longitude: -0.1278)
    private let newYork = SkyClock.Place(latitude: 40.7128, longitude: -74.0060)

    /// At sunrise and sunset the sun's center is about 0.83° below the horizon.
    private func isRisingOrSetting(_ sun: SkyClock.Sun) -> Bool {
        abs(sun.altitude - -0.833) < 0.6
    }

    @Test func sunriseAndSunsetMatchPublishedTimes() {
        // London, summer solstice 2026: sunrise 04:43 BST, sunset 21:21 BST.
        #expect(isRisingOrSetting(SkyClock.sun(at: Self.utc("2026-06-21T03:43:00Z"), place: london)))
        #expect(isRisingOrSetting(SkyClock.sun(at: Self.utc("2026-06-21T20:21:00Z"), place: london)))
        // New York, winter solstice 2026: sunrise 7:17 EST, sunset 16:32 EST.
        #expect(isRisingOrSetting(SkyClock.sun(at: Self.utc("2026-12-21T12:17:00Z"), place: newYork)))
        #expect(isRisingOrSetting(SkyClock.sun(at: Self.utc("2026-12-21T21:32:00Z"), place: newYork)))
    }

    @Test func theNoonSunIsAsHighAsTheSeasonAllows() {
        // London at the June solstice: 90° − 51.5° + 23.44° ≈ 61.9°.
        let noon = SkyClock.sun(at: Self.utc("2026-06-21T12:02:00Z"), place: london)
        #expect(abs(noon.altitude - 61.9) < 0.5)
        #expect(abs(noon.hourAngle) < 2)
    }

    @Test func phasesFollowTheSunThroughTheDay() {
        func phase(_ time: String) -> SkyClock.Phase {
            SkyClock.sun(at: Self.utc("2026-12-21T\(time):00Z"), place: newYork).phase
        }
        #expect(phase("06:00") == .night)        // 1 am
        #expect(phase("11:55") == .dawn)         // 6:55 am, just before sunrise
        #expect(phase("12:40") == .morningGold)  // 7:40 am
        #expect(phase("17:00") == .day)          // noon
        #expect(phase("21:10") == .eveningGold)  // 4:10 pm
        #expect(phase("21:50") == .dusk)         // 4:50 pm
        #expect(phase("23:30") == .night)        // 6:30 pm
    }

    @Test func theMoonsPhaseMatchesKnownNewAndFullMoons() {
        // New moon (annular solar eclipse) 17 February 2026, 12:01 UTC.
        let new = SkyClock.moonPhase(at: Self.utc("2026-02-17T12:01:00Z"))
        #expect(min(new, 1 - new) < 0.03)
        // Full moon (total lunar eclipse) 3 March 2026, 11:38 UTC.
        #expect(abs(SkyClock.moonPhase(at: Self.utc("2026-03-03T11:38:00Z")) - 0.5) < 0.03)
        #expect(SkyClock.moonIllumination(at: Self.utc("2026-03-03T11:38:00Z")) > 0.98)
        #expect(SkyClock.moonIllumination(at: Self.utc("2026-02-17T12:01:00Z")) < 0.02)
    }

    @Test func withoutALocationTheTimeZoneGivesARoughPlace() throws {
        let eastern = try #require(TimeZone(identifier: "America/New_York"))
        // Standard time is 5 hours behind: 75° west, whether or not it's summer.
        #expect(SkyClock.Place.guess(from: eastern, at: Self.utc("2026-01-15T12:00:00Z")).longitude == -75)
        #expect(SkyClock.Place.guess(from: eastern, at: Self.utc("2026-07-15T12:00:00Z")).longitude == -75)
    }
}
