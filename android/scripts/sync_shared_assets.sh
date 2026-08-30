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
# A source file that is EMPTY while the target is not means the shared copy is a
# placeholder, and `rsync --delete` would happily publish the placeholder. The
# repo-root assets/corpus.sqlite is exactly that: 0 bytes, while the real corpus
# each platform ships is 52MB. Refuse rather than silently ship an empty corpus.
for f in "$SHARED"/*; do
    t="$TARGET/$(basename "$f")"
    if [ -f "$f" ] && [ ! -s "$f" ] && [ -s "$t" ]; then
        echo "✗  $(basename "$f") is empty at the source but non-empty in Android — refusing to sync" >&2
        exit 1
    fi
done
# corpus.json is EXCLUDED: Android reads the corpus from corpus.sqlite only
# (Decision 049 — the in-RAM JSON corpus is what OOM'd version code 75). Shipping
# it anyway added 55MB of dead weight to every install, which is real storage
# pressure on the low-end devices review runs on and buys nothing.
# enrich.json (2.8MB) and README.md are the same story: no Kotlin source opens either.
# enrich.json is a BUILD-TIME input to the generators in tools/corpus, not a runtime asset.
# corpus.sqlite is EXCLUDED too: it is a per-platform BINARY build product, not a
# shared JSON bundle. Apple and Android each carry their own 52MB copy while the
# repo-root one is an empty placeholder, so syncing it publishes a corpus with no
# questions in it — the guard above catches that, and this keeps it out entirely.
rsync -a --delete --exclude 'corpus.json' --exclude 'enrich.json' --exclude 'README.md' \
    --exclude 'corpus.sqlite' \
    "$SHARED/" "$TARGET/"
echo "✓  synced $SHARED → $TARGET"
