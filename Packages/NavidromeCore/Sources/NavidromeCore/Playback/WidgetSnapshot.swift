import Foundation

/// What's playing, for the widgets and controls, which run in their own
/// process and can't see the engine: written by the app (`WidgetFeed`) into
/// the App Group's folder and read by the BzideControls extension. Only
/// what's shown on screen; never server details or credentials, so the
/// extension never talks to the server.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var title: String
    /// The artist, or for a station its name when the title is the announced song.
    public var subtitle: String?
    /// Playing or about to be (buffering, reconnecting): the button shows pause.
    public var isPlaying: Bool
    /// A radio station: no previous, and no favorite.
    public var isLive: Bool
    public var hasNext: Bool
    /// `nil` for a station.
    public var isFavorite: Bool?
    /// The cover the saved artwork is of, if any.
    public var coverArtID: String?

    public init(
        title: String, subtitle: String? = nil, isPlaying: Bool, isLive: Bool = false, hasNext: Bool = false,
        isFavorite: Bool? = nil, coverArtID: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isPlaying = isPlaying
        self.isLive = isLive
        self.hasNext = hasNext
        self.isFavorite = isFavorite
        self.coverArtID = coverArtID
    }
}

/// The app's theme, for the widgets to draw in: its colors (`nil` for the
/// System, Light and Dark themes, which follow the phone), and the accent as
/// it looks in light and dark mode (the same for a theme; the system accents
/// differ). Colors only, nothing else about the user.
public struct WidgetTheme: Codable, Equatable, Sendable {
    public struct Colors: Codable, Equatable, Sendable {
        public var base: UInt32
        /// Tiles and placeholders, a shade off the background.
        public var surface: UInt32
        public var text: UInt32
        public var isLight: Bool

        public init(base: UInt32, surface: UInt32, text: UInt32, isLight: Bool) {
            self.base = base
            self.surface = surface
            self.text = text
            self.isLight = isLight
        }
    }

    public var colors: Colors?
    public var accentLight: UInt32
    public var accentDark: UInt32

    public init(colors: Colors?, accentLight: UInt32, accentDark: UInt32) {
        self.colors = colors
        self.accentLight = accentLight
        self.accentDark = accentDark
    }

    /// For a theme with a palette: its colors and chosen accent. Light themes'
    /// tiles are a shade darker than the background (`crust`), dark themes'
    /// a shade lighter (`surface0`), as in the app's grouped lists.
    public init(palette: ThemePalette, accent: RGBColor) {
        self.init(
            colors: Colors(
                base: palette.base.hex, surface: (palette.isLight ? palette.crust : palette.surface0).hex,
                text: palette.text.hex, isLight: palette.isLight
            ),
            accentLight: accent.hex, accentDark: accent.hex
        )
    }
}

/// The snapshot and its artwork, as files in a folder both processes can
/// reach (the App Group's container on a device; any folder in tests).
/// Without a folder (no App Group), nothing is kept and nothing is read.
public struct WidgetSnapshotStore: Sendable {
    public static let appGroup = "group.com.erichebert.musicapp"
    static let snapshotName = "NowPlaying.json"
    static let artworkName = "NowPlayingArtwork.jpg"
    static let themeName = "Theme.json"

    public let directory: URL?

    public init(directory: URL?) {
        self.directory = directory
    }

    /// In the App Group's container.
    public static func shared() -> WidgetSnapshotStore {
        WidgetSnapshotStore(directory: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup))
    }

    /// `nil` when nothing is queued (or nothing was ever written).
    public func read() -> WidgetSnapshot? {
        guard let url = directory?.appending(path: Self.snapshotName), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func write(_ snapshot: WidgetSnapshot?) {
        guard let url = directory?.appending(path: Self.snapshotName) else { return }
        guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// `nil` before the app has shared one (the widgets then look as iOS draws them).
    public func readTheme() -> WidgetTheme? {
        guard let url = directory?.appending(path: Self.themeName), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetTheme.self, from: data)
    }

    public func writeTheme(_ theme: WidgetTheme) {
        guard let url = directory?.appending(path: Self.themeName), let data = try? JSONEncoder().encode(theme) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// A JPEG, small enough for a widget.
    public func readArtwork() -> Data? {
        directory.flatMap { try? Data(contentsOf: $0.appending(path: Self.artworkName)) }
    }

    public func writeArtwork(_ jpeg: Data?) {
        guard let url = directory?.appending(path: Self.artworkName) else { return }
        guard let jpeg else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? jpeg.write(to: url, options: .atomic)
    }
}
