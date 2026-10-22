import Foundation

/// Builds signed Subsonic request URLs.
struct RequestBuilder: Sendable {
    let credentials: ServerCredentials
    let identity: ClientIdentity
    let makeSalt: @Sendable () -> String

    func url(endpoint: String, parameters: [URLQueryItem] = []) throws(SubsonicError) -> URL {
        // An API key replaces the username and token; the spec forbids sending both.
        let login: [URLQueryItem]
        if let apiKey = credentials.apiKey {
            login = [URLQueryItem(name: "apiKey", value: apiKey)]
        } else {
            let salt = makeSalt()
            login = [
                URLQueryItem(name: "u", value: credentials.username),
                URLQueryItem(name: "t", value: AuthToken.make(password: credentials.password, salt: salt)),
                URLQueryItem(name: "s", value: salt),
            ]
        }
        let auth = login + [
            URLQueryItem(name: "v", value: identity.apiVersion),
            URLQueryItem(name: "c", value: identity.name),
            URLQueryItem(name: "f", value: "json"),
        ]
        // appendingPathComponent keeps any subpath in the base URL (reverse proxies).
        let endpointURL = credentials.baseURL.appendingPathComponent("rest").appendingPathComponent(endpoint)
        guard
            let scheme = credentials.baseURL.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false)
        else {
            throw .invalidBaseURL
        }
        components.percentEncodedQueryItems = (auth + parameters).map {
            URLQueryItem(name: $0.name, value: $0.value.map(Self.encodeQueryValue))
        }
        guard let url = components.url else { throw .invalidBaseURL }
        return url
    }

    /// URLComponents leaves `+` and `;` unescaped in queries, but Navidrome (Go)
    /// decodes `+` as a space, so "AC+DC" or a username with `+` would arrive
    /// mangled, and refuses a query with a raw `;` ("invalid semicolon
    /// separator in query"), common in Shoutcast stream addresses.
    private static func encodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=#;")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
