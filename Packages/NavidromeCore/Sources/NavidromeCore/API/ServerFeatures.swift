import Foundation

/// What the server supports, asked once and remembered. A failed check isn't
/// remembered, so it's tried again next time.
public actor ServerFeatures {
    private let client: SubsonicClient
    private var extensions: Set<String>?

    public init(client: SubsonicClient) {
        self.client = client
    }

    /// OpenSubsonic `songLyrics`: lyrics with timing, by song id.
    public func supportsSongLyrics() async -> Bool {
        await supports("songLyrics")
    }

    /// OpenSubsonic `formPost`: requests may be sent as a form POST.
    public func supportsFormPost() async -> Bool {
        await supports("formPost")
    }

    private func supports(_ name: String) async -> Bool {
        if let extensions { return extensions.contains(name) }
        guard let found = try? await client.openSubsonicExtensions() else { return false }
        let names = Set(found.map(\.name))
        extensions = names
        return names.contains(name)
    }
}
