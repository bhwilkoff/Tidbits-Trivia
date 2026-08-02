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
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -swift-version 6 \
  TidbitsTrivia/Core/Engine/SeededRNG.swift TidbitsTrivia/Core/Engine/DailyPick.swift \
  tools/daily-parity/apple_pick.swift -o /tmp/rc-apple >/dev/null 2>&1
/tmp/rc-apple /tmp/rc-ids.txt "$G/apple.txt"
cp js/engine.js /tmp/rc-engine.mjs
node tools/daily-parity/web_pick.mjs /tmp/rc-engine.mjs assets/corpus.json "$G/web.txt"
diff "$G/apple.txt" "$G/web.txt" >/dev/null && echo "   PASS: apple == web daily golden" \
  || { echo "   FAIL: apple != web"; exit 1; }
cp "$G/apple.txt" "$G/android.txt"   # identical algorithm+corpus; Android CI re-verifies

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
# Reporting is not a gate. This one FAILS, so a resync cannot land a question
# that should never ship.
python3 tools/corpus/quality_gate.py

echo "--- done. corpus + sqlite + golden + fixtures all resynced."
