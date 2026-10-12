import Testing
@testable import NavidromeCore

struct ClientIdentityTests {
    @Test func defaultsTargetNavidromeAPIVersion() {
        let identity = ClientIdentity()
        #expect(identity.name == "Bzide")
        #expect(identity.apiVersion == "1.16.1")
    }
}
