import Foundation
import Testing
@testable import NavidromeCore

@MainActor
struct ProfileModelTests {
    private let root = URL.temporaryDirectory.appending(path: "ProfileModelTests-\(UUID().uuidString)")
    private var file: URL { root.appending(path: "Profile.json") }
    private var cache: URL { root.appending(path: "Gravatar") }
    private var pictures: URL { root.appending(path: "ProfilePictures") }
    private let photo = Data([0xFF, 0xD8, 0xFF, 0x01])
    private let card = Data([0xFF, 0xD8, 0xFF, 0x02])
    private let picture = Data([0x89, 0x50, 0x4E, 0x47])

    /// Records what was asked and answers as told.
    private actor Fake {
        var serverEmail: String?
        var image: Data?
        var fails = false
        var serverFails = false
        var serverAsks = 0
        var imageURLs: [URL] = []

        init(serverEmail: String?, image: Data?) {
            self.serverEmail = serverEmail
            self.image = image
        }

        func askServer() throws -> String? {
            serverAsks += 1
            if serverFails { throw URLError(.notConnectedToInternet) }
            return serverEmail
        }

        func fetch(_ url: URL) throws -> Data? {
            imageURLs.append(url)
            if fails { throw URLError(.notConnectedToInternet) }
            return image
        }

        func set(image: Data?, fails: Bool) {
            self.image = image
            self.fails = fails
        }

        func goOffline() {
            fails = true
            serverFails = true
        }
    }

    /// The clock tests move forward.
    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    private func model(_ fake: Fake, clock: Clock = Clock()) -> ProfileModel {
        ProfileModel(
            fileURL: file, picturesDirectory: pictures, cacheDirectory: cache,
            services: .init(serverEmail: { try await fake.askServer() }, image: { try await fake.fetch($0) }),
            now: { clock.now }
        )
    }

    @Test func noPictureByDefaultAndNothingIsAsked() async {
        let fake = Fake(serverEmail: "listener@example.test", image: picture)
        let profile = model(fake)
        await profile.refresh()
        #expect(profile.lookup == .off)
        #expect(profile.avatar == nil)
        #expect(await fake.serverAsks == 0)
        #expect(await fake.imageURLs.isEmpty)
    }

    @Test func turnedOnItUsesTheServersEmail() async {
        let fake = Fake(serverEmail: "listener@example.test", image: picture)
        let profile = model(fake)
        profile.settings.picture = .gravatar
        await profile.refresh()
        #expect(profile.email == "listener@example.test")
        #expect(profile.lookup == .found)
        #expect(profile.avatar == picture)
        let url = await fake.imageURLs.first
        #expect(url?.absoluteString.contains(Gravatar.hash(of: "listener@example.test") ?? "-") == true)
    }

    @Test func aTypedEmailWinsOverTheServers() async {
        let fake = Fake(serverEmail: "listener@example.test", image: picture)
        let profile = model(fake)
        profile.settings = .init(picture: .gravatar, customEmail: " other@example.test ")
        await profile.refresh()
        #expect(profile.email == "other@example.test")
        let url = await fake.imageURLs.first
        #expect(url?.absoluteString.contains(Gravatar.hash(of: "other@example.test") ?? "-") == true)
    }

    @Test func noEmailAnywhere() async {
        let profile = model(Fake(serverEmail: nil, image: picture))
        profile.settings.picture = .gravatar
        await profile.refresh()
        #expect(profile.lookup == .noEmail)
    }

    @Test func aMistypedEmailIsntLookedUp() async {
        let fake = Fake(serverEmail: nil, image: picture)
        let profile = model(fake)
        profile.settings = .init(picture: .gravatar, customEmail: "listener@example")
        await profile.refresh()
        #expect(profile.lookup == .invalidEmail)
        #expect(await fake.imageURLs.isEmpty)
    }

    @Test func noPictureForTheEmail() async {
        let profile = model(Fake(serverEmail: "listener@example.test", image: nil))
        profile.settings.picture = .gravatar
        await profile.refresh()
        #expect(profile.lookup == .notFound)
        #expect(profile.avatar == nil)
    }

    @Test func answersAreKeptForADay() async {
        let fake = Fake(serverEmail: "listener@example.test", image: picture)
        let clock = Clock()
        let profile = model(fake, clock: clock)
        profile.settings.picture = .gravatar
        await profile.refresh()
        // Within the day, even a new launch uses the saved picture without asking.
        clock.now += 60 * 60
        let relaunched = model(fake, clock: clock)
        await relaunched.refresh()
        #expect(relaunched.avatar == picture)
        #expect(await fake.imageURLs.count == 1)
        // A day later it asks again.
        clock.now += ProfileModel.cacheLifetime
        await relaunched.refresh()
        #expect(await fake.imageURLs.count == 2)
    }

    @Test func offlineTheLastPictureStays() async {
        let fake = Fake(serverEmail: "listener@example.test", image: picture)
        let clock = Clock()
        let profile = model(fake, clock: clock)
        profile.settings.picture = .gravatar
        await profile.refresh()
        await fake.set(image: nil, fails: true)
        clock.now += ProfileModel.cacheLifetime + 1
        await profile.refresh()
        #expect(profile.avatar == picture)
        #expect(profile.lookup == .found)
    }

    @Test func offlineWithNothingSavedIsAFailure() async {
        let fake = Fake(serverEmail: "listener@example.test", image: picture)
        await fake.set(image: nil, fails: true)
        let profile = model(fake)
        profile.settings.picture = .gravatar
        await profile.refresh()
        #expect(profile.lookup == .failed)
        #expect(profile.avatar == nil)
    }

    @Test func choosingNoneHidesThePicture() async {
        let profile = model(Fake(serverEmail: "listener@example.test", image: picture))
        profile.settings.picture = .gravatar
        await profile.refresh()
        profile.settings.picture = .none
        await profile.refresh()
        #expect(profile.avatar == nil)
        #expect(profile.lookup == .off)
    }

    @Test func theServerIsAskedOncePerSession() async {
        let fake = Fake(serverEmail: "listener@example.test", image: picture)
        let profile = model(fake)
        profile.settings.picture = .gravatar
        await profile.refresh()
        await profile.refresh(force: true)
        #expect(await fake.serverAsks == 1)
    }

    @Test func offlineAtLaunchTheAccountsGravatarStillShows() async {
        let fake = Fake(serverEmail: "listener@example.test", image: picture)
        let clock = Clock()
        let profile = model(fake, clock: clock)
        profile.settings.picture = .gravatar
        await profile.refresh()
        #expect(profile.avatar == picture)
        // Relaunched in Airplane Mode, still within the day.
        await fake.goOffline()
        clock.now += 60 * 60
        let relaunched = model(fake, clock: clock)
        await relaunched.refresh()
        #expect(relaunched.email == "listener@example.test")
        #expect(relaunched.avatar == picture)
        #expect(relaunched.lookup == .found)
        // And a day later, when the saved picture is old, it's kept rather than lost.
        clock.now += ProfileModel.cacheLifetime
        let later = model(fake, clock: clock)
        await later.refresh()
        #expect(later.avatar == picture)
    }

    @Test func aChangedAccountEmailIsFollowed() async {
        let fake = Fake(serverEmail: "listener@example.test", image: picture)
        let profile = model(fake)
        profile.settings.picture = .gravatar
        await profile.refresh()
        let changed = Fake(serverEmail: "new@example.test", image: picture)
        let relaunched = model(changed)
        await relaunched.refresh()
        #expect(relaunched.email == "new@example.test")
        #expect(relaunched.settings.accountEmail == "new@example.test")
    }

    @Test func settingsAreSavedForNextTime() async {
        let profile = model(Fake(serverEmail: nil, image: nil))
        profile.settings = .init(picture: .gravatar, customEmail: "listener@example.test")
        let relaunched = model(Fake(serverEmail: nil, image: nil))
        #expect(relaunched.settings == .init(picture: .gravatar, customEmail: "listener@example.test"))
    }

    @Test func aPickedPictureIsShownAndKept() async {
        let fake = Fake(serverEmail: "listener@example.test", image: picture)
        let profile = model(fake)
        profile.setPicked(photo, for: .photo)
        #expect(profile.settings.picture == .photo)
        #expect(profile.avatar == photo)
        // Next launch: the same picture, and Gravatar and the server were never asked.
        let relaunched = model(fake)
        await relaunched.refresh()
        #expect(relaunched.avatar == photo)
        #expect(await fake.serverAsks == 0)
        #expect(await fake.imageURLs.isEmpty)
    }

    @Test func eachPickedSourceKeepsItsOwnPicture() async {
        let profile = model(Fake(serverEmail: nil, image: nil))
        profile.setPicked(card, for: .contactCard)
        profile.setPicked(photo, for: .photo)
        profile.settings.picture = .contactCard
        await profile.refresh()
        #expect(profile.avatar == card)
        #expect(profile.hasPicked(.photo))
        profile.settings.picture = .photo
        await profile.refresh()
        #expect(profile.avatar == photo)
    }

    @Test func aSourceNotYetPickedShowsTheGear() async {
        let profile = model(Fake(serverEmail: nil, image: nil))
        profile.settings.picture = .contactCard
        await profile.refresh()
        #expect(profile.avatar == nil)
        #expect(!profile.hasPicked(.contactCard))
    }

    @Test func onlyPickedSourcesTakeAPickedPicture() {
        let profile = model(Fake(serverEmail: nil, image: nil))
        profile.setPicked(photo, for: .gravatar)
        #expect(profile.settings.picture == .none)
        #expect(profile.avatar == nil)
    }

    @Test func theFirstGravatarOnlySettingsCarryOver() throws {
        let saved = Data(#"{"showGravatar":true,"customEmail":"listener@example.test"}"#.utf8)
        let settings = try JSONDecoder().decode(ProfileModel.Settings.self, from: saved)
        #expect(settings == .init(picture: .gravatar, customEmail: "listener@example.test"))
        let unknown = try JSONDecoder().decode(ProfileModel.Settings.self, from: Data(#"{"picture":"hologram"}"#.utf8))
        #expect(unknown.picture == .none)
    }
}
