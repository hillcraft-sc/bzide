import Foundation
import Testing
@testable import NavidromeCore

struct AccountSettingsTests {
    private let root = URL.temporaryDirectory.appending(path: "AccountSettingsTests-\(UUID().uuidString)")
    private let suite = "AccountSettingsTests-\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
    private var tagged: URL { root.appending(path: "Wishlist.json") }
    private var pictures: URL { root.appending(path: "ProfilePictures") }

    private var scope: AccountScope {
        let settings = AccountSettings(
            defaults: defaults, domain: suite, directory: root.appending(path: AccountSettings.directoryName), files: [tagged, pictures]
        )
        return AccountScope(defaults: defaults, dataLocations: [root.appending(path: "Downloads")], settings: settings)
    }

    private func account(_ user: String) -> ServerCredentials {
        ServerCredentials(baseURL: URL(string: "https://music.example.test")!, username: user, password: "sesame")
    }

    private func writeTagged(_ text: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: tagged)
    }

    private var taggedText: String? {
        (try? Data(contentsOf: tagged)).map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func aNewUserStartsWithTheDefaults() throws {
        scope.prepare(for: account("ann"))
        defaults.set("mocha", forKey: "theme")
        defaults.set(true, forKey: "findLyricsOnline")
        try writeTagged("ann's songs")
        #expect(scope.prepare(for: account("bob")))
        #expect(defaults.object(forKey: "theme") == nil)
        #expect(defaults.object(forKey: "findLyricsOnline") == nil)
        #expect(taggedText == nil)
        // Still knows who owns the data.
        #expect(defaults.string(forKey: AccountScope.fingerprintKey) == AccountScope.fingerprint(of: account("bob")))
    }

    @Test func switchingBackBringsTheSettingsBack() throws {
        scope.prepare(for: account("ann"))
        defaults.set("mocha", forKey: "theme")
        try writeTagged("ann's songs")
        scope.prepare(for: account("bob"))
        defaults.set("latte", forKey: "theme")
        defaults.set(5, forKey: "bobOnly")
        try writeTagged("bob's songs")

        scope.prepare(for: account("ann"))
        #expect(defaults.string(forKey: "theme") == "mocha")
        #expect(defaults.object(forKey: "bobOnly") == nil)
        #expect(taggedText == "ann's songs")

        scope.prepare(for: account("bob"))
        #expect(defaults.string(forKey: "theme") == "latte")
        #expect(defaults.integer(forKey: "bobOnly") == 5)
        #expect(taggedText == "bob's songs")
    }

    @Test func theSameUserKeepsEverything() throws {
        scope.prepare(for: account("ann"))
        defaults.set("mocha", forKey: "theme")
        try writeTagged("ann's songs")
        #expect(!scope.prepare(for: account("ann")))
        #expect(defaults.string(forKey: "theme") == "mocha")
        #expect(taggedText == "ann's songs")
    }

    @Test func theFirstSignInKeepsTheSettingsThere() throws {
        // Settings from before accounts were tracked are the first account's.
        defaults.set("mocha", forKey: "theme")
        #expect(!scope.prepare(for: account("ann")))
        #expect(defaults.string(forKey: "theme") == "mocha")
    }

    @MainActor
    @Test func theModelsReadTheSwitchedSettings() {
        let appearance = AppearanceModel(defaults: defaults)
        let layout = LibraryLayoutModel(defaults: defaults)
        let streaming = StreamingSettingsModel(defaults: defaults)
        scope.prepare(for: account("ann"))
        appearance.settings.theme = .mocha
        layout.layout.setShown(.radio, false)
        streaming.settings.findLyricsOnline = true

        scope.prepare(for: account("bob"))
        appearance.reload()
        layout.reload()
        streaming.reload()
        #expect(appearance.settings == AppearanceSettings())
        #expect(layout.layout == LibraryLayout())
        #expect(!streaming.settings.findLyricsOnline)

        scope.prepare(for: account("ann"))
        appearance.reload()
        layout.reload()
        streaming.reload()
        #expect(appearance.settings.theme == .mocha)
        #expect(!layout.layout.shown.contains(.radio))
        #expect(streaming.settings.findLyricsOnline)
    }

    @Test func foldersGoWithTheirAccountToo() throws {
        scope.prepare(for: account("ann"))
        try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
        try Data("photo".utf8).write(to: pictures.appending(path: "photo.jpg"))
        scope.prepare(for: account("bob"))
        #expect(!FileManager.default.fileExists(atPath: pictures.path(percentEncoded: false)))
        scope.prepare(for: account("ann"))
        #expect(FileManager.default.fileExists(atPath: pictures.appending(path: "photo.jpg").path(percentEncoded: false)))
    }
}
