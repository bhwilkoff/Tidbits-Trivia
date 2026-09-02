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

echo "--- 2. sync the shape files (iOS Resources, Android assets)"
# corpus.json is deliberately NOT copied into either app bundle. Both clients
# read corpus.sqlite; the JSON is the web/build source only. Copying it in cost
# 51MB per bundle (Android was 125MB before it was removed) — and step 5 then
# reported the stray THIS step had just created, every single run. Remove any
# copy a previous run left behind.
rm -f TidbitsTrivia/Resources/corpus.json android/app/src/main/assets/corpus.json
rm -f android/app/src/main/assets/enrich.json

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

echo "--- 2b. assert corpus.json's version hash AND count match its content"
python3 - <<'PY2'
# The web client busts its IndexedDB cache on this string and nothing else, so a
# content change under an unchanged version never reaches a returning player.
# That is not hypothetical: 944cbad1, c8d110b7 and 38c80ba7 shipped 110,618 ->
# 110,541 -> 110,512 questions all under version f3c1477ed04a, because 29 of the
# fix_*.py repair tools copied the old string forward instead of recomputing it.
import hashlib, json, sys
d = json.load(open("assets/corpus.json"))
body = json.dumps(d["questions"], ensure_ascii=False, separators=(",", ":"))
want = hashlib.md5(body.encode()).hexdigest()[:12]
if d.get("count") != len(d["questions"]):
    print(f"   COUNT-STALE: corpus.json declares count={d.get('count')} but carries "
          f"{len(d['questions'])} questions.")
    print("   The same failure as VERSION-STALE, one field over: a repair tool")
    print("   recomputed the hash and forgot the count. The Android golden asserts")
    print("   'corpus parse is short' against this field, so it fails a build LATER")
    print("   than the commit that broke it. Set doc['count'] = len(questions).")
    sys.exit(1)
if d["version"] != want:
    print(f"   VERSION-STALE: corpus.json says {d['version']} but its content hashes to {want}.")
    print("   Whatever last wrote corpus.json kept the old version. Every web player")
    print("   who already cached the corpus would keep serving the rows you changed.")
    sys.exit(1)
print(f"   ok: version {want} matches content ({len(d['questions']):,} questions)")
PY2

echo "--- 2c. bump the service-worker CACHE (the web shell serves cache-first)"
python3 - <<'PY3'
# sw.js serves the shell CACHE-FIRST, so a changed assets/corpus.json is invisible
# to anyone who has ever loaded the site until `const CACHE` is bumped. The Pages
# deploy has a guard for exactly this and it failed six pushes in a row while the
# corpus was being culled, because the bump is a separate manual act nobody
# remembers. Resync changes corpus.json, so resync bumps the cache.
import pathlib, re, subprocess
p = pathlib.Path("sw.js")
s = p.read_text()
m = re.search(r"const CACHE = 'tidbits-v(\d+)';", s)
if not m:
    print("   sw.js has no 'const CACHE = tidbits-vN' — not bumping"); raise SystemExit(0)
# Only bump when corpus.json actually differs from HEAD, so a no-op resync is a no-op.
changed = subprocess.run(["git", "diff", "--quiet", "HEAD", "--", "assets/corpus.json"]).returncode != 0
if not changed:
    print(f"   corpus.json unchanged — CACHE stays {m.group(0)[14:-2]}"); raise SystemExit(0)
n = int(m.group(1)) + 1
p.write_text(s.replace(m.group(0), f"const CACHE = 'tidbits-v{n}';"))
print(f"   corpus.json changed -> CACHE bumped to tidbits-v{n}")
PY3

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
