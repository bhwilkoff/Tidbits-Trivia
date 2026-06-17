#!/usr/bin/env bash
# install-android-skills.sh — clone the recommended Android skill stack
# into ~/.claude/sources/ so the next `refresh-skills.sh` run vendors
# them into .claude/skills/.
#
# Safe to re-run. Pulls latest commits if the clone exists.
#
# Skills installed (~150 Kotlin / Compose / Android skills, with some
# overlap):
#   - chrisbanes/skills            — 16 Compose + Kotlin (Google Android engineer)
#   - rcosteira79/android-skills   — 16 skills (architecture / M3 / testing / Coroutines / Flows / Room)
#   - Drjacky/claude-android-ninja — 25+ refs (Compose M3 / Nav 3 / Hilt / Room / Coil 3 / biometrics)
#   - skydoves/android-testing-skills    — 54 testing skills
#   - skydoves/compose-performance-skills — 26 perf skills
#   - android/skills               — Google's official (AGP / adaptive / edge-to-edge / R8)
#   - Kotlin/kotlin-agent-skills   — JetBrains' official (early-stage)
#   - aldefy/compose-skill         — 24 Compose refs against androidx source
#
# After install, edit tools/refresh-skills.sh to UNCOMMENT the
# android skills in GITHUB_SKILLS=(...), then run ./refresh-skills.sh.

set -euo pipefail

SOURCES="$HOME/.claude/sources"
mkdir -p "$SOURCES"

REPOS=(
  "https://github.com/android/skills.git|android-official-skills"
  "https://github.com/Kotlin/kotlin-agent-skills.git|kotlin-agent-skills"
  "https://github.com/chrisbanes/skills.git|chrisbanes-skills"
  "https://github.com/rcosteira79/android-skills.git|rcosteira79-android-skills"
  "https://github.com/Drjacky/claude-android-ninja.git|claude-android-ninja"
  "https://github.com/skydoves/android-testing-skills.git|skydoves-android-testing-skills"
  "https://github.com/skydoves/compose-performance-skills.git|skydoves-compose-performance-skills"
  "https://github.com/aldefy/compose-skill.git|aldefy-compose-skill"
)

say() { printf "\033[1;34m▸\033[0m %s\n" "$*"; }
ok()  { printf "\033[1;32m✓\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m!\033[0m %s\n" "$*" >&2; }

for entry in "${REPOS[@]}"; do
    IFS='|' read -r url name <<<"$entry"
    target="$SOURCES/$name"
    if [ -d "$target/.git" ]; then
        before=$(git -C "$target" rev-parse --short HEAD)
        git -C "$target" pull --ff-only --quiet 2>/dev/null \
            || warn "could not pull $name (uncommitted changes? offline?)"
        after=$(git -C "$target" rev-parse --short HEAD)
        if [ "$before" != "$after" ]; then
            ok "$name updated: $before → $after"
        else
            ok "$name up to date ($before)"
        fi
    else
        say "Cloning $name from $url ..."
        git clone --depth 1 --quiet "$url" "$target" \
            || warn "clone failed for $name"
        ok "$name cloned"
    fi
done

echo
ok "Android skill sources ready in $SOURCES/"
echo "   Next:"
echo "   1. Edit tools/refresh-skills.sh — UNCOMMENT the Android entries"
echo "      in the GITHUB_SKILLS=(...) block."
echo "   2. Run ./tools/refresh-skills.sh to vendor them into"
echo "      .claude/skills/ for this repo."
echo
echo "   Commit the resulting .claude/ delta to publish to template users."
