# Contributing to Bzide

Thanks for looking. Bzide is a one-person project with a narrow goal: a music player for a self-hosted Navidrome server that plays reliably, looks clean and works with CarPlay and widgets. Reports and ideas are welcome, and code changes are too, with the steps below.

## Reports and ideas

Open an [issue](https://github.com/hillcraft-sc/bzide/issues/new/choose). The forms ask for what helps most: the Bzide version (Settings > About), your iOS version and what you were doing. Issues are public, so never include your server address, username, password, API key or anything private. For a security problem, see [SECURITY.md](SECURITY.md) instead.

## Code changes

**Open an issue first.** Say what you'd like to change and why, so we can agree before you spend time on it. Small fixes (a typo, an obvious bug) can go straight to a pull request.

What the project cares about, in this order:

1. **Reliable playback.** Music must play correctly every time: background, lock screen, interruptions, network changes. A change that risks this needs a strong reason, and no feature work lands while a known playback bug is open.
2. **A clean, fast, simple interface.**
3. **CarPlay and widgets.**

How the code is organized and written:

- **Logic stays out of views.** Views display state and forward what the user does. Everything else lives in `Packages/NavidromeCore`, which uses no UI frameworks and is tested without a device or a live server.
- **Tests come with the change.** Use the existing protocols and fakes (network transport, audio player, storage) rather than a real server or audio hardware.
- **Simple and readable over clever.** Comment why, not what. No force unwraps or `try!` outside tests.
- **iOS 27 and later only.** Don't add availability checks or fallbacks for older versions.
- **Apple frameworks only.** A new dependency needs a conversation first.
- **Accessibility is part of done.** Every control has a spoken name and a tap area of at least 44 by 44 points, text follows the text size, motion respects Reduce Motion, and nothing is signaled by color alone. See [`docs/ACCESSIBILITY.md`](docs/ACCESSIBILITY.md).
- **Keep the docs true.** Playback, queue, caching or interruption changes go in [`docs/BEHAVIOR.md`](docs/BEHAVIOR.md) (the spec a web or Android client would be ported from). A user-visible feature or setting change goes in [`docs/USER-GUIDE.md`](docs/USER-GUIDE.md). Anything that changes what the app sends, to whom, or what it stores goes in [`docs/PRIVACY.md`](docs/PRIVACY.md) and the privacy manifests.
- **American English** in the UI, docs, comments and commit messages.
- **Privacy rules.** Credentials live in the Keychain only. Never commit server URLs, usernames, passwords, tokens or API keys, and redact auth parameters from logs. Outside services stay opt-in and off by default.

[`.claude/CLAUDE.md`](.claude/CLAUDE.md) has the full conventions, with more in [`.claude/rules/`](.claude/rules) and [`.claude/skills/`](.claude/skills). It's written for an AI coding assistant, but people can read it too.

## Building and testing

See [Building in the README](README.md#building). Run the tests in Xcode with ⌘U, once for the `MusicApp` scheme and once for the `NavidromeCore` scheme (open `Packages/NavidromeCore/Package.swift` on its own, with the project closed). `xcodebuild test` currently hangs from the command line on Xcode 27, so use ⌘U (see [`docs/ISSUES.md`](docs/ISSUES.md)). Integration tests against a real server run only when `NAVIDROME_URL`, `NAVIDROME_USER` and `NAVIDROME_PASSWORD` are set, and are skipped otherwise.

Real-world playback quality can only be judged on a physical device, so say in your pull request what you tried on one.

## Pull requests

- One change per pull request, with a message that says why.
- The tests pass, and you've said what you ran.
- Docs updated as above.
- You understand and have tested everything you submit. Using an AI assistant is fine (this project is built with one); sending code you haven't read isn't.

## License

By submitting a contribution you agree that it's licensed under the [GNU General Public License v3.0](LICENSE), the same as the rest of the code. You also agree that the maintainer may distribute it as part of Bzide on the App Store. The name Bzide, the icon and the website's branding aren't covered by the license; see [TRADEMARK.md](TRADEMARK.md).
