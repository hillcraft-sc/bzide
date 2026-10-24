import Foundation
import Testing
@testable import NavidromeCore

/// Back Up and Restore (Gitea #38).
struct AccountBackupTests {
    private let root = URL.temporaryDirectory.appending(path: "AccountBackupTests-\(UUID().uuidString)")
    private let suite = "AccountBackupTests-\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    private func file(_ name: String) -> URL { root.appending(path: name) }

    private var settings: AccountSettings {
        let names = [Wishlist.fileName, PhoneStationStore.fileName, StationDetailsStore.fileName, DialLog.fileName, PlayHistory.fileName, "PlaybackQueue.json"]
        return AccountSettings(
            defaults: defaults, domain: suite, deviceKeys: ["equalizer"],
            directory: root.appending(path: AccountSettings.directoryName), files: names.map(file)
        )
    }

    private func write(_ text: String, to name: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file(name))
    }

    private func read(_ name: String) -> String? {
        (try? Data(contentsOf: file(name))).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Ann's iPhone: settings, a Wishlist, stations, history and a queue.
    private func fillIn() throws {
        defaults.set("mocha", forKey: "theme")
        defaults.set(true, forKey: "wishlistRemovesFound")
        defaults.set("flat", forKey: "equalizer")
        defaults.set("yes", forKey: "NSSomethingOfApples")
        defaults.set("ann", forKey: AccountScope.fingerprintKey)
        try write(#"[{"id":1,"title":"Brandy"}]"#, to: Wishlist.fileName)
        try write(#"[{"name":"Night Waves","bitrate":128}]"#, to: PhoneStationStore.fileName)
        try write(#"[{"song":"Brandy"}]"#, to: PlayHistory.fileName)
        try write(#"{"queue":[]}"#, to: "PlaybackQueue.json")
    }

    @Test func aBackupHasTheSettingsAndDataButNotTheRest() throws {
        try fillIn()
        let backup = try AccountBackup.decode(try settings.backup(includingHistory: true, appVersion: "1.0").encoded())
        let saved = try #require(try PropertyListSerialization.propertyList(from: backup.settings, format: nil) as? [String: Any])
        #expect(saved["theme"] as? String == "mocha")
        #expect(saved["wishlistRemovesFound"] as? Bool == true)
        // This device's: the equalizer, the owner, and Apple's own.
        #expect(saved["equalizer"] == nil)
        #expect(saved[AccountScope.fingerprintKey] == nil)
        #expect(saved["NSSomethingOfApples"] == nil)
        #expect(Set(backup.files.keys) == [Wishlist.fileName, PhoneStationStore.fileName, PlayHistory.fileName])
        #expect(backup.hasHistory)
        #expect(backup.account == "ann")
        #expect(backup.appVersion == "1.0")
    }

    @Test func historyIsLeftOutWhenChosen() throws {
        try fillIn()
        #expect(try !settings.backup(includingHistory: false, appVersion: "1.0").hasHistory)
    }

    @Test func theFileKeepsTheDataAsJSON() throws {
        try fillIn()
        let data = try settings.backup(includingHistory: true, appVersion: "1.0").encoded()
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["format"] as? String == "bzide-backup")
        let files = try #require(json["files"] as? [String: Any])
        let stations = try #require(files[PhoneStationStore.fileName] as? [[String: Any]])
        #expect(stations.first?["name"] as? String == "Night Waves")
        // Whole numbers stay whole.
        let restored = try AccountBackup.decode(data)
        let text = String(decoding: try #require(restored.files[PhoneStationStore.fileName]), as: UTF8.self)
        #expect(text.contains(#""bitrate":128"#))
    }

    @Test func restoringReplacesWhatsHere() throws {
        try fillIn()
        let backup = try settings.backup(includingHistory: true, appVersion: "1.0")
        // Then, on this device: other settings and data.
        defaults.set("latte", forKey: "theme")
        defaults.set(5, forKey: "addedSince")
        defaults.set("bass", forKey: "equalizer")
        try write(#"[{"id":2,"title":"Other"}]"#, to: Wishlist.fileName)
        try write(#"["rb-1"]"#, to: DialLog.fileName)
        try write(#"[]"#, to: PlayHistory.fileName)

        try settings.restore(backup)
        #expect(defaults.string(forKey: "theme") == "mocha")
        #expect(defaults.object(forKey: "addedSince") == nil)
        #expect(defaults.string(forKey: "equalizer") == "bass")
        #expect(defaults.string(forKey: AccountScope.fingerprintKey) == "ann")
        #expect(read(Wishlist.fileName)?.contains("Brandy") == true)
        #expect(read(PlayHistory.fileName)?.contains("Brandy") == true)
        // There was no dial log in the backup: none now.
        #expect(read(DialLog.fileName) == nil)
        // The queue isn't part of it.
        #expect(read("PlaybackQueue.json") == #"{"queue":[]}"#)
    }

    @Test func aBackupWithoutHistoryLeavesHistoryAlone() throws {
        try fillIn()
        let backup = try settings.backup(includingHistory: false, appVersion: "1.0")
        try write(#"[{"song":"Newer"}]"#, to: PlayHistory.fileName)
        try settings.restore(backup)
        #expect(read(PlayHistory.fileName)?.contains("Newer") == true)
    }

    @Test func aBackupFromAnotherAccountIsNoted() throws {
        try fillIn()
        let backup = try settings.backup(includingHistory: false, appVersion: "1.0")
        #expect(!settings.isFromAnotherAccount(backup))
        defaults.set("bob", forKey: AccountScope.fingerprintKey)
        #expect(settings.isFromAnotherAccount(backup))
    }

    @Test func otherFilesArentBackups() {
        #expect(throws: BackupError.unreadable) { try AccountBackup.decode(Data(#"{"hello": 1}"#.utf8)) }
        #expect(throws: BackupError.unreadable) { try AccountBackup.decode(Data("not json".utf8)) }
        let later = #"{"format":"bzide-backup","version":99,"created":"2026-10-24T12:00:00Z","appVersion":"9","settings":"","files":{}}"#
        #expect(throws: BackupError.newerVersion) { try AccountBackup.decode(Data(later.utf8)) }
    }

    @Test func theFileIsNamedForItsDay() throws {
        let backup = try settings.backup(includingHistory: false, appVersion: "1.0", now: Date(timeIntervalSince1970: 1_792_843_200))
        #expect(backup.suggestedFileName.hasPrefix("Bzide Backup 2026-"))
        #expect(backup.suggestedFileName.hasSuffix(".json"))
    }
}
