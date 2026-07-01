#!/bin/zsh
# Trivia Night wire golden tests — both sides (docs/NIGHT-WIRE-SCHEMA.md).
# 1. Apple harness: validates fixtures, writes apple-*.hex frames.
# 2. Android GoldenWireTest: validates fixtures + apple frames, writes android-*.hex.
# 3. Apple harness again: cross-decodes the android frames.
set -e
cd "$(dirname "$0")/../.."

echo "--- apple golden (pass 1: fixtures + write apple frames)"
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -swift-version 6 \
  TidbitsTrivia/Core/Design/Design.swift \
  TidbitsTrivia/Core/Models/Question.swift \
  TidbitsTrivia/Core/Models/GameMode.swift \
  TidbitsTrivia/Core/Models/NightPlan.swift \
  TidbitsTrivia/Core/Networking/NightProtocol.swift \
  TidbitsTrivia/Core/Networking/NightTransport.swift \
  tools/night-wire/apple_golden.swift \
  -o /tmp/night-wire-golden
/tmp/night-wire-golden tools/night-wire/golden

echo "--- android golden (fixtures + apple frames; writes android frames)"
(cd android && JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
  ./gradlew :app:testDebugUnitTest --tests '*GoldenWireTest*' --rerun --no-daemon -q)

echo "--- apple golden (pass 2: cross-decode android frames)"
/tmp/night-wire-golden tools/night-wire/golden

echo "--- corpus id parity"
python3 tools/night-wire/check_id_parity.py
