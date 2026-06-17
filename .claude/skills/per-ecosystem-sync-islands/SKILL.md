---
name: per-ecosystem-sync-islands
description: Use when adding sync of user state (favorites, progress, playlists, preferences) across devices, when adding sign-in, or when tempted to stand up a sync backend. Carries the sync-islands architecture (CloudKit private DB for Apple, Google Drive App Data for Android+Web — the user's own cloud, no server to run), the query-free CloudKit record pattern that replaced a never-worked CKQuery design, tombstones + last-writer-wins merge, optional sign-in gating only sync, and user-visible sync status. Triggers on CloudKit, sync, iCloud, Drive App Data, sign in with Apple, sign in with Google, favorites sync, cross-device, "needs a backend", tombstone, last writer wins.
---

# Per-Ecosystem Sync Islands

Sync user state per ecosystem, each island on the **user's own free
cloud**. No custom backend — nothing to provision, pay for, secure,
or operate — and the developer never sees the data. Production-
verified (iPhone ↔ Apple TV households).

## The architecture

| Island | Mechanism | Server to run |
|---|---|---|
| **Apple** (iOS + iPadOS + tvOS) | CloudKit **private database** (the user's iCloud) | none |
| **Android** | Google Drive **App Data folder** (Sign in with Google + Credential Manager, `drive.appdata` scope) | none |
| **Web** | the SAME Drive App Data folder, via Google Identity Services token + Drive REST from the static site | none — just a public OAuth client ID |

- Drive App Data is the exact analog of CloudKit's private DB: a
  hidden, per-app folder in the user's own account.
- Web + Android sharing one Drive folder means a user signed into
  the same Google account converges across them for free — a bonus,
  not a backend. Namespace per platform only if isolation is wanted.
- **No cross-ecosystem sync.** Apple syncs with Apple, Google with
  Google. Accept the asymmetry; record it in PARITY.md. A neutral
  backend is the explicitly-rejected alternative (unneeded
  complexity for personal-state payloads).

## The non-negotiables

1. **Local-first.** SwiftData / Room+DataStore / IndexedDB is the
   source of truth on-device; the cloud is an upsert/merge mirror.
   Everything works offline.
2. **Sign-in is optional and gates ONLY sync.** Browse, play, save —
   all work signed-out. The sign-in button lives in Settings →
   Account, not in front of any content verb.
3. **Sync status is user-visible, never silent.** A "Last sync /
   last error / Sync Now" row in Settings. The original production
   sync was broken for WEEKS because every pull failed inside a
   silent `catch` — devices pushed but never converged, and nothing
   surfaced it. Observable state (`@Observable` sync service) is
   what made it debuggable.
4. **Account deletion** must exist once sign-in exists (App Store +
   Play requirement): delete all cloud data + sign out.

## The CloudKit pattern that actually works

**Never use `CKQuery` for whole-store pulls.** `CKQuery` with
`NSPredicate(value: true)` requires a queryable index on
`recordName` that CloudKit never auto-creates — every pull fails
with "recordName is not marked queryable," and if your error
handling is quiet, it fails invisibly forever.

Use **fixed-ID records fetched directly** instead:

- One record type (e.g. `AppSync`), a small fixed set of record IDs
  (`tombstones`, `favorites`, `playlists`, `progress`), each holding
  a JSON blob payload.
- Pull = `fetch(withRecordIDs:)` — no queries, no indexes, no schema
  surprises.
- Push = save the changed records (server-record-changed → refetch,
  merge, retry).
- Adding a new synced data type = a new key inside an existing blob
  or one more fixed record — **no schema deploy**.

Merge semantics (same model on Drive App Data — store one JSON file
and merge the same way):

- **Tombstones for deletions**: a removed favorite writes a
  tombstone (id + deletedAt); merge = union of favorites MINUS live
  tombstones; a re-add newer than its tombstone clears it. Without
  tombstones, deletions resurrect on every pull.
- **Last-writer-wins by `modifiedAt`** for structured records
  (playlists, progress) — per record, not per store.
- **Union** for grow-only sets.

Sync triggers: app foreground + debounced after local edits + a slow
timer (e.g. 60s) while active. Push notifications/subscriptions are
an optimization, not the spine.

## Operational gotchas (each cost real time)

- **Deploy the CloudKit schema to Production** before TestFlight/
  App Review builds — the Development environment only serves
  development-signed builds. Symptom of forgetting: sync works from
  Xcode, silently fails for TestFlight users.
- **Don't mix environments when testing cross-device**: two devices
  must run same-channel builds (both dev or both prod).
- The CloudKit container ID is shared across the universal target —
  one container = free iPhone ↔ Apple TV sync. Don't create
  per-platform containers.
- Sign in with Apple on tvOS: use the UIKit
  `ASAuthorizationController` path; test the button's legibility —
  an unreadable sign-in button means users never sign in and you'll
  chase "sync doesn't work" for a week (real incident).
- Gate the whole service behind a single
  `entitlementConfigured`-style flag (default false) so simulator
  builds stay green before the human adds capabilities in Xcode —
  capability-gated features can live in the tree without breaking
  anyone.
