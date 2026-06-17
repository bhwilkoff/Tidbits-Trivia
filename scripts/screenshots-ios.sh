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
launch;                                                                              shot 01-home 4
launch_env SIMCTL_CHILD_TIDBITS_AUTOPLAY=classic:science;                            shot 02-question 5
launch_env SIMCTL_CHILD_TIDBITS_AUTOPLAY=classic:mixed SIMCTL_CHILD_TIDBITS_AUTOPILOT=1; shot 03-reveal 9
launch_env SIMCTL_CHILD_TIDBITS_TAB=create;                                          shot 04-create 4
launch_env SIMCTL_CHILD_TIDBITS_ONBOARD=1;                                           shot 05-onboarding 4
launch_env SIMCTL_CHILD_TIDBITS_AUTOPLAY=classic:history SIMCTL_CHILD_TIDBITS_AUTOPILOT=1; shot 07-results 24
echo "Done. (App Store needs the 6.9\" size — re-run with a Pro Max sim if this one isn't 6.9\".)"
