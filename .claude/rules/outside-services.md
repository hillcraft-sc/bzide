---
paths:
  - "Packages/NavidromeCore/Sources/NavidromeCore/API/*Client.swift"
  - "Packages/NavidromeCore/Sources/NavidromeCore/Models/Gravatar.swift"
  - "Packages/NavidromeCore/Sources/NavidromeCore/Models/LiveWeather.swift"
  - "Packages/NavidromeCore/Sources/NavidromeCore/Models/RadioBrowserStation.swift"
  - "MusicApp/NowPlaying/AppleWeather.swift"
  - "MusicApp/NowPlaying/LiveWeatherSource.swift"
  - "MusicApp/Info.plist"
  - "**/PrivacyInfo.xcprivacy"
---

# Outside services

Outside services, all opt-in and off by default, never given server details or credentials: LRCLIB (lrclib.net) for lyrics the server doesn't have (Settings > Lyrics; gets only a song's title, artist, album and length, and the id of an LRCLIB entry the user picked with Wrong lyrics?), Gravatar (gravatar.com), one of the profile picture choices (Settings > Profile; gets only the SHA-256 of an email), Radio Browser (radio-browser.info) for finding radio stations (Settings > Radio > Find Stations Online; gets only the search text and chosen filters, the ids of stations found there when they're played, the stream addresses of saved stations, to look up their logo, country, genres and quality (and their names when an address isn't listed), and for Spin the Dial a genre and its restrictions per spin, never listening history), and Apple Weather (WeatherKit; the default source, with the `com.apple.developer.weatherkit` entitlement, falling back to MET Norway; gets the same rounded coordinates; its mark and legal link must be shown with its data) or MET Norway (api.met.no) for the Weather (Live) visualizer (Settings > Weather (Live) > Live Weather; gets only coordinates rounded to 2 decimals, while the visualizer is open; its terms require a contact in the User-Agent, set in Info.plist as `METNorwayContact`, and ask apps with many users to go through a caching proxy, which `METNorwayClient`'s base URL allows). MusicBrainz (musicbrainz.org) and the Cover Art Archive for the song a radio station is playing (Settings > Radio > Look Up Songs Online; get only its artist and title; MusicBrainz's terms require a contact in the User-Agent, Info.plist `MusicBrainzContact`, and at most one request a second, which `MusicBrainzClient` keeps). Look Up Artists Online (Settings > Artists) uses the same MusicBrainz client, the Cover Art Archive, and Wikidata and Wikipedia (Wikimedia) for an artist's releases (with their track counts, and an album's track titles for the Wishlist's missing songs) and biography; they get only the artist's name or MusicBrainz id, a release's MusicBrainz id, the Wikidata item and the article title, with the same contact in the User-Agent. A city typed for Weather (Live) is looked up with Apple's MapKit geocoder. The app asks for when-in-use location only for Weather (Live) (`NSLocationWhenInUseUsageDescription`). The contact card and photo choices use Apple's pickers, which need no permissions.

Keep `docs/PRIVACY.md` and the privacy manifests (`PrivacyInfo.xcprivacy`) true whenever this changes.
