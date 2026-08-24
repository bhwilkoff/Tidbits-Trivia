#!/usr/bin/env bash
# Build the tvOS app for the REAL Apple TV and install it on the paired device.
# The whole loop: tools/atv_install.sh && python3 tools/atv_run.py --scenario home
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
DEV="${TB_ATV:-Ben Bedroom}"

xcodebuild -project TidbitsTrivia.xcodeproj -scheme TidbitsTrivia \
  -destination 'generic/platform=tvOS' -configuration "${TB_CONFIG:-Debug}" \
  -derivedDataPath build/atv-dd -allowProvisioningUpdates build \
  | grep -E "error|BUILD (SUCCEEDED|FAILED)" || true

APP=build/atv-dd/Build/Products/${TB_CONFIG:-Debug}-appletvos/TidbitsTrivia.app
[ -d "$APP" ] || { echo "build failed — no $APP"; exit 1; }

# Installs work while the TV sleeps; no wake needed here.
xcrun devicectl device install app --device "$DEV" "$APP" >/dev/null
echo "installed $(defaults read "$PWD/$APP/Info.plist" CFBundleShortVersionString 2>/dev/null || echo '?') on $DEV"

# The OCR binary the harness needs (rebuild is cheap; /tmp gets cleared).
swiftc -O tools/ScreenOCR/main.swift -o /tmp/tbocr
