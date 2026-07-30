#!/usr/bin/env bash
# qa-sweep.sh — drive EVERY game mode and feature screen on a simulator and capture a PNG
# of each, so playability and feature completeness can be reviewed from the images rather
# than by clicking through 40 surfaces by hand.
#
#   tools/qa-sweep.sh ios   [outdir]     # iPhone
#   tools/qa-sweep.sh ipad  [outdir]
#   tools/qa-sweep.sh tvos  [outdir]
#
# This is a TEST pass, not the store capture (tools/capture-screenshots.sh) — it draws real
# questions rather than the screened set, because the point is to catch a mode that renders
# wrong, not to produce a listing.
#
# Every launch is independent: the app is terminated between cases so one mode's crash or
# stuck state cannot silently colour the next one's screenshot.
set -uo pipefail
cd "$(dirname "$0")/.."

PLATFORM="${1:-ios}"
OUT="${2:-/tmp/tidbits-qa/$PLATFORM}"
mkdir -p "$OUT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
BUNDLE=com.learningischange.tidbitstrivia

case "$PLATFORM" in
  ios)  DEVICE_MATCH="iPhone 17 Pro" ;;
  ipad) DEVICE_MATCH="iPad Pro" ;;
  tvos) DEVICE_MATCH="Apple TV" ;;
  *) echo "unknown platform: $PLATFORM"; exit 1 ;;
esac

SIM=$(xcrun simctl list devices available | grep -m1 "$DEVICE_MATCH" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$SIM" ] || { echo "no simulator matching '$DEVICE_MATCH'"; exit 1; }
echo "simulator: $DEVICE_MATCH ($SIM)"
xcrun simctl boot "$SIM" 2>/dev/null
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1

# Capture one case: name, then KEY=VALUE launch env, then a settle time.
shot() {
  local name="$1"; shift
  local settle="${SETTLE:-7}"
  xcrun simctl terminate "$SIM" "$BUNDLE" >/dev/null 2>&1
  local env_args=()
  for kv in "$@"; do env_args+=("SIMCTL_CHILD_${kv%%=*}=${kv#*=}"); done
  # Onboarding would sit over every single capture.
  local pid
  pid=$(env "${env_args[@]}" SIMCTL_CHILD_TIDBITS_SKIP_ONBOARD=1 \
    xcrun simctl launch "$SIM" "$BUNDLE" 2>/dev/null | grep -oE '[0-9]+$')
  sleep "$settle"
  xcrun simctl io "$SIM" screenshot "$OUT/$name.png" >/dev/null 2>&1
  # A dead PID means the case CRASHED — that is a finding, not a bad screenshot. Check the
  # actual pid simctl handed back; `launchctl list` does not reliably list simulator apps
  # and reported every case as dead on the first run.
  if [ -z "$pid" ]; then
    echo "  $name  <-- launch returned no pid"
  elif ! xcrun simctl spawn "$SIM" kill -0 "$pid" 2>/dev/null; then
    echo "  $name  <-- CRASHED (pid $pid gone)"
  else
    echo "  $name"
  fi
}

echo "== game modes (mid-question) =="
for mode in classic timeAttack survival stake sweep pictureId thisOrThat closestCall \
            ordering matching typeAnswer oddOneOut ladder enumerate daily; do
  shot "mode-$mode" "TIDBITS_AUTOPLAY=$mode:mixed"
done

echo "== game modes (after answering — reveal + scoring) =="
for mode in classic stake pictureId thisOrThat closestCall ordering matching typeAnswer oddOneOut; do
  shot "reveal-$mode" "TIDBITS_AUTOPLAY=$mode:mixed" "TIDBITS_AUTOPILOT=1" \
       "TIDBITS_AUTOPILOT_STEPS=1" "TIDBITS_AUTOPILOT_CORRECT=1"
done

echo "== end-of-game results =="
for mode in classic survival sweep; do
  SETTLE=30 shot "results-$mode" "TIDBITS_AUTOPLAY=$mode:mixed" "TIDBITS_AUTOPILOT=1" \
       "TIDBITS_AUTOPILOT_CORRECT=1"
done

echo "== feature screens =="
shot home              "TIDBITS_TAB=play"
shot records           "TIDBITS_TAB=records" "TIDBITS_SEED_RECORDS=24"
shot create            "TIDBITS_TAB=create"
shot settings          "TIDBITS_SETTINGS=1"
shot profile           "TIDBITS_PROFILE=1"
shot customize         "TIDBITS_CUSTOMIZE=1"
shot daily-archive     "TIDBITS_DAILY_ARCHIVE=1"
shot night-setup       "TIDBITS_NIGHT_SETUP=1"
shot party             "TIDBITS_PARTY=1"
shot versus            "TIDBITS_VERSUS=1"
shot multiplayer       "TIDBITS_MULTIPLAYER=1"
shot paywall           "TIDBITS_PAYWALL=1"
shot club-hub          "TIDBITS_CLUB_HUB=1" "TIDBITS_CLUB=1"
shot story-archive     "TIDBITS_STORY_ARCHIVE=1" "TIDBITS_CLUB=1" "TIDBITS_SEED_RECORDS=24"
shot atlas             "TIDBITS_ATLAS=1" "TIDBITS_CLUB=1" "TIDBITS_SEED_RECORDS=24"
shot linkwall          "TIDBITS_LINKWALL=1" "TIDBITS_CLUB=1"
shot expedition-map    "TIDBITS_EXPEDITION_MAP=1" "TIDBITS_CLUB=1"
shot marathon          "TIDBITS_MARATHON=1" "TIDBITS_CLUB=1" "TIDBITS_MARATHON_LEN=5"
shot weakspot          "TIDBITS_AUTOPLAY=weakSpot:mixed" "TIDBITS_CLUB=1" "TIDBITS_SEED_RECORDS=24"
shot mix               "TIDBITS_MIX=1"

echo
echo "captured $(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ') PNGs → $OUT"
