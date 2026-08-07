#!/usr/bin/env bash
# Run the Android release build through Firebase Test Lab Robo on REAL devices.
#
# This is the replacement for Play's Pre-launch report, which never generated for this
# app on either the internal or the closed track. It is the same engine underneath, it
# just takes a CLI, and it works on the free Spark tier.
#
# Why it is not optional (Decision 055): an emulator and a Test Lab VIRTUAL device have
# no Play Store, so they cannot see Play Billing, Play Integrity, Play Games, or a vendor
# OS skin. Version codes 75 and 85 were both rejected for "the app opens, but it keeps
# crashing" and both passed every local test; a single Robo run on a physical Galaxy A03s
# produced the actual stack in four minutes.
#
#   tools/testlab-android.sh              # default matrix (physical only)
#   tools/testlab-android.sh --quick      # one device, for a re-verify after a fix
#   tools/testlab-android.sh --apk path   # skip the build, test an existing APK
#
# Free-tier quota is a handful of PHYSICAL device-tests per day and the matrix is
# rejected wholesale when it would exceed it (TEST_QUOTA_EXCEEDED) — so --quick exists
# to leave headroom for the verify run after a fix.
set -euo pipefail

PROJECT="tidbits-trivia-f2ddb"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK=""
QUICK=0

while [ $# -gt 0 ]; do
    case "$1" in
        --quick) QUICK=1; shift ;;
        --apk)   APK="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# Low-RAM, Play-Store-bearing, and spread across the OS versions review actually uses.
# a03su is first on purpose: it is the device that caught Decision 055.
DEVICES=(
    "model=a03su,version=33,locale=en,orientation=portrait"        # Galaxy A03s — low RAM
    "model=OP535DL1,version=34,locale=en,orientation=portrait"     # OnePlus Nord CE 2 Lite
    "model=a05s,version=35,locale=en,orientation=portrait"         # Galaxy A05s
)
[ "$QUICK" = 1 ] && DEVICES=("${DEVICES[0]}")

if [ -z "$APK" ]; then
    echo "==> building release APK"
    export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
    (cd "$ROOT/android" && ./gradlew :app:assembleRelease --no-daemon -q)
    APK="$ROOT/android/app/build/outputs/apk/release/app-release.apk"
fi
echo "==> testing $APK ($(du -h "$APK" | cut -f1))"

ARGS=()
for d in "${DEVICES[@]}"; do ARGS+=(--device "$d"); done

# Robo drives the UI itself, so no test APK is needed. `|| true` because a crashing
# device is a FAILED matrix and a non-zero exit — which is the result we came for, not
# an error in this script.
set +e
gcloud firebase test android run \
    --type robo \
    --app "$APK" \
    "${ARGS[@]}" \
    --timeout 5m \
    --project "$PROJECT" 2>&1 | tr '\r' '\n' | grep -vE "Test matrix status"
STATUS=${PIPESTATUS[0]}
set -e

cat <<'NOTE'

--------------------------------------------------------------------------------
A row reading "Application crashed" has its stack waiting in the GCS bucket printed
above, NOT in this output:

  gcloud storage ls   "gs://<bucket>/<run>/<device>/"
  gcloud storage cp   "gs://<bucket>/<run>/<device>/data_app_crash_0_com_tidbitstrivia_app.txt" .

"Infrastructure failure" and "Test failed to run" are Test Lab's own flake — confirm
by checking the device logcat for our package before treating either as a real defect.
--------------------------------------------------------------------------------
NOTE
exit $STATUS
