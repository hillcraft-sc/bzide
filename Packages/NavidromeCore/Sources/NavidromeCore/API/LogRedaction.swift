import Foundation

/// Removes auth parameters from URLs before they are logged.
enum LogRedaction {
    private static let sensitiveNames: Set<String> = ["t", "s", "u", "p"]

    static func redact(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<unparseable URL>"
        }
        components.percentEncodedQueryItems = components.percentEncodedQueryItems?.map {
            sensitiveNames.contains($0.name) ? URLQueryItem(name: $0.name, value: "REDACTED") : $0
        }
        return components.string ?? "<unparseable URL>"
    }
}
