#!/bin/zsh
# Daily-parity golden (Decision 037): prove the Swift, Kotlin, and JS Daily
# pickers produce IDENTICAL sets from each platform's own bundled corpus.
# Run after ANY change to the daily rank/pick, corpus regen, or engine mirror.
set -e
cd "$(dirname "$0")/../.."
G=tools/daily-parity/golden

echo "--- apple (DailyPick.swift against corpus.sqlite ids)"
sqlite3 TidbitsTrivia/Resources/corpus.sqlite "SELECT id FROM questions" > /tmp/daily-parity-ids.txt
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -swift-version 6 \
  TidbitsTrivia/Core/Engine/SeededRNG.swift \
  TidbitsTrivia/Core/Engine/DailyPick.swift \
  tools/daily-parity/apple_pick.swift \
  -o /tmp/daily-parity-apple
/tmp/daily-parity-apple /tmp/daily-parity-ids.txt "$G/apple.txt"

echo "--- web (engine.js pickDaily against assets/corpus.json)"
cp js/engine.js /tmp/tidbits-engine-copy.mjs
node tools/daily-parity/web_pick.mjs /tmp/tidbits-engine-copy.mjs assets/corpus.json "$G/web.txt"

echo "--- android (Tidbits.kt pickDailyIds against the Android asset)"
(cd android && JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
  ./gradlew :app:testDebugUnitTest --tests '*DailyParityTest*' --rerun --no-daemon -q)

echo "--- diff"
diff "$G/apple.txt" "$G/web.txt" && diff "$G/apple.txt" "$G/android.txt" \
  && echo "PASS: daily parity — identical sets on all three stacks" \
  || { echo "FAIL: daily sets differ"; exit 1; }
