---
paths:
  - "MusicApp/CarPlay/**"
  - "MusicApp/Siri/**"
  - "BzideControls/**"
  - "Config/*.entitlements"
  - "Packages/NavidromeCore/Sources/NavidromeCore/Playback/WidgetFeed.swift"
  - "Packages/NavidromeCore/Sources/NavidromeCore/Playback/WidgetSnapshot.swift"
---

# CarPlay, Siri, widgets and controls

Siri lives in `MusicApp/Siri/`: App Intents entities and intents using the system audio schemas, annotations that tell Siri what a view shows, and lookups through the same `Library` models (`QuickActions`, `PlaylistEditor`). It needs no entitlement.

CarPlay lives in `MusicApp/CarPlay/` (a template scene declared in `Info.plist`) and fills Apple's templates from the same `Library` models as the phone. The owner has a paid Apple Developer account (individual, since 2026-10-21; same team ID as before). Entitlements: `Config/MusicApp.entitlements` (the app, device and simulator builds: CarPlay audio, WeatherKit and the App Group) and `Config/BzideControls.entitlements` (the extension: the App Group). Apple granted the CarPlay audio entitlement on 2026-10-22; it's enabled on the App ID, and Xcode's automatic signing includes it. Widgets and controls live in the `BzideControls` WidgetKit extension (target `BzideControlsExtension`, which links `NavidromeCore`): the Now Playing and Shortcuts widgets and the Lock Screen and Control Center "Favorite Song" control. They can't see the engine: the app shares what's playing through the App Group `group.com.erichebert.musicapp` (`WidgetSnapshot`, written by `WidgetFeed`), never credentials or server details. Their buttons are audio playback intents, which the system runs in the app's process. The intent definitions are in `MusicApp/Siri/FavoriteIntentDefinitions.swift` and `MusicApp/Siri/PlaybackIntentDefinitions.swift`, compiled into both targets (folder membership exceptions in the project); each target has its own `CurrentSongFavorite` and `WidgetPlayback` (the app's do the work, the extension's do nothing or say to play something first). All of these depend on `NavidromeCore` and must not duplicate logic.
