#!/usr/bin/env bash
# Capture the iMessage App Store screenshots.
#
# This script USED to stop short: it staged a simulator and left the four shots to be
# taken by hand, because Messages cannot be automated — `simctl` has no tap primitive
# and XCUITest drives only your own app. The consequence was worse than the manual
# work: the extension was the one surface in this repo with no observable output, so a
# UI regression in it could not be seen by anything.
#
# The fix is the TidbitsMsgShots target, which hosts the extension's REAL view types
# (RoundViews.swift and friends, the same files, not copies) in a plain app that picks
# a screen from TIDBITS_MSG_SHOT. That is automatable, and a shot taken from it is the
# actual UI.
#
# What it deliberately does NOT do is composite fake Messages chrome around them. A
# screenshot that invented a transcript would be a picture of an app that does not
# exist, which is not something to put in front of App Review.
#
#   tools/capture-imessage-screenshots.sh [iphone|ipad|all]
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
BUNDLE=com.learningischange.tidbitstrivia.MsgShots
DERIVED="$ROOT/build/dd-msgshots"

fail() { echo "  ✗ $1"; FAILED=1; }
FAILED=0

# Exact ASC bucket sizes. A shot that is the wrong size is rejected at upload, and
# finding that out during submission is the expensive way to learn it.
verify() {  # verify <png> <w> <h>
  local f="$1" w="$2" h="$3"
  [ -f "$f" ] || { echo "     (no file)"; return 1; }
  local gw gh
  gw=$(sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/{print $2}')
  gh=$(sips -g pixelHeight "$f" 2>/dev/null | awk '/pixelHeight/{print $2}')
  [ "$gw" = "$w" ] && [ "$gh" = "$h" ] || { echo "     got ${gw}x${gh}, want ${w}x${h}"; return 1; }
  return 0
}

boot_only() {  # exactly one simulator at a time (CLAUDE.md: parallel boots wedge both)
  for s in $(xcrun simctl list devices booted -j \
      | python3 -c 'import json,sys; print(" ".join(d["udid"] for v in json.load(sys.stdin)["devices"].values() for d in v))'); do
    [ "$s" = "$1" ] || xcrun simctl shutdown "$s" >/dev/null 2>&1
  done
  xcrun simctl boot "$1" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$1" -b >/dev/null 2>&1 || true
}

build_install() {
  echo "  building…"
  # `|| true`: with `set -e` + `pipefail`, a grep that matches NOTHING exits 1 and
  # kills the script immediately after a SUCCESSFUL build — the failure mode is a
  # silent stop with "building…" as the last line.
  xcodebuild build -project TidbitsTrivia.xcodeproj -scheme TidbitsMsgShots \
    -destination "id=$1" -configuration Debug -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD FAILED" | head -5 || true
  local app
  app=$(find "$DERIVED/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name "TidbitsMsgShots.app" | head -1)
  [ -n "$app" ] || { echo "  ✗ no .app built"; exit 1; }
  xcrun simctl install "$1" "$app" >/dev/null 2>&1
}

shoot() {  # shoot <sim> <outdir> <NN-name> <shot-key> <w> <h> <settle>
  local sim="$1" out="$2" name="$3" shot="$4" w="$5" h="$6" settle="$7"
  xcrun simctl terminate "$sim" "$BUNDLE" >/dev/null 2>&1 || true
  env "SIMCTL_CHILD_TIDBITS_MSG_SHOT=$shot" \
    xcrun simctl launch "$sim" "$BUNDLE" >/dev/null 2>&1
  sleep "$settle"
  xcrun simctl io "$sim" screenshot --type=png "$out/$name.png" >/dev/null 2>&1
  if verify "$out/$name.png" "$w" "$h"; then echo "  ✓ $name"; else fail "$name"; fi
}

capture() {  # capture <sim> <outdir> <w> <h>
  local sim="$1" out="$2" w="$3" h="$4"
  mkdir -p "$out"; boot_only "$sim"; build_install "$sim"
  # Ordered as a story: what you send, what you answer, what you learn, who won.
  shoot "$sim" "$out" "01-send-a-round" start    "$w" "$h" 6
  shoot "$sim" "$out" "02-question"     question "$w" "$h" 5
  shoot "$sim" "$out" "03-reveal"       reveal   "$w" "$h" 5
  shoot "$sim" "$out" "04-results"      finish   "$w" "$h" 6
}

WHICH="${1:-all}"
IPHONE_SIM="${TIDBITS_SHOT_IPHONE_SIM:-E62E2523-C45C-4372-974F-D611E514F93F}"  # iPhone 17 Pro Max (6.9")
IPAD_SIM="${TIDBITS_SHOT_IPAD_SIM:-1BBB3CED-B88D-4210-B752-685693159288}"      # iPad Pro 13"

case "$WHICH" in
  iphone) echo "== iMessage · iPhone 6.9\" =="
          capture "$IPHONE_SIM" "$ROOT/branding/store-screenshots/imessage-iphone-6.9" 1320 2868 ;;
  ipad)   echo "== iMessage · iPad 13\" =="
          capture "$IPAD_SIM" "$ROOT/branding/store-screenshots/imessage-ipad-13" 2064 2752 ;;
  all)    echo "== iMessage · iPhone 6.9\" =="
          capture "$IPHONE_SIM" "$ROOT/branding/store-screenshots/imessage-iphone-6.9" 1320 2868
          echo "== iMessage · iPad 13\" =="
          capture "$IPAD_SIM" "$ROOT/branding/store-screenshots/imessage-ipad-13" 2064 2752 ;;
  *) echo "usage: $0 [iphone|ipad|all]" >&2; exit 2 ;;
esac

[ "$FAILED" = "0" ] || { echo; echo "SOME SHOTS FAILED — do not upload a partial set."; exit 1; }
echo
echo "Done. Upload under the version's iMessage App section in App Store Connect."
