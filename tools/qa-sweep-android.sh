#!/usr/bin/env bash
# qa-sweep-android.sh — the Android half of the QA sweep (tools/qa-sweep.sh is Apple).
#
#   tools/qa-sweep-android.sh [outdir]
#
# Separate script rather than a branch in qa-sweep.sh because almost nothing is shared:
# Android drives ScreenshotHooks through DEBUG-only *intent extras* (--es/--ez/--ei), not
# SIMCTL_CHILD_ env vars, and reads crashes from logcat rather than a .ips report.
#
# Android's hook set is smaller than Apple's — autoplay, tabs, party, night setup — so this
# covers the game modes and the main tabs. The Club/dialog surfaces have no hooks yet and
# are NOT swept here; that gap is real and recorded in docs/QA-SWEEP-LOG.md rather than
# quietly presented as coverage.
set -uo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-/tmp/tidbits-qa/android}"
mkdir -p "$OUT"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"
"$ADB" get-state >/dev/null 2>&1 || { echo "no device/emulator attached"; exit 1; }

# ScreenshotHooks are DEBUG-only, and the debug build carries applicationIdSuffix ".debug",
# so the installed package is NOT the release id. Resolve it from the device instead of
# hardcoding: an early version used the release id, every `am start` failed with a bare
# "Error type 3", and because a failed launch is not a crash the sweep cheerfully reported
# 28 healthy screens that were all the launcher.
PKG=$("$ADB" shell pm list packages 2>/dev/null | sed 's/^package://' | tr -d '\r' \
      | grep -E '^com\.tidbitstrivia\.app(\.debug)?$' | sort -r | head -1)
[ -n "$PKG" ] || { echo "Tidbits is not installed on the device"; exit 1; }
ACT="$PKG/com.learningischange.tidbitstrivia.MainActivity"
echo "package: $PKG"

# name, then extras already formatted for `am start`.
shot() {
  local name="$1"; shift
  local settle="${SETTLE:-8}"
  "$ADB" shell am force-stop "$PKG" >/dev/null 2>&1
  "$ADB" logcat -c >/dev/null 2>&1
  "$ADB" shell am start -n "$ACT" --ez tidbits_skip_onboard true "$@" >/dev/null 2>&1
  sleep "$settle"
  "$ADB" exec-out screencap -p > "$OUT/$name.png" 2>/dev/null
  # Assert the captured screen actually BELONGS to the app. Checking only for a logcat
  # crash validates the wrong thing: a launch that never started (wrong package, missing
  # activity) leaves the launcher on screen and logs no exception at all.
  local focus
  focus=$("$ADB" shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus)
  if ! printf '%s' "$focus" | grep -q "$PKG"; then
    echo "  $name  <-- NOT FOREGROUND ($(printf '%s' "$focus" | sed -E 's/.*u0 ([^ }]*).*/\1/'))"
  elif "$ADB" logcat -d 2>/dev/null | grep -q "FATAL EXCEPTION"; then
    echo "  $name  <-- CRASHED"
    "$ADB" logcat -d 2>/dev/null | grep -A 6 "FATAL EXCEPTION" | head -8 | sed 's/^/      /'
  else
    echo "  $name"
  fi
}

echo "== game modes (mid-question) =="
for mode in classic timeAttack survival stake sweep pictureId thisOrThat closestCall \
            ordering matching typeAnswer oddOneOut ladder enumerate daily; do
  shot "mode-$mode" --es tidbits_autoplay "$mode:mixed"
done

echo "== reveal (answered once) =="
for mode in classic stake closestCall ordering matching typeAnswer; do
  shot "reveal-$mode" --es tidbits_autoplay "$mode:mixed" \
       --ez tidbits_autopilot true --ei tidbits_autopilot_steps 1 --ez tidbits_autopilot_correct true
done

echo "== end of game =="
for mode in classic sweep; do
  SETTLE=32 shot "results-$mode" --es tidbits_autoplay "$mode:mixed" \
       --ez tidbits_autopilot true --ez tidbits_autopilot_correct true
done

echo "== tabs + surfaces with hooks =="
shot home        --es tidbits_tab play
shot records     --es tidbits_tab records --ei tidbits_seed_records 24
shot create      --es tidbits_tab create
shot party       --ez tidbits_party true
shot night-setup --ez tidbits_night_setup true

echo
echo "captured $(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ') PNGs → $OUT"
