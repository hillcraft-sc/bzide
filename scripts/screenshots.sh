#!/bin/zsh
# Takes the App Store screenshots in a Simulator, using the debug-only
# launch arguments in MusicApp/Debug/ScreenshotScript.swift.
#
#   SCREENSHOT_SERVER=https://demo.navidrome.org SCREENSHOT_USER=demo SCREENSHOT_PASSWORD=demo \
#     scripts/screenshots.sh <simulator id> <output folder> [light|dark]
#
# The credentials are only used when the Simulator's app is signed out. The
# album ids are from Navidrome's demo server (Creative Commons music), so the
# screenshots show no commercial artwork. The music plays out loud on the Mac.
#
# Besides the PNGs, it saves upload-ready JPEGs (no alpha channel) in
# <output folder>/upload. From the iPhone 6.9" Simulator (1320 x 2868) it
# also makes 1206 x 2622 copies, the size App Store Connect requires
# ("iPhone with Dynamic Island (medium display)"); the iPad 13" size is
# required as taken. Each Simulator uses a lot of memory: run one at a time.
set -euo pipefail

device=$1
out=$2
appearance=${3:-light}
cd "$(dirname "$0")/.."
mkdir -p "$out"

xcodebuild -project MusicApp.xcodeproj -scheme MusicApp -destination "id=$device" build -quiet
app=$(xcodebuild -project MusicApp.xcodeproj -scheme MusicApp -destination "id=$device" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ CODESIGNING_FOLDER_PATH /{print $2}')

xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b >/dev/null
xcrun simctl install "$device" "$app"
xcrun simctl ui "$device" appearance "$appearance"
xcrun simctl status_bar "$device" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100

# name, seconds to wait, then the launch arguments.
shot() {
  local name=$1 wait=$2
  shift 2
  SIMCTL_CHILD_SCREENSHOT_SERVER=${SCREENSHOT_SERVER:-} \
  SIMCTL_CHILD_SCREENSHOT_USER=${SCREENSHOT_USER:-} \
  SIMCTL_CHILD_SCREENSHOT_PASSWORD=${SCREENSHOT_PASSWORD:-} \
    xcrun simctl launch --terminate-running-process "$device" com.erichebert.musicapp "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$device" screenshot "$out/$name.png" >/dev/null 2>&1
  echo "$out/$name.png"
}

fairytale=4ArIoYRbh0CaV7mFckEkXe   # Natasha Beller, Fairytale
chillhop=1PzQ7ahygHNPRAOSa8la67    # Chillhop Essentials - Fall 2016
ambassador=3ZE7pthjfyWFhRvT4JKKqJ  # The Polish Ambassador, Diplomatic Immunity
slip=2ilrD9t8Kda9ozUDLBqBE1        # Nine Inch Nails, The Slip (has lyrics)

shot 01-library 12 -screenshot library -screenshotAlbum $chillhop -screenshotSeek 40
shot 02-now-playing 10 -screenshot nowPlaying -screenshotAlbum $fairytale -screenshotSeek 79
shot 03-violent-sphere 15 -screenshot visualizer -screenshotAlbum $ambassador -screenshotTrack 3 -screenshotSeek 60 \
  -visualizerStyle violentSphere -visualizerColors multicolor
shot 04-album 10 -screenshot album -screenshotAlbum $chillhop -screenshotSeek 40
shot 05-spectrum 15 -screenshot visualizer -screenshotAlbum $chillhop -screenshotSeek 90 \
  -visualizerStyle spectrum -visualizerColors multicolor
shot 06-lyrics 10 -screenshot lyrics -screenshotAlbum $slip -screenshotTrack 2 -screenshotSeek 60
shot 07-albums 12 -screenshot albums -screenshotAlbum $chillhop -screenshotSeek 40
shot 08-chrome 15 -screenshot visualizer -screenshotAlbum $fairytale -screenshotSeek 100 \
  -visualizerStyle chrome -visualizerColors multicolor

# Leave the app stopped, so the music doesn't keep playing, and the
# Simulator shut down, for its memory.
xcrun simctl terminate "$device" com.erichebert.musicapp 2>/dev/null || true
xcrun simctl shutdown "$device" 2>/dev/null || true

mkdir -p "$out/upload"
for png in "$out"/[0-9]*.png; do
  name=$(basename "$png" .png)
  sips -s format jpeg -s formatOptions 95 "$png" --out "$out/upload/$name.jpg" >/dev/null
  if [[ $(sips -g pixelWidth "$png" | awk '/pixelWidth/{print $2}') == 1320 ]]; then
    sips -z 2622 1206 -s format jpeg -s formatOptions 95 "$png" --out "$out/upload/$name-1206x2622.jpg" >/dev/null
  fi
done
