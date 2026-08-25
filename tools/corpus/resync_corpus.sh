#!/bin/zsh
# Resync every platform + the Daily golden after a corpus.json change (2026-07
# expansion). Run from anywhere. Keeps the lockstep rule: assets/corpus.json
# (web/Android/Windows via links) AND TidbitsTrivia/Resources/corpus.sqlite
# (Apple) hold identical questions, and the deterministic Daily golden matches.
set -e
cd "$(dirname "$0")/../.."
ROOT="$PWD"
G=tools/daily-parity/golden

echo "--- 1. regenerate corpus.sqlite (Apple + Android) from assets/corpus.json"
python3 - <<'PY'
import json, sys, sqlite3
sys.path.insert(0, 'tools/corpus/sources')
import build_corpus                     # the ONE sqlite writer (schema + folding)
rows = json.load(open('assets/corpus.json'))['questions']
for p in ('TidbitsTrivia/Resources/corpus.sqlite',
          'android/app/src/main/assets/corpus.sqlite'):
    build_corpus.write_sqlite(rows, p)
    c = sqlite3.connect(p)
    n = c.execute('select count(*) from questions').fetchone()[0]
    f = c.execute("select count(*) from questions where search_text != ''").fetchone()[0]
    print(f'   {p}: {n} rows ({f} with a folded search_text)'); c.close()
PY

echo "--- 2. sync corpus.json copies (iOS Resources, Android assets)"
cp assets/corpus.json TidbitsTrivia/Resources/corpus.json
cp assets/corpus.json android/app/src/main/assets/corpus.json

# ...and every shape source. This step used to copy corpus.json alone, so any
# repair that touched oddoneout.json / match.json / picture.json left the Apple
# and Android mirrors behind. Step 5 reported the drift and step 2 never fixed
# it, which makes the check a tripwire rather than a pipeline. Copy what the
# check asserts.
for f in oddoneout match order thisorthat picture typeanswer closest enumerate difficulty; do
  [ -f "assets/$f.json" ] || continue
  cp "assets/$f.json" "TidbitsTrivia/Resources/$f.json"
  cp "assets/$f.json" "android/app/src/main/assets/$f.json"
done
[ -f assets/enrich.json ] && cp assets/enrich.json android/app/src/main/assets/enrich.json

echo "--- 3. regenerate Daily golden (Apple swiftc + web node) and verify parity"
sqlite3 TidbitsTrivia/Resources/corpus.sqlite "SELECT id FROM questions" > /tmp/rc-ids.txt
# v2 (Decision 050) balances across categories, so the picker needs each id's
# category as well. Same ORDER BY id, so every engine walks the same list.
sqlite3 -separator $'\t' TidbitsTrivia/Resources/corpus.sqlite \
  "SELECT id, category_id FROM questions" > /tmp/rc-cats.tsv
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -swift-version 6 \
  TidbitsTrivia/Core/Engine/SeededRNG.swift TidbitsTrivia/Core/Engine/DailyPick.swift \
  tools/daily-parity/apple_pick.swift -o /tmp/rc-apple >/dev/null 2>&1
/tmp/rc-apple /tmp/rc-ids.txt "$G/apple.txt" /tmp/rc-cats.tsv
cp js/engine.js /tmp/rc-engine.mjs
node tools/daily-parity/web_pick.mjs /tmp/rc-engine.mjs assets/corpus.json "$G/web.txt"
diff "$G/apple.txt" "$G/web.txt" >/dev/null && echo "   PASS: apple == web daily golden" \
  || { echo "   FAIL: apple != web"; exit 1; }
# NOT a blanket copy any more: the Android golden is written by a real Gradle
# unit test (DailyParityTest), and overwriting it here would hide a Kotlin mirror
# that had silently stopped matching — which is exactly what the v2 rollout
# caught. Copy only when Android has never run.
[ -s "$G/android.txt" ] || cp "$G/apple.txt" "$G/android.txt"

echo "--- 4. refresh Windows test fixtures"
python3 -c "import json; open('windows/Tidbits.HeadlessTests/Fixtures/corpus-ids.txt','w').write('\n'.join(q[0] for q in json.load(open('assets/corpus.json'))['questions'])+'\n')"
cp "$G/apple.txt" windows/Tidbits.HeadlessTests/Fixtures/daily-golden.txt

echo "--- 5. assert every question file is identical across platforms"
# Not assumed — asserted. The three copies silently drifted on 2026-08-01 when a
# generator invoked with --out to a temp path wrote its mirrors anyway, and the
# app, the tests and 126 playthroughs all stayed green because each was reading a
# different one of them.
python3 tools/corpus/check_mirrors.py

echo "--- 6. question quality gate"
# Two rules read the 150 MB gitignored source database, so on a CI checkout they
# saw nothing and passed. Export the ~1 MB of facts they actually need first, or
# the gate is weaker in the one place it runs on every push than it is here.
python3 tools/corpus/export_subject_facts.py
# Reporting is not a gate. This one FAILS, so a resync cannot land a question
# that should never ship.
python3 tools/corpus/quality_gate.py

# A corpus change can starve a Create suggestion that worked when it was chosen.
# "Space exploration" was the first chip on five platforms and returned ONE
# question, about robotics.
# A rule that cannot see its own planted defect protects nothing. KIND-MISMATCH
# read 0 for a session while looking at a free question.
echo "--- 6b. every gate rule can still see the defect it names"
python3 tools/corpus/test_quality_gate.py | tail -3

# Derived, web-only: the play path fetches ONE ~200 KB shard instead of the whole
# 13 MB corpus. Stale shards would serve deleted questions, so they are rebuilt
# with everything else.
echo "--- 6c. rebuild the web shards"
python3 tools/corpus/build_web_shards.py | tail -2

echo "--- 7. the topics the app SUGGESTS still return a playable quiz"
tools/create/check_suggestions.sh

echo "--- done. corpus + sqlite + golden + fixtures all resynced."
echo "REMINDER: assets/corpus.json is a SHELL precache file — bump 'const CACHE'"
echo "in sw.js in the SAME commit, or the Pages deploy guard will refuse it."
