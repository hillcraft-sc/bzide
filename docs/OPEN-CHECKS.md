# Open device checks

A snapshot of the 97 unticked checks in `docs/BEHAVIOR.md` (Manual test checklist), taken 2026-10-17. `BEHAVIOR.md` is the real record: tick a check there (or tell Claude which passed), not here. This file goes stale and can be regenerated or deleted.

The number after each check is its line in `BEHAVIOR.md`.

## Account (4)

- [x] Settings shows the server and user. Sign Out (confirm): playback stops, the sign-in screen appears, and the lock screen no longer shows the app. (line 357)
- [x] Sign back in to the same account: downloads, history and the queue (paused where it was) are all still there. (line 358)
- [x] Sign in to a different user or server (if available): downloads, history and the queue are gone, and Storage Used is zero. Sign back in to the first account: its downloads are gone too (they were removed when the account changed). (line 359)
- [x] Sign out and in again several times in one session: playback, lock screen controls and downloads keep working each time. (line 364)

## Basics (1)

- [x] Let the last track of a queue finish. The queue empties, the mini player shows Not Playing, and the lock screen and Control Center no longer show the app's track. (line 373)

## Audio session (1)

- [ ] Play through wired or USB headphones, unplug them. Music pauses and does not play through the speaker. Plug back in: still paused. (line 381)

## Lock screen and Control Center (1)

- [x] Wired or Bluetooth headphone buttons play, pause and skip. (line 394)

## Library (30)

- [ ] On a fresh layout (Edit Library > Reset), Library shows no carousels. Edit Library marks Recently Added, Recently Played and Spin It Back with the carousel icon. Switch on Recently Played and Spin It Back: they appear and fill in straight away. Recently Played shows albums played this week (including from Navidrome's web player), newest first. Spin It Back shows albums you've rated or favorited but not played in a while, at most two per artist, never Meh; it's the same all day and different tomorrow. (line 408)
- [ ] Search with nothing typed, funnel > Love: every song, album and artist you rated Love is listed; the line above says "Love" with Clear. Tap into the search field: the scope bar appears; pick Songs: only songs. Type a word: only matching Love songs. Clear: back to the genre grid. Force quit and relaunch with a filter on: it's still on. (line 409)
- [ ] Funnel > Favorites Only, then Downloaded Only: only favorites, then only downloaded songs and albums (no artists). (line 410)
- [ ] With Include Favorites in My Cuts on, favorite (heart) a few unrated songs: within half an hour they come up in Mix My Cuts; turn the setting off and they no longer do. A favorite rated Meh never does. (line 412)
- [ ] Library's toolbar shows Edit and Settings (no ladybug); Settings > Developer > Debug Player opens the debug player. (line 414)
- [ ] Edit: hide Radio and History, drag Artists and Albums above Recently Added, Done: Library shows exactly that, with Artists and Albums in one block at the top. Force quit and relaunch: kept. Edit > Reset: back to the default. (line 415)
- [ ] Hide everything: Library says to tap Edit. (line 416)
- [ ] Favorites: your hearted songs (Play and Shuffle work), albums and artists. Unheart a song from its long-press menu: it leaves the list. Heart an album elsewhere, come back: it's there. (line 417)
- [ ] Genres from Library opens the genre grid; a tile opens its genre. (line 419)
- [ ] The current song (top row) can't be swiped or dragged. Force quit and relaunch after editing: the queue keeps the new order. (line 434)
- [ ] Now Playing: Previous, Play and Next are centered under the progress bar, with Shuffle on the left and Repeat on the right. (line 435)
- [ ] Play an album, then tap Shuffle: it turns the accent color, the queue below is shuffled, the song keeps playing, and the next one plays without a gap. Tap it again: the rest of the album is back in order. (line 436)
- [ ] Tap an album's Shuffle button: Shuffle is shown on. Turn it off: the songs not yet played follow in album order. Play an album normally: Shuffle is off. (line 437)
- [ ] Turn Shuffle on, force quit and relaunch: it's still on, and turning it off restores the order. (line 438)
- [ ] Open an artist with no picture or biography: a placeholder image, the name and the albums, with no gap or error where the biography would be. (line 445)
- [ ] Library shows Recently Added covers at the top, newest first, matching Navidrome's "Recently Added". Tap a cover: the album opens. See All: the albums list in Recently Added order. (line 449)
- [ ] Long-press a Recently Added cover: Play replaces the queue with that album; Play Next and Add to Queue add it in the right place. (line 450)
- [ ] Long-press an artist in Artists: Play plays their albums oldest first, each in track order. Shuffle mixes them. Favorite and Rate show up in Navidrome. (line 451)
- [ ] Long-press an artist with more than 100 songs: it asks first ("Play 340 songs by …?"); Cancel does nothing. (line 452)
- [ ] Long-press an album in Albums, on an artist's page and in Search: Play, Play Next, Add to Queue, Download (then Remove Download on a second long-press), Go to Artist (not on the artist's page). (line 453)
- [ ] Long-press a playlist: Play, Shuffle and Download work. Long-press a download in Airplane Mode: Play works. (line 454)
- [ ] Tap the Recently Added heading: the row collapses. Force quit and relaunch: still collapsed. Tap again: it expands. (line 455)
- [ ] Long-press a genre tile > Shuffle: a mix of that genre plays. Switch to Catppuccin Mocha: the tiles take the theme's colors with dark, readable names. (line 461)
- [ ] Long-press a song, choose Add to Playlist…, pick a playlist: the sheet closes, the banner says it was added, and the playlist (here and in Navidrome's web UI) ends with that song. Do it again: "already in" and nothing added. (line 462)
- [ ] Add an album (⋯ menu) to a playlist that already has one of its songs: the banner counts the skipped one, and the rest are appended in album order. (line 463)
- [ ] Long-press a Recently Added cover > Add to Playlist… > New Playlist…, name it: a new playlist with that album's songs. (line 464)
- [ ] Long-press an artist > Add to Playlist…: all their songs, oldest album first, go into the chosen playlist (asking first if over 100). (line 465)
- [ ] Now Playing > Save Queue > New Playlist…: the new playlist holds the whole queue in order, including songs already played. Save Queue again into an existing playlist: only songs not already there are added. (line 466)
- [ ] Playlists > +: an empty playlist with that name appears in the list and in Navidrome. (line 467)
- [ ] The sheet lists only your own playlists (not other users' public ones). In Airplane Mode, adding shows "Couldn't Save Playlist" and the sheet stays open. (line 468)

## Streaming quality (2)

- [ ] Set cellular to 96 kbps, turn Wi-Fi off, and start an album. It sounds noticeably lower quality (or check Navidrome's activity view for the transcoding). Turn Wi-Fi back on: the next track is back to original. (line 471)
- [ ] Change the setting while playing: the current track carries on uninterrupted. (line 473)

## Downloads (5)

- [ ] Delete a downloaded playlist in Navidrome: Bzide keeps the download, and it still plays offline. (line 478)
- [ ] Search Downloaded by album name, artist and a song title: each finds the right download; a search with no match says so. (line 486)
- [ ] Long-press a song (in an album, search, history…) > Download: Library > Downloaded shows "Downloaded Songs" at the top with it inside, and it plays in Airplane Mode. Its long-press now says Remove Download, which removes it. (line 490)
- [ ] Long-press a song from an album you've downloaded: it shows "Downloaded", grayed out. (line 491)
- [ ] Long-press a song in Search, a playlist and History: Go to Album opens its album, Go to Artist its artist. On an album's own page, only Go to Artist is offered. (line 492)

## Appearance (7)

- [ ] Settings > Appearance > Theme: choose Catppuccin Mocha. The app turns Mocha at once without leaving Settings: dark blue-gray background, lighter rows, Mauve tint. (line 497)
- [ ] With Mocha, pick a few accents (e.g. Peach, Green, Blue): the swatch gets a tick and the tint changes everywhere (tab bar, Play and Shuffle, the current song, Now Playing's slider). (line 498)
- [ ] Browse every screen in Mocha: Library, Artists (letter headers), an artist, Albums, an album, Playlists, Downloaded, History, Search with results, Now Playing and its queue. No plain black areas left; text is readable. (line 499)
- [ ] Choose Latte: everything turns light, including Now Playing and the History date picker sheet. Then Frappé and Macchiato. (line 500)
- [ ] With the phone in light mode, Mocha stays dark; with the phone in dark mode, Latte stays light. (line 501)
- [ ] Back to System: the app follows the phone's light or dark mode with iOS blue, as before. (line 502)
- [ ] Force quit and relaunch: the chosen theme and accent are kept. Sign out: the sign-in screen is in the theme too. (line 503)

## Radio (9)

- [ ] Library > Radio lists the stations added in Navidrome, by name. Tap one: it plays within a few seconds; the row shows the speaker icon. (line 508)
- [ ] Play an http station and an https station; if one of your stations' addresses is a `.pls` or `.m3u` file, play that too. (line 509)
- [ ] Lock screen: shows the station (and current song if announced) as live, with no scrubber; play/pause works. (line 511)
- [ ] Pause for a minute, then play: it comes back live (what's on now), not where it paused. (line 512)
- [ ] Turn on Airplane Mode for ~10 seconds while it plays, then off: it reconnects on its own. (line 513)
- [ ] Force quit and relaunch: the station is shown paused; play rejoins it. Play an album afterwards: normal songs work as before (scrobbling, history). (line 514)
- [ ] Navidrome's web UI shows no scrobbles and play history shows nothing for radio listening. (line 515)
- [ ] As an admin: Radio shows +. Add a station (name, stream address, homepage): it appears in the list, plays, and shows in Navidrome's web UI. Leave the name blank: it's named after the stream's host. Type an address without http://: the form says why and stays open. (line 525)
- [ ] Swipe a station > Edit: the form shows its details; change the name: the list and Navidrome show the new name. Swipe > Delete, confirm: it's gone from the list and from Navidrome. Long-press offers Edit and Delete too. (line 526)

## Visualizer (2)

- [ ] Debug menu (Debug: Weather) in a debug build: try Downpour, Thunderstorm, Snow and Fog with a loud and a quiet song: the rain and snow are about twice as heavy in the loud song, lightning strikes on the drums only in Thunderstorm, fog thins in the loud song; no birds in any of them; Night with Cloudy hides the stars. (line 566)
- [ ] Scroll quickly through Albums and skip songs fast: every row and Now Playing always shows the right cover. (line 572)

## Spin Off and Keep Spinning (5)

- [ ] Rate a few songs Meh. Random Mix and Spin Off never play them (check Now Playing's queue); turn on Settings > Playback > Include Meh Songs and they can appear again. Spin off from a Meh song: it still plays first. (line 576)
- [ ] With repeat all on, long-press a song > Spin Off: it plays, repeat turns off, the queue heading reads "Spin-off of “…”", and up next is similar music. Skip quickly through every song: more keep being added, and it never wraps back to the first song. Force quit and relaunch: still a spin-off, and it keeps growing. (line 578)
- [ ] Long-press an artist (and the artist page's ⋯) > Spin Off: music by that artist and similar ones. Now Playing ⋯ > Spin Off: from the current song. (line 579)
- [ ] With Last.fm turned off in Navidrome (or another server without it): Spin Off still plays, with a banner explaining it's a mix of the song's genre. (line 580)
- [ ] Settings > Playback > Keep Spinning on: play a single song or let an album reach its last song; when it's on its last song, similar music is added after it. Off: the queue ends as before. With repeat on: nothing is added. (line 581)

## Volume normalization (2)

- [ ] While a tagged song plays, switch between Off, By Track and By Album: the volume changes at once with no skip, and the quality line follows. (line 586)
- [ ] Play an album with quiet and loud songs By Album, then By Track: By Album keeps the quiet song quiet, By Track brings it up to the others. (line 587)

## Sleep timer (1)

- [ ] Start a timer, then Moon > Turn Off Timer: the moon goes back to normal and the music keeps playing. Start one and pause before it ends: nothing happens when it runs out. (line 594)

## Siri (needs Apple Intelligence) (10)

- [ ] Long-press an artist > Ask Siri > "play this": that artist plays, oldest album first. Same from an album and a playlist row. (line 621)
- [ ] Long-press an artist > Ask Siri > "tell me about this artist": Siri talks about that artist (not about Bzide or the screen). (line 622)
- [ ] Long-press a song > Ask Siri > "add this to my <playlist> playlist": it's added; Siri says so. Ask again: Siri says it's already there. (line 623)
- [ ] With Now Playing open, "add this to <playlist>": the current song is added. (line 624)
- [ ] Without the app open: "Play <album name> in Bzide", "Shuffle <artist> in Bzide", "Play <playlist> in Bzide". (line 625)
- [ ] "Play <artist with more than 100 songs> in Bzide": Siri asks first; saying no plays nothing. (line 626)
- [ ] Signed out: a Siri request says to sign in first. (line 627)
- [ ] Play a song, lock the phone, "Favorite this song in Bzide": Siri confirms; the heart is filled in Now Playing and Navidrome. Say it again: still a favorite (not undone). "Unfavorite this song in Bzide": cleared. On a radio station: Siri says it can't be a favorite. (line 628)
- [ ] Play a song and say just "Favorite this song" (or "I like this song"), without "in Bzide": Siri favorites it in Bzide instead of saying the app doesn't support liking. (line 629)
- [ ] Settings > Action Button > Shortcut > Bzide > Favorite Current Song (or a Shortcut): pressing it hearts the playing song. (line 630)

## Lock Screen and Control Center control (3)

- [x] Lock Screen > Customize > Lock Screen > tap the flashlight (or camera) > remove it, add Bzide > Favorite Song. Play a song, lock the phone, press the heart: the song is a favorite (Now Playing's heart filled, and in Navidrome). Press again: still a favorite. (line 634)
- [x] Add Favorite Song to Control Center: pressing it hearts the playing song too. (line 635)
- [x] Play a radio station and press it: nothing changes, no error. (line 636)

## Home Screen quick actions (3)

- [x] With something queued, go to the Home Screen and long-press the icon: Continue (naming the song, or the station), Random Mix, Mix My Cuts, Search. Each works: Continue resumes, the mixes start, Search opens Search with the keyboard up. (line 640)
- [x] Force quit, then use each from the icon: the app opens and does it. (line 641)
- [x] Clear the queue (or fresh sign-in with nothing played): no Continue. Sign out: the menu offers nothing of Bzide's. (line 642)

## Play history (6)

- [x] Let a song play past halfway: it appears in Library > History under Today, with the time it started. Skip another song early: it doesn't appear. (line 645)
- [x] Search History by track, artist and album name. Switch the period between Today, Last 7 Days and a custom range. (line 646)
- [x] Play the same song twice in a day: History shows it once with "2 plays" at the later time. Turn on Show Every Play in the filter menu: both plays are listed. The choice is kept after relaunch. (line 647)
- [x] Tap a play: just that song plays. (line 648)
- [x] Settings > Keep History For: shorten it and check older plays disappear. Clear History empties the list. (line 649)
- [x] Force-quit and relaunch: the history is still there. (line 650)

## CarPlay (simulator) (5)

- [ ] Open the CarPlay window. The four tabs appear with artwork; each list loads. (line 653)
- [ ] Open an album, choose a song: it plays from that song and Now Playing appears with the right artwork and working controls. (line 654)
- [ ] Shuffle plays the album shuffled. (line 655)
- [ ] Downloaded lists downloads; with the network off, a downloaded album still opens and plays. (line 656)
- [ ] Play from the phone while CarPlay is open: CarPlay's Now Playing follows. (line 657)
