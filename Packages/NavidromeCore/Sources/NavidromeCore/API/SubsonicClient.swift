import Foundation
import os

/// Talks to one Subsonic/Navidrome server. Stateless apart from its configuration,
/// so it is a plain `Sendable` value that can be shared freely.
public struct SubsonicClient: Sendable {
    private let builder: RequestBuilder
    private let transport: any HTTPTransport
    private static let logger = Logger(subsystem: "MusicApp", category: "SubsonicClient")

    public init(
        credentials: ServerCredentials,
        identity: ClientIdentity = ClientIdentity(),
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.init(credentials: credentials, identity: identity, transport: transport, makeSalt: AuthToken.randomSalt)
    }

    /// Lets tests pin the salt so request URLs are predictable.
    init(
        credentials: ServerCredentials,
        identity: ClientIdentity = ClientIdentity(),
        transport: any HTTPTransport,
        makeSalt: @escaping @Sendable () -> String
    ) {
        self.builder = RequestBuilder(credentials: credentials, identity: identity, makeSalt: makeSalt)
        self.transport = transport
    }

    // MARK: - System

    /// Succeeds if the server is reachable and accepts the credentials.
    public func ping() async throws(SubsonicError) {
        _ = try await request("ping", as: EmptyPayload.self)
    }

    /// The username an API key belongs to (OpenSubsonic `tokenInfo`, part of
    /// `apiKeyAuthentication`), which also checks the key. Error 44: not a
    /// valid key.
    public func apiKeyUsername() async throws(SubsonicError) -> String {
        struct Payload: Decodable {
            struct TokenInfo: Decodable { let username: String? }
            let tokenInfo: TokenInfo?
        }
        guard let username = try await request("tokenInfo", as: Payload.self).tokenInfo?.username, !username.isEmpty else {
            throw .decoding("tokenInfo without a username")
        }
        return username
    }

    /// The OpenSubsonic extensions the server supports. Plain Subsonic servers don't
    /// have this endpoint; that is reported as an empty list, not an error.
    public func openSubsonicExtensions() async throws(SubsonicError) -> [OpenSubsonicExtension] {
        struct Payload: Decodable {
            let openSubsonicExtensions: [OpenSubsonicExtension]?
        }
        do {
            return try await request("getOpenSubsonicExtensions", as: Payload.self).openSubsonicExtensions ?? []
        } catch .server, .httpStatus(404) {
            return []
        }
    }

    // MARK: - Plumbing

    /// `post` sends it as a form POST, for servers with OpenSubsonic
    /// `formPost`, so a long list of parameters fits.
    func request<Payload: Decodable>(
        _ endpoint: String,
        parameters: [URLQueryItem] = [],
        post: Bool = false,
        as type: Payload.Type
    ) async throws(SubsonicError) -> Payload {
        let urlRequest: URLRequest
        if post {
            urlRequest = try builder.formRequest(endpoint: endpoint, parameters: parameters)
            // The body holds the login, so only the endpoint is logged.
            Self.logger.debug("POST \(endpoint, privacy: .public) (\(parameters.count) parameters)")
        } else {
            let url = try builder.url(endpoint: endpoint, parameters: parameters)
            urlRequest = URLRequest(url: url)
            Self.logger.debug("GET \(LogRedaction.redact(url), privacy: .public)")
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: urlRequest)
        } catch let error as URLError {
            throw .network(error.code)
        } catch {
            throw .network(.unknown)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw .httpStatus(response.statusCode)
        }
        return try Self.decode(data, as: type)
    }

    func mediaURL(_ endpoint: String, parameters: [URLQueryItem]) throws(SubsonicError) -> URL {
        try builder.url(endpoint: endpoint, parameters: parameters)
    }

    static func decode<Payload: Decodable>(_ data: Data, as type: Payload.Type) throws(SubsonicError) -> Payload {
        do {
            return try JSONDecoder().decode(SubsonicResponse<Payload>.self, from: data).payload
        } catch let failed as SubsonicResponse<Payload>.FailedStatus {
            throw .server(code: failed.code, message: failed.message)
        } catch {
            throw .decoding(String(describing: error))
        }
    }
}
