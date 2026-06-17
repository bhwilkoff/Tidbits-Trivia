#!/usr/bin/env bash
# sync_shared_assets.sh — mirror repo-root /assets/data/ into
# android/app/src/main/assets/data/ at preBuild time.
#
# Single source of truth: the repo-root /assets/data/. All three
# platforms (web, iOS, Android) consume the same JSON bundles, so
# this script keeps them in lockstep.
#
# Wire into the Gradle build by adding a `tasks.named("preBuild")
# { dependsOn(syncAssets) }` block in app/build.gradle.kts that
# shells out to this script.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SHARED="$REPO_ROOT/assets"
TARGET="$REPO_ROOT/android/app/src/main/assets"

if [ ! -d "$SHARED" ]; then
    echo "ℹ︎  no $SHARED — nothing to sync"
    exit 0
fi

mkdir -p "$TARGET"
rsync -a --delete "$SHARED/" "$TARGET/"
echo "✓  synced $SHARED → $TARGET"
