# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

A native iOS music player for a self-hosted Navidrome server. The owner finds existing Navidrome clients clunky and unreliable, with weak CarPlay and widget support. This app exists to fix that.

**Priorities, in order:**
1. **Reliable playback.** Music must play correctly every time: background, lock screen, interruptions, network changes.
2. **A clean, fast, well-designed interface.**
3. **CarPlay and widgets** (added after the core is solid).
4. Later, in this order: a web client, then an Android client. Do not build these yet, but do not make decisions that block them.

**Status:** see `docs/MILESTONES.md`, the source of truth for progress: tick a milestone off there when it is done, and check the repo itself rather than assuming. App name: **Bzide** (chosen 2026-10-12). It is what users see: the Home Screen name and the client name (`c`) sent to the server. Code, targets, folders, the bundle ID and internal identifiers (Keychain service, download session) keep the old `MusicApp` name on purpose; renaming them would sign the user out, orphan background downloads, or change signing.

## Principles

- Reliability beats features. Do not add features while known playback bugs are open.
- Keep logic out of the UI. Views display state and forward user intent; everything else lives in the core package.
- Everything important must be testable without a device or a live server.
- Prefer simple, readable code over clever code. The owner reads and reviews what you write.
- Behavior is documented in `docs/BEHAVIOR.md` so web and Android clients can be ported from the spec later, not reverse-engineered from Swift.

## Architecture

Siri (`MusicApp/Siri/`), CarPlay (`MusicApp/CarPlay/`) and the widgets and controls extension (`BzideControls/`) all fill their surfaces from the same `Library` models and depend on `NavidromeCore`; none may duplicate its logic. How they are wired, the entitlements and the App Group are in `.claude/rules/carplay-siri-widgets.md`, which loads when you work on those files.

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
- Decode defensively. Servers return optional fields inconsistently; a missing field must never crash or drop an entire list.
- Outside services (lyrics, profile pictures, radio and station lookup, artist info, weather) are all opt-in, off by default, and never given server details or credentials. What each one gets, and the terms for using it, are in `.claude/rules/outside-services.md`, which loads when you work on their clients; keep `docs/PRIVACY.md` true.
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
- Never commit server URLs, usernames, passwords, tokens, or API keys. Integration tests read them from environment variables (see the `build-and-test` skill).
- Redact auth parameters (`t`, `s`, `u`) from any logging.
- App Transport Security has one deliberate exception: `NSAllowsArbitraryLoadsForMedia` (in `MusicApp/Info.plist`), because many internet radio stations stream over plain http. It covers audio loaded by AVFoundation only; server API calls, artwork and radio playlist files (`.pls`/`.m3u`) still require https. Don't widen it.

## Testing

- Unit tests for the API client use a mocked `URLSession` / protocol-based transport with hand-written sample JSON responses in `Packages/NavidromeCore/Tests/NavidromeCoreTests/Fixtures` (see the README there).
- Tests that need a host app (Keychain, anything touching app entitlements) live in `MusicAppTests`, not the package. Everything else belongs in the package tests.
- Playback logic (queue, state machine, prefetch decisions) is tested through protocol abstractions around `AVPlayer`, so it runs without audio hardware.
- Run the full test suite before declaring any task done. Report failures honestly; do not skip or weaken tests to make them pass.
- Real-world playback quality can only be judged on a physical device. When a change affects playback, list what the owner should manually test.
- `xcodebuild test` hangs from the command line on Xcode 27 (see `docs/ISSUES.md`), so ask the owner to run ⌘U, then read the newest `.xcresult` with `xcrun xcresulttool get test-results summary --path <bundle>`. For building, the two test suites and how to run them, integration tests against a real server, Metal Toolchain setup and installing on a device, use the `build-and-test` skill.


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

## Out of scope for now

Android, web, App Store submission, social or discovery features, anything not in service of reliable playback of the owner's own library.
