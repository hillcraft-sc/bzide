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
- Failures are covered under "Network recovery" below. If a stream URL can't be built, the track fails without retrying.

### Audio session and interruptions

- Before every play, the app claims audio output for long-form music playback (category playback, long-form audio routing policy, which routes to AirPlay and CarPlay like other music apps). If the system refuses, the track fails with "Can't play right now: <reason>".
- When the system takes audio away (call, Siri, alarm, another app), playback pauses. If music was playing, the app remembers that.
- When the system later sends its resumption recommendation, playback resumes only if music was playing before the interruption **and** the system recommends resuming. A missing recommendation means don't resume.
- If the user presses play or pause during an interruption, their choice wins and the app won't auto-resume.
- When the output device goes away (headphones unplugged, Bluetooth disconnected), playback pauses and stays paused. It never continues through the speaker, and reconnecting does not auto-resume.
- When the system restarts its audio services ("media services were reset"), the app throws away its player and builds a new one. If music was playing (or buffering, or reconnecting), it reloads the current track at the same position and keeps playing; the user didn't stop it and the output route hasn't changed. If it was paused, it stays paused, and play picks up at the same position.
- Before a full audio reset the system first reports that media services were lost, and the audio system can stay down for many seconds (about 18 on device). During that outage the app shows paused, ignores the player's failure reports (they aren't real track failures), and doesn't retry anything. The tracks can fail a moment before the loss is announced; that failure starts reconnecting, which still counts as music on, so the resume still happens. While the outage lasts the app isn't playing, so iOS may suspend it and remove it from Control Center; it resumes once the reset arrives, which in practice can be when the user returns to the app. Pressing play during the outage shows reconnecting and starts once audio is back; pressing pause cancels the automatic resume. The queue is unchanged, Now Playing is sent again in full, and it counts as the same play for scrobbling.

### Lock screen, Control Center and remote commands

- Now Playing shows the current track's title, artist, album, artwork, duration and elapsed time. An empty queue clears it.
- A restored queue is sent to Now Playing paused at its saved position, but iOS 27 doesn't show the app in Control Center or on the lock screen until it has actually played since launch (observed on device, 2026-10-10). After the first play, it shows normally.
- Updates are sent on play, pause, seek, track changes and status changes, not on every time tick: the system extrapolates elapsed time from the playback rate (1 while playing, 0 otherwise, including while buffering). Unchanged info is not re-sent.
- Artwork is fetched by cover art id after the text appears. If the track changes before the image arrives, the late image is discarded.
- Remote commands (lock screen, Control Center, headphone buttons, CarPlay) map to the engine's own commands: play, pause, toggle, next, previous, and seek by dragging the progress bar. They follow the same rules as the in-app buttons.
- Next is disabled on the last track. Previous is always enabled, because it restarts the track when there's nothing before it.

### Network recovery

- If the current track fails while the user is listening, status becomes **reconnecting** and the engine retries automatically: it builds a fresh stream URL and resumes at the last known position. Retries wait 1, 2, then 4 seconds. After the third retry fails, status becomes failed with the error message.
- The retry budget resets only after 10 seconds of uninterrupted playback following a retry, so a stream that keeps dropping right after starting doesn't retry forever.
- If the current track fails while paused, status becomes failed with no automatic retry. Play retries it.
- A stall (the player ran out of buffered audio) gets 10 seconds to recover by itself. If it isn't playing by then, it is treated as a failure and the retries above apply.
- When the network comes back (offline to online, or a switch such as Wi-Fi to cellular), a pending retry runs immediately. If retries had run out while the user was listening, playback is retried once more with a fresh budget. A paused player is never started by this.
- If the preloaded next track fails, it is rebuilt in the background (same 1, 2, 4 second schedule) without interrupting the current track, so the hand-over stays gapless.
- Pause, play, next, previous, jump and starting a new queue cancel any pending retry. So do interruptions and losing the output device. A track change gives the new track a fresh retry budget.
- While reconnecting, the lock screen shows the track as paused (playback rate 0).

### Scrobbling

- A track is scrobbled once it has played for 50% of its duration or 4 minutes, whichever comes first. If the duration is unknown, 4 minutes.
- Only time actually listened counts toward the threshold. Seeking forward does not add to it; seeking back does not remove from it. Listening is counted from the player's time ticks (about every half second); any forward jump over 2 seconds counts as a seek.
- A play begins when a track becomes current (natural advance, next, previous, jump, new queue), when previous restarts the current track, and when the last track ends (so playing it again is a new play). Seeking within a track does not start a new play. A queue restored after relaunch starts a fresh play at the saved position; listening from before the relaunch is not counted.
- Each play is scrobbled at most once, with the time the play began.
- "Now playing" is sent once per play, when it first plays (including when one track flows straight into the next). It is best effort and never retried.
- Scrobbles are saved to `Application Support/PendingScrobbles.json` before sending and removed only once the server accepts them. They are sent oldest first, never in parallel, stopping at the first failure. Pending ones are retried at the next scrobble and at launch.
- Known limit: if the server records a scrobble but the reply is lost, it will be sent again and may count twice.

## Queue

- The queue is an ordered list of entries plus a current position. Each entry has its own id, so the same song can appear more than once and the UI and player can tell the copies apart.
- A new queue starts at the requested index, clamped into range. An empty queue has no current entry.
- Next moves to the following entry. At the last entry it does nothing.
- Previous: if the current track has played more than 3 seconds, restart it. Otherwise go to the previous track. On the first track, restart it.
- Jumping to an entry that isn't in the queue does nothing.
- Appending adds to the end. Appending to an empty queue makes the first added song current.
- Shuffle play shuffles the chosen songs once and plays them as an ordinary queue starting at the first. There is no shuffle mode that stays on, and repeat is not implemented yet.

### Persistence

- The queue and the position within the current entry are saved as JSON to `Application Support/PlaybackQueue.json`, replaced atomically so a crash never leaves a half-written file.
- The file stays writable while the device is locked (after the first unlock since boot), because saves happen during locked-screen playback.
- A saved file that can't be read is reported, not crashed on; the app starts with an empty queue. A saved current index outside the entries is clamped into range.

## Library

- **Loading.** Each screen fetches what it shows when it appears. Until that arrives it shows loading; if it fails with nothing to show, the error and a retry. A refresh keeps the current content on screen; if the refresh fails, the content stays and the error is reported alongside it. A load that's still running when the screen goes away is dropped, and runs again when the screen comes back.
- **Album lists** come in these orders: recently added, recently played, most played, name, artist, random, starred. They load 40 albums at a time; the next page is requested when the user scrolls within 10 albums of the end, and a page shorter than 40 means there are no more. An album already shown is never shown twice, even if the library changed between pages; the next request still starts where the server's previous page ended. If a page fails, scrolling doesn't retry it; an explicit retry does. Random shows a single page, and a refresh picks again, because paging a random list would repeat albums. Changing the order replaces the list, and a late reply for the old order is ignored.
- **Search** runs 300 ms after the user stops typing, with surrounding spaces ignored. An empty query clears the results. While a new search runs, the previous results stay on screen. A reply for an older query is ignored, so results never jump back to something the user has already typed past.
- **Starring** shows the change immediately, then tells the server. If the server call fails, the star goes back to how it was and the error is shown. A second tap on the same item while its first change is still being sent is ignored. A change made in this session wins over the flag in lists fetched earlier, so every screen agrees.
- **Playing from the library.** Tapping a track plays its album or playlist from that track. Play starts at the first track; shuffle plays the same songs in a shuffled order (see Queue). Add to queue appends the songs to the end of the current queue without interrupting playback.

## Caching and offline

_Filled in during M4._

## Manual test checklist

Run on a physical iPhone. Each line is one check; note failures in `docs/ISSUES.md`.

### Basics
- [ ] Play an album, lock the phone, and leave it for several tracks. Playback continues track to track with the screen off.
- [ ] Play, switch to another app (Safari, Messages). Playback continues.
- [ ] Play an album that is meant to be gapless (a live album or continuous mix). Track changes have no audible gap or click. Note the file format if there is one.
- [ ] Skip quickly with next several times in a row. Each skip lands on the right track and the queue view agrees.
- [ ] Play a few tracks into an album, pause mid-track, force-quit the app (swipe it away), relaunch. The same track is shown, paused at roughly the same position. Press play: it resumes there.
- [ ] Same, but force-quit while playing. Relaunch: same track, paused, position within about 10 seconds of where it was.
- [ ] Let the last track of a queue finish. Playback stops on it, rewound. Pressing play starts it again.

### Audio session
- [ ] Play, then receive a phone call. Music pauses. Decline or end the call: music resumes.
- [ ] Play, then trigger Siri and dismiss it. On iOS 27 the system sends no interruption for Siri, so music keeps playing (possibly quieter while Siri talks). Check only that playback is still going normally afterwards.
- [ ] Play, then start a video in another app. Music stops. Close the video: music does not resume on its own unless iOS offers resumption.
- [ ] Pause, then receive and end a call. Music stays paused.
- [ ] Play, receive a call, press play then pause during the call, end the call. Music stays paused.
- [ ] Play through wired or USB headphones, unplug them. Music pauses and does not play through the speaker. Plug back in: still paused.
- [ ] Play through Bluetooth headphones, turn them off. Music pauses, no speaker output. Turn them back on: still paused.
- [ ] Play, switch output to AirPlay or a Bluetooth speaker from Control Center. Music continues on the new device.
- [ ] Play, then Settings > Developer > Reset Media Services (iOS 27 lists each service separately; try each, especially Reset Audio Services). Music resumes by itself within a few seconds, at about the same point, and the lock screen shows the track with working controls. Repeat while paused: it stays paused, and play resumes at the same point.

### Lock screen and Control Center
- [ ] Play, lock the phone. Lock screen shows title, artist, album, artwork and a moving progress bar.
- [ ] Pause and play from the lock screen. The app follows, and the progress bar stops and starts at the right time.
- [ ] Next and previous from the lock screen follow the same rules as in the app (previous restarts after 3 seconds).
- [ ] Drag the lock screen progress bar. Playback jumps there.
- [ ] On the last track, next is disabled.
- [ ] Control Center shows the same info and controls.
- [ ] Wired or Bluetooth headphone buttons play, pause and skip.
- [ ] Skip quickly through several tracks. Artwork always matches the track shown.
- [ ] Force-quit the app and relaunch, then press play. Control Center and the lock screen show the restored track. (Before pressing play they show nothing; that's iOS behavior.)

### Network recovery
- [ ] Play on Wi-Fi, walk out of Wi-Fi range (or turn Wi-Fi off) so the phone switches to cellular. Playback continues, or resumes within a few seconds at the same point.
- [ ] Play, turn on Airplane Mode for 5 seconds, turn it off. Playback resumes at the same point without pressing anything.
- [ ] Play, turn on Airplane Mode for 30 seconds or more, until the app shows failed. Turn it off. Playback resumes by itself.
- [ ] Pause, turn on Airplane Mode, turn it off. The app stays paused.
- [ ] Play, turn on Airplane Mode, then press pause while it shows reconnecting. Turn Airplane Mode off. The app stays paused.
- [ ] Play near the end of a track on a weak connection. The next track still starts without a gap, or with only a short one.
- [ ] Lock the phone during all of the above. Recovery works the same with the screen off.

### Scrobbling
- [ ] Play a track past halfway (or 4 minutes). It appears once in Navidrome's play history, at the time you started it.
- [ ] Play a track, skip to near the end, let it finish. It is not scrobbled.
- [ ] While a track plays, Navidrome shows it as now playing. Let it flow into the next track: now playing updates.
- [ ] Turn on Airplane Mode, play two tracks past halfway, turn Airplane Mode off and play a third. All three appear in order.
- [ ] Turn on Airplane Mode, play a track past halfway, force-quit the app, turn Airplane Mode off, relaunch. The track appears.
