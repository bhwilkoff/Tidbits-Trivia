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
# corpus.json is EXCLUDED: Android reads the corpus from corpus.sqlite only
# (Decision 049 — the in-RAM JSON corpus is what OOM'd version code 75). Shipping
# it anyway added 55MB of dead weight to every install, which is real storage
# pressure on the low-end devices review runs on and buys nothing.
# enrich.json (2.8MB) and README.md are the same story: no Kotlin source opens either.
# enrich.json is a BUILD-TIME input to the generators in tools/corpus, not a runtime asset.
rsync -a --delete --exclude 'corpus.json' --exclude 'enrich.json' --exclude 'README.md' \
    "$SHARED/" "$TARGET/"
echo "✓  synced $SHARED → $TARGET"
