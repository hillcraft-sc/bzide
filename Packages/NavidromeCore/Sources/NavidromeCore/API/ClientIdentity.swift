/// How this app identifies itself to the server on every request.
public struct ClientIdentity: Sendable, Equatable {
    /// Sent as `c`. Shows up in Navidrome's player list, so keep it stable.
    public var name: String
    /// Sent as `v`. Navidrome implements Subsonic API 1.16.1.
    public var apiVersion: String

    public init(name: String = "Bzide", apiVersion: String = "1.16.1") {
        self.name = name
        self.apiVersion = apiVersion
    }
}
