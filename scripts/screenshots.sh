#!/bin/zsh
# Takes the App Store screenshots in a Simulator, using the debug-only
# launch arguments in MusicApp/Debug/ScreenshotScript.swift.
#
#   SCREENSHOT_SERVER=https://demo.navidrome.org SCREENSHOT_USER=demo SCREENSHOT_PASSWORD=demo \
#     scripts/screenshots.sh <simulator id> <output folder>
#
# The credentials are only used when the Simulator's app is signed out. The
# album ids are from Navidrome's demo server (Creative Commons music), so the
# screenshots show no commercial artwork. The music plays out loud on the Mac.
#
# Besides the PNGs, scripts/compose-screenshots.swift makes the App Store
# images from them (headlines, Bzide Red, the stacked Themes image) in
# <output folder>/upload, as JPEGs: from the iPhone 6.9" Simulator
# (1320 x 2868) also at 1206 x 2622, the size App Store Connect requires
# ("iPhone with Dynamic Island (medium display)"); the iPad 13" size is
# required as taken. Each Simulator uses a lot of memory: run one at a time.
#
# iPhone Duo: the Simulator starts folded, which takes the outer display
# (1398 x 2034). For the inner display (2007 x 2853), unfold it in Xcode's
# Device Hub first and set SCREENSHOT_DISPLAY=primary-1 (the screens are
# listed by `xcrun simctl io <id> enumerate`).
#
# To retake one shot (say, when the demo server's Recently Played shows
# something unsuitable), set SCREENSHOT_ONLY=<its name>, e.g. 02-library. The
# others are skipped and nothing is composed; copy the new PNG into the folder
# of a full run and run `swift scripts/compose-screenshots.swift <folder>`.
set -euo pipefail

device=$1
display=${SCREENSHOT_DISPLAY:-}
out=$2
cd "$(dirname "$0")/.."
mkdir -p "$out"

xcodebuild -project MusicApp.xcodeproj -scheme MusicApp -destination "id=$device" build -quiet
app=$(xcodebuild -project MusicApp.xcodeproj -scheme MusicApp -destination "id=$device" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ CODESIGNING_FOLDER_PATH /{print $2}')

xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b >/dev/null
xcrun simctl install "$device" "$app"
xcrun simctl ui "$device" appearance light
xcrun simctl status_bar "$device" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100

# name, seconds to wait, then the launch arguments.
shot() {
  local name=$1 wait=$2
  shift 2
  if [[ -n ${SCREENSHOT_ONLY:-} && $name != "$SCREENSHOT_ONLY" ]]; then return 0; fi
  SIMCTL_CHILD_SCREENSHOT_SERVER=${SCREENSHOT_SERVER:-} \
  SIMCTL_CHILD_SCREENSHOT_USER=${SCREENSHOT_USER:-} \
  SIMCTL_CHILD_SCREENSHOT_PASSWORD=${SCREENSHOT_PASSWORD:-} \
    xcrun simctl launch --terminate-running-process "$device" com.erichebert.musicapp "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$device" screenshot ${display:+--display=$display} "$out/$name.png" >/dev/null 2>&1
  echo "$out/$name.png"
}

fairytale=4ArIoYRbh0CaV7mFckEkXe   # Natasha Beller, Fairytale
chillhop=1PzQ7ahygHNPRAOSa8la67    # Chillhop Essentials - Fall 2016
ambassador=3ZE7pthjfyWFhRvT4JKKqJ  # The Polish Ambassador, Diplomatic Immunity
slip=2ilrD9t8Kda9ozUDLBqBE1        # Nine Inch Nails, The Slip (has lyrics)

# The App Store set, in its order, all in the Light theme; the themes shots
# make the stacked Themes image (scripts/compose-screenshots.swift).
light=(-screenshotTheme light)
library_base=(-screenshot library -screenshotShowAll YES -recentlyAddedCollapsed NO -recentlyPlayedCollapsed NO
  -spinItBackCollapsed NO)
library=($library_base -screenshotAlbum $chillhop -screenshotSeek 40)
library_bare=($library_base -screenshotNoMiniPlayer YES)

# The album shown downloaded (07) starts downloading first, so it's done by then.
shot 01-now-playing 10 -screenshot nowPlaying -screenshotAlbum $fairytale -screenshotSeek 79 $light \
  -screenshotDownload YES
# Library shows its three carousels open and no mini player (it would cover
# the last row, even when nothing is playing).
shot 02-library 15 "${library_bare[@]}" $light
shot 03-radio 15 -screenshot findStations -screenshotStationGenre jazz -screenshotAlbum $chillhop -screenshotSeek 40 $light
shot 04-spectrum 15 -screenshot visualizer -screenshotAlbum $chillhop -screenshotSeek 90 \
  -visualizerStyle spectrum -visualizerColors multicolor $light
shot 06-lyrics 10 -screenshot lyrics -screenshotAlbum $slip -screenshotTrack 2 -screenshotSeek 60 $light
for theme in tokyoNight latte gruvboxDark nord; do
  shot themes-$theme 15 $library -screenshotTheme $theme
done
shot 07-album 15 -screenshot album -screenshotAlbum $fairytale -screenshotSeek 79 $light

# Leave the app stopped, so the music doesn't keep playing, and the
# Simulator shut down, for its memory.
xcrun simctl terminate "$device" com.erichebert.musicapp 2>/dev/null || true
xcrun simctl shutdown "$device" 2>/dev/null || true

[[ -n ${SCREENSHOT_ONLY:-} ]] || swift scripts/compose-screenshots.swift "$out"
