# Behavior spec

How the app behaves, written so the web and Android clients can be ported from this file rather than from the Swift code. Each playback rule gets a manual checklist entry for testing on a real device.

## Server communication

- Protocol: Subsonic API 1.16.1 as implemented by Navidrome, JSON (`f=json`), HTTP GET.
- Requests go to `<base URL>/rest/<endpoint>`. Any path in the base URL is kept, so servers behind a reverse proxy subpath work.
- Only `http` and `https` base URLs are accepted.
- Auth: every request carries `u`, `t = md5(password + salt)`, `s = salt`, `v`, `c`. The salt is 16 random bytes as hex, new for every request. The plain password is never sent.
- Query values are percent-encoded including `+`, because the server decodes a bare `+` as a space.
- Auth parameters (`t`, `s`, `u`, `p`) are replaced with `REDACTED` before a URL is logged.
- Errors are reported as one of: invalid base URL, network failure, non-2xx HTTP status, server `status: "failed"` (with the Subsonic error code), or an unreadable response. Codes 40 and 41 count as authentication failures.
- Decoding is tolerant, because servers fill fields inconsistently:
  - An item without a non-empty `id` is dropped. Nothing else in its list is affected.
  - Any other field that is missing, `null`, or the wrong type is treated as absent. Numbers sent as strings (`"320"`, `"187.0"`) and booleans sent as strings are accepted. Missing names and titles become empty strings; the UI chooses a placeholder.
  - A list sent as a single object is treated as a one-element list. A missing list is empty.
  - List endpoints (`getArtists`, `getAlbumList2`, `getPlaylists`, `getRandomSongs`, `search3`) return an empty result when the wrapper object is missing. Single-item endpoints (`getArtist`, `getAlbum`, `getPlaylist`) report an error.
  - `starred` is read as "starred if present", ignoring the date.
- Media (`stream`, `download`, `getCoverArt`) is fetched by URL, not through the API client. These URLs contain a valid token, so they are built on demand and never logged or persisted.
- Scrobble times are sent in milliseconds since the Unix epoch. `submission=false` updates "now playing" only.
- OpenSubsonic: `getOpenSubsonicExtensions` returning a server error or HTTP 404 means "no extensions", not a failure. Network failures are still reported.

## Playback

- One engine owns the queue and playback state. The UI shows that state and sends commands; it never changes playback itself.
- Status is one of: idle (nothing queued), paused, buffering, playing, or failed (with a message).
- Gapless: the player always holds the current track and the one after it, so the next track is buffered before the current one ends. When a track ends, the player moves on by itself and the engine loads the track after that.
- Next uses the already-buffered next track. On the last track it does nothing.
- Previous, jump, and starting a new queue load the chosen track from the start, keeping the play/pause state.
- When the last track ends, playback stops on that track, rewound to the start. Play starts it again.
- Seek is clamped to the track's length.
- Duration comes from the server's metadata until the player knows the real duration.
- Stream URLs contain auth tokens, so they are built only when a track is loaded and are never saved.
- On launch, a saved queue is restored paused at its saved position. Nothing loads or plays until the user presses play.
- The queue is saved whenever it changes. While playing, the position is saved every 10 seconds of playback, and on pause and seek.
- Failures:
  - If the current track fails, status becomes failed and stays failed until the user acts. Play retries the track. (Automatic recovery comes later in M2.)
  - If the preloaded next track fails, the current track keeps playing.
  - If a stream URL can't be built, the track fails the same way.

### Audio session and interruptions

- Before every play, the app claims audio output for long-form music playback (category playback, long-form audio routing policy, which routes to AirPlay and CarPlay like other music apps). If the system refuses, the track fails with "Can't play right now: <reason>".
- When the system takes audio away (call, Siri, alarm, another app), playback pauses. If music was playing, the app remembers that.
- When the system later sends its resumption recommendation, playback resumes only if music was playing before the interruption **and** the system recommends resuming. A missing recommendation means don't resume.
- If the user presses play or pause during an interruption, their choice wins and the app won't auto-resume.
- When the output device goes away (headphones unplugged, Bluetooth disconnected), playback pauses and stays paused. It never continues through the speaker, and reconnecting does not auto-resume.
- Not handled yet: "media services were reset" (see `docs/ISSUES.md`).

### Scrobbling

- A track is scrobbled once it has played for 50% of its duration or 4 minutes, whichever comes first.
- A single play is never scrobbled twice.
- Only time actually listened counts toward the threshold. Seeking forward does not add to it; seeking back does not remove from it.

## Queue

- The queue is an ordered list of entries plus a current position. Each entry has its own id, so the same song can appear more than once and the UI and player can tell the copies apart.
- A new queue starts at the requested index, clamped into range. An empty queue has no current entry.
- Next moves to the following entry. At the last entry it does nothing.
- Previous: if the current track has played more than 3 seconds, restart it. Otherwise go to the previous track. On the first track, restart it.
- Jumping to an entry that isn't in the queue does nothing.
- Appending adds to the end. Appending to an empty queue makes the first added song current.
- Shuffle and repeat are not implemented yet.

### Persistence

- The queue and the position within the current entry are saved as JSON to `Application Support/PlaybackQueue.json`, replaced atomically so a crash never leaves a half-written file.
- The file stays writable while the device is locked (after the first unlock since boot), because saves happen during locked-screen playback.
- A saved file that can't be read is reported, not crashed on; the app starts with an empty queue. A saved current index outside the entries is clamped into range.

## Caching and offline

_Filled in during M4._

## Manual test checklist

Run on a physical iPhone. Each line is one check; note failures in `docs/ISSUES.md`.

### Audio session
- [ ] Play, then receive a phone call. Music pauses. Decline or end the call: music resumes.
- [ ] Play, then trigger Siri and dismiss it. Music pauses and resumes.
- [ ] Play, then start a video in another app. Music stops. Close the video: music does not resume on its own unless iOS offers resumption.
- [ ] Pause, then receive and end a call. Music stays paused.
- [ ] Play, receive a call, press play then pause during the call, end the call. Music stays paused.
- [ ] Play through wired or USB headphones, unplug them. Music pauses and does not play through the speaker. Plug back in: still paused.
- [ ] Play through Bluetooth headphones, turn them off. Music pauses, no speaker output. Turn them back on: still paused.
- [ ] Play, switch output to AirPlay or a Bluetooth speaker from Control Center. Music continues on the new device.
