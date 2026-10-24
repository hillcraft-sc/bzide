# Bzide User Guide

Bzide plays the music on your own Navidrome (or other Subsonic) server. This guide walks through everything it does, from signing in to widgets and CarPlay. It's also in the app, under Settings > Help.

## Getting started

### What you need

- **A music server** running Navidrome or another Subsonic-compatible server, with your music on it.
- **Its address**, the one you'd type into a web browser to reach it, such as `https://music.example.com`. Ask whoever runs the server if you're not sure.
- **Your username and password** for that server. Or, if your server offers them, an **API key** from its settings.

### Signing in

1. Open Bzide. The sign-in screen appears.
2. Type the server's full address, starting with `https://` (or `http://`).
3. Choose **Password** and enter your username and password, or choose **API Key** and paste a key from your server's settings.
4. Tap **Sign in**.

Your login is saved securely on this iPhone, so you only do this once. If the address starts with `http://` and isn't on your home network, Bzide warns you: that connection isn't encrypted, so use `https://` if your server supports it.

**Tip:** an API key is the most private option. Your password never touches the phone.

## Finding your way around

Bzide has two tabs at the bottom:

- **Library:** your music, organized: Artists, Albums, Playlists, Favorites, Genres, Radio, Downloaded, History and Wishlist, plus quick ways to start music (Random Mix, Mix My Cuts, Spin the Dial).
- **Search:** find anything by name. Before you type, it shows your genres as colored tiles.

Above the tabs sits the **mini player**: what's playing, with play/pause and next. Tap it to open **Now Playing**, the full-screen player with the cover, controls, and your queue. Swipe it down or tap the arrow to close it.

**Settings** is the gear (or your profile picture) at the top of Library.

## Playing music

- **Tap a song** to play its album or playlist from that song.
- **Play** and **Shuffle** buttons at the top of an album, playlist, genre or Favorites start them in order or shuffled.
- **Long-press** almost anything (a song, album, artist, playlist, genre) for a menu: **Play**, **Shuffle**, **Play Next** (right after the current song), **Add to Queue** (at the end), **Add to Playlist…**, **Download**, **Favorite**, **Rate**, and **Go to Album** or **Go to Artist**.
- **Random Mix** (top of Library) plays 50 random songs from your library.
- **Mix My Cuts** plays the songs you've rated Love or Like, or 3 stars and up (and your favorites), shuffled, without end.
- **Spin Off** (in a song's or artist's long-press menu, or Now Playing's ••• menu) plays endless music that grows from a song or artist: similar songs if your server knows them, otherwise songs from the same genre.

### Now Playing

- **Controls:** shuffle, previous, play/pause, next and repeat. Previous restarts the song if it has played for more than 3 seconds; tap again to go back a song.
- **The progress bar:** drag it to jump to any point.
- **The row of buttons** under the controls: the **heart** (favorite), the **rating**, **AirPlay** (choose speakers, headphones or a TV), **Lyrics**, and the **visualizer**.
- **The status line** shows whether it's playing, and the song's format and quality. Tap the quality to hide it.
- **The moon** (top right) is the **sleep timer**: 15, 30 or 45 minutes, 1 hour, or End of Song. The music fades out and pauses.
- **The ••• menu:** Spin Off, Song Info, Album Info, Equalizer, Go to Album, Go to Artist, and Save Queue as Playlist.

### The queue

The list under the controls in Now Playing is your **queue**: the current song, then what's coming up.

- **Tap** a song to jump to it.
- **Swipe left** on an upcoming song to remove it.
- **Long-press and drag** to move it.
- **Long-press** for Song Info, Go to Album and Go to Artist.
- **Clear Up Next** removes everything after the current song.
- **Save Queue as Playlist** (••• menu) keeps it for later.

Your queue is saved, so after closing Bzide it's waiting where you left off, paused.

### Keep the music going

Turn on **Settings > Playback > Keep Spinning**, and when a queue reaches its last song, Bzide carries on with similar music instead of stopping.

## Favorites and ratings

- **Favorites:** tap the heart on a song, album or artist (in Now Playing, or its long-press menu). They're saved on your server, so they show in your other apps too. Library > **Favorites** lists them all.
- **Ratings:** rate a song, album or artist **Meh** 😩, **Like** 👌 or **Love** 😈. Choose the same rating again to clear it. Ratings drive Mix My Cuts, and Meh songs are left out of the mixes (unless you turn on Settings > Playback > Include Meh Songs).
- **Prefer stars?** Turn off **Settings > Ratings > Use Simplified Rating** to rate 1 to 5 stars, as in Navidrome. The Rate menu then shows a row of five stars: tap one to set it, tap it again or choose **Clear Rating** to clear it. Your server keeps the same ratings either way: Meh, Like and Love are saved as 1, 3 and 5 stars, and 1–2 stars count as Meh in the mixes (Include 1–2 Star Songs).

Favorited and rated songs show a small heart, and a face or their stars (such as 4★), in song lists.

## Searching and browsing

- **Search** finds artists, albums and songs as you type. Use the bar at the top (All, Artists, Albums, Songs) to narrow it down.
- **The funnel** filters by rating, favorites, or what's downloaded. With a filter on and nothing typed, Search lists everything in your library that matches.
- **Genres:** tap a genre tile to see its albums, or long-press it to play the whole genre.
- **History** (in Library) lists what you've played on this iPhone, by day. Filter by text or dates; set how long it's kept in Settings > Play History.
- **Make Library yours:** tap **Edit** (top of Library) to show, hide and reorder what's there, including optional rows of covers: Recently Added, Recently Played, and Spin It Back (albums you love but haven't played in a while).

## Playlists

- **Add to a playlist:** long-press a song, album, artist or playlist and choose **Add to Playlist…**. Pick a playlist, or **New Playlist**. Songs already in the playlist aren't added twice.
- **Save the queue** as a playlist from Now Playing's ••• menu.
- **Rename, share or delete** one of your playlists: long-press it in Playlists, or use the **•••** menu on its page. **Share Playlist** makes it public, so everyone with an account on your server can see and play it (tap again to stop sharing). **Delete Playlist…** asks first; the songs stay in your library.
- **Remove a song** from one of your playlists: on the playlist's page, swipe the song left, or long-press it and choose **Remove from Playlist**. It only leaves that playlist.
- **Reorder songs:** on the playlist's page, long-press a song and drag it to a new place.
- Playlists are saved on your server, so they're in your other apps too. Playlists other people shared with you can be played but not changed.

## Downloads and offline listening

1. Long-press an album, playlist or song and choose **Download**.
2. Watch progress in Library > **Downloaded**.
3. Downloaded music plays from the phone, with or without a connection, and stays there until you remove it.

- **Downloaded playlists stay up to date:** add a song to the playlist (in any app) and Bzide downloads it too.
- **Quality and data:** Settings > Downloads > **Download Quality** (Original, or smaller files), and **Download over Cellular** (off by default, so downloads wait for Wi-Fi).
- **Streaming quality:** Settings > Streaming Quality, one for Wi-Fi and one for Cellular. Lower qualities use less data; Original is best.
- **Space:** Settings > Downloads shows the space used, and **Remove All Downloads**. To remove one, long-press it and choose **Remove Download**.

## Radio

- **Your stations:** Library > **Radio** lists the internet radio stations saved on your server. Tap one to play it.
- **Add a station:** tap **+**, then enter a name and the stream's address. It's saved on your server (if you're its admin) or on this iPhone.
- **Find stations online:** turn on **Settings > Radio > Find Stations Online**, then tap the magnifying glass in Radio to search thousands of stations by name, country or genre. Tap **+** on a station to save it.
- **Station Info:** tap the info button in Now Playing for a station's details: country, genre, quality and website.

### Spin the Dial

**Spin the Dial** (in Library) tunes to a random station you'll probably like, based on what you listen to. Tap **Next** while it plays to spin again. If you like one, tap **Save Station**. Settings > Spin the Dial chooses how it picks, and can limit it to your country, chosen genres, or a minimum quality. It needs Find Stations Online.

### What's playing on the station

When a station announces the song it's playing:

- If the song is in your library, Now Playing shows **In Your Library**. Tap it to play your copy or open the album.
- If it isn't, tap **Tag Song** to remember it. It goes on your **Wishlist** (Library > Wishlist), under Found on Radio, which marks the ones that show up in your library later.
- With **Settings > Radio > Look Up Songs Online** on, Bzide also shows the song's album cover and details.

## Lyrics

Tap the **speech bubble** in Now Playing.

- **Synced lyrics** follow along, the current line lit up word by word. Tap a line to jump the song there.
- **Out of step?** Tap the **timer** button (top right) to show them earlier or later. The fix is remembered for that song.
- **No lyrics?** If your server doesn't have them, turn on **Settings > Lyrics > Find Lyrics Online** to look them up on LRCLIB, a free lyrics database.
- **Wrong version?** Turn on **Settings > Lyrics > Wrong Lyrics Button**. Then, for lyrics from LRCLIB, tap **Wrong lyrics?** to try the next match, or stop using LRCLIB for that song. Your choice is remembered, and the button turns your accent color while a changed version shows.

**For server owners:** with Navidrome 0.63 or later, install the [Navidrome Lyrics Plugin](https://github.com/J0R6IT0/navidrome-lyrics-plugin) (nd-lyrics). The server then finds lyrics online itself, for every app, and Bzide shows them with no setup.

## The visualizer

Tap the **waveform** in Now Playing for a full-screen visualizer that moves with the music. **Swipe** left or right, or tap its name at the top, to change the style: Bars, Waveform, Plasma, Polygraph, Groove, Living Cover, Tapestry, Weather, Weather (Live), Chrome and Typeset. Choose colors from the same menu.

- **Weather (Live)** can show the real weather where you are. Turn on **Settings > Weather (Live) > Live Weather**.
- The visualizer works for songs on this iPhone. It isn't available for radio stations or over AirPlay.
- **Prefer less motion?** With Reduce Motion on (iPhone Settings > Accessibility > Motion), the visualizer asks before it starts. To hide it completely, turn off **Settings > Visualizer**.

## The equalizer

**Settings > Equalizer** (or Now Playing's ••• menu) shapes the sound: turn it on, then choose a preset (Bass Boost, Vocal, Rock, Late Night…) or move the ten bands yourself.

- It works for songs played on this iPhone's speaker, headphones and Bluetooth.
- It can't change **radio stations** or **AirPlay**, whose audio doesn't pass through the app.
- Now Playing's status line says **EQ** while you're hearing it, and **EQ unavailable** when what's playing can't be equalized.

## Artists

An artist's page shows their picture, a short biography and their albums. Turn on **Settings > Artists > Look Up Artists Online** for a longer biography from Wikipedia, and the albums, singles and live releases you don't have yet (under **Not Owned**; tap one to see it on MusicBrainz).

- **Similar Artists** at the bottom of an artist's page lists artists like them (from your server, usually via Last.fm). Tap one you have to open their page; tap one with an arrow, which isn't in your library, to look them up on MusicBrainz.
- **Your Wishlist** (Library > Wishlist) keeps what you'd like to get, in sections:
  - **Found on Radio:** songs you tagged while a station played them.
  - **Missing Songs:** on an album you only partly have, tap ••• > **Add Missing Songs to Wishlist** (needs Look Up Artists Online, which knows the song titles).
  - **Albums:** long-press an album under **Not Owned** > **Add to Wishlist**.
  - **Artists:** long-press an artist with an arrow under **Similar Artists** > **Add to Wishlist**.

  Bzide checks your library for each one: anything that turns up there is marked, and tapping it plays it or opens it. Swipe to remove one, or turn on **Settings > Wishlist > Remove Found Items** to have them leave by themselves once they're in your library.

  To **buy** something on your Wishlist, long-press it and choose **Buy**: Apple Music, Bandcamp, Qobuz or Amazon opens its search for it. To **share** the list, tap the share button at the top: as text, or as a CSV file for a spreadsheet.
- **Albums you don't have all of** are marked in the artist's album list: **Missing tracks** when there's a gap in the track numbers, or **9 of 12 tracks** when the full count is known. The album's page says how many you have, and its **Album Info** has **View on MusicBrainz** to see the full track list. Bzide can always spot gaps; to catch tracks missing from the end, turn on Look Up Artists Online, which gets each album's full track count from MusicBrainz. Deluxe editions don't count against a standard album. To do this, Bzide reads each of an artist's albums from your server the first time you open them; to save data, turn off **Settings > Artists > Mark Incomplete Albums**.

## Make it yours

- **Themes:** Settings > Appearance > **Theme**. Pick System (follows your iPhone), Light, Dark, or a color theme: Catppuccin, Gruvbox, Nord, Dracula or Tokyo Night. Then choose an **Accent** color. Each theme family remembers its own accent.
- **Profile picture:** Settings > Profile. Choose a photo, a contact card, or Gravatar. It replaces the Settings gear.
- **Library layout:** tap **Edit** at the top of Library.

## Widgets, controls and shortcuts

- **Widgets:** long-press your Home Screen, tap **Edit > Add Widget**, and search for Bzide.
  - **Now Playing:** what's playing, with play/pause (and previous, next and favorite on the medium size).
  - **Shortcuts:** Continue, Random Mix, Mix My Cuts and Favorite, without opening the app.
  - Both follow your Bzide theme.
- **Favorite Song control:** add it to Control Center, or to the Lock Screen in place of the flashlight or camera (Lock Screen > Customize). It hearts the song playing.
- **Quick actions:** long-press the Bzide icon for Continue, Random Mix, Mix My Cuts and Search.
- **Siri** (with Apple Intelligence): say "Play [an artist, album or playlist] in Bzide", "Shuffle [something] in Bzide", "Add this to my [playlist] in Bzide", or "Favorite this song in Bzide". "Play music in Bzide" carries on with what you were listening to, or starts a Random Mix; "Play Random Mix in Bzide" works too. This works in CarPlay as well.

## CarPlay

Connect to CarPlay and open Bzide. The tabs are **Recently Played**, **Library** (Random Mix, Mix My Cuts, Artists, Albums, Playlists, Favorites, Genres), **Radio**, and **Downloaded**. Downloaded music plays even without a signal.

- **Getting in the car doesn't start the music** unless you want it to. Some cars tell the music app to play as soon as they connect; Bzide ignores that, and plays when you press play. To let the car start Bzide where you left off, turn on **Settings > CarPlay > Play When CarPlay Connects**. It covers car stereos connected by Bluetooth too.

## Your account

- **Sign out:** Settings > Sign Out. Everything stays on the phone for when you sign back in.
- **Switching to another account:** Bzide asks first. Each account keeps its own settings, history and queue, and they come back when it signs in again. Downloads are removed, as they belong to the other server.
- **Same server, different address** (say, your home network instead of the internet): choose **Same Server, Keep Everything** when asked.
- **Start over:** Settings > **Restore Default Settings** puts every setting back as it was, keeping your downloads, history and favorites.

## Privacy

Bzide has no ads, no tracking and no accounts of its own. Your music and listening go only to your server, and every outside service is off until you turn it on. Settings > **Privacy** explains exactly what goes where.

- **Scrobbling:** Bzide tells your server what you play (for play counts, and Last.fm or ListenBrainz if you've linked them on your server). Turn it off in Settings > Scrobbling > **Send Plays to Server**.

## Troubleshooting

- **Can't sign in:** check the address (with `https://` or `http://`, and any port such as `:4533`) by opening it in Safari. Check the username and password on your server's website. If your server refuses passwords, use an API key.
- **A station won't play:** some stations give a playlist file over plain `http://`, which iPhones won't load. Use the station's direct stream address instead.
- **No lyrics:** turn on Settings > Lyrics > Find Lyrics Online, or ask your server's admin about the lyrics plugin (see Lyrics).
- **The lyrics are for a different version:** turn on the Wrong Lyrics Button (see Lyrics).
- **Spin Off says similar songs aren't available:** your server needs a music-information service (in Navidrome, Last.fm) for similar songs. Bzide plays songs from the same genre instead.
- **"EQ unavailable" or no visualizer:** you're playing radio or using AirPlay. Both work for songs on the iPhone, headphones and Bluetooth.
- **Downloads aren't starting:** they wait for Wi-Fi unless Settings > Downloads > Download over Cellular is on.
- **Siri doesn't understand:** Siri needs Apple Intelligence, and the phrase must say "in Bzide" (say it "Bee-zide"). If Siri plays something from Apple Music instead, it probably misheard the app's name: try again, stressing "in Bee-zide".
- **Everything looks wrong after changing lots of settings:** Settings > Restore Default Settings.
- **Still stuck?** Ask whoever runs your server, or the person who gave you Bzide.
