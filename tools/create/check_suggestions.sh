#!/usr/bin/env bash
# The topics the app SUGGESTS must produce a playable quiz.
#
# Found by tapping through Create on the simulator: "Space exploration" was the
# first chip under "Need a spark?" on five platforms, and the shipped ranker
# returned ONE question for it — about robotics. A new player's first tap
# produced a one-question quiz on the wrong subject.
#
# Nothing checked this because the suggestions are hardcoded per platform while
# the ranker reads the corpus, so dropping or re-categorising rows can quietly
# starve a chip that worked when it was chosen.
#
# Two assertions:
#   1. every platform's hardcoded list matches tools/create/suggested-topics.txt
#   2. every topic in that file returns at least MIN questions from the real
#      js/api.js ranker over the real corpus
#
#   tools/create/check_suggestions.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

LIST=tools/create/suggested-topics.txt
MIN="${SUGGESTION_MIN:-6}"          # a playable round; the ranker caps at 8
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0

# ---- 1. the five hardcoded copies agree with the canonical list -------------
while IFS= read -r topic; do
  [ -n "$topic" ] || continue
  for f in TidbitsTrivia/iOS/Views/CreateQuizView.swift \
           TidbitsTrivia/macOS/CreateView_macOS.swift \
           TidbitsTrivia/tvOS/CreateView_tvOS.swift \
           js/app.js \
           android/app/src/main/java/com/learningischange/tidbitstrivia/ui/AppRoot.kt; do
    grep -qF "$topic" "$f" || { echo "MISSING  \"$topic\" not in $f"; fail=1; }
  done
done < "$LIST"

# ---- 2. each suggestion returns a playable quiz -----------------------------
mkdir -p "$WORK/webmod"
cp js/*.js "$WORK/webmod/"
for f in "$WORK"/webmod/*.js; do mv "$f" "${f%.js}.mjs"; done
python3 - "$WORK/webmod" <<'PY'
import pathlib, re, sys
for p in pathlib.Path(sys.argv[1]).glob("*.mjs"):
    p.write_text(re.sub(r"(from\s+'\./[A-Za-z0-9_-]+)\.js'", r"\1.mjs'", p.read_text()))
PY

node tools/create/web_search.mjs "$WORK/webmod/api.mjs" assets/corpus.json "$LIST" > "$WORK/out.txt"
while IFS=$'\t' read -r topic ids; do
  n=$(echo "$ids" | wc -w | tr -d ' ')
  if [ "$n" -lt "$MIN" ]; then
    echo "THIN     \"$topic\" returns $n question(s), needs $MIN"
    fail=1
  else
    printf '  ok     %-20s %s\n' "$topic" "$n"
  fi
done < "$WORK/out.txt"

if [ "$fail" != "0" ]; then
  echo
  echo "A suggested topic that returns nothing is a first-run failure: the app"
  echo "offered it. Replace it in $LIST and in all five platform copies."
  exit 1
fi
echo "all suggested topics return a playable quiz"
