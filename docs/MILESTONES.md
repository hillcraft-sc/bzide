# Milestones

The source of truth for project progress: tick a milestone off when it is done, and check the repo itself rather than assuming.

- [x] **M1: Foundation.** Repo, package layout, API client with auth, Keychain storage, unit tests, integration test against the real server.
- [x] **M2: Playback engine.** Background audio, lock screen controls, interruptions, route changes, gapless, queue persistence, tested through a bare debug screen. Stress-test on a real device before moving on.
  - *Done 2026-10-11:* device checklist (`docs/BEHAVIOR.md`) passed, including media services reset. A real phone call resumed correctly on retest (one earlier failure not reproduced, see `docs/ISSUES.md`). Wired headphones passed on 2026-11-08. Async audio session activation was deferred to M6 (see `docs/ISSUES.md`).
- [x] **M3: Library UI.** Artists, albums, playlists, search, now playing.
  - *Done 2026-10-11:* plain, system-styled screens: Library and Search tabs, mini player, Now Playing, plus Random Mix, Play Next, repeat and play history. The Library device checklist in `docs/BEHAVIOR.md` passed in full.
- [x] **M4: Offline and caching.** Downloads, cover art cache, cellular transcoding settings.
  - *Done 2026-10-11:* per-connection streaming quality, background downloads of albums and playlists, cover art disk cache with covers kept for downloads. On device: the Downloads checklist, offline artwork, Wi-Fi to cellular handoff, and seeking within a transcoded stream on cellular all passed. Not separately confirmed: hearing the 96 kbps drop, changing quality mid-track, and searching Downloaded (added later).
- [x] **M5: CarPlay (simulator) and widgets.**
  - *Done 2026-10-24:* CarPlay used on real drives with no issues; the owner tested everything, including #27 (the car no longer starts the music on connecting). Widgets and controls in since #8. Follow-ups are their own issues (#28 CarPlay UX, #34 CarPlay Siri).
- [ ] **M6: Daily-drive period.** Fix issues from `docs/ISSUES.md`.
- [ ] **Later:** web client, then Android client, ported from `docs/BEHAVIOR.md`.
