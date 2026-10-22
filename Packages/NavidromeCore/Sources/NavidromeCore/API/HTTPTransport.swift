import Foundation

/// The network boundary. Production uses `URLSession`; tests substitute a fake.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    /// A private session by default: nothing on disk (no URL cache), no
    /// cookies. The shared session keeps an on-disk cache keyed by full
    /// request URLs, which for the server carry the username and login token.
    public init(session: URLSession = URLSessionTransport.privateSession) {
        self.session = session
    }

    /// No disk cache, no cookies, no credentials kept: each answer lives in
    /// memory for the request only.
    public static let privateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }()

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
