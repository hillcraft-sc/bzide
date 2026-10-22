import Foundation

/// Keeps each account's settings and small data, so every user on a shared
/// iPhone has their own: theme, Library layout, playback options, the
/// outside-service switches, filters, and files: the saved queue, play
/// history, unsent scrobbles, the profile (picture choice, email, saved
/// pictures), stations saved on the iPhone and what's remembered about
/// stations, Spin the Dial's log, and Tagged Radio Songs.
///
/// Settings live in UserDefaults, where the app reads them, for whoever is
/// signed in. When a different account signs in (see `AccountScope`), the
/// outgoing account's settings and files are set aside in a folder named by
/// its fingerprint, the settings are cleared, and the incoming account's are
/// put back if it has been here before (otherwise it starts with the
/// defaults). Nothing readable about the account is stored.
public struct AccountSettings {
    private let defaults: UserDefaults
    /// The UserDefaults domain the app's settings are in.
    private let domain: String
    /// Settings that belong to the iPhone, not an account (e.g. which account owns the data).
    private let deviceKeys: Set<String>
    private let directory: URL
    private let files: [URL]

    public static let directoryName = "AccountSettings"
    static let settingsFileName = "Settings.plist"

    public init(defaults: UserDefaults, domain: String, deviceKeys: Set<String> = [], directory: URL, files: [URL]) {
        self.defaults = defaults
        self.domain = domain
        self.deviceKeys = deviceKeys.union([AccountScope.fingerprintKey])
        self.directory = directory
        self.files = files
    }

    /// The app's own settings in the standard places, with the files that
    /// travel with them.
    public static func standard() throws -> AccountSettings {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return AccountSettings(
            defaults: .standard,
            domain: Bundle.main.bundleIdentifier ?? "",
            // About this iPhone and its listener, not the account: kept on a switch.
            deviceKeys: [EqualizerModel.key],
            directory: support.appending(path: directoryName),
            files: [
                support.appending(path: Wishlist.fileName),
                support.appending(path: ProfileModel.fileName),
                support.appending(path: ProfileModel.picturesDirectoryName),
                support.appending(path: FileQueueStore.fileName),
                support.appending(path: FileScrobbleStore.fileName),
                support.appending(path: PlayHistory.fileName),
                support.appending(path: PhoneStationStore.fileName),
                support.appending(path: StationDetailsStore.fileName),
                support.appending(path: StationDetailsStore.oldLogosFileName),
                support.appending(path: DialLog.fileName),
            ]
        )
    }

    /// Settings kept by Restore Default Settings: things the user made, not
    /// chose (lyrics timing fixes), and how long history is kept, which would
    /// otherwise delete older plays.
    static let keptByRestore: Set<String> = [LyricsTiming.key, LyricsChoices.key, PlayHistory.retentionKey, PlayHistory.combineKey]

    /// Restore Default Settings: clears the signed-in account's settings, so
    /// everything reads its default (outside services off). Keeps its files
    /// (Tagged Radio Songs, the profile) and `keptByRestore`. Models already
    /// loaded need reloading after.
    public func restoreDefaults() {
        for key in accountSettings.keys where !Self.keptByRestore.contains(key) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Sets aside `old`'s settings and files and brings back `new`'s (or the defaults).
    func switchAccount(from old: String, to new: String) {
        stash(old)
        clear()
        restore(new)
    }

    private var accountSettings: [String: Any] {
        (defaults.persistentDomain(forName: domain) ?? [:]).filter { !deviceKeys.contains($0.key) }
    }

    private func folder(_ fingerprint: String) -> URL {
        directory.appending(path: fingerprint, directoryHint: .isDirectory)
    }

    private func stash(_ fingerprint: String) {
        let fileManager = FileManager.default
        let folder = folder(fingerprint)
        try? fileManager.removeItem(at: folder)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(fromPropertyList: accountSettings, format: .binary, options: 0) {
            try? data.write(to: folder.appending(path: Self.settingsFileName), options: .atomic)
        }
        for file in files where fileManager.fileExists(atPath: file.path(percentEncoded: false)) {
            try? fileManager.moveItem(at: file, to: folder.appending(path: file.lastPathComponent))
        }
    }

    private func clear() {
        for key in accountSettings.keys { defaults.removeObject(forKey: key) }
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    private func restore(_ fingerprint: String) {
        let fileManager = FileManager.default
        let folder = folder(fingerprint)
        guard fileManager.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
        if let data = try? Data(contentsOf: folder.appending(path: Self.settingsFileName)),
           let saved = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for (key, value) in saved where !deviceKeys.contains(key) { defaults.set(value, forKey: key) }
        }
        for file in files {
            try? fileManager.moveItem(at: folder.appending(path: file.lastPathComponent), to: file)
        }
        try? fileManager.removeItem(at: folder)
    }
}
