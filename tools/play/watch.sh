#!/usr/bin/env bash
# Watch real games render — question, reveal, and results — for every mode.
#
#   tools/play/watch.sh [category] [outdir]        (default: mixed, tools/play/shots)
#
# The engine playthrough (TIDBITS_PLAYTHROUGH) proves the RULES work: the right
# answer is accepted, the round ends, the score adds up. It cannot see what the
# player sees. A question whose options overflow their buttons, a reveal with an
# empty explanation panel, a results screen that says nothing — all of those pass
# every engine check and still spoil the game. So this drives the real views with
# the real autopilot and takes a picture of each phase, which is the only evidence
# that actually answers "does this look right".
#
# Three launches per mode, because TIDBITS_AUTOPILOT_STEPS parks the app on a
# phase: 0 steps holds the question, 1 step holds the reveal, unset runs to the
# results screen.
set -euo pipefail
cd "$(dirname "$0")/../.."

CAT="${1:-mixed}"
OUT="${2:-$PWD/tools/play/shots}"
DEV="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
SIM="${TIDBITS_SIM:-iPhone 17 Pro}"
BUNDLE=com.learningischange.tidbitstrivia
MODES="${TIDBITS_WATCH_MODES:-classic timeAttack survival stake sweep pictureId thisOrThat closestCall ordering matching typeAnswer oddOneOut ladder enumerate}"

mkdir -p "$OUT"
UDID="$(DEVELOPER_DIR=$DEV xcrun simctl list devices available \
        | grep -F "$SIM (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[ -n "$UDID" ] || { echo "FAIL: no available simulator named '$SIM'"; exit 1; }
DEVELOPER_DIR=$DEV xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || \
  DEVELOPER_DIR=$DEV xcrun simctl boot "$UDID" >/dev/null 2>&1 || true

APP="$(find ~/Library/Developer/Xcode/DerivedData -name 'TidbitsTrivia.app' \
        -path '*Debug-iphonesimulator*' -print -quit 2>/dev/null || true)"
[ -n "$APP" ] || { echo "FAIL: no built TidbitsTrivia.app"; exit 1; }
DEVELOPER_DIR=$DEV xcrun simctl install "$UDID" "$APP"

shoot() {  # mode phase steps settle
  local mode="$1" phase="$2" steps="$3" settle="$4"
  DEVELOPER_DIR=$DEV xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  # macOS bash 3.2 treats "${extra[@]}" on an EMPTY array as unbound under
  # `set -u`, so the array always carries one (possibly inert) entry.
  local extra=(TIDBITS_WATCH_NOOP=1)
  if [ "$steps" != "-" ]; then extra=(SIMCTL_CHILD_TIDBITS_AUTOPILOT_STEPS="$steps"); fi
  env SIMCTL_CHILD_TIDBITS_SKIP_ONBOARD=1 \
      SIMCTL_CHILD_TIDBITS_NO_GAMECENTER=1 \
      SIMCTL_CHILD_TIDBITS_AUTOPLAY="$mode:$CAT" \
      SIMCTL_CHILD_TIDBITS_AUTOPILOT=1 \
      SIMCTL_CHILD_TIDBITS_AUTOPILOT_CORRECT=1 \
      "${extra[@]}" \
      DEVELOPER_DIR=$DEV xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
  sleep "$settle"
  DEVELOPER_DIR=$DEV xcrun simctl io "$UDID" screenshot "$OUT/$mode-$phase.png" >/dev/null 2>&1
  echo "   $mode $phase"
}

for mode in $MODES; do
  echo "--- $mode"
  shoot "$mode" question 0 5
  shoot "$mode" reveal   1 6
  shoot "$mode" results  - 40      # autopilot advances every 0.9s; a round needs time
done
echo "--- wrote $(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ') screenshots to $OUT"
