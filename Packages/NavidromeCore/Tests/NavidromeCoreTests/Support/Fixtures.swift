import Foundation

enum Fixture {
    /// The contents of `Fixtures/<name>.json`.
    static func json(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Fixtures/\(name).json"])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

extension FakeTransport {
    /// A transport that answers once with the named fixture.
    init(fixture name: String) throws {
        self.init(.json(try Fixture.json(name)))
    }
}
