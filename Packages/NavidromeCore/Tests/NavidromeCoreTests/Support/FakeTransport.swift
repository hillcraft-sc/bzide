import Foundation
@testable import NavidromeCore

/// Returns canned responses and records every request it receives.
actor FakeTransport: HTTPTransport {
    enum Reply {
        case json(String, status: Int = 200, headers: [String: String] = [:])
        case failure(URLError.Code)
    }

    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: Reply...) {
        self.replies = replies
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.resourceUnavailable) }
        switch replies.removeFirst() {
        case .json(let body, let status, let headers):
            let url = request.url ?? URL(filePath: "/")
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)
            guard let response else { throw URLError(.badServerResponse) }
            return (Data(body.utf8), response)
        case .failure(let code):
            throw URLError(code)
        }
    }
}

enum TestServer {
    static let credentials = ServerCredentials(
        baseURL: URL(string: "https://music.example.test")!,
        username: "listener",
        password: "sesame"
    )

    static func client(_ transport: FakeTransport, credentials: ServerCredentials = credentials) -> SubsonicClient {
        SubsonicClient(credentials: credentials, transport: transport, makeSalt: { "c19b2d" })
    }

    static let ok = #"{"subsonic-response":{"status":"ok","version":"1.16.1"}}"#

    static func failed(code: Int, message: String) -> String {
        #"{"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":\#(code),"message":"\#(message)"}}}"#
    }
}

extension URL {
    /// Query parameters as a dictionary, for assertions. Last value wins.
    var queryParameters: [String: String] {
        let items = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }
}
