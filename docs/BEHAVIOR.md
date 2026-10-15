# Behavior spec

How the app behaves, written so the web and Android clients can be ported from this file rather than from the Swift code. Each playback rule gets a manual checklist entry for testing on a real device.

## Server communication

- Protocol: Subsonic API 1.16.1 as implemented by Navidrome, JSON (`f=json`), HTTP GET.
- Requests go to `<base URL>/rest/<endpoint>`. Any path in the base URL is kept, so servers behind a reverse proxy subpath work.
- Only `http` and `https` base URLs are accepted.
- Auth: every request carries `u`, `t = md5(password + salt)`, `s = salt`, `v`, `c` (the client name, `Bzide`). The salt is 16 random bytes as hex, new for every request. The plain password is never sent.
- Query values are percent-encoded including `+`, because the server decodes a bare `+` as a space.
- Auth parameters (`t`, `s`, `u`, `p`) are replaced with `REDACTED` before a URL is logged.
- Errors are reported as one of: invalid base URL, network failure, non-2xx HTTP status, server `status: "failed"` (with the Subsonic error code), or an unreadable response. Codes 40 and 41 count as authentication failures.
- Decoding is tolerant, because servers fill fields inconsistently:
  - An item without a non-empty `id` is dropped. Nothing else in its list is affected.
  - Any other field that is missing, `null`, or the wrong type is treated as absent. Numbers sent as strings (`"320"`, `"187.0"`) and booleans sent as strings are accepted. Missing names and titles become empty strings; the UI chooses a placeholder.
  - A list sent as a single object is treated as a one-element list. A missing list is empty.
  - List endpoints (`getArtists`, `getAlbumList2`, `getPlaylists`, `getRandomSongs`, `search3`) return an empty result when the wrapper object is missing. Single-item endpoints (`getArtist`, `getAlbum`, `getPlaylist`) report an error. `getArtistInfo2` is the exception: a missing or empty `artistInfo2` means the server knows nothing more, not an error.
  - `starred` is read as "starred if present", ignoring the date.
  - `userRating` is 1–5 stars; 0, missing, or anything out of range means unrated.
- Media (`stream`, `download`, `getCoverArt`) is fetched by URL, not through the API client. These URLs contain a valid token, so they are built on demand and never logged or persisted.
- Scrobble times are sent in milliseconds since the Unix epoch. `submission=false` updates "now playing" only.
- OpenSubsonic: `getOpenSubsonicExtensions` returning a server error or HTTP 404 means "no extensions", not a failure. Network failures are still reported.

## Account

- One account (server address and user) is signed in at a time. Its login is in the Keychain only.
- Settings shows the user and the server's host name beside a profile picture (a person symbol unless a Gravatar is shown), and Sign Out (after confirmation).
- **Profile picture** (Settings > Profile > Picture): None (the default), Contact Card, Photo or Gravatar. A picture replaces the Settings gear on Library and shows at the top of Settings beside the user; with None, or a choice that has no picture yet, the gear stays (and Settings shows a person symbol). iOS gives apps no way to read the Apple Account photo, and on iPhone no way to know which contact is the user, so these are the closest options.
  - **Contact Card:** "Choose Contact Card…" opens Apple's contact picker (contacts without a photo can't be picked); only the picked contact's photo reaches the app, so no Contacts permission is asked. **Photo:** "Choose Photo…" opens Apple's photo picker; only the chosen photo reaches the app, no Photos permission. Either is cropped to a centered square, shrunk to 480 pixels and saved (`Application Support/ProfilePictures`, one per choice, so switching back keeps it). Later changes to the contact or photo don't carry over until it's picked again. An image that can't be read says so.
  - **Gravatar:** the email is the one typed in Profile, or, if that's empty, the one on the server account (`getUser`, asked only once Gravatar is chosen, once per session). The account email is remembered with the profile, so offline at launch the saved picture is still found; when the server answers, a changed email is followed, and a failed request leaves the remembered one in place. It's looked up as the SHA-256 of the trimmed, lowercased address (`https://gravatar.com/avatar/<hash>?s=240&d=404`), so the address itself is never sent; `d=404` means only a real picture counts, never a stand-in face. Typing waits 0.6 s after the last keystroke. Profile shows what happened: found (with the picture), no Gravatar for this email, the account has no email, not an email address, or Gravatar couldn't be reached. A picture, or "none for this email", is kept for a day in `Caches/Gravatar`, so it shows at once on launch and offline; when a lookup fails, the last picture stays. Requests use their own cookie-less session.
  - The choice and email (`Application Support/Profile.json`) and all saved pictures are account data (below). Settings saved by the first, Gravatar-only version carry over.
- Sign out pauses playback (saving the position), unloads the player, clears the lock screen and Control Center, tries once to send unsent scrobbles, and removes the login. It does not delete anything else.
- Downloads, the saved queue, unsent scrobbles, play history, cached cover art and the profile (picture choice, email and saved pictures) belong to the account they came from. Signing back in to the same account keeps them all. Signing in to a different server or user deletes them before anything loads, so nothing from one account (in particular, scrobbles) reaches another.
- The owning account is recorded as a SHA-256 fingerprint of the server address and username, never in plain text. The same server written differently (letter case, trailing slash) is the same account; the username must match exactly. Data from before this check existed is assumed to belong to whoever signs in next.
- Device settings (streaming quality, downloads over cellular) and how long history is kept are not account data and stay as they are.
- CarPlay switches to "Sign in on your iPhone" on sign-out and back to the library on sign-in.

## Playback

- One engine owns the queue and playback state. The UI shows that state and sends commands; it never changes playback itself.
- Status is one of: idle (nothing queued), paused, buffering, playing, or failed (with a message).
- Gapless: the player always holds the current track and the one after it, so the next track is buffered before the current one ends. When a track ends, the player moves on by itself and the engine loads the track after that.
- Next uses the already-buffered next track. On the last track it does nothing.
- Previous, jump, and starting a new queue load the chosen track from the start, keeping the play/pause state.
- When the last track ends with repeat off, the queue is done: it is emptied, status becomes idle, and Now Playing (lock screen, Control Center) is cleared. If the player runs out while the queue still has a next track (it couldn't be loaded in time), playback carries on with that track instead.
- Seek is clamped to the track's length.
- Duration comes from the server's metadata until the player knows the real duration.
- Stream URLs contain auth tokens, so they are built only when a track is loaded and are never saved.
- On launch, a saved queue is restored paused at its saved position. Nothing loads or plays until the user presses play.
- The queue is saved whenever it changes. While playing, the position is saved every 10 seconds of playback, and on pause and seek.
- Failures are covered under "Network recovery" below. If a stream URL can't be built, the track fails without retrying.

### Audio session and interruptions

- The audio category (playback, long-form audio routing policy, which routes to AirPlay and CarPlay like other music apps) is set once at launch, while the session is inactive, and again after a media services reset, which forgets it. On every play the app then activates the session asynchronously (iOS 27's non-blocking activation, so the main thread never waits) and starts the player only once it's active; meanwhile the status is Buffering, and the player's own "paused" reports are ignored. Pausing, an interruption, media services going down, the queue ending or a new queue cancels a waiting activation, so a late one never starts playback; a skip to the preloaded next song keeps it, and that song starts when it completes. If the system refuses, the track shows as failed ("Can't play right now: …") and play tries again.
- When the system takes audio away (call, Siri, alarm, another app), playback pauses. If music was playing, the app remembers that.
- When the system later sends its resumption recommendation, playback resumes only if music was playing before the interruption **and** the system recommends resuming. A missing recommendation means don't resume.
- If the user presses play or pause during an interruption, their choice wins and the app won't auto-resume.
- When the output device goes away (headphones unplugged, Bluetooth disconnected, car turned off), playback pauses and stays paused. It never continues through the speaker, and reconnecting does not auto-resume by itself. Many cars send a play command when they reconnect; that arrives as an ordinary remote play and resumes at the saved position (seen on device, 2026-10-11).
- When the system restarts its audio services ("media services were reset"), the app throws away its player and builds a new one. If music was playing (or buffering, or reconnecting), it reloads the current track at the same position and keeps playing; the user didn't stop it and the output route hasn't changed. If it was paused, it stays paused, and play picks up at the same position.
- Before a full audio reset the system first reports that media services were lost, and the audio system can stay down for many seconds (about 18 on device). During that outage the app shows paused, ignores the player's failure reports (they aren't real track failures), and doesn't retry anything. The tracks can fail a moment before the loss is announced; that failure starts reconnecting, which still counts as music on, so the resume still happens. While the outage lasts the app isn't playing, so iOS may suspend it and remove it from Control Center; it resumes once the reset arrives, which in practice can be when the user returns to the app. Pressing play during the outage shows reconnecting and starts once audio is back; pressing pause cancels the automatic resume. The queue is unchanged, Now Playing is sent again in full, and it counts as the same play for scrobbling.

### Audio levels (visualizer groundwork)

- The player can tap each item's audio (an `MTAudioProcessingTap` on its audio mix) to measure live left/right levels for a future visualizer. The tap passes the audio through untouched and its real-time callbacks never lock or allocate: they measure with vDSP and store numbers in atomics that the UI reads as it draws.
- Every item is tapped when it's loaded, before it plays (a streamed item once its audio track has loaded, normally while it buffers), and the tap stays until the item is gone. Adding or removing a tap on an item that's playing makes AVFoundation rebuild its audio chain, heard as a skip, so the tap is never added or removed mid-song. What's switched is only whether it measures: off by default and at every launch, on while the visualizer is open (or the Debug player's "Audio tap" switch is on). Not measuring, it just passes the audio through.
- Over AirPlay the tap sees no audio, so the levels stay still while playback itself is unaffected (confirmed on device 2026-10-12). AirPlay 2 sends the encoded audio to the receiver, which decodes and plays it; it never passes through the phone's local audio path where the tap sits. A visualizer needs a fallback while AirPlay is the output.
- Radio stations get no levels either (playback unaffected; confirmed on device 2026-10-12). A live stream reports no audio track up front, and even attaching the tap to the track the playing item exposes later (tried the same day) gives no audio: the tap is attached but never called. AVFoundation plays endless streams through a path that skips audio taps, so a visualizer needs the same fallback for radio as for AirPlay.

### Visualizer

- Now Playing's waveform button (in the row with the heart, rating and AirPlay) opens a full-screen visualizer on black, with a close button and a capsule naming the current style at the top, and the song's title and artist with previous, play/pause and next at the bottom (the same commands as Now Playing: previous off for radio, next only when there's a next song), so it needn't be closed to change track. Sideways (wider than tall), the title and controls move to a panel on the right, vertically centered, so the drawing gets the full height on the left; Plasma still fills the screen, darkened toward the panel instead of top and bottom. Two styles, changed by swiping left or right or from the capsule's menu: **Bars**, about 40 spectrum bars, bass on the left to treble on the right (60 Hz to 16 kHz, spaced like musical pitch); **Waveform**, the sound wave as a glowing line across the middle; and **Plasma**, the classic demoscene effect over the whole screen behind the controls (a Metal shader, `Plasma.metal`): four sine waves interfere into fine swirling bands that cycle through the palette twice, at steady brightness, darkened a little at the top and bottom so the controls stay readable. The music drives it without strobing: a **beat** signal jumps when the bass rises suddenly above its recent average (by 0.25 or more for a full beat; the average follows at 3/s) and fades at 5/s, and each beat zooms the pattern in slightly, sends a ripple through it, pushes the flow on and lifts the brightness by at most 10%. The flow is a clock that only moves forward, at 0.4 to 1.4 times its normal pace by mid-range energy plus the beat's push, so it never jumps. The bass swells the circular rings, the mid-range strengthens the diagonal bands, and the treble adds a fine shimmer and slides the colors along.
- **Polygraph**, after a lie detector: off-white chart paper fills the whole screen, running past four steel needles at 70 points a second, with the controls floating over it in dark ink instead of white (a black play button; the text and buttons get a soft halo of paper so the ink under them doesn't clutter them). In portrait the needles reach down from pivots above the top edge, their tips just below the menu, and the paper runs down; sideways they reach in from the left and the paper runs right, away from the controls panel. The grid (lines every 16 points, every fifth darker) covers the sheet and moves with the paper. Pens 1–3 follow the bass, mid-range and treble: each swings either way around its lane's center by how much its part is louder (or quieter) than it has been lately (its own average, following at 0.8/s; a change of 0.25, 0.2 and 0.15 respectively is a full swing), so the lines wander rather than pinning to one side, and drum hits kick the bass pen. Pen 4 draws the overall loudness (the average of all the bands) as back-and-forth hatching: none at 0.15 or below, full width at 0.6 or above, in proportion between, so quiet songs draw a thin band, loud ones a wide one, and a swell into a chorus widens it. The pens are stiff, lightly damped springs, so they overshoot and wiggle like real needles, and stop at the edge of their lanes. Paused, the paper keeps running and the pens rest at center, drawing four flat lines as if nothing is being recorded; each pen's "lately" holds still meanwhile, so playing again picks up smoothly instead of jolting. The inks are the visualizer's colors (one per pen in Multicolor and Custom), darkened 30% so pale ones read on the paper. 20 seconds of paper are kept.
- **Groove** (an original style) is a record turning under a steel tonearm with a ball pivot (after the app icon), the album cover as its label, its groove cut as the song plays. Loudness is kept 20 times a second of song time (from the bass, mids and treble, plus the beat); loud moments engrave a deep wiggle (depth by the square of the level, at most a third of the gap between turns), quiet ones a smooth line. The groove spirals from the edge to the label over the song's length, the record turning about once every 7 seconds, so the finished record shows the whole song. What's still to come is blank vinyl; moments played before the visualizer opened (not heard) are a plain gray line. Song time runs smoothly between the engine's position updates and follows seeks; a new song starts a blank record. In Multicolor and Custom the groove changes color from the edge inward.
- **Living Cover** (an original style) cuts the album cover into an 8×8 grid of tiles over a blurred, darkened copy of itself filling the screen. Bass and beats push the tiles out from the center (outer tiles further), the mids tilt them with neighbors in opposite directions, each tile lifts with its own band (bass in the middle, treble at the corners), and treble makes the tile edges sparkle in the visualizer's colors (one per row in Multicolor and Custom). With no music every tile is in place, so the cover is whole. An album without a cover shows tiles in the visualizer's colors.
- **Tapestry** (an original style) weaves the song into cloth from the top down, one row every half second of song time, under a steel loom beam whose shuttle crosses once per row trailing its thread. Each of 20 threads is a frequency band (the spectrum's bands averaged in groups, bass on the left), and each row keeps the loudest its band got during that half second: the louder, the wider (a third of the thread's space when silent, nearly all when loudest) and brighter (four shades). The whole song's rows fit the height (a song running past its stated length squeezes up to keep fitting), so the finished cloth shows the whole song. Below the loom the bare warp threads wait; rows played before the visualizer opened (not heard) are woven as bare threads. Song time is kept as in Groove (smooth between updates, follows seeks, a new song starts fresh cloth); pausing stops the weaving. In Multicolor and Custom each thread has its own color across the sweep.
- **Weather** (an original style) is a small landscape (two rolling hills with a row of trees) under a sky that follows the music, filling the screen behind the controls (darkened under the menu, and toward the panel sideways). The weather changes gradually: **cloud cover** follows how busy the music is (mostly mid-range and treble) at 0.4/s, so a calm passage clears the sky and a busy one clouds it over in a few seconds; the sun fades as clouds come in, and up to eight clouds appear and darken with the cover (one light cloud stays on clear days). The **wind** follows the bass (1.2/s): it drifts the clouds (always a little, never jumping), slants the rain, and bends and sways the trees. **Rain** follows the treble, only once the sky is more than half covered. **Lightning** strikes on a beat's rising edge (0.6 or more) in a storm, at most once every 0.6 s, as a jagged forked bolt that fades over half a second; the sky lifts by at most 10%, never a flash of the whole screen. The sky runs from the palette's darkest color overhead to its lightest at the horizon (a dusky sky in the accent, or the sweep's colors in Multicolor and Custom), turning storm gray as it clouds over.
- **Chrome** (an original style) is a blob of liquid metal, like the steel of the app icon, reflecting the album cover (a Metal shader, `Chrome.metal`). Its outline is 128 points around the middle, joined by smooth curves: each of the spectrum's bands pushes out a bulge at its own height, mirrored left and right, bass at the bottom and treble at the top, blending with its neighbors (at most 0.4 of the resting size, which is a third of the drawing space's shorter side); a slow wobble keeps it moving when quiet, and a beat swells it all by 8% and sends rings across its surface. A strong drum hit (beat 0.6 or more, at most every 0.25 s) also **splashes** three to five droplets (each a tenth to a fifth of the blob's size) from random places just past its edge, flying outward; they slow and are pulled back like beads of mercury, stopping at the edge of the free space if they reach it, and melt back into the blob about 2.5 seconds later (at most 16 at once). The blob and droplets are drawn as one surface that melts together where they come close, so a droplet stretches a neck of metal as it leaves and as it rejoins. Inside, it's shaded as a dome: the surface's slope picks which part of the cover it reflects, like a polished ball, toned 30% toward steel, with a highlight at the top left and the visualizer's colors catching its edges (four, going around it). Without a cover it reflects plain steel, light above and dark below.
- **Typeset** (an original style) sets the song's title big in heavy rounded type (SF Pro Rounded), with the artist below, centered: the title as large as fits in up to three lines (76 pt down to 26 pt) and the artist at about 40% of that in up to two, leaving a quarter of the height and 6% of the width either side spare for movement; letters moving past the drawing space are still drawn, so nothing is cut off before the screen's edge. The small title at the bottom is hidden, since the screen is the title. The letters move with the feel of the track, each riding springs toward where the music puts it, so they leap and settle rather than tremble. Each plays its part of the spectrum by its place in the words (the title's first letter bass, its last treble; the artist's spread the same way), averaging its band with two either side. A letter **jumps when its part gets louder than it has been lately** (its level compared with its own average over about the last second; a rise of 0.4 is a full jump of 0.6 of the font size, stretching it up to 30% taller from its baseline) and dips a little (up to 0.15) when it gets quieter; as a new level becomes normal it settles back home, so a loud song keeps the words in place and only the changes move them. It brightens with how loud its part is (very quiet parts, below 0.08, stay dim), the loudest glowing. A bass hit (the bass rising above its own recent average; a rise of 0.3 is full) thumps the whole title up together (up to 0.35, lifting without stretching); a steady bass line doesn't. Treble leans the letters all the same way (up to 0.18 rad at the treble end, so neighbors don't collide), and loudness swells the words by up to 12%. A strong drum hit (beat 0.6 or more, at most every 0.3 s) makes the letters jump out: each pops bigger and is thrown, mostly upward and with a spin, then springs back. A **calm** measure follows how loud the music has been over the last few seconds (0.5/s): soft passages float the letters on a slow wave (up to 0.14 of the font size) with a gentle sway, and the springs go from loose and drifting when calm to tight and punchy when loud. The artist moves half as much as the title. In Multicolor and Custom the letters run through the sweep.
- Colors, from the same menu: **Accent** (the theme's accent); **Multicolor**: in a Catppuccin theme its 14 accents in palette order blended across the screen, otherwise a sweep of hues starting from the accent (red → orange → yellow → green → teal for Bzide Red, blue → purple → pink → orange for blue); and, in Catppuccin themes only, **Custom**: the accents the user picks ("Choose Custom Colors…" in the menu opens 14 swatches; at least two; mauve, pink, peach, teal and blue to start), blended in palette order. Custom is remembered; in a non-Catppuccin theme it shows as Multicolor. Bars take a color each; the waveform a left-to-right gradient; Plasma loops through four of them (in Accent, shades of the accent from deep to light). Style and colors are remembered on the device. While it's open the audio tap runs and the screen doesn't dim; closing it turns both back to how they were.
- Each frame takes the latest 2048 samples (mixed to mono), applies a Hann window and a Fourier transform, and takes each band's peak on a decibel scale (−75 dB empty to −15 dB full), so quiet passages still move. Bars rise quickly and fall at most 1.6 of their height per second. When no new audio has arrived for a quarter of a second (paused, between songs, or the tap isn't running) they fall to a sliver rather than freezing.
- The waveform shows 512 samples (about 12 ms) starting at a rising zero crossing, so it holds still like an oscilloscope, averaged to 128 points and scaled up 2.5× for typical music levels. It eases halfway to each new frame, and flattens out when the audio stops.
- For a radio station it shows "The visualizer isn't available for radio.", and over AirPlay "The visualizer isn't available over AirPlay." (neither can be tapped; see Audio levels). Both follow changes while it's open.

### Spin Off and Keep Spinning

- **Spin Off** (a song's long-press menu, an artist's long-press and ⋯ menus, and Now Playing's ⋯ menu for the current song) plays endless music grown from a song or an artist. A song plays first, then the first batch; an artist starts straight into its batch. Now Playing's queue heading reads "Spin-off of “…”" while it lasts.
- **Where the songs come from**, in order, so it works on any server: the server's similar songs (`getSimilarSongs` for a song, `getSimilarSongs2` for an artist; Navidrome needs an agent such as Last.fm, and returns nothing without one), shuffled; else random songs from the seed song's genre (`getRandomSongs` with `genre`); else random songs from the whole library. Songs already in the queue and repeats are left out; a batch is up to 25 songs. A mix says why in a banner for 5 seconds ("Similar songs aren't available from this server, so this is a mix of Rock."). If nothing can be found (offline), the queue is left as it was and a banner says so.
- **It keeps going:** whenever the current song changes and 2 or fewer songs are left after it, the next batch is fetched and added at the end without a gap. Skipping songs while a batch is being fetched doesn't lose it, and if the queue is low again by the time it arrives, another is fetched. The seed is saved with the queue, so it carries on after a restart (a queue saved before spin-offs existed isn't one). Playing anything else ends it. Starting a spin-off turns repeat off, since it's endless; turning repeat back on afterwards loops the queue instead of growing it.
- **Keep Spinning** (Settings > Playback, off by default): when any queue reaches its last song, Bzide spins off from that song the same way, so the music keeps going, and the queue becomes a spin-off. Not with repeat on, and not for radio.

- **Meh songs** (rated Meh, 1 or 2 of the server's 5 stars) are left out of Random Mix (from the server and from downloads), Spin Off's and Keep Spinning's suggestions, unless Settings > Playback > Include Meh Songs is on (off by default). A song the user spins off from plays even if it's Meh, since they picked it. Unrated songs, and servers without ratings, are never left out. Mix My Cuts never includes Meh either way. Random Mix still asks for 50 songs, so a mix can be a few short when some were Meh.

### Volume normalization

- Settings > Playback > Volume Normalization: Off (the default), By Track or By Album. It evens out loudness between songs with their ReplayGain (OpenSubsonic `replayGain` on each song: track and album gain in dB, and track and album peak), which Navidrome has when the music files are tagged with it; it doesn't calculate it. Songs without it, and radio, play unchanged.
- **By Track** uses the track's gain (falling back to the album's), **By Album** the album's (falling back to the track's), so an album's quiet and loud songs keep their difference. A boost is capped so the song's peak (of the gain used) stays at full scale, so normalization never clips.
- The gain is applied in each item's audio tap (the same one the visualizer measures with), multiplying the samples on the audio thread without locks or allocation, so it can boost as well as cut. It's set when a song is loaded; changing the setting applies at once to the current, next and (for repeat all) first songs, without interrupting playback. The tap attaches as the item loads, normally before it's heard.
- Now Playing's quality line adds the adjustment in use, e.g. "FLAC · 964 kbps · −4.2 dB" (nothing when there's none).

### Sleep timer

- Now Playing's moon button (top bar, beside Save Queue) offers 15, 30 and 45 minutes, 1 hour, and End of Song; while a timer runs it also offers Turn Off Timer, and the button shows a filled moon and when the music will stop, counting down each second in the accent: the time left on the timer ("14:53"), or for End of Song the time left in the song ("End" if its length isn't known). Choosing again replaces the running timer.
- **Timed:** it counts to a fixed clock time, so it stays right with the screen locked and the app in the background. Over the last 10 seconds the music fades out (the player's own volume, on top of the system volume), then pauses, and the volume goes back to normal so the next Play isn't silent.
- **End of Song:** waits for the song playing when it was set. The song fades out over its last 4 seconds (position estimated smoothly between the engine's updates), and when it ends the music pauses: the next song, already started silently for gapless playback, is paused at once and the volume restored. Skipping to another song before the end moves the timer to that song; the queue running out ends it.
- Pausing early doesn't cancel it; it ends quietly. Turning it off mid-fade restores the volume. The timer isn't saved, so a forgotten one can't stop the music another day. The fade volume is kept if the player is rebuilt after a media services reset.

### Lyrics

- Now Playing's speech-bubble button (between AirPlay and the visualizer's waveform) opens the song's lyrics full screen over a blurred, darkened copy of its cover (a dark gradient without one), with a close button at the top and the title, artist, previous, play/pause and next at the bottom. It follows the queue: skipping changes the lyrics.
- **Where they come from**, in order, the first that has them winning: (1) the server's synced lyrics, (2) LRCLIB's synced lyrics, (3) the server's plain lyrics, (4) LRCLIB's plain lyrics. So synced lyrics win wherever they come from, and the server wins between equals. The server is asked for synced lyrics with OpenSubsonic `getLyricsBySongId` only if it advertises the `songLyrics` extension (checked once per sign-in; a failed check is tried again), and otherwise, or when it has none, for plain lyrics with classic `getLyrics` (by artist and title). Navidrome reads lyrics from the music files' tags and `.lrc` files beside them. A set marked synced with any untimed line is treated as plain; a structured set's `offset` (milliseconds) shifts its lines and word times.
- **LRCLIB** (lrclib.net, a free lyrics database) is asked only when Settings > Lyrics > Find Lyrics Online is on (off by default) and the server has no synced lyrics. A request sends the song's title, artist, album and length (`/api/get`); with no exact match, or no artist, it searches by title and artist (`/api/search`) and keeps a result within 3 seconds of the song's length, synced lyrics first. It identifies the app in its User-Agent, uses its own cookie-less session, and sends nothing else. LRCLIB's lyrics are credited ("Lyrics from LRCLIB") at the end.
- Results are kept for the session (per song and setting), so reopening is instant; a failure isn't kept, so it's tried again.
- **Synced lyrics** (LRC: `[mm:ss.xx]` line times, several times for a repeated line, `[offset:±ms]`, metadata tags skipped): lines are big and bold, left-aligned. The current line is the last to have started, shown 0.15 s early so the eye arrives with the voice; it's bright and sharp, its letters lighting up as each word is sung (60% bright before, full once sung), and the view scrolls smoothly to keep it about a third of the way down. Other lines are dimmed (35%), slightly smaller and softened, more so further away (up to 3 lines). An empty line is an instrumental break: three dots that breathe while it's current, otherwise almost no space. Lines fade out toward the top and bottom bars.
- **Word timing**: exact where the lyrics have word times (enhanced LRC, `<mm:ss.xx>` before each word, in a server line or an LRCLIB file); each word lasts until the next, the last at most 1.5 s. Otherwise estimated: a line's words share the time until the next line by their rough syllable counts (groups of vowels, a silent final "e" not counted), taking at most 90% of the gap and no more than 0.32 s a syllable plus 0.6 s, so a line before a long break isn't stretched out. Song time runs smoothly between the engine's position updates and follows seeks.
- Tapping a line jumps the song to it. Scrolling by hand stops the view following for 3 seconds after the scroll ends, then it returns to the current line.
- **Plain lyrics** scroll freely, all lines bright, verses separated, under a note that they aren't synced.
- With no lyrics anywhere: "No Lyrics: There are no lyrics for this song." An instrumental (LRCLIB says so): "Instrumental: This song has no words." Radio: "Lyrics aren't available for radio." If neither source could be reached: "Couldn't Load Lyrics" with a hint to check the connection.

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
- A play begins when a track becomes current (natural advance, next, previous, jump, new queue), when previous restarts the current track. Seeking within a track does not start a new play. A queue restored after relaunch starts a fresh play at the saved position; listening from before the relaunch is not counted.
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
- Clear up next removes every entry after the current one. The current track keeps playing (the player drops its buffered next track), and when it ends the queue is done, as at the end of any queue.
- The queue as shown is the current entry and what's after it. Entries already played are kept out of sight, so previous can still go back to them, until the queue ends or is replaced.
- Play next inserts songs right after the current entry, ahead of everything else upcoming; the most recent play next goes first. The current track keeps playing; the track the player had buffered as next is swapped for the first inserted song, so the handover stays gapless. On an empty queue it behaves like appending (queued, not started). A queue restored after relaunch and not yet played isn't loaded just to insert.
- **Editing up next.** In Now Playing's queue, swiping an upcoming song left offers Remove, and long-pressing and dragging an upcoming song moves it. Only upcoming entries can be edited: the current song stays at the top (neither removable nor movable) and played entries stay hidden and untouched. Removing takes out just that entry, even if the same song is queued again. If the edit changes which entry plays next, the player's buffered next track is swapped, without interrupting the current one, so the handover stays gapless; an edit further down leaves the buffer alone. Edits are saved with the queue. On a restored queue that hasn't been played yet, editing doesn't load the player.
- **Shuffle** is a mode, turned on and off by the button left of the playback controls (gray when off, the accent color when on).
  - Turning it on shuffles the upcoming entries; the current song plays on, and played entries are untouched. The original order is remembered.
  - Turning it off puts the upcoming entries back in that original order; the current song plays on. Entries added while shuffled (play next, add to queue) keep their places; removed ones are simply gone; reorders made while shuffled are undone.
  - Shuffle buttons elsewhere (album, playlist, genre, menus, Siri) start the songs in a random order with shuffle on, so turning it off continues with the songs not yet played in their original order. Play, and anything else that starts a new queue in order, turns shuffle off.
  - The mode and the original order are saved with the queue (a queue saved before shuffle existed has it off). It can't be turned on for a radio station.
  - Either way, if the entry that plays next changes, the buffered next track is swapped without interrupting the current one; otherwise the buffer is left alone.
- Repeat has three modes, stepped through by one button: off, repeat all, repeat one. It's saved with the queue (a queue saved before repeat existed has it off) and stays as set when a new queue starts.
  - **Off:** when the last track ends, the queue is done (see Playback).
  - **Repeat all:** after the last track the queue starts again from the first entry, including entries already played. On the last track the player preloads the first, so the wrap is gapless, and next wraps too. A queue of one track plays it again.
  - **Repeat one:** the current track plays again when it ends, as a new play (scrobbled and added to history each time). Nothing is preloaded, so there is a brief gap at the restart. Next and previous still move between tracks, and repeat one stays on.
  - Changing the mode while playing swaps the preloaded next track to match, without interrupting the current one.

### Persistence

- The queue and the position within the current entry are saved as JSON to `Application Support/PlaybackQueue.json`, replaced atomically so a crash never leaves a half-written file.
- The file stays writable while the device is locked (after the first unlock since boot), because saves happen during locked-screen playback.
- A saved file that can't be read is reported, not crashed on; the app starts with an empty queue. A saved current index outside the entries is clamped into range.

## Library

- **The Library screen** shows, by default and in this order: Random Mix and Mix My Cuts (together in one block), then links to Artists, Albums, Playlists, Favorites, Genres, Radio, Downloaded and History (links next to each other are grouped in one block). **Edit** (top right, beside Settings) opens Edit Library: tap an item to show or hide it, drag to reorder; Reset restores the default. Carousels (rows of album covers: Recently Added, Recently Played, Spin It Back) are hidden by default, to keep Library minimal, and are marked in Edit Library with a row-of-panels icon at the end of the line. The layout is saved on this device and kept across sign-outs. A layout saved by another version still loads: unknown items and repeats are dropped, and items added since appear, shown, in their usual place (after the item that comes before them by default, e.g. Mix My Cuts after Random Mix). With everything hidden, the screen says to tap Edit. Recently Added is only fetched while it's shown.
- **Favorites** (a Library link) lists everything favorited, from `getStarred2`: songs first (Play, Shuffle, tap a song to play the list from it, the song row menu), then albums and artists (with their row menus). It reloads each time it opens; anything unfavorited in this session, here or elsewhere, leaves the list at once. With nothing favorited it says how to add some.
- **Genres** is also a Library link, opening the same genre grid as Search.
- **Song Info and Album Info** (a song's long-press menu and Now Playing's ⋯ menu; an album's long-press and ⋯ menus) open a full-height sheet with the cover and name, then everything the server says, in groups, each only with the rows it has: **General** (title, artist, album, album artist when different, track and disc, year, genres, composer, length, BPM, mood, comment), **Audio** for songs (format, bit depth and sample rate e.g. "24-bit / 96 kHz", channels, bitrate, file size, ReplayGain), and **Library** (plays, last played, added, rating, favorite). Albums show year (with "originally …" when the original release differs), genres, release type (not when it's just "Album"; compilations say so), record label, songs and length. Plain Subsonic gives fewer of these; Navidrome's OpenSubsonic fields fill in the rest; 0 and empty values count as not given. A song's Info shows what's at hand at once, then the server's latest (`getSong`, for current play counts); an album's fetches it (`getAlbum`). Values can be selected and copied. Song details are kept with the saved queue.
- **Album pages** show a details line under the artist and year: genre, number of songs and length, e.g. "Contemporary R&B · 18 songs · 1 hr 2 min" (whatever the server gives). The record label is in Album Info.
- **Settings > Developer > Debug Player** opens the bare player kept for testing playback (it used to be a toolbar button on Library).
- **Loading.** Each screen fetches what it shows when it appears. Until that arrives it shows loading; if it fails with nothing to show, the error and a retry. A refresh keeps the current content on screen; if the refresh fails, the content stays and the error is reported alongside it. A load that's still running when the screen goes away is dropped, and runs again when the screen comes back.
- **Recently Added** (a carousel, hidden by default; switched on in Edit Library) shows the 15 newest albums (`getAlbumList2`, type `newest`) as a row of covers with name and artist. Tapping a cover opens the album; long-pressing gives the album's row menu (below). See All opens the album list in Recently Added order. Tapping the heading collapses or expands the row; this is remembered on the device. The row reloads whenever Library is shown or pulled to refresh, keeping the old covers on screen meanwhile; if it can't load, it says why with Try Again.
- **Row menus.** Long-pressing a row acts on it without opening it:
  - Artist (Artists, Search): Play, Shuffle, Play Next, Add to Queue, Add to Playlist…, Favorite, Rate. The artist page's ⋯ menu has the same.
  - Album (Albums, Recently Added, an artist's page, Search): the same five, Download or Remove Download, Favorite, Rate, and Go to Artist (not on the artist's own page).
  - Playlist (Playlists): the same five, and Download or Remove Download.
  - Download (Downloaded): the same five, using the stored songs, so they work offline, and Remove Download.
  - Song (album and playlist pages, Search, History, Downloaded): Play Next, Add to Queue, Add to Playlist…, Download or Remove Download, Favorite, Rate, then Go to Album and Go to Artist (when the server gave their ids; Go to Album is left out on the album's own page, including its downloaded copy).
  - The songs are fetched first: an album or playlist in its order; an artist's albums oldest first by year (albums without a year last, otherwise in the server's order), each in track order, fetching at most 4 albums at a time. If any fetch fails, nothing happens and the error is shown ("Couldn't Load Songs"). A second choice for the same item while it loads is ignored.
  - An artist with more than 100 songs (counted from their albums' song counts) asks first, e.g. "Add 340 songs by X to the queue?"; for Add to Playlist the question comes before the playlist sheet.
- **Genres.** Before anything is typed, Search shows the library's genres (`getGenres`) as a two-column grid of tiles, most albums first (ties by name; genres with no albums are left out, and one whose count isn't given goes last). Each tile has a color that stays the same for that genre (system colors, or the Catppuccin accents in a Catppuccin theme) and one of the genre's album covers tilted in its corner: the first album `getAlbumList2` gives for `byGenre`, fetched when the tile first appears and kept for the session (a genre with no cover just shows the color; a failed fetch is tried again when the tile next appears). Typing a search replaces the grid with results; clearing it brings the grid back.
  - Tapping a tile opens the genre's page: Play and Shuffle, then its albums (`getAlbumList2` `byGenre`, paged like the album list, with the album row menu). Long-pressing a tile offers Play, Shuffle, Play Next, Add to Queue and Add to Playlist… for the genre.
  - A genre's songs are up to 500 from `getSongsByGenre`, in the server's order (Shuffle shuffles them).
- **Album lists** come in these orders: recently added, recently played, most played, name, artist, random, starred. They load 40 albums at a time; the next page is requested when the user scrolls within 10 albums of the end, and a page shorter than 40 means there are no more. An album already shown is never shown twice, even if the library changed between pages; the next request still starts where the server's previous page ended. If a page fails, scrolling doesn't retry it; an explicit retry does. Random shows a single page, and a refresh picks again, because paging a random list would repeat albums. Changing the order replaces the list, and a late reply for the old order is ignored.
- **Search** runs 300 ms after the user stops typing, with surrounding spaces ignored. An empty query clears the results. While a new search runs, the previous results stay on screen. A reply for an older query is ignored, so results never jump back to something the user has already typed past.
- **Search filters.** A scope bar (shown while searching): All, Artists, Albums or Songs; and the funnel button: a rating (Any, Rocks, Don't Hate It, Meh, Unrated), Favorites Only, Downloaded Only (downloaded songs and albums; artists aren't downloads, so none show), and Clear Filters. While any is on, the funnel fills in and a line above the results names them (e.g. "Albums · Rocks · Favorites") with Clear. Changing them searches again at once. To leave enough after filtering, Search asks for 100 of each kind when a filter is on (20 normally), or 100 of the one kind chosen. Filtering uses each result's rating and favorite as the server sent them. The scope and filters are remembered on this device until cleared.
- **Browsing by filter.** With nothing typed and a filter on, Search lists everything in the library that matches: artists from `getArtists`, albums from `getAlbumList2` alphabetically 500 at a time, songs from an empty `search3` (Navidrome lists every song that way; other servers may list none, and the empty message says songs can only be browsed on servers that can). Each list is kept for 30 minutes. A scope alone, with nothing typed, still shows the genre grid.
- **Downloaded** can be filtered (the search field is always shown at the top of the list): a download matches when its name or artist, or any of its songs' titles or artists, contains the search text, ignoring case and accents. Newest download first.
- **Favorites.** Songs, albums and artists can be favorited (a heart). On the server this is Subsonic's star (`star`/`unstar`), which is what Navidrome shows as a favorite. The change shows immediately, then the server is told. If the server call fails, the heart goes back to how it was and the error is shown. A second tap on the same item while its first change is still being sent is ignored. A change made in this session wins over the flag in lists fetched earlier, so every screen agrees. The album sort Navidrome calls "starred" is shown as Favorites.
- **Ratings.** Songs, albums and artists can be rated Meh 😩, Don't Hate It 👌 or Rocks 😈 (the faces are shown beside each choice), sent with `setRating` as 2, 3 and 5 stars. Choosing the current rating again clears it (sent as 0). Ratings set elsewhere on any 1–5 scale show as the nearest level: 1–2 Meh, 3 Don't Hate It, 4–5 Rocks; they change on the server only if the user picks a rating in the app. Showing, failing and repeated taps follow the same rules as favorites.
- **Marks in song lists.** In album and playlist pages, Search, History and Downloaded, a favorited song shows a small heart and a rated song its face (😩 Meh, 👌 Don't Hate It, 😈 Rocks), just before the duration (in History, before the time played). They follow the same session-first rule as favorites and ratings, so a change from a menu shows at once. They're display only: tapping a row still plays it, and marks are changed from the song's menu.
- **Playlists.** "Add to Playlist…" is offered for a song (its long-press menu, wherever songs are listed), an album, a playlist and an artist (their ⋯ menus and row long-presses), and a download. Now Playing's Save Queue button offers the same for the whole queue, in order, including songs already played. The sheet lists "New Playlist…" first, then only the playlists the signed-in user owns, by name (the server refuses changes to anyone else's; a playlist with no owner given is offered and the server decides). The Playlists screen's + makes an empty playlist.
  - **Adding** (`updatePlaylist` with `songIdToAdd`) appends to the end, skipping songs already in the playlist (fetched just before) and repeats within what's being added.
  - **Creating** (`createPlaylist`) keeps the songs exactly as given, repeats included, so a saved queue keeps its shape. The name is trimmed and can't be blank.
  - Song ids travel in the request URL, so at most 100 go in one request; more are sent in further `updatePlaylist` calls (a new playlist is created with the first 100, then filled). If the server doesn't return the new playlist, only a playlist of up to 100 songs can be created.
  - One change at a time. On success the sheet closes and a banner at the top says what happened for 3 seconds (e.g. "Added 8 songs to “Morning”. 2 were already there.", "All 3 songs are already in “Morning”.", "Created “Road Trip” with 40 songs."); VoiceOver announces it. On failure the sheet stays open with the server's message, so another playlist can be chosen; a chunked change may have half-completed, which the reloaded playlist shows.
- **Artist page.** The artist's image (their `coverArt`, served by `getCoverArt` like album covers and cached the same way; a placeholder when there is none), their name, then the first three lines of their biography with More and Less when it is longer, then their albums. The biography comes from `getArtistInfo2` (usually Last.fm, via the server): its HTML is turned into plain text and the trailing "Read more on Last.fm" link is dropped. It loads alongside the albums but separately, so a slow or failed lookup never delays or breaks the album list; with no biography the section is simply absent. Pull to refresh reloads both.
- **Playing from the library.** Tapping a track plays its album or playlist from that track. Play starts at the first track; shuffle plays the same songs in a shuffled order (see Queue). Play Next (songs, albums, playlists) puts them right after the current track; Add to Queue appends them to the end. Neither interrupts playback. In search results, tapping a song plays the listed songs starting from it.
- **Random Mix** (top of Library) asks the server for 50 random songs (`getRandomSongs`) and plays them as a new queue. While it loads the button shows progress and ignores further taps; an empty result is shown under it and nothing changes. If the server can't be reached (any failure: no connection, server down, HTTP error), it plays up to 50 downloaded songs instead, shuffled, each once and only those whose files are on the device, with a note under the button saying so; the note goes away on the next mix from the server. With nothing downloaded, the error is shown and nothing changes. When the phone is online but the server doesn't answer, the fallback waits for the request to time out.
- **Carousels**, all hidden by default so Library stays simple, switched on in Edit Library (they come first, Recently Added, then Recently Played, then Spin It Back). A layout saved before keeps its own choice for Recently Added. Each is a row of album covers like Recently Added: tap one to open the album, long-press for its menu, tap the heading to collapse it (remembered). Shown carousels load when Library appears, on pull to refresh, and as soon as one is switched on.
  - **Recently Played:** albums played in the last 7 days from any app, newest first (`getAlbumList2` type `recent`, filtered by each album's last-played date; a server that doesn't give play dates shows its 15 most recent). See All opens History (Bzide's own plays).
  - **Spin It Back:** albums worth hearing again, from the whole album list (the library catalog). An album must be liked (rated Rocks or Don't Hate It, a favorite, or played at least twice) and is never rated Meh. Its score is how much it's liked (Rocks 1.0, Don't Hate It 0.7, otherwise 0.35; +0.4 for a favorite; up to +0.6 for plays) times its time away (played in the last 14 days 0.05; then rising from 0.3 to 1.0 at a year; never played 0.4), times a daily shuffle (0.85–1.15, the same all day). The top 15 are shown, at most two per artist. A server without plays, dates or ratings in its album list gets its most played albums, less any of the 30 most recently played.
- **Mix My Cuts** (under Random Mix; first called Shuffle Rated) plays My Cuts, shuffled, without end: songs rated Rocks or Don't Hate It, and, with Settings > Playback > Include Favorites in My Cuts on (the default), favorites too, unless a favorite is rated Meh (the more specific verdict). Subsonic can't ask for songs by rating, so Bzide looks through the whole library: `search3` with an empty query lists every song with its rating (Navidrome supports this), 500 per page, four pages at a time, until a page comes back short. The songs found (rated or favorite) are kept for 30 minutes, so a song favorited or rated now joins within half an hour; the favorites setting applies at once; two taps at once share one look. It plays a shuffled batch of 25 and keeps topping up like Spin Off (same engine: saved with the queue, repeat turned off, playing something else ends it), with rated songs not yet in the queue, and once all have played, a fresh shuffle of them all. Now Playing's queue heading reads "My Cuts". If My Cuts is empty: a banner says to rate or favorite songs from their long-press menu; if the server lists no songs at all (some non-Navidrome servers don't support an empty search): a banner says My Cuts can't be found on it; offline: a banner says to check the connection. While it looks, the button shows progress and ignores further taps.
- **Layout.** Two tabs, Library (artists, albums, playlists) and Search, with a mini player above the tab bar showing the current track, play/pause and next. Tapping the mini player opens Now Playing: artwork, controls, favorite and rating, an AirPlay button, and the queue. The AirPlay button is the system output picker (AirPlay speakers and TVs, Bluetooth, the iPhone), in the theme's accent; it's there for radio stations too, which have no favorite or rating.
- **Playing quality.** Now Playing's status line ("Playing", "Paused"…) shows at its right end what the current song is playing as: format and bitrate, then "Converted" if the server is transcoding it and "Downloaded" if it plays from a file, e.g. "FLAC · 1,411 kbps", "MP3 · 192 kbps · Converted", "MP3 · 128 kbps · Converted · Downloaded". It's decided with the same rule that picks the source (a download first, otherwise the current connection's streaming quality; an MP3 already at or under the cap is sent as is, so it shows as the original), and recorded when the song is loaded, so a preloaded next song shows the quality it was loaded at. The original's format and bitrate are the server's metadata. Nothing shows before a restored queue is loaded or for a radio station. Tapping the label hides it, leaving a small waveform icon; tapping that shows it again. The choice is remembered on the device.
- **Cover art** is looked up by cover art id and size (never by URL, which carries a fresh auth salt each time): memory first, then disk, then the server. Each image is fetched once however many rows show it. Fetched images are saved in `Caches/CoverArt`, which iOS may clear when space runs low. If the server can't be reached, any size of that cover already on disk is shown rather than nothing. Artwork responses never go into the shared on-disk URL cache, because their URLs carry a reusable auth token; only image responses (HTTP 200, `image/*`) are kept.

## Appearance

- **Themes.** Settings > Appearance offers System (follows the phone's light or dark mode, the default), Light, Dark, and four [Catppuccin](https://catppuccin.com) flavors: Latte (light), Frappé, Macchiato and Mocha (dark). A flavor forces its own mode; it doesn't switch with the phone. The choice is kept on the device, applies at once, including on the sign-in screen, and stays across sign-outs. A saved theme or accent the app doesn't recognize falls back to its default without resetting the other.
- **Catppuccin colors.** With a flavor chosen, the user also picks one of its 14 accents (Rosewater, Flamingo, Pink, Mauve, Red, Maroon, Peach, Yellow, Green, Teal, Sky, Sapphire, Blue, Lavender; Mauve by default), shown as swatches in that flavor's shades. The accent replaces the system tint everywhere iOS would use it: buttons and their icons (Play, Shuffle, favorite, rating, toolbar, mini player), list icons, the selected tab, the current song and sliders. Text keeps iOS's own label colors (white and gray in dark flavors, black and gray in Latte), because a theme-wide text color would also override the accent on buttons. Plain lists sit on `base`. Grouped lists (Settings, the Library home, sign-in, the date picker) sit on `base` with `surface0` rows in dark flavors, and on `crust` with `base` rows in Latte. The System, Light and Dark themes keep iOS's own colors, with their own accent (next).
- **System accent.** The System, Light and Dark themes have their own accent, kept separately from the Catppuccin one: **Bzide Red** by default, the red of the app icon's leather (#4F2F33) lifted to read as an accent, #9B2D3F in light mode and #E0606F in dark mode; or iOS's red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink or brown. It's chosen from swatches under the Theme in Settings > Appearance (the chosen one's name beside "Accent") and used everywhere the accent is.
- **Limits.** iOS draws some things itself: the navigation and tab bars and the mini player are glass over the themed background, navigation titles are iOS's black or white, and menus, alerts, context menus and the keyboard follow only the flavor's light or dark mode.
- Palette values are Catppuccin's published ones (MIT license), from github.com/catppuccin/palette.

## Radio

- **Stations** are the internet radio stations saved on the server (`getInternetRadioStations`), listed by name under Library > Radio; each shows its stream's host. Stations without a usable http(s) stream address are left out. They're added and edited in Navidrome's web UI, not in the app. Long-press offers Play and Open Homepage (when the station has one).
- **Playing a station** replaces the queue with that one station, like playing a new album. A second tap while one is starting is ignored.
- **Stream address.** A direct stream or an HLS (`.m3u8`) address goes to the player as is. A `.pls` or `.m3u` playlist file is read first and its first stream is played (`.pls`: the lowest-numbered `File` entry; `.m3u`: the first line that isn't blank or a `#` comment). Plain http streams play (the app's only App Transport Security exception, for audio); a playlist *file* on plain http can't be read, and the app says to use the station's direct stream address instead. If the file can't be fetched or lists no stream, the error says so ("Couldn't Play Station").
- **A station is live:** no duration or progress bar ("Live" instead), no seeking, previous and repeat disabled, nothing preloaded after it. It's never scrobbled or added to play history, can't be favorited, rated or added to a playlist (Save Queue leaves it out), and isn't offered to Siri. The lock screen marks it as a live stream with scrubbing and previous disabled.
- **Pause and resume** rejoins the broadcast live rather than continuing minutes behind. If the stream ends or fails while listening, it's retried like a failed song (same delays and network-return retry), always from "now".
- **What's on.** When the stream announces what it's playing (Shoutcast/Icecast `StreamTitle`, or a title in its metadata), that becomes the title in the mini player, Now Playing and on the lock screen, with the station's name beneath; otherwise the station's name is the title. A new track or station clears it.
- **Relaunch:** a station that was playing comes back paused, and play rejoins it live.

## Siri

- **What Siri knows.** Songs, albums, artists and playlists are Siri entities using the system's audio schemas (ids are the server's). Every artist, album, playlist, song, download and queue row is annotated with its entity, as are the album, artist and playlist page headers; Now Playing publishes the current song. So "Ask Siri" from a long-press, or "play this" / "add this to …" while looking at something, refers to that item. iOS 27 adds Ask Siri to menus on its own; the app can't remove it (see `docs/ISSUES.md`).
- **Finding things by name.** Siri looks entities up by id (`getArtist`, `getAlbum`, `getPlaylist`, `getSong`; ids the server no longer has are skipped) or by name (`search3`, 10 of each kind; playlists by filtering the user's list, since the server has no playlist search). For "play X", an exact (case- and accent-insensitive) name match comes first, then songs, albums, artists and playlists.
- **Play** (`playAudio` schema): plays the item as the long-press Play does (an artist's albums oldest first). Shuffle plays it shuffled; Repeat also turns on repeat all; "next" and "last" put it after the current song or at the end of the queue instead of replacing it.
- **Add to Playlist** (`addToPlaylist` schema): adds the item to the named playlist with the same rules as the sheet (only new songs; long lists chunked). Siri says the result, e.g. "Added 8 songs to “Morning”. 2 were already there."; a failure is spoken as the server's message.
- An artist with more than 100 songs asks for confirmation first, as the menus do.
- Signed out, every Siri request fails with "Sign in to your Navidrome server in Bzide first." Siri needs Apple Intelligence; none of this works without it.

## Play history

- A play is added to the history at the moment it counts for scrobbling (half the track or 4 minutes, whichever comes first), recorded with the song as it was and the time the play started. Skipped plays aren't recorded. Works offline.
- Kept on this device only, in `Application Support/PlayHistory.json`; the Subsonic API has no list of plays to sync with. Each client (iOS, later web and Android) keeps its own.
- Shown newest first, grouped by day (Today, Yesterday, then dates).
- Repeat plays are combined by default: within a day, a song appears once, at the time of its latest play that day, with its number of plays that day ("3 plays") when more than one. Only plays that match the current filters are counted. "Show Every Play" in the filter menu lists each play separately; the choice is remembered.
- Filters combine: text matching the track, artist or album (ignoring case and accents), and a period: Today, Last 7 Days, Last 30 Days, All (the default), or a custom range of whole days, in either order.
- Tapping a play plays just that song. Long-press offers Play Next, Add to Queue, Favorite and Rate.
- Retention: 7 days, 30 days (default), 90 days, 1 year, or forever. Older plays are dropped at launch, on every new play, and when the setting changes. Clear History removes everything, after confirmation.

## CarPlay

- Tabs: Recently Played and Albums (recently added) show the first page of those album lists; Playlists; Downloaded, built from the saved downloads so it works with no connection and refreshed each time it's shown.
- An album or playlist opens as a list of its songs, headed by Shuffle. Choosing a song plays the album or playlist from that song, the same rule as on the phone, and shows CarPlay's Now Playing screen.
- Now Playing is CarPlay's built-in screen. It shows the same title, artwork, progress and controls as the lock screen, from the same source.
- Lists stop at CarPlay's maximum length. While loading a list shows "Loading…"; a failure shows the reason and a Try Again row.
- Signed out, CarPlay shows "Sign in on your iPhone" and switches to the library once the user signs in.
- The CarPlay screen can start without the phone's own window (app launched from the car with the phone locked); it uses the same single app model and playback engine as the phone.
- Until Apple grants the CarPlay entitlement (after M6), only simulator builds carry it.

## Caching and offline

### Streaming quality

- The user picks a quality for Wi-Fi and one for cellular: Original, or 320, 256, 192, 128 or 96 kbps. Defaults: Original on Wi-Fi, 192 kbps on cellular.
- "Cellular" means any connection iOS marks as expensive (cellular, a personal hotspot) or constrained (Low Data Mode).
- Original streams the file as stored. Any bitrate asks the server to transcode to MP3 at that bitrate (`maxBitRate`, `format=mp3`); the server may send the original when it is already at or below that.
- The quality is chosen each time a track is loaded. A change of network or setting applies from the next track loaded; a track already playing, or already buffered as the next one, keeps its quality.
- A downloaded song always plays from its file, whatever the connection.
- Settings are saved on the device (not secret). Saved settings that can't be read fall back to the defaults; a setting missing from what was saved (added in a later version) takes its default and the others are kept.

### Downloads

- The user downloads a whole album or playlist. Its song list is saved as it was at that moment, so it can be listed and played with no server. Downloading it again updates the list: new songs are fetched, songs no longer in it are dropped.
- **Downloaded playlists stay up to date.** A playlist can change after it's downloaded (in Bzide or another app), so Bzide checks: every downloaded playlist when the app comes to the foreground (at most every 15 minutes, after a check that reached the server), a playlist whenever its page is opened online, and right after songs are added to it in Bzide. A change (songs added, removed or reordered, a new name or cover) updates the download as downloading it again would: new songs download under the usual quality and cellular rules, removed songs' files go unless another download uses them, and the download keeps its place in the list. Offline nothing changes, and the foreground check runs again on the next return to the app. A playlist the server says no longer exists keeps its download until the user removes it. Albums aren't checked.
- **Single songs.** A song's long-press menu offers Download, which downloads that one song as its own download (`song:<id>`), with the same quality, cellular, ordering and storage rules. Once downloaded it offers Remove Download. A song that's only on the phone as part of a downloaded album or playlist shows a grayed-out "Downloaded" instead: it's removed with them. Library > Downloaded lists songs downloaded on their own as one "Downloaded Songs" row at the top (with their count and progress; its long-press plays or queues them all), which opens the list, newest first. The Downloaded search matches them by title and artist too.
- **Download quality** (Settings > Downloads, Original by default, same choices as streaming quality). At Original, songs are downloaded in their original format (`download` endpoint, never transcoded). Below it, they're fetched from `stream` with that `maxBitRate` and `format=mp3`, so the server converts them as they download; the size isn't known in advance, so such a song shows as downloading without a percentage until it's done. The quality is fixed for each song when its download starts and saved with the download index, so changing the setting mid-download, or a relaunch before a converted song finishes, never mislabels a file. Songs already downloaded are kept as they are: a change applies to songs downloaded afterwards.
- Files go to `Application Support/Downloads/Files/<song id>.<extension>`, excluded from iCloud backup. A converted song is `.mp3`; an original takes the extension from the song's metadata, else from the server's file name.
- Each song is stored once, however many downloaded albums or playlists contain it. Removing an album or playlist deletes only files no other download still uses, and stops their running downloads.
- Three songs download at a time; the rest wait in the order the user asked for them (oldest download first, album order within). Downloads run in a background `URLSession`, so they carry on while the app is suspended or terminated. On the next launch the app reconnects to them, restarts whatever was waiting, and cancels system downloads nothing wants any more.
- A failed song stays failed until the user retries; after a relaunch, failed songs are tried again. A response that isn't 2xx, or is JSON/XML (how Subsonic reports errors, even with HTTP 200), is a failure, never saved as a song.
- "Download over cellular" is off by default: downloads then wait for Wi-Fi. The setting applies to downloads started after changing it.
- Any song with a downloaded file plays from it, on any connection and with the server unreachable. If the file has gone missing, the song streams instead.
- Downloaded albums and playlists keep their covers offline: the collection's cover and every song's cover (they can differ, e.g. compilations) are stored once each at 900 px in `Downloads/CoverArt`, and serve every size. A cover no remaining download uses is deleted. Covers that couldn't be fetched are retried when downloads change and at launch.
- No storage limit; the user removes downloads, one at a time or all at once in Settings, which also shows the space used.
- The download URL carries an auth token and is handed to iOS's download service. Subsonic has no other way to authenticate a download.

## Manual test checklist

Run on a physical iPhone. Each line is one check; note failures in `docs/ISSUES.md`.

### Account
- [ ] Settings shows the server and user. Sign Out (confirm): playback stops, the sign-in screen appears, and the lock screen no longer shows the app.
- [ ] Sign back in to the same account: downloads, history and the queue (paused where it was) are all still there.
- [ ] Sign in to a different user or server (if available): downloads, history and the queue are gone, and Storage Used is zero. Sign back in to the first account: its downloads are gone too (they were removed when the account changed).
- [x] Settings > Profile > Picture: Contact Card > Choose Contact Card…, pick yourself (contacts without a photo are grayed out): Library's gear becomes your photo, and Settings shows it beside your name. No permission prompt appears. (2026-10-13)
- [x] Picture: Photo > Choose Photo…, pick one: it replaces the contact photo, cropped to a circle. Switch back to Contact Card: your contact photo returns without picking again. None: the gear returns at once. (2026-10-13)
- [x] Picture: Gravatar, with an email that has a Gravatar (typed, or your Navidrome account's): Profile says it was found and shows it, and it appears on the toolbar and beside your name. Type an address with no Gravatar: "No Gravatar for this email" and the gear returns. (2026-10-13)
- [x] With a picture showing (any choice), force quit and relaunch in Airplane Mode: the picture still shows. (2026-10-13)
- [ ] Sign out and in again several times in one session: playback, lock screen controls and downloads keep working each time.

### Basics
- [ ] Play an album, lock the phone, and leave it for several tracks. Playback continues track to track with the screen off.
- [ ] Play, switch to another app (Safari, Messages). Playback continues.
- [ ] Play an album that is meant to be gapless (a live album or continuous mix). Track changes have no audible gap or click. Note the file format if there is one.
- [ ] Skip quickly with next several times in a row. Each skip lands on the right track and the queue view agrees.
- [ ] Play a few tracks into an album, pause mid-track, force-quit the app (swipe it away), relaunch. The same track is shown, paused at roughly the same position. Press play: it resumes there.
- [ ] Same, but force-quit while playing. Relaunch: same track, paused, position within about 10 seconds of where it was.
- [ ] Let the last track of a queue finish. The queue empties, the mini player shows Not Playing, and the lock screen and Control Center no longer show the app's track.

### Audio session
- [ ] Play, then receive a phone call. Music pauses. Decline or end the call: music resumes.
- [ ] Play, then trigger Siri and dismiss it. On iOS 27 the system sends no interruption for Siri, so music keeps playing (possibly quieter while Siri talks). Check only that playback is still going normally afterwards.
- [ ] Play, then start a video in another app. Music stops. Close the video: music does not resume on its own unless iOS offers resumption.
- [ ] Pause, then receive and end a call. Music stays paused.
- [ ] Play, receive a call, press play then pause during the call, end the call. Music stays paused.
- [ ] Play through wired or USB headphones, unplug them. Music pauses and does not play through the speaker. Plug back in: still paused.
- [ ] Play through Bluetooth headphones, turn them off. Music pauses, no speaker output. Turn them back on: still paused.
- [ ] Play, switch output to AirPlay or a Bluetooth speaker from Control Center. Music continues on the new device.
- [x] Play in a car over CarPlay (system Now Playing): the car shows the track and its controls work. Turn the car off: playback pauses. Turn it on: it resumes at the same point when the car sends play. (2026-10-11)
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
- [x] Play on Wi-Fi, walk out of Wi-Fi range (or turn Wi-Fi off) so the phone switches to cellular. Playback continues, or resumes within a few seconds at the same point.
- [ ] Play, turn on Airplane Mode for 5 seconds, turn it off. Playback resumes at the same point without pressing anything.
- [ ] Play, turn on Airplane Mode for 30 seconds or more, until the app shows failed. Turn it off. Playback resumes by itself.
- [ ] Pause, turn on Airplane Mode, turn it off. The app stays paused.
- [ ] Play, turn on Airplane Mode, then press pause while it shows reconnecting. Turn Airplane Mode off. The app stays paused.
- [ ] Play near the end of a track on a weak connection. The next track still starts without a gap, or with only a short one.
- [ ] Lock the phone during all of the above. Recovery works the same with the screen off.

### Library
- [ ] On a fresh layout (Edit Library > Reset), Library shows no carousels. Edit Library marks Recently Added, Recently Played and Spin It Back with the carousel icon. Switch on Recently Played and Spin It Back: they appear and fill in straight away. Recently Played shows albums played this week (including from Navidrome's web player), newest first. Spin It Back shows albums you've rated or favorited but not played in a while, at most two per artist, never Meh; it's the same all day and different tomorrow.
- [ ] Search with nothing typed, funnel > Rocks: every song, album and artist you rated Rocks is listed; the line above says "Rocks" with Clear. Tap into the search field: the scope bar appears; pick Songs: only songs. Type a word: only matching Rocks songs. Clear: back to the genre grid. Force quit and relaunch with a filter on: it's still on.
- [ ] Funnel > Favorites Only, then Downloaded Only: only favorites, then only downloaded songs and albums (no artists).
- [x] Library > Mix My Cuts (under Random Mix): within a few seconds, songs you rated Rocks or Don't Hate It play shuffled, and Now Playing's queue heading reads "My Cuts". Skip until two are left: more rated songs are added. Edit Library: Mix My Cuts can be hidden or moved, and it appeared under Random Mix even with a saved layout. (2026-10-15)
- [ ] With Include Favorites in My Cuts on, favorite (heart) a few unrated songs: within half an hour they come up in Mix My Cuts; turn the setting off and they no longer do. A favorite rated Meh never does.
- [x] Open an album: under the artist and year, a line with its genre, songs and length. Long-press a song > Song Info: a full sheet with General, Audio and Library details; play counts are current. Now Playing ⋯ > Song Info: the same for the playing song. An album's ⋯ or long-press > Album Info: year, genre, release type, label, songs, length, plays. (2026-10-15)
- [ ] Library's toolbar shows Edit and Settings (no ladybug); Settings > Developer > Debug Player opens the debug player.
- [ ] Edit: hide Radio and History, drag Artists and Albums above Recently Added, Done: Library shows exactly that, with Artists and Albums in one block at the top. Force quit and relaunch: kept. Edit > Reset: back to the default.
- [ ] Hide everything: Library says to tap Edit.
- [ ] Favorites: your hearted songs (Play and Shuffle work), albums and artists. Unheart a song from its long-press menu: it leaves the list. Heart an album elsewhere, come back: it's there.
- [ ] Genres from Library opens the genre grid; a tile opens its genre.
- [x] Artists: the A–Z index scrolls and jumps by letter; an artist shows their albums; an album shows its tracks in order with numbers. (2026-10-11)
- [x] Albums: scroll a long list to the end. More albums load without a visible stop and none repeat. Switch sort orders; each shows the right list. (2026-10-11)
- [x] Turn on Airplane Mode and open a screen that hasn't loaded yet: it shows the error and Try Again. Turn it off and press Try Again: it loads. Pull to refresh with Airplane Mode on: the content stays. (2026-10-11)
- [x] Search: type quickly. Results settle on what you typed last, without flicker back to older results. Clear the field: results clear. (2026-10-11)
- [x] Random Mix: 50 random songs start playing; tap again for a different mix. (2026-10-11)
- [x] Random Mix in Airplane Mode with downloads: a shuffled mix of downloaded songs plays, with a note under the button. Turn Airplane Mode off and tap again: a server mix plays and the note goes away. With no downloads, Airplane Mode shows an error instead. (2026-10-11)
- [x] Tap a track in an album: the album plays from that track. Play and Shuffle buttons work. Add to Queue appends without interrupting. (2026-10-11)
- [x] While a track plays, Play Next on another song: the current track carries on, and when it ends the chosen song follows with no gap. Play Next on an album: its songs come next, in order, before the rest of the queue. (2026-10-11)
- [x] Repeat All: let the last song of an album end. The first starts with no gap. Next on the last song also goes to the first. (2026-10-11)
- [x] Repeat One: the song plays again when it ends (it shows twice in History, combined as "2 plays"). Next still goes to the following song, and repeat one stays on. (2026-10-11)
- [x] Switch repeat modes while a song plays: no interruption. Relaunch the app: the mode is kept. (2026-10-11)
- [x] In Now Playing, Clear Up Next: the queue shows only the current song, which keeps playing without a hiccup; when it ends the queue empties. The button is hidden when nothing is up next. (2026-10-11)
- [x] In Now Playing, swipe an upcoming song left > Remove: it's gone and the current song plays on. Remove the very next song: when the current one ends, the one after it plays, without a gap. (2026-10-12)
- [x] Long-press and drag an upcoming song to a new place; drag another to right after the current song: when the current one ends, that song plays next, without a gap. (2026-10-12)
- [ ] The current song (top row) can't be swiped or dragged. Force quit and relaunch after editing: the queue keeps the new order.
- [ ] Now Playing: Previous, Play and Next are centered under the progress bar, with Shuffle on the left and Repeat on the right.
- [ ] Play an album, then tap Shuffle: it turns the accent color, the queue below is shuffled, the song keeps playing, and the next one plays without a gap. Tap it again: the rest of the album is back in order.
- [ ] Tap an album's Shuffle button: Shuffle is shown on. Turn it off: the songs not yet played follow in album order. Play an album normally: Shuffle is off.
- [ ] Turn Shuffle on, force quit and relaunch: it's still on, and turning it off restores the order.
- [x] Play an album and let a few tracks pass: the queue in Now Playing starts at the current song, but Previous still goes back through the earlier ones. (2026-10-11)
- [x] Star an album, go back and reopen it: still starred. Check in Navidrome's web UI that it's starred there too. (2026-10-11)
- [x] Favorite an album, an artist and a song (heart): each stays favorited after reopening, and shows as a favorite in Navidrome's web UI. Unfavorite one: it clears there too. (2026-10-11)
- [x] Rate a song, an album and an artist Meh, Don't Hate It and Rocks: Navidrome's web UI shows 2, 3 and 5 stars. Choose the same rating again: it clears in the app and on the web. (2026-10-11)
- [x] In the web UI, give an album 4 stars. Reopen it in the app: it shows Rocks (checkmark in Rate). (2026-10-11)
- [x] Open an artist with a picture in Navidrome: the image is at the top, then the name and three lines of biography, then the albums. More shows the whole biography, Less shortens it again; a short biography has no More. (2026-10-12)
- [ ] Open an artist with no picture or biography: a placeholder image, the name and the albums, with no gap or error where the biography would be.
- [x] Rate in Airplane Mode: the rating goes back and "Couldn't Change Rating" explains why. (2026-10-11)
- [x] The mini player always shows the current track and its play/pause and next work. Tapping it opens Now Playing, which matches the lock screen. (2026-10-11)
- [x] Artwork appears in lists and on Now Playing, and scrolling back up doesn't reload it. (2026-10-11)
- [ ] Library shows Recently Added covers at the top, newest first, matching Navidrome's "Recently Added". Tap a cover: the album opens. See All: the albums list in Recently Added order.
- [ ] Long-press a Recently Added cover: Play replaces the queue with that album; Play Next and Add to Queue add it in the right place.
- [ ] Long-press an artist in Artists: Play plays their albums oldest first, each in track order. Shuffle mixes them. Favorite and Rate show up in Navidrome.
- [ ] Long-press an artist with more than 100 songs: it asks first ("Play 340 songs by …?"); Cancel does nothing.
- [ ] Long-press an album in Albums, on an artist's page and in Search: Play, Play Next, Add to Queue, Download (then Remove Download on a second long-press), Go to Artist (not on the artist's page).
- [ ] Long-press a playlist: Play, Shuffle and Download work. Long-press a download in Airplane Mode: Play works.
- [ ] Tap the Recently Added heading: the row collapses. Force quit and relaunch: still collapsed. Tap again: it expands.
- [x] Play a song on Wi-Fi at Original: the status line shows its format and bitrate (e.g. "FLAC · 1,411 kbps"). Play a downloaded song: it adds "Downloaded". On cellular with a lower cellular quality, a new song shows "MP3 · 192 kbps · Converted". (2026-10-12)
- [x] Tap the quality: it's replaced by a small waveform icon. Tap that: it's back. Close and reopen Now Playing, and relaunch: your choice is kept. (2026-10-12)
- [x] Now Playing > AirPlay button: the system picker lists your AirPlay speakers and Apple TV. Choose one: music moves there and keeps playing; the lock screen controls still work. Choose iPhone: it comes back. Also works while a radio station plays. (2026-10-12)
- [x] Search with nothing typed shows genre tiles, your biggest genres first, each with a cover from that genre. Type something: results replace the grid; clear it: the grid is back. (2026-10-12)
- [x] Tap a genre: its page lists that genre's albums (scroll to the end of a big genre: more load). Play and Shuffle play that genre's songs. (2026-10-12)
- [ ] Long-press a genre tile > Shuffle: a mix of that genre plays. Switch to Catppuccin Mocha: the tiles take the theme's colors with dark, readable names.
- [ ] Long-press a song, choose Add to Playlist…, pick a playlist: the sheet closes, the banner says it was added, and the playlist (here and in Navidrome's web UI) ends with that song. Do it again: "already in" and nothing added.
- [ ] Add an album (⋯ menu) to a playlist that already has one of its songs: the banner counts the skipped one, and the rest are appended in album order.
- [ ] Long-press a Recently Added cover > Add to Playlist… > New Playlist…, name it: a new playlist with that album's songs.
- [ ] Long-press an artist > Add to Playlist…: all their songs, oldest album first, go into the chosen playlist (asking first if over 100).
- [ ] Now Playing > Save Queue > New Playlist…: the new playlist holds the whole queue in order, including songs already played. Save Queue again into an existing playlist: only songs not already there are added.
- [ ] Playlists > +: an empty playlist with that name appears in the list and in Navidrome.
- [ ] The sheet lists only your own playlists (not other users' public ones). In Airplane Mode, adding shows "Couldn't Save Playlist" and the sheet stays open.

### Streaming quality
- [ ] Set cellular to 96 kbps, turn Wi-Fi off, and start an album. It sounds noticeably lower quality (or check Navidrome's activity view for the transcoding). Turn Wi-Fi back on: the next track is back to original.
- [x] On cellular at a low bitrate, drag the progress bar forward and back within a track. Playback jumps there. (Transcoded streams are a known weak spot for seeking in Subsonic servers; note anything odd.) (2026-10-11)
- [ ] Change the setting while playing: the current track carries on uninterrupted.

### Downloads
- [x] Download a playlist. In Navidrome's web UI, add two songs to it and remove one. Switch away from Bzide and back (or wait 15 minutes): the download gets the two new songs (they download) and loses the removed one; Downloaded shows the new count. Open the playlist offline: the new list plays. (2026-10-13)
- [x] Add a song to a downloaded playlist from Bzide (long-press > Add to Playlist…): it starts downloading right away. (2026-10-13)
- [ ] Delete a downloaded playlist in Navidrome: Bzide keeps the download, and it still plays offline.
- [x] Download an album on Wi-Fi. Progress shows on the album and in Library > Downloaded, and it completes. (2026-10-11)
- [x] Start a large download, lock the phone (or switch apps) for a few minutes. It keeps going; reopen the app and it shows the right progress. (2026-10-11)
- [x] Start a download and force-quit the app. Relaunch: it carries on or restarts, and finishes. (2026-10-11)
- [x] Turn on Airplane Mode. Library > Downloaded lists it and it plays from start to end, including on the lock screen. (2026-10-11)
- [x] With "Download over cellular" off, turn Wi-Fi off and download something: it waits, and finishes when Wi-Fi is back. (2026-10-11)
- [x] Download a playlist that shares songs with a downloaded album. Remove the album: the playlist's songs still play offline. (2026-10-11)
- [x] Remove All Downloads in Settings: Storage Used goes to zero. (2026-10-11)
- [ ] Search Downloaded by album name, artist and a song title: each finds the right download; a search with no match says so.
- [x] Download an album, then turn on Airplane Mode and force-quit and relaunch the app. Library > Downloaded, the album screen, Now Playing and the lock screen all show its artwork. (2026-10-11)
- [x] Settings > Downloads > Download Quality: 128 kbps. Download an album: it finishes, plays offline, and Storage Used grows much less than for the same album at Original. (2026-10-12)
- [x] With some songs of that album still downloading, switch back to Original: the album finishes and every song plays. Albums downloaded earlier aren't downloaded again. (2026-10-12)
- [ ] Long-press a song (in an album, search, history…) > Download: Library > Downloaded shows "Downloaded Songs" at the top with it inside, and it plays in Airplane Mode. Its long-press now says Remove Download, which removes it.
- [ ] Long-press a song from an album you've downloaded: it shows "Downloaded", grayed out.
- [ ] Long-press a song in Search, a playlist and History: Go to Album opens its album, Go to Artist its artist. On an album's own page, only Go to Artist is offered.
- [x] Favorite a song and rate another from their long-press menus: a heart and the rating's face appear in the row before the duration straight away, and in Search and History too. Tapping the row plays it as before. (2026-10-12)

### Appearance

- [ ] Settings > Appearance > Theme: choose Catppuccin Mocha. The app turns Mocha at once without leaving Settings: dark blue-gray background, lighter rows, Mauve tint.
- [ ] With Mocha, pick a few accents (e.g. Peach, Green, Blue): the swatch gets a tick and the tint changes everywhere (tab bar, Play and Shuffle, the current song, Now Playing's slider).
- [ ] Browse every screen in Mocha: Library, Artists (letter headers), an artist, Albums, an album, Playlists, Downloaded, History, Search with results, Now Playing and its queue. No plain black areas left; text is readable.
- [ ] Choose Latte: everything turns light, including Now Playing and the History date picker sheet. Then Frappé and Macchiato.
- [ ] With the phone in light mode, Mocha stays dark; with the phone in dark mode, Latte stays light.
- [ ] Back to System: the app follows the phone's light or dark mode with iOS blue, as before.
- [ ] Force quit and relaunch: the chosen theme and accent are kept. Sign out: the sign-in screen is in the theme too.

- [x] In System, Light or Dark: buttons, icons and the tab bar are Bzide Red (darker in light mode, brighter in dark mode). Settings > Appearance shows Accent swatches with Bzide Red ticked; pick another: the app follows. Switch to a Catppuccin theme and back: each keeps its own accent. (2026-10-13)
### Radio

- [ ] Library > Radio lists the stations added in Navidrome, by name. Tap one: it plays within a few seconds; the row shows the speaker icon.
- [ ] Play an http station and an https station; if one of your stations' addresses is a `.pls` or `.m3u` file, play that too.
- [ ] While a station plays: Now Playing shows "Live", no progress bar; previous and repeat are grayed out; no heart or rating. If the station announces songs, the title changes with them and the station name shows beneath.
- [ ] Lock screen: shows the station (and current song if announced) as live, with no scrubber; play/pause works.
- [ ] Pause for a minute, then play: it comes back live (what's on now), not where it paused.
- [ ] Turn on Airplane Mode for ~10 seconds while it plays, then off: it reconnects on its own.
- [ ] Force quit and relaunch: the station is shown paused; play rejoins it. Play an album afterwards: normal songs work as before (scrobbling, history).
- [ ] Navidrome's web UI shows no scrobbles and play history shows nothing for radio listening.

### Audio levels (visualizer phase 1, from the Debug player)

- [x] Turn on Audio tap and play a streamed album: the bars move with the music and Buffers keeps climbing. Let two songs hand over: no gap, no glitch. (2026-10-12)
- [x] With the tap on: a downloaded song and a converted (lower-quality) stream move the bars too; note whether a radio station does. (2026-10-12: downloads and converted streams move them; a radio station plays fine but the bars don't move, see Audio levels.)
- [x] With the tap on: pause/resume, skip, lock the phone for a few minutes, take a call or alarm, unplug or disconnect headphones: all behave as without it. Note anything that sounds different. (2026-10-12)
- [x] With the tap on, AirPlay to a speaker: playback is unaffected; note whether the bars still move. (2026-10-12: playback fine; the bars don't move, as expected, see Audio levels.)
- [x] Turn it off: playback carries on untouched. Relaunch: it's off. (2026-10-12)

### Visualizer

- [x] Play an album, open Now Playing > waveform button: full-screen bars in your accent move with the music (bass on the left), title and artist at the bottom. Let a song end: the next one starts without a gap and the bars carry on. (2026-10-12)
- [x] Open and close the visualizer several times in the middle of a song, and start a new album with it closed and with it open: no skip or hiccup in the audio. (2026-10-12)
- [x] Pause: the bars fall flat. Play: they come back. Leave it open a few minutes: the screen doesn't dim or lock. Close it: the screen dims normally again. (2026-10-12)
- [x] Play a radio station and open it: "The visualizer isn't available for radio." Switch to AirPlay with a song: "…isn't available over AirPlay."; back to the iPhone: the bars return. (2026-10-12)
- [x] Switch to Catppuccin with another accent: the bars use it. (2026-10-12)
- [x] Swipe left or right on the visualizer: it switches between Bars and Waveform (the capsule at the top follows). The waveform moves with the music and flattens when paused. (2026-10-12)
- [x] Tap the capsule: the menu lists Style (Bars, Waveform) and Colors (Accent, Multicolor) with checkmarks; choosing one applies it. Multicolor: bars and waveform sweep through colors from your accent; in Catppuccin, through its accents in palette order. Back to Accent: one color. Close and reopen, and relaunch: the style and colors are kept. (2026-10-12)
- [x] On the visualizer, previous, play/pause and next work and the title follows the song, without closing it. On radio, previous is off. (2026-10-12)
- [x] Choose Plasma (menu or swipe): fine swirling bands of color flow over the whole screen behind the controls, without strobing. It pulses with the drums (a small zoom and ripple on each hit), the rings swell with the bass, the bands strengthen with the mids, and cymbals and vocals add a fine shimmer; quiet passages drift slowly. The title and buttons stay readable. Try Accent and Multicolor, and a Catppuccin theme. Leave it a few minutes: no stutter in the audio, and the phone doesn't get hot. (2026-10-12)
- [x] Choose Groove: a record turns with the album cover as its label and the steel tonearm on the right. The groove is cut under the stylus as the song plays, deeper on loud parts and drum hits, spiraling inward; open it mid-song and the earlier part is a plain gray groove. Seek: the stylus jumps. Next song: a blank record. Try Multicolor: the groove changes color as it moves inward. (2026-10-13)
- [x] Turn the phone sideways with each style open (Bars, Waveform, Plasma, Groove): the title and controls move to the right, and the visualization fills the height on the left (the Groove record as big as the screen allows). Turn it back: the portrait layout returns. (2026-10-13)
- [x] Choose Living Cover: the album cover breaks into tiles that burst outward with the bass and drums, tilt with the mids and sparkle at the edges with the cymbals, over a blurred copy of the cover; quiet passages put it back together. Skip to the next song: the new album's cover appears (never the previous one's). (2026-10-13)
- [x] Choose Tapestry: the loom beam moves down as the song plays, its shuttle crossing back and forth, weaving rows of threads that are wider and brighter where the music is loud (bass threads on the left). Pause: the weaving stops. Seek ahead: the beam jumps and the skipped part stays bare. Next song: fresh cloth. Try Multicolor: each thread its own color. Sideways: the cloth fills the height on the left. (2026-10-13)
- [x] Choose Weather: a quiet acoustic song gives a clear sky with the sun out; a loud rock song clouds over within a few seconds, rains, and strikes lightning bolts on the drum hits (bolts only, no screen flash). Heavy bass bends the trees and speeds the clouds. Pause: the sky clears. Sideways: the sun moves left of the panel and the controls stay readable. (2026-10-13)
- [x] Choose Chrome: a liquid-metal blob reflects the album cover, bulging at the bottom with the bass and at the top with the cymbals, swelling and rippling on drum hits, splashing droplets into the free space that melt back into it a few seconds later, and settling into a gently wobbling round shape when quiet. Next song: it reflects the new cover. Try Multicolor: the edges catch the colors. Sideways: it fits on the left. (2026-10-13)
- [x] Choose Typeset: the title fills the screen with the artist below (the small title at the bottom is gone). Letters at the start bounce with the bass and at the end with the cymbals, lifting, stretching and glowing; drum hits knock them loose and they spring back. Try a long title: it wraps to at most three lines, smaller. Next song: the new title. Sideways: it fits on the left. (2026-10-13)
- [x] Choose Polygraph: paper fills the screen and four needles reach down from the top edge, drawing on it as it runs down; the first three lines swing with the bass, mids and treble (the bass pen kicks on drum hits), the fourth hatches with the loudness. Pause: the paper keeps running and the needles settle to center, drawing flat lines; play again: the lines pick up without a jolt. Sideways: the needles reach in from the left and the paper runs right. The paper fills the screen and the controls (dark, over the paper) stay readable. Try Multicolor: one ink per pen, all readable on the paper. (2026-10-13)
- [ ] Scroll quickly through Albums and skip songs fast: every row and Now Playing always shows the right cover.
- [x] In a Catppuccin theme, the visualizer menu offers Accent, Multicolor and Custom, and "Choose Custom Colors…": pick a few accents (at least two stay), Done: the bars, waveform and plasma use just those, in palette order. Switch to a non-Catppuccin theme: Custom isn't offered and the colors show as Multicolor. (2026-10-13)

### Spin Off and Keep Spinning
- [ ] Rate a few songs Meh. Random Mix and Spin Off never play them (check Now Playing's queue); turn on Settings > Playback > Include Meh Songs and they can appear again. Spin off from a Meh song: it still plays first.

- [ ] With repeat all on, long-press a song > Spin Off: it plays, repeat turns off, the queue heading reads "Spin-off of “…”", and up next is similar music. Skip quickly through every song: more keep being added, and it never wraps back to the first song. Force quit and relaunch: still a spin-off, and it keeps growing.
- [ ] Long-press an artist (and the artist page's ⋯) > Spin Off: music by that artist and similar ones. Now Playing ⋯ > Spin Off: from the current song.
- [ ] With Last.fm turned off in Navidrome (or another server without it): Spin Off still plays, with a banner explaining it's a mix of the song's genre.
- [ ] Settings > Playback > Keep Spinning on: play a single song or let an album reach its last song; when it's on its last song, similar music is added after it. Off: the queue ends as before. With repeat on: nothing is added.

### Volume normalization

- [x] Settings > Playback > Volume Normalization: By Album. Play a song with ReplayGain tags: Now Playing's quality line ends with its adjustment (e.g. "−6.1 dB") and it plays at that level; a song without tags shows none and sounds as before. (2026-10-13)
- [ ] While a tagged song plays, switch between Off, By Track and By Album: the volume changes at once with no skip, and the quality line follows.
- [ ] Play an album with quiet and loud songs By Album, then By Track: By Album keeps the quiet song quiet, By Track brings it up to the others.

### Sleep timer

- [x] Now Playing > moon > 15 Minutes: the moon shows 15:00 counting down. Lock the phone: after 15 minutes the music fades out over about 10 seconds and pauses. Press play: normal volume. (2026-10-13)
- [x] Moon > End of Song near the end of a song: it fades out over the last few seconds and stops as the song ends, with no burst of the next song. Set it again and skip to the next song early: that song plays, and the music stops at its end. (2026-10-13)
- [ ] Start a timer, then Moon > Turn Off Timer: the moon goes back to normal and the music keeps playing. Start one and pause before it ends: nothing happens when it runs out.

### Lyrics

- [x] Play a song with synced lyrics on the server and tap the speech bubble in Now Playing: lyrics over the blurred cover, the current line bright with its words lighting up as they're sung, the view scrolling along with the song; the other lines dim. (2026-10-13)
- [ ] Tap an earlier line: the song jumps there and the lyrics follow. Scroll away by hand: the view stays put, then returns to the current line a few seconds after you stop.
- [ ] A song whose server lyrics are plain only: they scroll freely under "These lyrics aren't synced to the music." A song with none: "No Lyrics". Radio: "Lyrics aren't available for radio."
- [x] Turn on Settings > Lyrics > Find Lyrics Online, open lyrics for a song the server has none for: LRCLIB's lyrics appear, credited at the end. Turn it off: back to the server's lyrics or "No Lyrics". (2026-10-13)
- [ ] Skip songs with the lyrics open: they change with the song, and the previous song's lyrics never show for the new one.
- [ ] Watch a song with estimated word timing (no word times in its lyrics): the words light up roughly with the singing and finish before the next line.

### Siri (needs Apple Intelligence)

- [ ] Long-press an artist > Ask Siri > "play this": that artist plays, oldest album first. Same from an album and a playlist row.
- [ ] Long-press an artist > Ask Siri > "tell me about this artist": Siri talks about that artist (not about Bzide or the screen).
- [ ] Long-press a song > Ask Siri > "add this to my <playlist> playlist": it's added; Siri says so. Ask again: Siri says it's already there.
- [ ] With Now Playing open, "add this to <playlist>": the current song is added.
- [ ] Without the app open: "Play <album name> in Bzide", "Shuffle <artist> in Bzide", "Play <playlist> in Bzide".
- [ ] "Play <artist with more than 100 songs> in Bzide": Siri asks first; saying no plays nothing.
- [ ] Signed out: a Siri request says to sign in first.

### Play history
- [ ] Let a song play past halfway: it appears in Library > History under Today, with the time it started. Skip another song early: it doesn't appear.
- [ ] Search History by track, artist and album name. Switch the period between Today, Last 7 Days and a custom range.
- [ ] Play the same song twice in a day: History shows it once with "2 plays" at the later time. Turn on Show Every Play in the filter menu: both plays are listed. The choice is kept after relaunch.
- [ ] Tap a play: just that song plays.
- [ ] Settings > Keep History For: shorten it and check older plays disappear. Clear History empties the list.
- [ ] Force-quit and relaunch: the history is still there.

### CarPlay (simulator)
- [ ] Open the CarPlay window. The four tabs appear with artwork; each list loads.
- [ ] Open an album, choose a song: it plays from that song and Now Playing appears with the right artwork and working controls.
- [ ] Shuffle plays the album shuffled.
- [ ] Downloaded lists downloads; with the network off, a downloaded album still opens and plays.
- [ ] Play from the phone while CarPlay is open: CarPlay's Now Playing follows.

### Scrobbling
- [ ] Play a track past halfway (or 4 minutes). It appears once in Navidrome's play history, at the time you started it.
- [ ] Play a track, skip to near the end, let it finish. It is not scrobbled.
- [ ] While a track plays, Navidrome shows it as now playing. Let it flow into the next track: now playing updates.
- [ ] Turn on Airplane Mode, play two tracks past halfway, turn Airplane Mode off and play a third. All three appear in order.
- [ ] Turn on Airplane Mode, play a track past halfway, force-quit the app, turn Airplane Mode off, relaunch. The track appears.
