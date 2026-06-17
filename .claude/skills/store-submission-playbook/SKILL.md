---
name: store-submission-playbook
description: Use when preparing ANY store submission — App Store (iOS/iPadOS/tvOS) or Google Play — including TestFlight/internal-track setup, store listings, screenshots, signing, review prep, and the post-approval follow-ups. Carries the cross-store checklist and the expensive gotchas pre-paid - layered tvOS icons, Play App Signing vs upload-key fingerprints, AASA/assetlinks serving, the personal-account 12-tester rule, screenshot automation via env hooks, privacy manifests, and account-deletion requirements. Triggers on App Store submission, Play Console, TestFlight, app review, store listing, screenshots, signing, archive build, assetlinks, AASA, privacy manifest, release prep.
---

# Store Submission Playbook

The end-to-end path to both stores, with the gotchas that cost real
days already paid. Three app lineages shipped through this:
App Store (iOS + tvOS approved), Play (internal track + production
prep), plus web (no gate — which is exactly why the web build ships
first and continuously).

## Sequencing rule

Store plumbing has multi-day EXTERNAL latencies (developer-account
review, domain DNS, store review itself). Start these at the
beginning of a release phase, not the end: store records, signing
setup, verification files, privacy forms. Engineering can proceed in
parallel; the human (owner) steps are the critical path — surface
them as an explicit OWNER list.

## Shared pre-flight (all stores)

- **Versioning**: bump marketing version + build per ship —
  `AppVersion.xcconfig` (Apple), `versionCode`/`versionName`
  (Android, kept in lockstep with the Apple marketing version).
  A mismatched `versionName` in a store listing screenshot is a
  real, recurring embarrassment — check it in the artifact, not
  the source.
- **Listing doc in the repo** (`docs/app-store-listing.md`,
  `docs/play-store-listing.md`): every field paste-ready — name,
  subtitle/short description, full description, keywords, URLs,
  copyright, release notes. Written once, reused every release; the
  human pastes, never composes in the console.
- **Screenshots via env hooks** (Decision 018): drive the app to
  each screen with `APP_START_TAB`/`APP_START_ITEM`
  (`SIMCTL_CHILD_…` on Apple sims; intent extras on Android), use
  demo/clean status bars (Android SystemUI demo mode), allow ~25s
  cold-start before the shot. Screenshot IDs must come from LIVE
  data — a stale seed ID renders an error screen in your marketing.
- **Required legal surfaces in-app**: third-party attribution
  rendered VERBATIM where the license requires it; privacy policy;
  account deletion if any sign-in exists (both stores reject
  without it).
- **Icon discipline**: every store/asset icon derives from the ONE
  canonical master in `branding/` (Decision-level: delete retired
  masters from the repo entirely — a stale master WILL get picked
  up by a future asset-generation pass; this happened twice on one
  project).

## App Store (iOS / iPadOS)

- App ID + capabilities (SiwA, iCloud, Push, App Groups) before the
  first archive; capability changes invalidate provisioning.
- `PrivacyInfo.xcprivacy` privacy manifest — required; include
  required-reason API declarations (UserDefaults → CA92.1 etc.).
- ATT only if you actually track (don't add the prompt "just in
  case" — it invites rejection questions).
- Universal Links: AASA at the domain root `/.well-known/` (apex
  domain — a project-pages subpath cannot serve it), Associated
  Domains capability (`applinks:domain`). Adding the entitlement
  re-signs — don't flip it while a build is in review.
- Xcode Cloud: `.xcodeproj` at repo root, no spaces in product name.

## App Store (tvOS) — the extra mile

- **Layered icon (imagestack), not a flat PNG**: App Icon + App
  Store icon as layered "App Icon & Top Shelf Image" brandassets;
  layers are LANDSCAPE (400×240 / 800×480 / 1280×768). Square
  layers fail actool **only on clean builds** — incremental builds
  mask it; verify with a from-scratch build before archiving.
- Top Shelf image (1920×720/2320×720 class) required for the
  product page even if you ship no Top Shelf extension.
- Back-button contract is a review item (Guideline 4.0): never
  intercept Back outside player/modal.
- tvOS screenshots are 3840×2160 (4K) — the env-hook protocol
  handles them like any other platform.
- On-device test before submitting: the simulator hides the
  writable-directory crash class entirely (Decision 017).

## Google Play

- **Play App Signing**: production installs are PLAY-signed, your
  AAB is UPLOAD-signed. `assetlinks.json` must include BOTH
  SHA-256 fingerprints — add the Play signing cert print
  (Console → Setup → App signing) right after enrollment, or App
  Links break ONLY in production while every local build verifies.
- **Personal developer accounts**: production release requires a
  closed test with **12+ testers for 14 days** first. Plan the
  calendar; an internal track release does NOT count toward it.
- Keystore in `~/keystores/`, credentials in
  `~/.gradle/gradle.properties` — never in git. Verify the AAB's
  signer fingerprint matches assetlinks before upload
  (`keytool -printcert`).
- Data Safety form: answer from what the app DOES (for a
  no-account, no-analytics app: nothing collected) — overclaiming
  triggers review friction too.
- Listing assets: 512 icon, 1024×500 feature graphic, phone
  screenshots; deep-link-driven screenshot generation works the
  same as Apple.
- Manifest audit before submitting: every deep-link host/path the
  app EMITS (share links, App Links routes) must be declared in an
  intent-filter, and every route must land on the right screen —
  test with `adb shell am start -a android.intent.action.VIEW -d <url>`.

## Web (the no-gate platform)

No review — but the deep-link infrastructure other stores depend on
lives here: `/.well-known/` must actually serve (add `.nojekyll` on
GitHub Pages — Jekyll silently drops dot-directories), HTTPS
enforced, share URLs render a real landing (a 404-forwarder into
the app router makes every native share URL meaningful even before
the web feature exists).

## After approval

- Update listing URLs when domains change; keep `docs/*-listing.md`
  the source of truth.
- Keep CloudKit/any schema deployed to Production in lockstep with
  releases (see `per-ecosystem-sync-islands`).
- Archive the exact submitted build number in SCRATCHPAD's session
  log — "which build is in review" is a question that otherwise
  recurs weekly.
