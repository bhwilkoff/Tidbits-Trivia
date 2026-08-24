#!/usr/bin/env bash
# Capture the Apple TV screen and REFUSE to return a frame the OCR cannot read.
# Ported from Archive Watch (instrument-honesty rules, docs/TVOS-TEST-PLAYBOOK.md §2):
# a sweep that returns "not found" is worthless if the frames were blank — a null
# result from a blind instrument is indistinguishable from a real absence.
#
# Usage: bash tools/atv_see.sh <out.png> [min_bytes]   -> exits 1 blind, 2 wrong screen
#   TB_ATV     device name/UDID for devicectl   (default: Ben Bedroom)
#   TB_EXPECT  regex the app's own UI must show; "-" to skip (default: Tidbits home chrome)
set -uo pipefail
OUT="${1:?usage: atv_see.sh <out.png> [min_bytes]}"
MIN="${2:-400000}"
DEV="${TB_ATV:-Ben Bedroom}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}" \
  xcrun devicectl device capture screenshot --device "$DEV" --destination "$OUT" >/dev/null 2>&1
sz=$(stat -f%z "$OUT" 2>/dev/null || echo 0)
if [ "$sz" -lt "$MIN" ]; then
  # ~108 KB EXACTLY, repeatedly, while process launch reports "Launched", means
  # the Apple TV is awake and rendering to a display that is OFF (television off
  # or on another input — pyatv turn_on only sends CEC, which the set may ignore).
  # Distinguish from a sleeping Apple TV, where the LAUNCH itself fails with
  # CoreDeviceError 10002. Launch works + capture black = go turn the TV on.
  echo "BLIND: $OUT is ${sz}B (<${MIN}B)" >&2
  echo "  if launch SUCCEEDS but capture is black, the television is off/on another input" >&2
  exit 1
fi
if [ -x /tmp/tbocr ]; then
  txt=$(/tmp/tbocr "$OUT" 2>/dev/null)
  n=$(printf '%s' "$txt" | tr -cd '"' | wc -c)
  [ "$n" -lt 8 ] && { echo "BLIND: $OUT has no readable text" >&2; exit 1; }
  # A READABLE frame of the WRONG APP is worse than a blank one — it survives
  # every check and answers questions about a screen we are not testing (Archive
  # Watch once graded the tvOS HOME SCREEN and reported app shelves missing).
  EXPECT="${TB_EXPECT:-Tidbits|Surprise me|Customize|Start a night|Join a game|Quick Match|Records|Settings|Daily}"
  if [ "$EXPECT" != "-" ] && ! printf '%s' "$txt" | grep -qiE "$EXPECT"; then
    if printf '%s' "$txt" | grep -qiE "prime video|pluto|fubo|Apple TV\+|Select up for full screen"; then
      echo "WRONG SCREEN: $OUT is the tvOS home screen, not Tidbits" >&2
    else
      echo "WRONG SCREEN: $OUT does not match TB_EXPECT ($EXPECT)" >&2
    fi
    exit 2
  fi
fi
exit 0
