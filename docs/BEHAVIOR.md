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

_Filled in during M2._

### Scrobbling

- A track is scrobbled once it has played for 50% of its duration or 4 minutes, whichever comes first.
- A single play is never scrobbled twice.
- Open question: whether seeking forward counts toward the threshold. Decide before implementing.

## Queue

_Filled in during M2._

## Caching and offline

_Filled in during M4._

## Manual test checklist

_Entries are added alongside each playback rule._
