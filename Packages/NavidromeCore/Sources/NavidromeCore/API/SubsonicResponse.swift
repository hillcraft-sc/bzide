import Foundation

/// The `subsonic-response` wrapper around every JSON reply.
///
/// The payload sits beside `status` in the same object (e.g. `"artists": {...}`),
/// so `Payload` decodes from the same container and looks up its own key.
struct SubsonicResponse<Payload: Decodable>: Decodable {
    let payload: Payload

    private enum OuterKeys: String, CodingKey {
        case response = "subsonic-response"
    }

    private enum StatusKeys: String, CodingKey {
        case status, error
    }

    private struct ServerError: Decodable {
        let code: Int?
        let message: String?
    }

    struct FailedStatus: Error {
        let code: Int
        let message: String
    }

    init(from decoder: any Decoder) throws {
        let outer = try decoder.container(keyedBy: OuterKeys.self)
        let inner = try outer.superDecoder(forKey: .response)
        let status = try inner.container(keyedBy: StatusKeys.self)
        if try status.decode(String.self, forKey: .status) != "ok" {
            let error = try status.decodeIfPresent(ServerError.self, forKey: .error)
            throw FailedStatus(code: error?.code ?? 0, message: error?.message ?? "Unknown error")
        }
        payload = try Payload(from: inner)
    }
}

/// For endpoints whose only answer is "ok" (ping, star, scrobble...).
struct EmptyPayload: Decodable {}
