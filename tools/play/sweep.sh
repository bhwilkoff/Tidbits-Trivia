#!/usr/bin/env bash
# Play N real games on the simulator and capture every delivered question.
#
#   tools/play/sweep.sh [games] [out.jsonl]      (default: 1000, /tmp play.jsonl)
#
# The corpus can be audited from a script; a ROUND cannot. What decides whether a
# game is enjoyable — whether the distractors are guessable, whether the mode kept
# its shape, whether the round even filled — is a property of the assembled round,
# produced by the bundled database, the shape sources, the seen-set and the mode's
# own rules acting together. That only exists inside the app, so this drives the
# app and reads the result back out.
set -euo pipefail
cd "$(dirname "$0")/../.."

GAMES="${1:-1000}"
OUT="${2:-$PWD/tools/play/play.jsonl}"
DEV="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
SIM="${TIDBITS_SIM:-iPhone 17 Pro}"
BUNDLE=com.learningischange.tidbitstrivia

UDID="$(DEVELOPER_DIR=$DEV xcrun simctl list devices available \
        | grep -F "$SIM (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[ -n "$UDID" ] || { echo "FAIL: no available simulator named '$SIM'"; exit 1; }

DEVELOPER_DIR=$DEV xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || \
  DEVELOPER_DIR=$DEV xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
DEVELOPER_DIR=$DEV xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true

echo "--- playing $GAMES games on $SIM"
# Kept, not mktemp'd: when a sweep comes back empty the raw console log is the
# only evidence of why, and a trap that deletes it leaves nothing to read.
RAW="${OUT%.jsonl}.raw.log"

# The sweep marks questions seen as it goes (a real player's pool depletes), and
# that set persists in UserDefaults across launches — so a second sweep on the
# same simulator measures a half-exhausted corpus, not a fresh install. Uninstall
# first so every run starts where a new player does.
DEVELOPER_DIR=$DEV xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
APP="$(find ~/Library/Developer/Xcode/DerivedData -name 'TidbitsTrivia.app' \
        -path '*Debug-iphonesimulator*' -print -quit 2>/dev/null || true)"
[ -n "$APP" ] || { echo "FAIL: no built TidbitsTrivia.app — build for the simulator first"; exit 1; }
DEVELOPER_DIR=$DEV xcrun simctl install "$UDID" "$APP"

export SIMCTL_CHILD_TIDBITS_PLAY_SWEEP="$GAMES"
export SIMCTL_CHILD_TIDBITS_SKIP_ONBOARD=1
export SIMCTL_CHILD_TIDBITS_NO_GAMECENTER=1
# `[ ... ] && export ...` would return 1 when the test fails, which under
# `set -e` exits the script — an if is the only safe shape here.
if [ -n "${TIDBITS_PLAY_SWEEP_MODES:-}" ]; then
  export SIMCTL_CHILD_TIDBITS_PLAY_SWEEP_MODES="$TIDBITS_PLAY_SWEEP_MODES"
fi
if [ -n "${TIDBITS_PLAY_SWEEP_CATS:-}" ]; then
  export SIMCTL_CHILD_TIDBITS_PLAY_SWEEP_CATS="$TIDBITS_PLAY_SWEEP_CATS"
fi

DEVELOPER_DIR=$DEV xcrun simctl launch --console-pty "$UDID" "$BUNDLE" > "$RAW" 2>&1 &
PID=$!

# --console-pty emits CRLF; strip it or every JSON line ends in a stray \r.
for _ in $(seq 1 900); do
  grep -q "PLAY-END" "$RAW" 2>/dev/null && break
  kill -0 $PID 2>/dev/null || break
  sleep 2
done
kill $PID 2>/dev/null || true

tr -d '\r' < "$RAW" > "$OUT"
if ! grep -q "PLAY-END" "$OUT"; then
  echo "WARNING: no PLAY-END — the sweep did not finish (truncated capture)" >&2
fi
echo "--- wrote $(grep -c 'PLAY-Q' "$OUT" || true) questions to $OUT"
python3 tools/play/audit.py "$OUT"
