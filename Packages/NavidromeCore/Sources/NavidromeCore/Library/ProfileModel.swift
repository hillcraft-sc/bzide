import Foundation
import Observation

/// The user's profile picture, shown in place of the Settings gear and at the
/// top of Settings. The user chooses where it comes from: none (the gear, the
/// default), a contact card or a photo they pick (copied in once), or their
/// Gravatar. iOS doesn't let apps read the Apple Account photo itself.
///
/// Gravatar is a lookup on the open internet: it sends a hash of the email to
/// gravatar.com (hashes of common addresses can be matched back), so it only
/// happens once chosen. The email is the one the user typed, or else the one
/// on their server account. Gravatar's answers ("this picture", or "none for
/// this email") are kept for a day, so the picture shows at once on launch and
/// offline. The settings and all pictures belong to the account (see
/// `AccountScope`).
@MainActor
@Observable
public final class ProfileModel {
    /// Where the picture comes from.
    public enum Picture: String, Codable, CaseIterable, Sendable {
        case none, contactCard, photo, gravatar

        public var title: String {
            switch self {
            case .none: "None"
            case .contactCard: "Contact Card"
            case .photo: "Photo"
            case .gravatar: "Gravatar"
            }
        }

        /// Picked by the user and copied in, rather than looked up.
        public var isPicked: Bool { self == .contactCard || self == .photo }
    }

    public struct Settings: Codable, Equatable, Sendable {
        public var picture: Picture
        /// For Gravatar, typed by the user; empty means use the server account's email.
        public var customEmail: String
        /// The server account's email as last fetched, so the saved Gravatar
        /// can be found when the server can't be reached (offline at launch).
        public var accountEmail: String?

        public init(picture: Picture = .none, customEmail: String = "", accountEmail: String? = nil) {
            self.picture = picture
            self.customEmail = customEmail
            self.accountEmail = accountEmail
        }

        private enum CodingKeys: String, CodingKey { case picture, customEmail, accountEmail, showGravatar }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(picture, forKey: .picture)
            try c.encode(customEmail, forKey: .customEmail)
            try c.encodeIfPresent(accountEmail, forKey: .accountEmail)
        }

        /// An unknown picture source falls back to none. Settings saved by the
        /// first, Gravatar-only version (a `showGravatar` switch) carry over.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let saved = ((try? c.decodeIfPresent(Picture.self, forKey: .picture)) ?? nil)
            let showedGravatar = ((try? c.decodeIfPresent(Bool.self, forKey: .showGravatar)) ?? nil) ?? false
            picture = saved ?? (showedGravatar ? .gravatar : .none)
            customEmail = ((try? c.decodeIfPresent(String.self, forKey: .customEmail)) ?? nil) ?? ""
            accountEmail = (try? c.decodeIfPresent(String.self, forKey: .accountEmail)) ?? nil
        }
    }

    /// How the Gravatar lookup went.
    public enum Lookup: Equatable, Sendable {
        /// Gravatar isn't the chosen picture.
        case off
        /// No email typed and none on the server account.
        case noEmail
        case invalidEmail
        case loading
        case found
        case notFound
        case failed
    }

    /// What the app needs from outside. `image` returns `nil` when Gravatar has
    /// no picture for the address.
    public struct Services: Sendable {
        public var serverEmail: @Sendable () async throws -> String?
        public var image: @Sendable (URL) async throws -> Data?

        public init(
            serverEmail: @escaping @Sendable () async throws -> String?,
            image: @escaping @Sendable (URL) async throws -> Data?
        ) {
            self.serverEmail = serverEmail
            self.image = image
        }
    }

    public var settings: Settings {
        didSet { save() }
    }
    public private(set) var serverEmail: String?
    public private(set) var avatar: Data?
    public private(set) var lookup: Lookup = .off

    /// The picture size fetched: large enough for the top of Settings at 3x.
    public static let pixels = 240
    /// How long a picture, or a "not found", is trusted before asking again.
    public static let cacheLifetime: TimeInterval = 24 * 60 * 60
    nonisolated public static let fileName = "Profile.json"
    nonisolated public static let cacheDirectoryName = "Gravatar"
    nonisolated public static let picturesDirectoryName = "ProfilePictures"

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let cacheDirectory: URL?
    @ObservationIgnored private let picturesDirectory: URL?
    @ObservationIgnored private let services: Services
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var askedServer = false
    /// Bumped by each refresh; an older refresh's answer is dropped.
    @ObservationIgnored private var generation = 0

    /// `picturesDirectory` keeps the picked contact card and photo pictures;
    /// `cacheDirectory` keeps Gravatar's answers.
    public init(
        fileURL: URL?, picturesDirectory: URL?, cacheDirectory: URL?, services: Services,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.fileURL = fileURL
        self.picturesDirectory = picturesDirectory
        self.cacheDirectory = cacheDirectory
        self.services = services
        self.now = now
        settings = fileURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) }
            ?? Settings()
        serverEmail = settings.accountEmail
    }

    /// The email in use: the typed one, else the server account's.
    public var email: String? {
        let typed = settings.customEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? serverEmail : typed
    }

    /// Shows the chosen picture: the saved one for a contact card or photo,
    /// or Gravatar's for the email. `force` ignores Gravatar's day-long cache.
    public func refresh(force: Bool = false) async {
        generation += 1
        let mine = generation
        switch settings.picture {
        case .none:
            avatar = nil
            lookup = .off
            return
        case .contactCard, .photo:
            avatar = savedPicture(for: settings.picture)
            lookup = .off
            return
        case .gravatar:
            break
        }
        // Only asked once the user has opted in, and once per session. If the
        // server can't be reached, the email remembered from last time stands.
        if !askedServer {
            askedServer = true
            do {
                let found = try await services.serverEmail()
                guard mine == generation else { return }
                serverEmail = found
                if settings.accountEmail != found { settings.accountEmail = found }
            } catch {
                // Asked again next session.
                askedServer = false
                guard mine == generation else { return }
            }
        }
        guard let email else {
            avatar = nil
            lookup = .noEmail
            return
        }
        guard let hash = Gravatar.hash(of: email), let url = Gravatar.imageURL(forHash: hash, pixels: Self.pixels) else {
            avatar = nil
            lookup = .invalidEmail
            return
        }
        let cached = cachedAnswer(for: hash)
        if !force, let cached, cached.isFresh {
            avatar = cached.image
            lookup = cached.image == nil ? .notFound : .found
            return
        }
        // Keep showing the last picture while asking again.
        if let image = cached?.image { avatar = image } else { avatar = nil }
        lookup = .loading
        do {
            let image = try await services.image(url)
            guard mine == generation else { return }
            store(image, for: hash)
            avatar = image
            lookup = image == nil ? .notFound : .found
        } catch {
            guard mine == generation else { return }
            // Offline: an old picture is better than none.
            avatar = cached?.image
            lookup = cached?.image == nil ? .failed : .found
        }
    }

    // MARK: - Picked pictures

    /// Saves a picture the user picked (already sized for a profile picture)
    /// and makes it the one shown.
    public func setPicked(_ image: Data, for picture: Picture) {
        guard picture.isPicked else { return }
        generation += 1
        if let file = pictureFile(for: picture) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? image.write(to: file, options: .atomic)
        }
        settings.picture = picture
        avatar = image
        lookup = .off
    }

    /// Whether a contact card or photo has been picked before.
    public func hasPicked(_ picture: Picture) -> Bool {
        savedPicture(for: picture) != nil
    }

    private func savedPicture(for picture: Picture) -> Data? {
        pictureFile(for: picture).flatMap { try? Data(contentsOf: $0) }
    }

    private func pictureFile(for picture: Picture) -> URL? {
        guard picture.isPicked else { return nil }
        return picturesDirectory?.appending(path: "\(picture.rawValue).img")
    }

    // MARK: - Saving

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(settings) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// A picture is `<hash>.img`; "no picture" is an empty `<hash>.none`.
    private func cachedAnswer(for hash: String) -> (image: Data?, isFresh: Bool)? {
        guard let cacheDirectory else { return nil }
        let fileManager = FileManager.default
        for (name, isImage) in [("\(hash).img", true), ("\(hash).none", false)] {
            let file = cacheDirectory.appending(path: name)
            guard let attributes = try? fileManager.attributesOfItem(atPath: file.path(percentEncoded: false)),
                  let modified = attributes[.modificationDate] as? Date else { continue }
            let isFresh = now().timeIntervalSince(modified) < Self.cacheLifetime
            if isImage {
                guard let data = try? Data(contentsOf: file) else { continue }
                return (data, isFresh)
            }
            return (nil, isFresh)
        }
        return nil
    }

    private func store(_ image: Data?, for hash: String) {
        guard let cacheDirectory else { return }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let imageFile = cacheDirectory.appending(path: "\(hash).img")
        let noneFile = cacheDirectory.appending(path: "\(hash).none")
        try? fileManager.removeItem(at: imageFile)
        try? fileManager.removeItem(at: noneFile)
        let written = image.map { (imageFile, $0) } ?? (noneFile, Data())
        try? written.1.write(to: written.0, options: .atomic)
        // Dated by our clock, so the day's lifetime is measured consistently.
        try? fileManager.setAttributes([.modificationDate: now()], ofItemAtPath: written.0.path(percentEncoded: false))
    }
}
