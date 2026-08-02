#!/usr/bin/env bash
# Create-parity — does the SAME topic return the SAME questions on Apple and web?
#
#   tools/create/parity.sh [topics-file]        (default: tools/create/parity-topics.txt)
#
# The four engines are unit-tested against the same cases, but nothing compared
# what they ACTUALLY select for a real topic over the real 128k-row corpus until
# this existed — and "the same topic returns the same quiz everywhere" is the
# six-platform contract, not a unit-test property. It found one real divergence
# immediately: Swift's sort is not stable and JavaScript's is, so rows tied on
# score came out in different orders, and the per-category cap in `diversify`
# then kept a different SET.
#
# Compares the corpus ranker alone (TIDBITS_CREATE_SWEEP_SEARCH_ONLY) because the
# shape sets reuse corpus IDs — `src:describe:K._R._Narayanan` is both a corpus
# row and a picture row, so a mixed diff cannot tell which source a question came
# from. Order is not compared: `diversify` shuffles on purpose so a quiz does not
# march category-by-category. Membership is the contract.
set -euo pipefail
cd "$(dirname "$0")/../.."

# --regenerate rewrites tools/create/golden/search.txt from the Apple capture.
# The README documented this flag; the script never implemented it, so the flag
# was read as the TOPICS filename and node tried to open "--regenerate". Nobody
# noticed because nothing regenerated the golden until a corpus change made it
# stale and the Windows CreateGoldenTest went red.
REGEN=0
ARGS=()
for a in "$@"; do
  if [ "$a" = "--regenerate" ]; then REGEN=1; else ARGS+=("$a"); fi
done
TOPICS="${ARGS[0]:-tools/create/parity-topics.txt}"
DEV="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
SIM="${TIDBITS_SIM:-iPhone 17 Pro}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "--- web: running the real js/api.js Corpus.search"
# The repo has no package.json, so node parses .js as CommonJS — copy to .mjs and
# rewrite the relative imports, the same trick tools/daily-parity/run.sh uses.
mkdir -p "$WORK/webmod"
cp js/*.js "$WORK/webmod/"
for f in "$WORK"/webmod/*.js; do mv "$f" "${f%.js}.mjs"; done
python3 - "$WORK/webmod" <<'PY'
import pathlib, re, sys
for p in pathlib.Path(sys.argv[1]).glob("*.mjs"):
    p.write_text(re.sub(r"(from\s+'\./[A-Za-z0-9_-]+)\.js'", r"\1.mjs'", p.read_text()))
PY
node tools/create/web_search.mjs "$WORK/webmod/api.mjs" assets/corpus.json "$TOPICS" > "$WORK/web.txt"

echo "--- apple: running the shipped ranker on the $SIM simulator"
UDID="$(DEVELOPER_DIR=$DEV xcrun simctl list devices available \
        | grep -F "$SIM (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[ -n "$UDID" ] || { echo "FAIL: no booted-capable '$SIM'"; exit 1; }
DEVELOPER_DIR=$DEV xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || \
  DEVELOPER_DIR=$DEV xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
DEVELOPER_DIR=$DEV xcrun simctl terminate "$UDID" com.learningischange.tidbitstrivia 2>/dev/null || true
SIMCTL_CHILD_TIDBITS_CREATE_SWEEP="$(cd "$(dirname "$TOPICS")" && pwd)/$(basename "$TOPICS")" \
SIMCTL_CHILD_TIDBITS_CREATE_SWEEP_CORPUS_ONLY=1 \
SIMCTL_CHILD_TIDBITS_CREATE_SWEEP_SEARCH_ONLY=1 \
DEVELOPER_DIR=$DEV xcrun simctl launch --console-pty "$UDID" \
  com.learningischange.tidbitstrivia > "$WORK/apple.out" 2>&1 &
SWEEP=$!
for _ in $(seq 1 120); do grep -q "SWEEP-END" "$WORK/apple.out" 2>/dev/null && break; sleep 2; done
kill $SWEEP 2>/dev/null || true
tr -d '\r' < "$WORK/apple.out" | awk -F'\t' '/SWEEP-Q/{a[$2]=a[$2]" "$3} END{for(t in a) print t"\t"a[t]}' \
  > "$WORK/apple.txt"

if [ "$REGEN" = "1" ]; then
  echo "--- regenerating tools/create/golden/search.txt from the Apple capture"
  python3 - "$WORK/apple.txt" "$TOPICS" <<'PYGOLD'
import pathlib, sys
caught = {}
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    if "\t" not in line:
        continue
    t, ids = line.split("\t", 1)
    caught[t.strip()] = sorted({i for i in ids.split() if i})
# Topics that correctly return NOTHING stay in the file on purpose: a golden
# listing only the topics with results would pass a regression that answered
# "Harry Kane" with Spokane again.
topics = [t.strip() for t in pathlib.Path(sys.argv[2]).read_text().splitlines() if t.strip()]
out = pathlib.Path("tools/create/golden/search.txt")
out.write_text("".join(f"{t}\t{' '.join(caught.get(t, []))}\n" for t in topics))
empty = sum(1 for t in topics if not caught.get(t))
print(f"    wrote {len(topics)} topics ({empty} correctly empty)")
PYGOLD
fi

python3 - "$WORK/web.txt" "$WORK/apple.txt" <<'PY'
import pathlib, sys
def load(p):
    d = {}
    for line in pathlib.Path(p).read_text().splitlines():
        if "\t" not in line:
            continue
        t, ids = line.split("\t", 1)
        d[t.strip()] = {i for i in ids.split() if i}
    return d
web, apple = load(sys.argv[1]), load(sys.argv[2])
bad = 0
for t in sorted(set(web) | set(apple)):
    w, a = web.get(t, set()), apple.get(t, set())
    if w != a:
        bad += 1
        print(f"DIFFER  {t}\n    web only:   {sorted(w - a)}\n    apple only: {sorted(a - w)}")
print(f"\n{len(set(web) | set(apple)) - bad} identical, {bad} differing")
sys.exit(1 if bad else 0)
PY
