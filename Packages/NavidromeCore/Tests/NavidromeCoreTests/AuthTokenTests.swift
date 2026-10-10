import Testing
@testable import NavidromeCore

struct AuthTokenTests {
    @Test func matchesSubsonicSpecExample() {
        // The worked example from the Subsonic API documentation.
        #expect(AuthToken.make(password: "sesame", salt: "c19b2d") == "26719a1196d2a940705a59634eb18eab")
    }

    @Test func randomSaltIsFreshEachTime() {
        let salts = Set((0..<50).map { _ in AuthToken.randomSalt() })
        #expect(salts.count == 50)
        #expect(salts.allSatisfy { $0.count == 32 })
    }
}
