#!/bin/zsh
# Daily-parity golden (Decision 037): prove the Swift, Kotlin, and JS Daily
# pickers produce IDENTICAL sets from each platform's own bundled corpus.
# Run after ANY change to the daily rank/pick, corpus regen, or engine mirror.
set -e
cd "$(dirname "$0")/../.."
G=tools/daily-parity/golden

echo "--- apple (DailyPick.swift against corpus.sqlite ids)"
sqlite3 TidbitsTrivia/Resources/corpus.sqlite "SELECT id FROM questions" > /tmp/daily-parity-ids.txt
# v2 (Decision 050) balances across categories, so the pickers need each id's
# category as well. Same ORDER BY id, so every engine walks the same list.
sqlite3 -separator $'\t' TidbitsTrivia/Resources/corpus.sqlite \
  "SELECT id, category_id FROM questions" > /tmp/daily-parity-cats.tsv
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -swift-version 6 \
  TidbitsTrivia/Core/Engine/SeededRNG.swift \
  TidbitsTrivia/Core/Engine/DailyPick.swift \
  tools/daily-parity/apple_pick.swift \
  -o /tmp/daily-parity-apple
/tmp/daily-parity-apple /tmp/daily-parity-ids.txt "$G/apple.txt" /tmp/daily-parity-cats.tsv

echo "--- web (engine.js pickDaily against assets/corpus.json)"
cp js/engine.js /tmp/tidbits-engine-copy.mjs
node tools/daily-parity/web_pick.mjs /tmp/tidbits-engine-copy.mjs assets/corpus.json "$G/web.txt"

echo "--- android (Tidbits.kt pickDailyIds against the Android asset)"
(cd android && JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
  ./gradlew :app:testDebugUnitTest --tests '*DailyParityTest*' --rerun --no-daemon -q)

echo "--- cron (aggregate_dailysix.py pick_daily against assets/corpus.json)"
python3 tools/daily-parity/cron_pick.py assets/corpus.json "$G/cron.txt"

echo "--- diff"
diff "$G/apple.txt" "$G/web.txt" && diff "$G/apple.txt" "$G/android.txt" \
  && diff "$G/apple.txt" "$G/cron.txt" \
  && echo "PASS: daily parity — identical sets on all four stacks (incl. the cron)" \
  || { echo "FAIL: daily sets differ"; exit 1; }
