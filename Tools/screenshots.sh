#!/bin/bash
#
# Capture the App Store screenshot set from the real Simulator build.
#   Tools/screenshots.sh            # build + capture everything
#   KEEP_BUILD=1 Tools/screenshots.sh   # skip the rebuild
#
# Output: Screenshots/AppStore/{iphone-6.9,ipad-13,watch-ultra3}/*.png (opaque RGB).
# See Screenshots/AppStore/README.md for what each frame is and the honesty notes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/.build/screenshots-dd"
OUT="$ROOT/Screenshots/AppStore"
BID="com.avaresearch.lensbeacon"
WBID="com.avaresearch.lensbeacon.watch"

PHONE="iPhone 17 Pro Max"          # 1320 x 2868 (6.9-inch)
IPAD="iPad Pro 13-inch (M5)"       # 2064 x 2752 (13-inch)
WATCH="Apple Watch Ultra 3 (49mm)" # 422 x 514

if [[ "${KEEP_BUILD:-0}" != "1" ]]; then
  xcodebuild -project "$ROOT/LensBeacon.xcodeproj" -scheme LensBeacon \
    -destination "platform=iOS Simulator,name=$PHONE" -configuration Debug \
    -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build >/dev/null
  xcodebuild -project "$ROOT/LensBeacon.xcodeproj" -scheme LensBeaconWatch \
    -destination "platform=watchOS Simulator,name=$WATCH" -configuration Debug \
    -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build >/dev/null
fi

APP_IOS="$DD/Build/Products/Debug-iphonesimulator/LensBeacon.app"
APP_WATCH="$DD/Build/Products/Debug-watchsimulator/LensBeacon.app"

udid () { xcrun simctl list devices available | grep -F "$1 (" | grep -oE '[0-9A-F-]{36}' | head -1; }

capture () { # udid  bundle-id  out-path  args...
  local u="$1" b="$2" o="$3"; shift 3
  xcrun simctl launch --terminate-running-process "$u" "$b" "$@" >/dev/null
  sleep 5
  xcrun simctl io "$u" screenshot "$o" >/dev/null 2>&1
  python3 - "$o" <<'PY'
import sys; from PIL import Image
p=sys.argv[1]; im=Image.open(p)
if im.mode!="RGB": im.convert("RGB").save(p,"PNG")
PY
  echo "  $(basename "$(dirname "$o")")/$(basename "$o")"
}

for pair in "$PHONE|iphone-6.9" "$IPAD|ipad-13"; do
  name="${pair%%|*}"; sub="${pair##*|}"; u="$(udid "$name")"
  mkdir -p "$OUT/$sub"
  xcrun simctl boot "$u" 2>/dev/null || true
  xcrun simctl bootstatus "$u" >/dev/null 2>&1 || true
  xcrun simctl status_bar "$u" override --time "9:41" --batteryState charged \
    --batteryLevel 100 --cellularMode notSupported --wifiBars 3 2>/dev/null || true
  xcrun simctl install "$u" "$APP_IOS"
  echo "[$sub]"
  capture "$u" "$BID" "$OUT/$sub/01-onboarding.png"
  capture "$u" "$BID" "$OUT/$sub/02-dashboard.png"      -skip-onboarding -demo-data
  capture "$u" "$BID" "$OUT/$sub/03-sightings.png"      -skip-onboarding -demo-data -screen sightings
  capture "$u" "$BID" "$OUT/$sub/04-sighting-detail.png" -skip-onboarding -demo-data -screen detail
  capture "$u" "$BID" "$OUT/$sub/05-settings.png"       -skip-onboarding -demo-data -screen settings
  capture "$u" "$BID" "$OUT/$sub/06-unlock.png"         -skip-onboarding -demo-data -screen unlock
done

w="$(udid "$WATCH")"
mkdir -p "$OUT/watch-ultra3"
xcrun simctl boot "$w" 2>/dev/null || true
xcrun simctl bootstatus "$w" >/dev/null 2>&1 || true
xcrun simctl install "$w" "$APP_WATCH"
echo "[watch-ultra3]"
capture "$w" "$WBID" "$OUT/watch-ultra3/01-scanning.png" -demo-scanning
capture "$w" "$WBID" "$OUT/watch-ultra3/02-nearby.png"   -demo-data
capture "$w" "$WBID" "$OUT/watch-ultra3/03-detail.png"   -demo-data -screen detail
echo "done -> $OUT"
