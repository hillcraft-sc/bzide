# Issues

Running log of bugs and annoyances found in real-world use or during development. Newest first.

Format: `- [open|fixed] YYYY-MM-DD: description (where it was seen)`

- [fixed] 2026-10-10: Keychain tests can't run as package tests. The bare test runner has no Keychain entitlement, so every Keychain call fails with -34018 (`errSecMissingEntitlement`). Fixed by moving `KeychainCredentialStoreTests` into `MusicAppTests`, which is hosted by the app; all 3 pass there. (NavidromeCore tests, iOS 27 Simulator)
- [open] 2026-10-10: `xcodebuild test` from the command line hangs with "The test runner hung before establishing connection" on the iOS 27 virtual device, while ⌘U in Xcode runs the same tests fine. Tried `xcodebuild -runFirstLaunch` and restarting CoreSimulatorService. Possibly related to Device Hub replacing Simulator in Xcode 27; not yet understood. Until fixed, tests are run from Xcode and results read from the `.xcresult` bundle. (Xcode 27.0 beta 27A5218g)
- [fixed] 2026-10-10: Step 3 (audio session) used `AVAudioSession.interruptionNotification`, deprecated in iOS 27. Switched to `didBecomeInactiveNotification` (system deactivation = interruption) and `resumptionRecommendationNotification` (resume only on `.shouldResume`). (M2 step 3)
- [open] 2026-10-10: "Media services were reset" (`AVAudioSession.mediaServicesWereResetNotification`) is not handled. After a reset the AVQueuePlayer and session setup are invalid and must be rebuilt; until then playback may silently stop after one. Rare, but worth handling before M6. (M2 step 3)
- [open] 2026-10-10: Mac keyboard input is broken on the "iPhone 17" iOS 27 virtual device in Device Hub: text fields in every app (including Safari) accept only the first character, and one keystroke sent the app to the background. Not an app bug. Workarounds: paste, restart the virtual device, or test on a physical iPhone. (Xcode 27.0 beta, Device Hub)
- [fixed] 2026-10-10: App hung when a track started. MediaPlayer called the lock-screen artwork closure on its own background queue; the app target defaults to main-actor isolation, so Swift 6's runtime isolation check failed inside the closure and deadlocked. Fixed by building the closure in a nonisolated function. The same risk was fixed pre-emptively in AVQueueAudioPlayer's KVO handlers (now `@Sendable`). (M2 step 7, debug screen)
