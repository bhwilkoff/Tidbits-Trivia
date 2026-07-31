#!/usr/bin/env bash
# test-apple.sh — run the Apple Core unit tests.
#
#   tools/test-apple.sh [extra xcodebuild args...]
#
# macOS destination on purpose: these are pure-logic tests over the
# platform-agnostic Core, so there is no simulator to boot and no app to install
# — the suite runs in seconds. The Windows analogue is `cd windows && dotnet test`.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

# The pbxproj is generated from project.yml; regenerate so a newly added test
# file is actually in the target (forgetting this reads as "my test didn't run").
command -v xcodegen >/dev/null && xcodegen generate >/dev/null

xcodebuild test \
  -project TidbitsTrivia.xcodeproj \
  -scheme TidbitsTrivia \
  -destination 'platform=macOS' \
  -only-testing:TidbitsTriviaTests \
  CODE_SIGNING_ALLOWED=NO "$@" 2>&1 \
  | grep -E "error:|✘|✔|Test run with|TEST (SUCCEEDED|FAILED)"
