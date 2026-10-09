# CLAUDE.md

## Project overview

A native iOS music player for a self-hosted Navidrome server. The owner finds existing Navidrome clients clunky and unreliable, with weak CarPlay and widget support. This app exists to fix that.

**Priorities, in order:**
1. **Reliable playback.** Music must play correctly every time: background, lock screen, interruptions, network changes.
2. **A clean, fast, well-designed interface.**
3. **CarPlay and widgets** (added after the core is solid).
4. Later, in this order: a web client, then an Android client. Do not build these yet, but do not make decisions that block them.

**Status:** greenfield. Nothing exists yet. App name: TBD (use `MusicApp` as a placeholder).

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
│   └── ISSUES.md          # Running log of bugs and annoyances found in real-world use
├── Packages/
│   └── NavidromeCore/     # Swift package, NO UI imports (no SwiftUI/UIKit)
│       ├── API/           # Subsonic/OpenSubsonic client
│       ├── Models/        # Artist, Album, Song, Playlist, etc.
│       ├── Auth/          # Credentials, Keychain storage
│       ├── Playback/      # Audio engine, queue, session handling, Now Playing
│       └── Cache/         # Cover art cache, offline downloads
└── MusicApp/              # iOS app target (SwiftUI), thin layer over NavidromeCore
```

Later additions (not yet): a CarPlay scene, a WidgetKit extension. Both depend on `NavidromeCore` and must not duplicate logic.

## Tech stack and targets

- Swift, SwiftUI, Swift concurrency (async/await, actors). Use the `@Observable` macro for view state.
- Minimum and target iOS: **27**. No backward compatibility: do not write availability checks (`#available`, `@available`) or fallbacks for older versions, and set the package's platform to iOS 27 as well. Use current APIs freely. Confirm with the owner before changing this.
- Your training data may predate parts of the iOS 27 SDK. When unsure whether an API exists or how it behaves, check Apple's current documentation instead of guessing, and flag anything you could not verify.
- Audio: AVFoundation (`AVPlayer` / `AVQueuePlayer`), `AVAudioSession`, `MediaPlayer` (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`).
- No third-party dependencies without asking first. Prefer Apple frameworks.
- Keep the core package free of UI frameworks so it stays portable and fast to test.

## Navidrome / Subsonic API notes

- Target the Subsonic API as implemented by Navidrome, plus OpenSubsonic extensions where the server advertises them (query `getOpenSubsonicExtensions` and degrade gracefully if unavailable).
- Auth: token + salt (`t = md5(password + salt)`, `s = salt`), with `u`, `v`, `c` (client name), and `f=json` on every request. Never send the plain password.
- Endpoints we expect to use: `ping`, `getArtists`, `getArtist`, `getAlbum`, `getAlbumList2`, `getPlaylists`, `getPlaylist`, `search3`, `stream`, `download`, `getCoverArt`, `star`/`unstar`, `scrobble`, `getRandomSongs`.
- Decode defensively. Servers return optional fields inconsistently; a missing field must never crash or drop an entire list.
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
- Scrobble correctly: only after a reasonable play threshold, and never twice for the same play.

## Security

- Credentials go in the Keychain only. Never in UserDefaults, logs, or source.
- Never commit server URLs, usernames, passwords, tokens, or API keys. Integration tests read them from environment variables (see Testing).
- Redact auth parameters (`t`, `s`, `u`) from any logging.

## Testing

- Unit tests for the API client use a mocked `URLSession` / protocol-based transport with recorded sample JSON responses in `Tests/Fixtures`.
- Integration tests against the real Navidrome server run only when `NAVIDROME_URL`, `NAVIDROME_USER`, and `NAVIDROME_PASSWORD` are set in the environment, and are skipped otherwise.
- Playback logic (queue, state machine, prefetch decisions) is tested through protocol abstractions around `AVPlayer`, so it runs without audio hardware.
- Run the full test suite before declaring any task done. Report failures honestly; do not skip or weaken tests to make them pass.
- Real-world playback quality can only be judged on a physical device. When a change affects playback, list what the owner should manually test.

Build and test commands (fill in once the project exists):
```
# Core package
swift test --package-path Packages/NavidromeCore

# App
xcodebuild -scheme MusicApp -destination 'platform=iOS Simulator,name=<an installed iOS 27 simulator>' build test
```

## Code conventions

- Models are `Sendable` value types (`struct`) and `Codable` where they cross the network.
- Use protocols at boundaries (network transport, audio player, storage) so each can be faked in tests.
- Use actors or `@MainActor` deliberately; avoid shared mutable state.
- No force unwraps (`!`) or `try!` outside tests. Handle errors with typed errors and surface useful messages.
- Small files, small functions, clear names. Comment the *why*, not the *what*.
- Keep SwiftUI views small and composable. No networking or business logic inside views.

## Workflow rules for Claude

- For any non-trivial task, propose a short plan first and wait for approval before large changes.
- Work in small, reviewable steps. Suggest a commit message after each logical unit.
- Ask before: adding a dependency, changing the iOS target (it is 27, by design), changing project structure, or touching entitlements, signing, or capabilities.
- Never put credentials, real server details, or personal data in code, tests, fixtures, or commits.
- When you find a bug or annoyance during work, add it to `docs/ISSUES.md` rather than silently working around it.
- Update `docs/BEHAVIOR.md` whenever playback, queue, caching, or interruption behavior changes.
- If a requirement is ambiguous, ask instead of guessing, especially for design and UX decisions.

## Design direction

The owner has strong opinions about interface quality and will provide references and descriptions before UI work begins. Until then, build functional, minimal screens only. Do not invest in visual polish without direction.

Design goals: fast, uncluttered, large readable controls, minimal taps to play something, no unnecessary chrome.

## Milestones

- [ ] **M1: Foundation.** Repo, package layout, API client with auth, Keychain storage, unit tests, integration test against the real server.
- [ ] **M2: Playback engine.** Background audio, lock screen controls, interruptions, route changes, gapless, queue persistence, tested through a bare debug screen. Stress-test on a real device before moving on.
- [ ] **M3: Library UI.** Artists, albums, playlists, search, now playing.
- [ ] **M4: Offline and caching.** Downloads, cover art cache, cellular transcoding settings.
- [ ] **M5: CarPlay (simulator) and widgets.**
- [ ] **M6: Daily-drive period.** Fix issues from `docs/ISSUES.md`. Only after this: paid Apple Developer account and CarPlay entitlement request.
- [ ] **Later:** web client, then Android client, ported from `docs/BEHAVIOR.md`.

## Out of scope for now

Android, web, CarPlay entitlement submission, App Store submission, social or discovery features, anything not in service of reliable playback of the owner's own library.
