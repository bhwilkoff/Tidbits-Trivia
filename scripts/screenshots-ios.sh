#!/usr/bin/env bash
# Generate the iOS App Store marketing screenshot set by driving the app to
# each key screen via the DebugHooks env vars (no-ops in production).
# Output → branding/screenshots/. Re-run after UI/content changes.
#
# Usage: scripts/screenshots-ios.sh ["iPhone 17 Pro"]
#   App Store wants the 6.9" size — pass a Pro Max sim name to capture it.
set -euo pipefail
SIM="${1:-iPhone 17 Pro}"
BID=com.learningischange.tidbitstrivia
APP=/tmp/tidbits-dd/Build/Products/Debug-iphonesimulator/TidbitsTrivia.app
OUT="$(cd "$(dirname "$0")/.." && pwd)/branding/screenshots"
mkdir -p "$OUT"
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true
xcrun simctl install "$SIM" "$APP" >/dev/null 2>&1
xcrun simctl spawn "$SIM" defaults write $BID tidbits.hasOnboarded -bool true >/dev/null 2>&1

launch() { xcrun simctl terminate "$SIM" $BID >/dev/null 2>&1 || true; xcrun simctl launch "$SIM" $BID >/dev/null 2>&1; }
launch_env() { xcrun simctl terminate "$SIM" $BID >/dev/null 2>&1 || true; env "$@" xcrun simctl launch "$SIM" $BID >/dev/null 2>&1; }
shot() { sleep "$2"; xcrun simctl io "$SIM" screenshot "$OUT/$1.png" >/dev/null 2>&1; echo "  $1"; }

echo "Capturing to $OUT (sim: $SIM)"
# WARM the app first: the FIRST launch after install is a cold start, so a short-delay
# capture catches the iOS springboard (home screen) or the red splash — both look like
# "not the app" and get the submission REJECTED. Launch once and wait past the splash
# before any capture. (Do NOT use TIDBITS_ONBOARD for a marketing shot — it IS the splash.)
xcrun simctl launch "$SIM" $BID >/dev/null 2>&1; sleep 10
xcrun simctl io "$SIM" screenshot "$OUT/01-home.png" >/dev/null 2>&1; echo "  01-home"
launch_env SIMCTL_CHILD_TIDBITS_AUTOPLAY=classic:science;                            shot 02-question 8
launch_env SIMCTL_CHILD_TIDBITS_AUTOPLAY=classic:mixed SIMCTL_CHILD_TIDBITS_AUTOPILOT=1; shot 03-reveal 11
launch_env SIMCTL_CHILD_TIDBITS_TAB=create;                                          shot 04-create 8
launch_env SIMCTL_CHILD_TIDBITS_AUTOPLAY=classic:history SIMCTL_CHILD_TIDBITS_AUTOPILOT=1; shot 05-results 26
echo "Done. Read EVERY png before uploading. App Store needs the 6.9\" size (Pro Max sim);"
echo "the ASC iPhone slot may want 6.5\" (1284x2778) — resize with: sips -z 2778 1284 <png>."
