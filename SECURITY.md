# Security

## Reporting a vulnerability

Please report security problems privately, not in a public issue. Email **bzide-admin@hillcraft-sc.com** with:

- what you found and where (a screen, a setting, a file in this repository),
- the steps to reproduce it,
- the Bzide version (Settings > About) and iOS version.

This is a one-person project, so I can't promise a response time, but I'll reply as soon as I can, keep you updated and credit you in the fix if you'd like.

## What counts

Bzide handles a login to your own server, so the areas that matter most are:

- how credentials and API keys are stored and sent (the Keychain, token authentication, API keys),
- anything that sends data somewhere it shouldn't, or to a service that wasn't turned on (see [`docs/PRIVACY.md`](docs/PRIVACY.md)),
- network handling: App Transport Security (the one deliberate exception is plain-http audio for internet radio), certificate checks, and redirects,
- local data: downloads, caches, backups and the data shared with the widgets (the App Group never holds credentials or server details),
- the CarPlay, widget and Siri entry points.

## Out of scope

- Vulnerabilities in Navidrome or another server. Please report those to that project.
- Vulnerabilities in the outside services Bzide can call (LRCLIB, Radio Browser, MusicBrainz, Apple's services).
- Problems that need a jailbroken device, or physical access to an unlocked phone.
- Reports that only show a missing best practice, with no way to exploit it.

## Supported versions

Only the latest release on the App Store gets fixes.
