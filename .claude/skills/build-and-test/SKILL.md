---
name: build-and-test
description: "How to build, run and test Bzide: the two test suites and their schemes, xcodebuild commands for the iOS Simulator, integration tests against a real Navidrome server, Metal Toolchain setup, and installing on a device. Use when building, running or testing, or when a build or test setup fails."
---

# Building and testing Bzide

The two suites are run separately: the `MusicApp` scheme in `MusicApp.xcodeproj`, and the `NavidromeCore` scheme with `Packages/NavidromeCore/Package.swift` opened on its own (close the project first; the package can't be open in both). Inside the app project, Xcode 27 doesn't offer the package's tests, so they can't be added to the `MusicApp` test plan. Only the package's own test plan has the integration-test variables.

Integration tests against the real Navidrome server run only when `NAVIDROME_URL`, `NAVIDROME_USER`, and `NAVIDROME_PASSWORD` are set in the environment, and are skipped otherwise. In Xcode, they are set in the test plan: Configurations > Environment Variables, double-click the value cell. Xcode saves them in `Packages/NavidromeCore/.swiftpm/NavidromeCore.xctestplan`, which is git-ignored. `xcodebuild` only forwards variables to the Simulator test process when they carry a `TEST_RUNNER_` prefix (it strips the prefix), so set `TEST_RUNNER_NAVIDROME_URL`, `TEST_RUNNER_NAVIDROME_USER`, and `TEST_RUNNER_NAVIDROME_PASSWORD`. Without the prefix the integration tests skip silently.

On device, install with ⌘R, then press Stop and launch the app from the Home Screen for testing. With the Xcode 27 beta debugger attached, launch stalls (black screen) and the app feels slow, so behavior and responsiveness under the debugger are not representative (see `docs/ISSUES.md`). Use the debugger only when you need it, e.g. to pause and read a stuck thread. The shared `MusicApp` scheme has **Debug executable** off (since 2026-10-24), so ⌘R installs and launches without attaching it; turn it on in Product > Scheme > Edit Scheme > Run when needed. Crash and hang reports can be read from the paired phone with `xcrun devicectl device copy from --domain-type systemCrashLogs`.

## Build and test commands

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
