#!/usr/bin/env bash
# Play N games THROUGH THE REAL VIEWS and photograph every screen.
#
#   tools/play/marathon.sh [games] [outdir] [autopilot-delay]
#
# The engine sweep (TIDBITS_PLAYTHROUGH) finishes a thousand games in minutes
# because it renders nothing — it proves the rules, and it is blind to a blank
# panel, a clipped option, a reveal that never drew. Every content bug found by
# LOOKING this session ("founded or created", the Business round with no
# business in it, an era that eliminates three options) was invisible to it.
#
# This is the other thing. The app plays game after game in one session through
# GamePlayView and ResultsView at the autopilot's real pace, this script
# photographs the screen continuously, and every frame goes through
# screen_audit.py. A thousand games takes hours; that is what it costs to
# actually watch them.
#
# Frames are audited as they are taken and then DISCARDED unless flagged or
# sampled — 6 hours of capture is tens of thousands of PNGs and several
# gigabytes, and keeping the boring ones buys nothing.
set -uo pipefail
cd "$(dirname "$0")/../.."

GAMES="${1:-1008}"
OUT="${2:-$PWD/tools/play/marathon}"
DELAY="${3:-0.7}"
SAMPLE_EVERY="${SAMPLE_EVERY:-60}"      # keep one boring frame in N as evidence
DEV="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
SIM="${TIDBITS_SIM:-iPhone 17 Pro}"
BUNDLE=com.learningischange.tidbitstrivia

mkdir -p "$OUT/flagged" "$OUT/sample"
LOG="$OUT/frames.jsonl"
CONSOLE="$OUT/console.log"
: > "$LOG"

UDID="$(DEVELOPER_DIR=$DEV xcrun simctl list devices available \
        | grep -F "$SIM (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[ -n "$UDID" ] || { echo "FAIL: no available simulator named '$SIM'"; exit 1; }
DEVELOPER_DIR=$DEV xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || \
  DEVELOPER_DIR=$DEV xcrun simctl boot "$UDID" >/dev/null 2>&1 || true

APP="$(find ~/Library/Developer/Xcode/DerivedData -name 'TidbitsTrivia.app' \
        -path '*Debug-iphonesimulator*' -print -quit 2>/dev/null || true)"
[ -n "$APP" ] || { echo "FAIL: no built TidbitsTrivia.app"; exit 1; }

# A rendered pass is only evidence about the corpus INSIDE the bundle. On
# 2026-08-01 a run "confirmed" a reveal defect that had been repaired 90 minutes
# earlier: the bundle still carried the pre-repair sqlite, so the screenshots
# were arguing about old data. Refuse to run rather than read the wrong corpus
# confidently.
# An unresolvable mode name is a typo, not a filter. Fail before spending 20
# minutes rendering the wrong three modes.
if [ -n "${TIDBITS_PLAY_SWEEP_MODES:-}" ]; then
  _known="classic,timeAttack,survival,stake,sweep,pictureId,thisOrThat,closestCall,ordering,matching,typeAnswer,oddOneOut,ladder,enumerate"
  for _m in $(echo "$TIDBITS_PLAY_SWEEP_MODES" | tr ',' ' '); do
    case ",$_known," in
      *",$_m,"*) ;;
      *) echo "FAIL: unknown mode '$_m'. Known: $_known" >&2; exit 2 ;;
    esac
  done
fi

# Compare CONTENT, not timestamps. The first version compared mtimes, and a
# `git rebase` — which rewrites every checked-out file — made it refuse a
# perfectly fresh bundle. A guard that cries wolf is one people learn to work
# around, which is worse than not having it.
if [ -f "$APP/corpus.json" ] \
   && [ "$(shasum -a 256 "$APP/corpus.json" | cut -d' ' -f1)" \
        != "$(shasum -a 256 assets/corpus.json | cut -d' ' -f1)" ]; then
  echo "FAIL: stale bundle — the app's corpus.json differs from assets/corpus.json." >&2
  echo "      Rebuild and reinstall; otherwise these frames show a different corpus." >&2
  exit 2
fi
DEVELOPER_DIR=$DEV xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
DEVELOPER_DIR=$DEV xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
DEVELOPER_DIR=$DEV xcrun simctl install "$UDID" "$APP"

echo "--- $GAMES games through the real views, ${DELAY}s per step, shots -> $OUT"
export SIMCTL_CHILD_TIDBITS_MARATHON_GAMES="$GAMES"
export SIMCTL_CHILD_TIDBITS_AUTOPILOT=1
export SIMCTL_CHILD_TIDBITS_AUTOPILOT_CORRECT=1
export SIMCTL_CHILD_TIDBITS_AUTOPILOT_DELAY="$DELAY"
export SIMCTL_CHILD_TIDBITS_SKIP_ONBOARD=1
export SIMCTL_CHILD_TIDBITS_NO_GAMECENTER=1
# The marathon walks DebugHooks.playSweepModes, so restricting it means passing
# the restriction THROUGH to the app — setting it only in this shell walked the
# full fourteen and quietly ignored the request.
if [ -n "${TIDBITS_PLAY_SWEEP_MODES:-}" ]; then
  export SIMCTL_CHILD_TIDBITS_PLAY_SWEEP_MODES="$TIDBITS_PLAY_SWEEP_MODES"
fi
if [ -n "${TIDBITS_PLAY_SWEEP_CATS:-}" ]; then
  export SIMCTL_CHILD_TIDBITS_PLAY_SWEEP_CATS="$TIDBITS_PLAY_SWEEP_CATS"
fi
DEVELOPER_DIR=$DEV xcrun simctl launch --console-pty "$UDID" "$BUNDLE" > "$CONSOLE" 2>&1 &
APP_PID=$!

frame=0
flagged=0
shot="$OUT/.current.png"
while kill -0 $APP_PID 2>/dev/null; do
  played=$(tr -d '\r' < "$CONSOLE" 2>/dev/null | grep -c 'MARATHON-GAME' || true)
  played=${played:-0}
  [ "$played" -ge "$GAMES" ] && break
  if DEVELOPER_DIR=$DEV xcrun simctl io "$UDID" screenshot "$shot" >/dev/null 2>&1; then
    frame=$((frame + 1))
    line=$(python3 tools/play/screen_audit.py "$shot" --json 2>/dev/null | head -1)
    if [ -n "$line" ]; then
      echo "$line" | python3 -c "
import json,sys,os
d=json.loads(sys.stdin.read()); d['frame']=$frame; d['game']=$played
open('$LOG','a').write(json.dumps(d)+'\n')
sys.exit(1 if d.get('flags') else 0)" && keep=0 || keep=1
      if [ "$keep" = "1" ]; then
        flagged=$((flagged + 1))
        cp "$shot" "$OUT/flagged/f${frame}-g${played}.png"
      elif [ $((frame % SAMPLE_EVERY)) -eq 0 ]; then
        cp "$shot" "$OUT/sample/s${frame}-g${played}.png"
      fi
    fi
  fi
  if [ $((frame % 200)) -eq 0 ]; then
    echo "   frame $frame · game $played/$GAMES · flagged $flagged"
  fi
done

kill $APP_PID 2>/dev/null || true
rm -f "$shot"
played=$(tr -d '\r' < "$CONSOLE" | grep -c 'MARATHON-GAME' || true)
played=${played:-0}
echo "--- done: $played games rendered, $frame frames audited, $flagged flagged"
echo "--- flagged screens in $OUT/flagged, samples in $OUT/sample, per-frame log $LOG"
