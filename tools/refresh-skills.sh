#!/usr/bin/env bash
# refresh-skills.sh — re-sync vendored skills/commands from upstream
# sources, so this template stays current.
#
# Marketplace skills get pulled from their git origins; user-authored
# skills get re-copied from ~/.claude/ in case you've edited them
# globally and want to update the bundled copy.
#
# Safe to re-run. Reports what changed.

set -euo pipefail

TEMPLATE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="$TEMPLATE_ROOT/.claude/skills"
COMMANDS_DIR="$TEMPLATE_ROOT/.claude/commands"

USER_CLAUDE="$HOME/.claude"
MARKETPLACES="$USER_CLAUDE/plugins/marketplaces"
PLUGIN_CACHE="$USER_CLAUDE/plugins/cache"
SOURCES="$USER_CLAUDE/sources"   # GitHub-tracked skills not in any marketplace

# Marketplace skills — sourced from your installed plugin marketplaces
SWIFT_IOS_SKILLS_SRC="$MARKETPLACES/swift-ios-skills/skills"
UI_UX_PRO_MAX_SRC="$MARKETPLACES/ui-ux-pro-max-skill/.claude/skills/ui-ux-pro-max"
FRONTEND_DESIGN_SRC="$PLUGIN_CACHE/claude-plugins-official/frontend-design/unknown/skills/frontend-design"

# GitHub-tracked skills — cloned to ~/.claude/sources/<name>/ and refreshed
# from upstream. Each entry: "<local-name>|<git-url>|<path-inside-repo>"
# (path "." means the whole repo root is the skill content)
#
# Android skills are commented out by default — they roughly double the
# .claude bundle size when added. Uncomment to vendor them; the same
# rsync logic mirrors them into .claude/skills/. Tier-1/Tier-2 list
# matches README.md → "Adding the Android skill stack".
GITHUB_SKILLS=(
  "app-store-screenshots|https://github.com/ParthJadhav/app-store-screenshots.git|skills/app-store-screenshots"
  "killer-ui|https://github.com/BigSiggis/Killer-UI.git|."

  # --- Android skill stack (uncomment to vendor) ---------------------
  # "android-official-skills|https://github.com/android/skills.git|."
  # "kotlin-agent-skills|https://github.com/Kotlin/kotlin-agent-skills.git|."
  # "chrisbanes-skills|https://github.com/chrisbanes/skills.git|."
  # "rcosteira79-android-skills|https://github.com/rcosteira79/android-skills.git|."
  # "claude-android-ninja|https://github.com/Drjacky/claude-android-ninja.git|."
  # "skydoves-android-testing-skills|https://github.com/skydoves/android-testing-skills.git|."
  # "skydoves-compose-performance-skills|https://github.com/skydoves/compose-performance-skills.git|."
  # "aldefy-compose-skill|https://github.com/aldefy/compose-skill.git|."
)

# Killer-UI's GitHub repo also ships the KUI/* slash commands at /commands/.
# After GITHUB_SKILLS sync, mirror those into the template's KUI commands
# folder. (Special-case; if more multi-artifact repos show up, generalize.)
KILLER_UI_COMMANDS_SRC="$SOURCES/killer-ui/commands"
KILLER_UI_COMMANDS_DEST="$COMMANDS_DIR/KUI"

# When path-inside-repo is ".", exclude these from the skill rsync so we
# don't bring repo-housekeeping files into .claude/skills/<name>/.
ROOT_SYNC_EXCLUDES=(--exclude=README.md --exclude=install.sh
  --exclude=commands --exclude=assets --exclude=.git --exclude=.github
  --exclude=LICENSE --exclude=CONTRIBUTING.md)

# User-authored — live in ~/.claude/, refreshed alongside marketplace pulls
USER_SKILLS_SRC="$USER_CLAUDE/skills"
USER_KUI_SRC="$USER_CLAUDE/commands/KUI"

# Template-owned skills — canonical IN THIS REPO, edited in-template.
# Step 3 must never overwrite these from ~/.claude/ (a stale global copy
# with the same name would clobber the expanded template version).
TEMPLATE_OWNED_SKILLS=(
  tvos-platform-patterns
  web-platform-patterns
  ios-production-gotchas
  android-production-gotchas
  cross-platform-parity-discipline
  multiplatform-expansion-method
  shared-data-plane-contract
  per-ecosystem-sync-islands
  resilient-media-streaming
  store-submission-playbook
)

is_template_owned() {
  local name="$1"
  for owned in "${TEMPLATE_OWNED_SKILLS[@]}"; do
    [ "$name" = "$owned" ] && return 0
  done
  return 1
}

say()   { printf "\033[1;34m▸\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m!\033[0m %s\n" "$*" >&2; }
ok()    { printf "\033[1;32m✓\033[0m %s\n" "$*"; }
fail()  { printf "\033[1;31m✗\033[0m %s\n" "$*" >&2; exit 1; }

# 1. Pull marketplace updates ------------------------------------------------
say "Pulling marketplace updates..."

for repo in \
  "$MARKETPLACES/swift-ios-skills" \
  "$MARKETPLACES/ui-ux-pro-max-skill"
do
  if [ -d "$repo/.git" ]; then
    name=$(basename "$repo")
    before=$(git -C "$repo" rev-parse --short HEAD)
    git -C "$repo" pull --ff-only --quiet 2>/dev/null || warn "could not pull $name (uncommitted changes? offline?)"
    after=$(git -C "$repo" rev-parse --short HEAD)
    if [ "$before" != "$after" ]; then
      ok "$name updated: $before → $after"
    else
      ok "$name up to date ($before)"
    fi
  else
    warn "$(basename "$repo") is not a git checkout — skipping pull"
  fi
done

# claude-plugins-official is a meta-marketplace; frontend-design comes
# from its plugin cache rather than a top-level git checkout. Updates
# arrive via Claude Code's plugin refresh, not git.

# 2. Sync marketplace skills into vendored copy ------------------------------
say "Syncing marketplace skills into $SKILLS_DIR ..."

sync_marketplace_skill() {
  local src="$1"
  local label="$2"
  if [ ! -d "$src" ]; then
    warn "$label source missing at $src — skipping"
    return
  fi
  # -L dereferences symlinks so cloners get real files, not broken links.
  # Per-skill copy so we don't blow away user-authored siblings.
  local count=0
  if [ -f "$src/SKILL.md" ]; then
    # single-skill source (e.g. ui-ux-pro-max, frontend-design)
    local name=$(basename "$src")
    rsync -aL --delete "$src/" "$SKILLS_DIR/$name/"
    count=1
  else
    # multi-skill source (e.g. swift-ios-skills/skills/)
    for skill in "$src"/*/; do
      [ -d "$skill" ] || continue
      local name=$(basename "$skill")
      rsync -aL --delete "$skill" "$SKILLS_DIR/$name/"
      count=$((count + 1))
    done
  fi
  ok "$label: $count skill(s) synced"
}

sync_marketplace_skill "$SWIFT_IOS_SKILLS_SRC" "swift-ios-skills"
sync_marketplace_skill "$UI_UX_PRO_MAX_SRC"    "ui-ux-pro-max"
sync_marketplace_skill "$FRONTEND_DESIGN_SRC"  "frontend-design"

# 2b. Sync GitHub-tracked skills (not in any marketplace) -------------------
say "Refreshing GitHub-tracked skills..."

mkdir -p "$SOURCES"
for entry in "${GITHUB_SKILLS[@]}"; do
  IFS='|' read -r name url subpath <<< "$entry"
  repo_dir="$SOURCES/$name"
  if [ -d "$repo_dir/.git" ]; then
    before=$(git -C "$repo_dir" rev-parse --short HEAD)
    git -C "$repo_dir" pull --ff-only --quiet 2>/dev/null || warn "could not pull $name (offline?)"
    after=$(git -C "$repo_dir" rev-parse --short HEAD)
    if [ "$before" != "$after" ]; then
      ok "$name updated: $before → $after"
    else
      ok "$name up to date ($before)"
    fi
  else
    say "  cloning $name from $url ..."
    git clone --depth 1 --quiet "$url" "$repo_dir" || { warn "clone failed for $name"; continue; }
    ok "$name cloned"
  fi
  # Resolve source path inside the cloned repo
  if [ "$subpath" = "." ]; then
    src="$repo_dir"
    sync_args=(-aL --delete "${ROOT_SYNC_EXCLUDES[@]}")
  else
    src="$repo_dir/$subpath"
    sync_args=(-aL --delete)
    if [ ! -d "$src" ]; then
      warn "  expected $subpath inside $name repo, not found — skipping"
      continue
    fi
  fi
  # Refresh the user's global install (~/.claude/skills/<name>/). The
  # user-authored sync below then mirrors that into the template, so we
  # don't end up with a stale ~/.claude/skills/<name>/ overwriting fresh
  # upstream content.
  mkdir -p "$USER_SKILLS_SRC/$name"
  rsync "${sync_args[@]}" "$src/" "$USER_SKILLS_SRC/$name/"
  ok "  refreshed global install at $USER_SKILLS_SRC/$name/"
done

# Mirror killer-ui's commands/ into the user's global KUI commands folder.
# (User-authored sync below copies that into the template.)
if [ -d "$KILLER_UI_COMMANDS_SRC" ]; then
  mkdir -p "$USER_KUI_SRC"
  rsync -aL --delete "$KILLER_UI_COMMANDS_SRC/" "$USER_KUI_SRC/"
  ok "killer-ui commands refreshed at $USER_KUI_SRC/"
fi

# 3. Sync user-authored skills ----------------------------------------------
# These are the ones you wrote yourself in ~/.claude/skills/. They're not
# in any marketplace, so they only update when you edit them globally and
# re-run this script.
say "Syncing user-authored skills..."

if [ -d "$USER_SKILLS_SRC" ]; then
  count=0
  skipped=0
  for skill in "$USER_SKILLS_SRC"/*/; do
    [ -d "$skill" ] || continue
    name=$(basename "$skill")
    if is_template_owned "$name"; then
      skipped=$((skipped + 1))
      continue
    fi
    rsync -a --delete "$skill" "$SKILLS_DIR/$name/"
    count=$((count + 1))
  done
  ok "user skills: $count synced from ~/.claude/skills/ ($skipped template-owned skipped)"
else
  warn "$USER_SKILLS_SRC not found — no user-authored skills to sync"
fi

# 4. Sync KUI slash commands ------------------------------------------------
say "Syncing KUI commands..."

if [ -d "$USER_KUI_SRC" ]; then
  mkdir -p "$COMMANDS_DIR/KUI"
  rsync -a --delete "$USER_KUI_SRC/" "$COMMANDS_DIR/KUI/"
  count=$(ls "$COMMANDS_DIR/KUI/"*.md 2>/dev/null | wc -l | tr -d ' ')
  ok "KUI commands: $count synced from ~/.claude/commands/KUI/"
else
  warn "$USER_KUI_SRC not found — no KUI commands to sync"
fi

# 5. Summary ----------------------------------------------------------------
total_skills=$(ls "$SKILLS_DIR" | wc -l | tr -d ' ')
total_commands=$(ls "$COMMANDS_DIR" | wc -l | tr -d ' ')
total_size=$(du -sh "$TEMPLATE_ROOT/.claude" | cut -f1)

echo
ok "Refresh complete."
echo "   Skills: $total_skills    Commands: $total_commands    Bundle size: $total_size"
echo
echo "Next: review with 'git diff', commit, push."
