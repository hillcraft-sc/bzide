import Foundation

/// A backup of the signed-in account's own data in one file, to keep anywhere
/// and restore on a new or second device (Gitea #38): its settings, the
/// Wishlist, stations saved on the iPhone and what's known about stations,
/// Spin the Dial's log, and play history if chosen. Never the login, the
/// server's address, downloads, the queue or unsent plays. Restoring
/// replaces what's here with what's in the backup.
///
/// JSON: the data files as they are (each is JSON), and the settings as a
/// base64 property list, as UserDefaults keeps them. The account is named
/// only by its fingerprint (a hash), to warn when a backup is from another.
public struct AccountBackup: Sendable, Equatable {
    public static let format = "bzide-backup"
    public static let version = 1

    public var created: Date
    public var appVersion: String
    /// `AccountScope`'s fingerprint of the server and user it came from.
    public var account: String?
    /// Binary property list of the settings.
    var settings: Data
    /// File name to its contents.
    var files: [String: Data]

    public var hasHistory: Bool { files[PlayHistory.fileName] != nil }

    /// The data files a backup carries; play history only when chosen.
    nonisolated static let dataFiles = [Wishlist.fileName, PhoneStationStore.fileName, StationDetailsStore.fileName, DialLog.fileName]

    /// "Bzide Backup 2026-10-24.json"
    public var suggestedFileName: String {
        // The day here, not in UTC: an evening backup is today's.
        "Bzide Backup \(created.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())).json"
    }
}

public enum BackupError: Error, Equatable, Sendable {
    /// Not a Bzide backup, or damaged.
    case unreadable
    /// Made by a later version of Bzide.
    case newerVersion
    case io(String)

    public var message: String {
        switch self {
        case .unreadable: "This file isn't a Bzide backup, or it's damaged."
        case .newerVersion: "This backup was made by a newer version of Bzide. Update Bzide, then try again."
        case .io(let detail): "Couldn't read or write the data: \(detail)"
        }
    }
}

extension AccountBackup {
    private struct Document: Codable {
        var format: String
        var version: Int
        var created: Date
        var appVersion: String
        var account: String?
        var settings: Data
        var files: [String: JSONValue]
    }

    /// The backup as a file.
    public func encoded() throws(BackupError) -> Data {
        var embedded: [String: JSONValue] = [:]
        for (name, data) in files {
            guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { continue }
            embedded[name] = value
        }
        let document = Document(
            format: Self.format, version: Self.version, created: created, appVersion: appVersion,
            account: account, settings: settings, files: embedded
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(document)
        } catch {
            throw .io(String(describing: error))
        }
    }

    /// A backup file read back.
    public static func decode(_ data: Data) throws(BackupError) -> AccountBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(Document.self, from: data), document.format == format else {
            throw .unreadable
        }
        guard document.version <= version else { throw .newerVersion }
        var files: [String: Data] = [:]
        let known = Set(dataFiles + [PlayHistory.fileName])
        for (name, value) in document.files where known.contains(name) {
            files[name] = try? JSONEncoder().encode(value)
        }
        return AccountBackup(
            created: document.created, appVersion: document.appVersion, account: document.account,
            settings: document.settings, files: files
        )
    }
}

extension AccountSettings {
    /// What's here now, as a backup.
    public func backup(includingHistory: Bool, appVersion: String, now: Date = .now) throws(BackupError) -> AccountBackup {
        let settings: Data
        do {
            settings = try PropertyListSerialization.data(fromPropertyList: backedUpSettings, format: .binary, options: 0)
        } catch {
            throw .io(String(describing: error))
        }
        var names = AccountBackup.dataFiles
        if includingHistory { names.append(PlayHistory.fileName) }
        var contents: [String: Data] = [:]
        for name in names {
            guard let file = files.first(where: { $0.lastPathComponent == name }),
                  let data = try? Data(contentsOf: file) else { continue }
            contents[name] = data
        }
        return AccountBackup(
            created: now, appVersion: appVersion, account: defaults.string(forKey: AccountScope.fingerprintKey),
            settings: settings, files: contents
        )
    }

    /// Whether the backup is from another server or user than the one signed
    /// in (`false` when either isn't known).
    public func isFromAnotherAccount(_ backup: AccountBackup) -> Bool {
        guard let theirs = backup.account, let ours = defaults.string(forKey: AccountScope.fingerprintKey) else { return false }
        return theirs != ours
    }

    /// Replaces this account's settings and data files with the backup's.
    /// Play history is replaced only if the backup has it. Models already
    /// loaded need building again after.
    public func restore(_ backup: AccountBackup) throws(BackupError) {
        guard let saved = try? PropertyListSerialization.propertyList(from: backup.settings, format: nil) as? [String: Any] else {
            throw .unreadable
        }
        var names = AccountBackup.dataFiles
        if backup.hasHistory { names.append(PlayHistory.fileName) }
        for name in names {
            guard let file = files.first(where: { $0.lastPathComponent == name }) else { continue }
            do {
                if let data = backup.files[name] {
                    try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                } else if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                    // Not in the backup: there was none of it.
                    try FileManager.default.removeItem(at: file)
                }
            } catch {
                throw .io(String(describing: error))
            }
        }
        for key in backedUpSettings.keys { defaults.removeObject(forKey: key) }
        for (key, value) in saved where !deviceKeys.contains(key) && Self.isBackedUp(key) { defaults.set(value, forKey: key) }
    }

    /// The account's settings, less what Apple's frameworks keep in the
    /// app's settings for themselves, which belongs to this device.
    private var backedUpSettings: [String: Any] {
        accountSettings.filter { Self.isBackedUp($0.key) }
    }

    nonisolated static func isBackedUp(_ key: String) -> Bool {
        !["Apple", "NS", "com.apple.", "WebKit", "AK", "PK"].contains { key.hasPrefix($0) }
    }
}

/// Any JSON, kept as it is: the data files go into a backup as JSON, not as
/// opaque base64, so the file can be read by other clients later.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    /// Whole numbers stay whole: a Double would round past 2^53 and
    /// could be read back as "5.0" where an Int is expected.
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Int64.self) { self = .integer(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let value): try c.encode(value)
        case .integer(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        }
    }
}
