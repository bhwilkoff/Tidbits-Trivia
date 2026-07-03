---
name: play-cli-submission
description: Use when shipping an Android build (AAB) to Google Play from the command line — no Play Console GUI. Carries the Play Developer API v3 "edits" transaction (insert → upload AAB → set track+notes → commit), service-account JSON auth, the versionCode-+1-every-upload rule, applicationId≠namespace, staged rollout fractions, and the org-policy-block gotcha (create the SA under a personal gmail via gcloud, with an eventual-consistency retry on key create). Triggers on Google Play, Play Console, AAB upload, submit-play, androidpublisher, service account, versionCode, staged rollout, "Play rejected the version", internal track, org policy key block.
---

# Play CLI Submission

Ship an Android App Bundle to Google Play entirely from the CLI, via the **Play Developer API v3**. Pairs with `store-submission-playbook` (listing / Data Safety / screenshots) and `android-production-gotchas` (building the signed AAB) — this skill is the **upload+release transaction** and its auth gotchas.

## When to invoke

- Uploading a signed AAB to any Play track (internal / closed / production) from the command line
- Setting up service-account auth for automated Play publishing
- Play rejects a version code, or an SA key can't be created

## Rule 1 — Publishing is one "edits" transaction

The Play Developer API v3 is transactional: **insert an edit** (get an edit-id) → **upload the AAB** to that edit → **assign it to a track** with release notes and status → **commit** the edit. Nothing is live until commit; a validation failure aborts the whole edit cleanly (no partial release). The shipped driver `tools/submit-play.sh` → `tools/play-publish.py` runs exactly this sequence.

## Rule 2 — Service-account JSON auth, scope androidpublisher

Auth is a **service-account JSON key** (from a GCP project) with the `https://www.googleapis.com/auth/androidpublisher` scope, and that service account **granted access in the Play Console** (Users & permissions → invite the SA email → release permissions). No OAuth user flow, no interactive login — the SA key is the whole credential. Keep it out of git (`~/.config/…` or a CI secret).

## Rule 3 — versionCode +1 on EVERY upload

Bump `versionCode` for every single AAB you upload. **Why**: Play permanently rejects any `versionCode` it has seen before — **even one uploaded to a draft/unreleased track and never shipped**. There is no reuse. Keep `versionName` in lockstep with the app's marketing version across platforms; `versionCode` is a monotonic integer that only ever increments.

## Rule 4 — applicationId ≠ namespace

The `applicationId` (the immutable Play identity of the app) is independent of the Gradle `namespace` (the R/BuildConfig package). Set `applicationId` deliberately and never change it after first publish — it IS the app on Play. The `namespace` can differ and can be refactored freely.

## Rule 5 — Staged rollout via track status + fraction

A release on a track carries a status: `draft` (staged, not live), `inProgress` + a `userFraction` (e.g. 0.1 = 10% staged rollout), or `completed` (100%). Ramp by editing the fraction on subsequent edits; promote by moving the same AAB to a higher track. Pass the target track + status + notes through the publish script rather than hardcoding.

## Rule 6 — The org-policy key-block gotcha

Creating a service-account **key** under a Google Workspace / organization-owned GCP project can hit an **IAM org-policy block** (`iam.disableServiceAccountKeyCreation`) — the key create is refused outright. Fix: create the GCP project AND the service account under a **personal gmail** (no org attached, so no key policy) via `gcloud`:

```
gcloud projects create …            # personal account, no org
gcloud iam service-accounts create …
gcloud iam service-accounts keys create key.json --iam-account …
```

Then invite that SA's email into the Play Console. **Eventual-consistency retry**: a freshly-created SA sometimes isn't yet visible to the key-create call — retry key creation a few times with backoff before treating it as a real failure. Full walkthrough in `docs/play-api-key-setup.md`.

## Scaffolding shipped

- `tools/submit-play.sh` — the CLI entry point
- `tools/play-publish.py` — the edits-transaction driver (insert → upload → track → commit)
- `docs/play-api-key-setup.md` — SA key setup + the org-policy workaround

## See also

- `store-submission-playbook` — Play listing, Data Safety answers, screenshots, the 12-tester/14-day personal-account rule, assetlinks
- `android-production-gotchas` — building + signing the AAB, verifying the signer fingerprint against assetlinks
- `cloud-appstore-submission` — the Apple App Store CLI analog
