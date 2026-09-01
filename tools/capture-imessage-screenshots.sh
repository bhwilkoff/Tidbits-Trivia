#!/usr/bin/env bash
# Stage a simulator for capturing the iMessage App Store screenshots.
#
# HONEST SCOPE: this script gets the simulator to the point where the shots can be
# taken; it does NOT take them. Opening the Messages app drawer and picking Tidbits
# needs taps, and there is no way to send one — `simctl` has no tap primitive, and
# XCUITest can only drive your own app, not Messages. The alternative is clicking the
# Simulator window at guessed coordinates, which is exactly the "blind coordinate
# click" this repo's harnesses refuse to do elsewhere.
#
# So: run this, then take four shots by hand (about two minutes). They are also the
# kind of asset worth art-directing rather than generating.
#
#   tools/capture-imessage-screenshots.sh [iphone|ipad]
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
WHICH="${1:-iphone}"

case "$WHICH" in
  iphone) SIM=C59ABDDA-D028-4BC4-BBEB-B35E510771AA; OUT=branding/store-screenshots/imessage-iphone-6.9 ;;
  ipad)   SIM=1BBB3CED-B88D-4210-B752-685693159288; OUT=branding/store-screenshots/imessage-ipad-13 ;;
  *) echo "usage: $0 [iphone|ipad]" >&2; exit 2 ;;
esac

mkdir -p "$OUT"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true

echo "building…"
xcodebuild build -project TidbitsTrivia.xcodeproj -scheme TidbitsTrivia \
  -destination "id=$SIM" -configuration Debug >/dev/null 2>&1

APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/TidbitsTrivia-*/Build/Products/Debug-iphonesimulator/TidbitsTrivia.app | head -1)
xcrun simctl install "$SIM" "$APP"
# The extension rides inside the app bundle — installing the app registers it.
[ -d "$APP/PlugIns/Tidbits.appex" ] || { echo "FAIL: Tidbits.appex is not embedded"; exit 1; }

xcrun simctl launch "$SIM" com.apple.MobileSMS >/dev/null
open -a Simulator
cat <<'NOTE'

Simulator is up with Tidbits installed and Messages open.

Take these four, then drop them into App Store Connect → the version → iMessage App:

  1. A conversation with the Tidbits drawer open (the app icon row)
  2. "Send a round" — category chips and the send button
  3. A live question with its four options
  4. A reveal — the explanation and the scoreboard

Capture each with:  xcrun simctl io <SIM_UDID> screenshot <file>.png
They land at the device's native size, which is what Connect wants.

Apple's rule for a bundled extension: show the iMessage experience, and do NOT show
the Home screen or the app-to-extension transition.
NOTE
