# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

A native iOS music player for a self-hosted Navidrome server. The owner finds existing Navidrome clients clunky and unreliable, with weak CarPlay and widget support. This app exists to fix that.

**Priorities, in order:**
1. **Reliable playback.** Music must play correctly every time: background, lock screen, interruptions, network changes.
2. **A clean, fast, well-designed interface.**
3. **CarPlay and widgets** (added after the core is solid).
4. Later, in this order: a web client, then an Android client. Do not build these yet, but do not make decisions that block them.

**Status:** see the Milestones checklist below. It is the source of truth for progress: tick a milestone off when it is done, and check the repo itself rather than assuming. App name: **Bzide** (chosen 2026-10-12). It is what users see: the Home Screen name and the client name (`c`) sent to the server. Code, targets, folders, the bundle ID and internal identifiers (Keychain service, download session) keep the old `MusicApp` name on purpose; renaming them would sign the user out, orphan background downloads, or change signing.

## Principles

- Reliability beats features. Do not add features while known playback bugs are open.
- Keep logic out of the UI. Views display state and forward user intent; everything else lives in the core package.
- Everything important must be testable without a device or a live server.
- Prefer simple, readable code over clever code. The owner reads and reviews what you write.
- Behavior is documented in `docs/BEHAVIOR.md` so web and Android clients can be ported from the spec later, not reverse-engineered from Swift.

## Architecture

```
/
├── CLAUDE.md
├── docs/
│   ├── BEHAVIOR.md        # Spec: queue rules, interruption handling, prefetch, caching
│   ├── PRIVACY.md         # Plain-language privacy page: what's sent where, what's stored
│   ├── USER-GUIDE.md      # How to use Bzide, for users (Settings > Help; also hostable)
│   ├── ACCESSIBILITY.md   # For users: how Bzide works with iOS accessibility (the website's App Store Accessibility URL)
│   └── ISSUES.md          # Running log of bugs and annoyances found in real-world use
├── Packages/
│   └── NavidromeCore/     # Swift package, NO UI imports (no SwiftUI/UIKit)
│       ├── API/           # Subsonic/OpenSubsonic client
│       ├── Models/        # Artist, Album, Song, Playlist, etc.
│       ├── Auth/          # Credentials, Keychain storage
│       ├── Library/       # Screen logic for browsing: loading, paging, search, starring
│       ├── Playback/      # Audio engine, queue, session handling, Now Playing
│       └── Cache/         # Cover art cache, offline downloads
├── MusicApp/              # iOS app target (SwiftUI), thin layer over NavidromeCore
├── scripts/
│   ├── screenshots.sh     # App Store screenshots in a Simulator (MusicApp/Debug/ScreenshotScript.swift)
│   └── compose-screenshots.swift # Their App Store images: headlines on Bzide Red, stacked themes
└── website/               # bzide.hillcraft-sc.com: Home, Support and Privacy, built from docs/ (see its README)
```

Siri lives in `MusicApp/Siri/`: App Intents entities and intents using the system audio schemas, annotations that tell Siri what a view shows, and lookups through the same `Library` models (`QuickActions`, `PlaylistEditor`). It needs no entitlement.

CarPlay lives in `MusicApp/CarPlay/` (a template scene declared in `Info.plist`) and fills Apple's templates from the same `Library` models as the phone. The owner has a paid Apple Developer account (individual, since 2026-10-21; same team ID as before). Entitlements: `Config/MusicApp.entitlements` (the app, device and simulator builds: CarPlay audio, WeatherKit and the App Group) and `Config/BzideControls.entitlements` (the extension: the App Group). Apple granted the CarPlay audio entitlement on 2026-10-22; it's enabled on the App ID, and Xcode's automatic signing includes it. Widgets and controls live in the `BzideControls` WidgetKit extension (target `BzideControlsExtension`, which links `NavidromeCore`): the Now Playing and Shortcuts widgets and the Lock Screen and Control Center "Favorite Song" control. They can't see the engine: the app shares what's playing through the App Group `group.com.erichebert.musicapp` (`WidgetSnapshot`, written by `WidgetFeed`), never credentials or server details. Their buttons are audio playback intents, which the system runs in the app's process. The intent definitions are in `MusicApp/Siri/FavoriteIntentDefinitions.swift` and `MusicApp/Siri/PlaybackIntentDefinitions.swift`, compiled into both targets (folder membership exceptions in the project); each target has its own `CurrentSongFavorite` and `WidgetPlayback` (the app's do the work, the extension's do nothing or say to play something first). All of these depend on `NavidromeCore` and must not duplicate logic.

## Tech stack and targets

- Swift, SwiftUI, Swift concurrency (async/await, actors). Use the `@Observable` macro for view state.
- Minimum and target iOS: **27**. No backward compatibility: do not write availability checks (`#available`, `@available`) or fallbacks for older versions, and set the package's platform to iOS 27 as well. Use current APIs freely. Confirm with the owner before changing this.
- Your training data may predate parts of the iOS 27 SDK. When unsure whether an API exists or how it behaves, check Apple's current documentation instead of guessing, and flag anything you could not verify.
- Audio: AVFoundation (`AVPlayer` / `AVQueuePlayer`), `AVAudioSession`, `MediaPlayer` (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`).
- No third-party dependencies without asking first. Prefer Apple frameworks.
- Keep the core package free of UI frameworks so it stays portable and fast to test.

## Navidrome / Subsonic API notes

- Target the Subsonic API as implemented by Navidrome, plus OpenSubsonic extensions where the server advertises them (query `getOpenSubsonicExtensions` and degrade gracefully if unavailable).
- Auth: token + salt (`t = md5(password + salt)`, `s = salt`), with `u`, `v`, `c` (client name), and `f=json` on every request. Never send the plain password. Or an API key (OpenSubsonic `apiKeyAuthentication`): `apiKey` instead of `u`, `t` and `s`, the username from `tokenInfo`.
- Endpoints we expect to use: `ping`, `getArtists`, `getArtist`, `getArtistInfo2`, `getAlbum`, `getSong`, `getAlbumList2`, `getPlaylists`, `getPlaylist`, `createPlaylist`, `updatePlaylist`, `deletePlaylist`, `getGenres`, `getSongsByGenre`, `getInternetRadioStations`, `createInternetRadioStation`, `updateInternetRadioStation`, `deleteInternetRadioStation`, `getLyrics`, `getLyricsBySongId` (OpenSubsonic `songLyrics`), `search3`, `stream`, `download`, `getCoverArt`, `star`/`unstar`, `getStarred2`, `getUser`, `scrobble`, `getRandomSongs` (with `genre`), `getSimilarSongs`, `getSimilarSongs2`, `savePlayQueue`/`getPlayQueue` (or `savePlayQueueByIndex`/`getPlayQueueByIndex`, OpenSubsonic `indexBasedQueue`).
- Decode defensively. Servers return optional fields inconsistently; a missing field must never crash or drop an entire list.
- Outside services, all opt-in and off by default, never given server details or credentials: LRCLIB (lrclib.net) for lyrics the server doesn't have (Settings > Lyrics; gets only a song's title, artist, album and length, and the id of an LRCLIB entry the user picked with Wrong lyrics?), Gravatar (gravatar.com), one of the profile picture choices (Settings > Profile; gets only the SHA-256 of an email), Radio Browser (radio-browser.info) for finding radio stations (Settings > Radio > Find Stations Online; gets only the search text and chosen filters, the ids of stations found there when they're played, the stream addresses of saved stations, to look up their logo, country, genres and quality (and their names when an address isn't listed), and for Spin the Dial a genre and its restrictions per spin, never listening history), and Apple Weather (WeatherKit; the default source, with the `com.apple.developer.weatherkit` entitlement, falling back to MET Norway; gets the same rounded coordinates; its mark and legal link must be shown with its data) or MET Norway (api.met.no) for the Weather (Live) visualizer (Settings > Weather (Live) > Live Weather; gets only coordinates rounded to 2 decimals, while the visualizer is open; its terms require a contact in the User-Agent, set in Info.plist as `METNorwayContact`, and ask apps with many users to go through a caching proxy, which `METNorwayClient`'s base URL allows). MusicBrainz (musicbrainz.org) and the Cover Art Archive for the song a radio station is playing (Settings > Radio > Look Up Songs Online; get only its artist and title; MusicBrainz's terms require a contact in the User-Agent, Info.plist `MusicBrainzContact`, and at most one request a second, which `MusicBrainzClient` keeps). Look Up Artists Online (Settings > Artists) uses the same MusicBrainz client, the Cover Art Archive, and Wikidata and Wikipedia (Wikimedia) for an artist's releases (with their track counts, and an album's track titles for the Wishlist's missing songs) and biography; they get only the artist's name or MusicBrainz id, a release's MusicBrainz id, the Wikidata item and the article title, with the same contact in the User-Agent. A city typed for Weather (Live) is looked up with Apple's MapKit geocoder. The app asks for when-in-use location only for Weather (Live) (`NSLocationWhenInUseUsageDescription`). The contact card and photo choices use Apple's pickers, which need no permissions.
- The server may be reached over a local network, a reverse proxy, or a VPN. Support a configurable base URL and handle HTTP vs HTTPS explicitly (App Transport Security exceptions must be deliberate and documented, not blanket).

## Playback requirements (the core of this app)

These must all work and each needs automated tests where feasible and a manual checklist entry in `docs/BEHAVIOR.md`:

- Background audio continues with the screen locked and the app suspended.
- Lock screen and Control Center show correct metadata, artwork, progress, and working controls (play/pause/next/previous/seek).
- Interruptions (phone call, Siri, other apps) pause and resume correctly, honoring the `shouldResume` hint.
- Route changes (headphones unplugged, Bluetooth/CarPlay connect or disconnect) behave as users expect: pause on unplug, no surprise blasting through the speaker.
- Gapless playback: the next track is prefetched and queued before the current one ends.
- Network resilience: Wi-Fi to cellular handoff and brief signal loss must recover without stopping the queue or losing position when avoidable.
- Queue state (current item, position, upcoming items) persists across app termination and relaunch.
- Playback and queue state live in one place (the engine). The UI observes it and never owns it.
- Scrobble correctly: only once the track has played for 50% of its duration or 4 minutes, whichever comes first, and never twice for the same play.

## Security

- Credentials go in the Keychain only. Never in UserDefaults, logs, or source.
- Never commit server URLs, usernames, passwords, tokens, or API keys. Integration tests read them from environment variables (see Testing).
- Redact auth parameters (`t`, `s`, `u`) from any logging.
- App Transport Security has one deliberate exception: `NSAllowsArbitraryLoadsForMedia` (in `MusicApp/Info.plist`), because many internet radio stations stream over plain http. It covers audio loaded by AVFoundation only; server API calls, artwork and radio playlist files (`.pls`/`.m3u`) still require https. Don't widen it.

## Testing

- Unit tests for the API client use a mocked `URLSession` / protocol-based transport with hand-written sample JSON responses in `Packages/NavidromeCore/Tests/NavidromeCoreTests/Fixtures` (see the README there).
- Integration tests against the real Navidrome server run only when `NAVIDROME_URL`, `NAVIDROME_USER`, and `NAVIDROME_PASSWORD` are set in the environment, and are skipped otherwise. In Xcode, they are set in the test plan: Configurations > Environment Variables, double-click the value cell. Xcode saves them in `Packages/NavidromeCore/.swiftpm/NavidromeCore.xctestplan`, which is git-ignored. `xcodebuild` only forwards variables to the Simulator test process when they carry a `TEST_RUNNER_` prefix (it strips the prefix), so set `TEST_RUNNER_NAVIDROME_URL`, `TEST_RUNNER_NAVIDROME_USER`, and `TEST_RUNNER_NAVIDROME_PASSWORD`. Without the prefix the integration tests skip silently.
- Tests that need a host app (Keychain, anything touching app entitlements) live in `MusicAppTests`, not the package. Everything else belongs in the package tests. The two suites are run separately: the `MusicApp` scheme in `MusicApp.xcodeproj`, and the `NavidromeCore` scheme with `Packages/NavidromeCore/Package.swift` opened on its own (close the project first; the package can't be open in both). Inside the app project, Xcode 27 doesn't offer the package's tests, so they can't be added to the `MusicApp` test plan. Only the package's own test plan has the integration-test variables.
- Playback logic (queue, state machine, prefetch decisions) is tested through protocol abstractions around `AVPlayer`, so it runs without audio hardware.
- Run the full test suite before declaring any task done. Report failures honestly; do not skip or weaken tests to make them pass.
- Real-world playback quality can only be judged on a physical device. When a change affects playback, list what the owner should manually test.
- On device, install with ⌘R, then press Stop and launch the app from the Home Screen for testing. With the Xcode 27 beta debugger attached, launch stalls (black screen) and the app feels slow, so behavior and responsiveness under the debugger are not representative (see `docs/ISSUES.md`). Use the debugger only when you need it, e.g. to pause and read a stuck thread. The shared `MusicApp` scheme has **Debug executable** off (since 2026-10-24), so ⌘R installs and launches without attaching it; turn it on in Product > Scheme > Edit Scheme > Run when needed. Crash and hang reports can be read from the paired phone with `xcrun devicectl device copy from --domain-type systemCrashLogs`.

Build and test commands:

Known problem: `xcodebuild test` currently hangs from the command line on Xcode 27, while ⌘U in Xcode works (Xcode 27 has no Simulator app; virtual devices are managed in Device Hub). See `docs/ISSUES.md`. Until it's fixed, ask the owner to run ⌘U and read the newest `.xcresult` with `xcrun xcresulttool get test-results summary --path <bundle>`.

Building the app needs Xcode's Metal Toolchain (the visualizer has a Metal shader); on a fresh machine install it once with `xcodebuild -downloadComponent MetalToolchain` or from Xcode > Settings > Components.

Run the core package's tests on the iOS Simulator with `xcodebuild`, not with `swift test`. `swift test` builds for the macOS host, where `AVAudioSession` doesn't exist and the iOS-27-only platform setting doesn't apply, so `Playback/` won't compile there.
```
# Core package (run from Packages/NavidromeCore)
xcodebuild test -scheme NavidromeCore -destination 'platform=iOS Simulator,name=<an installed iOS 27 simulator>'

# App, including MusicAppTests (tests that need a host app, e.g. Keychain)
xcodebuild -project MusicApp.xcodeproj -scheme MusicApp -destination 'platform=iOS Simulator,name=<an installed iOS 27 simulator>' build test

# Single test class or method (works with either command above; repeat the flag for more)
xcodebuild test ... -only-testing:<TestTarget>/<TestClass>
xcodebuild test ... -only-testing:<TestTarget>/<TestClass>/<testMethod>
```

## Code conventions

- Models are `Sendable` value types (`struct`) and `Codable` where they cross the network.
- Use protocols at boundaries (network transport, audio player, storage) so each can be faked in tests.
- Use actors or `@MainActor` deliberately; avoid shared mutable state.
- No force unwraps (`!`) or `try!` outside tests. Handle errors with typed errors and surface useful messages.
- The app target defaults to main-actor isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). A closure written inside main-actor code is main-actor isolated, and Swift 6 checks that at runtime. Closures handed to Apple frameworks that may call them on another thread (KVO handlers, `MPMediaItemArtwork`, AVFoundation and MediaPlayer callbacks) must be `@Sendable` or built in a `nonisolated` function, then hop to the main actor themselves. Getting this wrong hangs or crashes the app, and unit tests with fakes won't catch it.
- Small files, small functions, clear names. Comment the *why*, not the *what*.
- Keep SwiftUI views small and composable. No networking or business logic inside views.
- Accessibility is part of done (see `docs/BEHAVIOR.md`, Accessibility): every control has a spoken name and a tap area of at least 44 by 44 points (`.labelStyle(.tapTarget)` for icon buttons, `.tapTarget()` inside a custom label; a frame around a button doesn't widen it); text follows the text size (`@ScaledMetric` where a fixed size is wanted); motion respects Reduce Motion; nothing is signaled by color alone; dim text brightens with Increase Contrast. Keep `docs/ACCESSIBILITY.md` true: it backs the App Store's accessibility labels (VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion).

## Workflow rules for Claude

- For any non-trivial task, propose a short plan first and wait for approval before large changes.
- Work in small, reviewable steps. Suggest a commit message after each logical unit.
- Ask before: adding a dependency, changing the iOS target (it is 27, by design), changing project structure, or touching entitlements, signing, or capabilities.
- Never put credentials, real server details, or personal data in code, tests, fixtures, or commits.
- When you find a bug or annoyance during work, add it to `docs/ISSUES.md` rather than silently working around it.
- Update `docs/BEHAVIOR.md` whenever playback, queue, caching, or interruption behavior changes.
- Update `docs/USER-GUIDE.md` whenever a user-visible feature, setting name or menu changes: it's shown in the app (Settings > Help) and on the website's Support page (rebuild and redeploy it, see `website/README.md`). Plain language, task by task, exact names of buttons and settings.
- Update `docs/PRIVACY.md` (and the privacy manifests, `PrivacyInfo.xcprivacy` in the app and the extension) whenever what the app sends, to whom, or stores changes. Every network session is private (`URLSessionTransport.privateSession`: no disk cache, cookies or stored credentials); keep it that way.
- If a requirement is ambiguous, ask instead of guessing, especially for design and UX decisions.

## Design direction

The owner has strong opinions about interface quality and will provide references and descriptions before UI work begins. Until then, build functional, minimal screens only. Do not invest in visual polish without direction.

Design goals: fast, uncluttered, large readable controls, minimal taps to play something, no unnecessary chrome.

## Milestones

- [x] **M1: Foundation.** Repo, package layout, API client with auth, Keychain storage, unit tests, integration test against the real server.
- [x] **M2: Playback engine.** Background audio, lock screen controls, interruptions, route changes, gapless, queue persistence, tested through a bare debug screen. Stress-test on a real device before moving on.
  - *Done 2026-10-11:* 144 package + 3 app tests pass; device checklist (`docs/BEHAVIOR.md`) passed, including media services reset. A real phone call resumed correctly on retest (one earlier failure not reproduced, see `docs/ISSUES.md`). Still open: wired headphones (owner has none), and async audio session activation (deferred to M6, see `docs/ISSUES.md`).
- [x] **M3: Library UI.** Artists, albums, playlists, search, now playing.
  - *Done 2026-10-11:* plain, system-styled screens: Library and Search tabs, mini player, Now Playing, plus Random Mix, Play Next, repeat and play history. 266 package + 3 app tests pass; the Library device checklist in `docs/BEHAVIOR.md` passed in full. Design direction from the owner is still to come.
- [x] **M4: Offline and caching.** Downloads, cover art cache, cellular transcoding settings.
  - *Done 2026-10-11:* per-connection streaming quality, background downloads of albums and playlists (originals, no storage cap; a download quality setting came later), cover art disk cache with covers kept for downloads. 266 package + 3 app tests pass. On device: the Downloads checklist, offline artwork, Wi-Fi to cellular handoff, and seeking within a transcoded stream on cellular all passed. Not separately confirmed: hearing the 96 kbps drop, changing quality mid-track, and searching Downloaded (added later).
- [x] **M5: CarPlay (simulator) and widgets.**
  - *Done 2026-10-24:* CarPlay used on real drives with no issues; the owner tested everything, including #27 (the car no longer starts the music on connecting). Widgets and controls in since #8. Follow-ups are their own issues (#28 CarPlay UX, #34 CarPlay Siri).
  - *Status (2026-10-22):* nearly done. Widgets: the App Group and the Now Playing and Shortcuts widgets are in (Gitea #8). CarPlay: Apple granted the audio entitlement, device builds carry it, and the scene works in Apple's CarPlay Simulator connected to the owner's iPhone, with Recently Played, Library, Radio and Downloaded tabs. Left before ticking M5: a drive in a real car.
  - *Earlier status (2026-10-11):* paused. The CarPlay scene is written and committed but has never run: Xcode 27's Device Hub has no CarPlay window (see `docs/ISSUES.md`). A Now Playing widget needs an App Group, which the free account can't use. A standalone Control Center button was skipped as redundant with iOS's own Now Playing panel, which the app already feeds. Resume with a newer Xcode beta or the paid account.
  - *Deferred (2026-10-11):* the owner chose to leave CarPlay and widgets until last, after M6. Perfecting the core iOS app comes first; don't pick M5 back up unless the owner asks.
- [ ] **M6: Daily-drive period.** Fix issues from `docs/ISSUES.md`. Only after this: paid Apple Developer account and CarPlay entitlement request.
- [ ] **Later:** web client, then Android client, ported from `docs/BEHAVIOR.md`.

## Out of scope for now

Android, web, CarPlay entitlement submission, App Store submission, social or discovery features, anything not in service of reliable playback of the owner's own library.
