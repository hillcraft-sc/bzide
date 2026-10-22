# Bzide and your privacy

Bzide is a music player for your own Navidrome (or other Subsonic) server. It's built so that your music, your listening and your login stay between your iPhone and your server.

This page is also in the app, under Settings > Privacy.

## The short version

- **No tracking, no ads, no analytics.** Bzide contains no third-party code at all: no analytics or crash-reporting kits, no ad networks. It's Apple's frameworks and Bzide's own code.
- **We never see your data.** There's no Bzide account and no Bzide server. Nothing you play, search or save is ever sent to us.
- **Your listening goes to your server, and only there.** What you play is reported to *your own* server, the same as any other app you use with it, and you can turn that off.
- **Every outside service is off until you turn it on,** and each one gets only what it needs to do its job. None of them ever gets your server's address or your login.
- **Your password stays in the iPhone's Keychain** and never leaves the phone. You can sign in with an API key instead, so your password is never on the phone at all.

## What Bzide sends, and to whom

### Your server

Bzide talks to the server you sign in to: to browse and search your library, play and download music, and save favorites, ratings and playlists.

It also reports what you play (scrobbling), so your server can keep play counts and lists such as Recently Played, and pass your plays to Last.fm or ListenBrainz *if you've linked them on your server*. Bzide itself never contacts Last.fm or ListenBrainz. **Settings > Scrobbling > Send Plays to Server** turns this off entirely.

### Outside services (all off by default)

| Service | What it's for | Turned on in | What it gets |
|---|---|---|---|
| **LRCLIB** (lrclib.net) | Lyrics your server doesn't have | Settings > Lyrics > Find Lyrics Online | A song's title, artist, album and length |
| **Radio Browser** (radio-browser.info) | Finding radio stations, Spin the Dial | Settings > Radio > Find Stations Online | Your search and filters; the addresses of your saved stations (to find their logos and details); the id of a station found there when you play it (Radio Browser counts plays this way). Never your listening history. |
| **MusicBrainz** and the **Cover Art Archive** | What song a station is playing; an artist's albums | Settings > Radio > Look Up Songs Online; Settings > Artists > Look Up Artists Online | An artist's name and a song title, or an artist's name or MusicBrainz id |
| **Wikipedia** and **Wikidata** | Artist biographies | Settings > Artists > Look Up Artists Online | Which artist's article to show |
| **Apple Weather** or **MET Norway** | The Weather (Live) visualizer | Settings > Weather (Live) > Live Weather | Your location, rounded to about a kilometer, only while the visualizer is open |
| **Apple Maps** | Finding the city you type for Weather (Live) | Typing a place in Settings > Weather (Live) | What you typed |
| **Gravatar** (gravatar.com) | A profile picture | Choosing Gravatar in Settings > Profile | A one-way hash of the email address (not the address itself) |

### Radio stations

Internet radio plays straight from each station's own server, which sees your connection as any listener's would. Some stations only stream over plain http, which isn't encrypted: someone on your network could see which station you're listening to (not who you are). Station logos load from the station's own website.

## What stays on your iPhone

- **Your login** in the Keychain, readable only on this iPhone (it isn't synced to iCloud Keychain or put in backups).
- **Your downloads**, cover art and caches (downloads aren't put in backups).
- **Play history, the queue, Tagged Radio Songs, saved stations, your profile picture and your settings,** each kept per account. Like all app data, they're encrypted by iOS and included in your iPhone's backups.
- **What the widgets show** (the song playing and its cover), shared only with Bzide's own widgets.

Bzide doesn't keep copies of your server's answers on disk: its connections use private sessions with no web cache or cookies.

## What Bzide never does

- Collect, sell or share anything about you. There's nothing to collect it into.
- Track you across apps or websites, or use an advertising identifier.
- Send your server's address, your username or your password to anyone but your server.
- Talk to an outside service you haven't turned on.
- Log song names, searches or logins: the app's diagnostic logs record only what kind of failure happened.

## Apple

Bzide runs on Apple's platform, so some things go through Apple as they do for every app: Siri and Apple Intelligence (if you use them with Bzide), CarPlay, the App Store and TestFlight, and crash reports *if you've chosen to share analytics with developers* in the iPhone's settings. Apple Weather is used only if you turn on Live Weather and keep Apple Weather as its source.

## For the technically minded

- **Connections:** HTTPS for everything, except a server address you enter as `http://` and radio stations that stream over http. Bzide's only App Transport Security exception covers audio, for those stations.
- **Signing in:** with a password, each request carries a salted token (Subsonic's token authentication) rather than the password. Because that token is derived from the password, Bzide warns when you sign in over plain http to an address outside your own network, where it could be read on the way. With an **API key** (servers supporting OpenSubsonic's `apiKeyAuthentication`), the key is sent instead and no password is stored at all.
- **Network sessions:** private (ephemeral) sessions with no disk cache, cookies or stored credentials, for your server and every outside service. Background downloads keep no cache either. iOS's shared web cache is emptied at each launch.
- **Storage:** the Keychain item is `AfterFirstUnlockThisDeviceOnly` (readable while the phone is locked, so music can keep playing, but never synced or backed up). App files use iOS's standard data protection.
- **Privacy manifest:** the app and its widgets extension declare no tracking, no tracking domains and no collected data, and the two "required reason" APIs they use: app settings (`UserDefaults`, CA92.1) and the dates of the app's own cache files (C617.1).
- **App Store privacy label:** Data Not Collected.

*Kept up to date with the app: when what Bzide sends or stores changes, this page changes with it.*
