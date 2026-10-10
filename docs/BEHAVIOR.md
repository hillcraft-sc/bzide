# Behavior spec

How the app behaves, written so the web and Android clients can be ported from this file rather than from the Swift code. Each playback rule gets a manual checklist entry for testing on a real device.

## Server communication

_Filled in during M1._

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
