#!/bin/zsh
# Resync every platform + the Daily golden after a corpus.json change (2026-07
# expansion). Run from anywhere. Keeps the lockstep rule: assets/corpus.json
# (web/Android/Windows via links) AND TidbitsTrivia/Resources/corpus.sqlite
# (Apple) hold identical questions, and the deterministic Daily golden matches.
set -e
cd "$(dirname "$0")/../.."
ROOT="$PWD"
G=tools/daily-parity/golden

echo "--- 1. regenerate Apple corpus.sqlite from assets/corpus.json"
python3 - <<'PY'
import json, sqlite3, os
rows = json.load(open('assets/corpus.json'))['questions']
p = 'TidbitsTrivia/Resources/corpus.sqlite'
if os.path.exists(p): os.remove(p)
c = sqlite3.connect(p)
c.execute("""CREATE TABLE questions (id TEXT PRIMARY KEY, prompt TEXT,
  option0 TEXT, option1 TEXT, option2 TEXT, option3 TEXT, correct_index INTEGER,
  category_id TEXT, difficulty INTEGER, explanation TEXT, source_title TEXT, source_url TEXT,
  template_id TEXT)""")
# template_id mirrors JSONQuestionSource.swift's convention: the id's first colon segment.
c.executemany("INSERT OR REPLACE INTO questions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
  [(q[0],q[1],q[2][0],q[2][1],q[2][2],q[2][3],q[3],q[4],q[5],q[6],q[7],q[8],q[0].split(':')[0]) for q in rows])
c.commit(); print('   corpus.sqlite:', c.execute('select count(*) from questions').fetchone()[0], 'rows'); c.close()
PY

echo "--- 2. sync corpus.json copies (iOS Resources, Android assets)"
cp assets/corpus.json TidbitsTrivia/Resources/corpus.json
cp assets/corpus.json android/app/src/main/assets/corpus.json

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

echo "--- done. corpus + sqlite + golden + fixtures all resynced."
