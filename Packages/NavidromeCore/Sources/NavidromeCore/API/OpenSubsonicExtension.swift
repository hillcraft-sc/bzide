/// An optional protocol extension the server advertises via `getOpenSubsonicExtensions`.
public struct OpenSubsonicExtension: Sendable, Equatable, Decodable {
    public var name: String
    public var versions: [Int]

    public init(name: String, versions: [Int]) {
        self.name = name
        self.versions = versions
    }

    private enum CodingKeys: String, CodingKey { case name, versions }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        versions = try container.decodeIfPresent([Int].self, forKey: .versions) ?? []
    }
}
