# Tidbits Trivia — v1 Launch Checklist

The path to shipping v1 on **Web, iOS, iPadOS, tvOS, and Android**. v1 scope is
the **offline / local** experience (single-player + daily + create-a-quiz +
local pass-and-play + records). Online multiplayer, sign-in, and sync are the
**post-launch** track — v1 has **no account, no analytics, no data collection**,
which keeps store review simple.

Two columns: **OWNER** = human/account steps with multi-day external latency
(start these first — they're the critical path). **ENG** = code/asset work
(done in-repo, mostly complete). See `store-submission-playbook` skill for the
gotchas behind each line.

---

## OWNER critical path (start now — external latency)

### Accounts & identifiers
- [ ] **Apple Developer Program** enrollment ($99/yr) active.
- [ ] **Google Play Console** account ($25 one-time) active.
- [ ] Set `DEVELOPMENT_TEAM` in `project.yml` (currently empty) to the Apple
      team ID, then `xcodegen generate`. Bundle ID: `com.learningischange.tidbitstrivia`.
- [ ] App Store Connect: create the app record (same bundle ID).
- [ ] Play Console: create the app (package `com.learningischange.tidbitstrivia`).

### Signing
- [ ] iOS/tvOS: automatic signing once the team is set (no special capabilities
      in v1 — no SiwA/iCloud/Push/Game Center until the online track).
- [ ] Android **upload keystore** in `~/keystores/`, credentials in
      `~/.gradle/gradle.properties` (NEVER in git). Wire release signing in
      `android/app/build.gradle.kts`. After Play enrollment, add the **Play App
      Signing** cert SHA-256 to `assetlinks.json` (only matters once App Links ship).

### Legal surfaces (required by both stores)
- [ ] **Privacy policy URL** — `privacy.html` is in the repo; it serves at the
      GitHub Pages URL once Pages is confirmed live. Confirm the URL.
- [ ] **Support URL** — `support.html` likewise.
- [ ] Account deletion: **N/A for v1** (no sign-in). Add when the online track lands.

### Store listings (copy is paste-ready in the repo)
- [ ] App Store: paste `docs/app-store-listing.md`. App Privacy questionnaire →
      "Data Not Collected". Age rating questionnaire → expect 4+.
- [ ] Play: paste `docs/play-store-listing.md`. Data Safety form → "No data
      collected / shared". Content rating questionnaire.
- [ ] Upload screenshots (generated to `branding/screenshots/`, see ENG).

### Play-specific calendar gotcha
- [ ] **Personal Play accounts require a closed test with 12+ testers for 14
      days** before production. An internal-track release does NOT count. Plan
      the 2-week window. (Org accounts are exempt.)

### Domain (optional for v1)
- [ ] Universal Links / App Links need an **apex domain** serving
      `/.well-known/` (a GitHub Pages project subpath can't). v1 ships fine with
      the custom scheme + the web landing twin; decide a domain when deep links
      become a priority. Until then share URLs point at the GitHub Pages URL.

---

## ENG status (in-repo)

- [x] **Branded launch screen** (iOS) — cream `UILaunchScreen` + centered logo
      (was the default white flash). tvOS launches from the brand asset.
- [x] **`PrivacyInfo.xcprivacy`** — no tracking, nothing collected, UserDefaults
      (CA92.1) required-reason declared.
- [x] **Version**: `1.0` / build `1` aligned across `AppVersion.xcconfig` +
      Android `versionName`/`versionCode`. Bump both in lockstep every ship.
- [x] **Clean content** — clues AND explanations stripped of IPA / foreign-
      script / romanization clutter.
- [x] **`privacy.html` + `support.html`** — served by the web app for the URLs.
- [x] **Icons**: iOS ✓ (AppIcon + LaunchLogo). Android ✓ (adaptive icon —
      background/foreground/monochrome — + splash). Web ✓ (manifest icon).
- [ ] **tvOS layered icon + Top Shelf** — REMAINING. Needs a "Brand Assets"
      imagestack with LANDSCAPE layers (400×240 / 1280×768) + a Top Shelf image
      (1920×720 / 2320×720). Square layers fail actool only on CLEAN builds —
      verify from-scratch before archiving. The one hard blocker for tvOS submit.
- [x] **Store screenshots** (iOS) → `branding/screenshots/`, regenerable via
      `scripts/screenshots-ios.sh`. Note: capture the 6.9" size on a Pro Max sim
      for App Store. Android/tvOS sets use the same env-hook approach (pending).
- [ ] **Web**: confirm `.nojekyll` so `/.well-known/` serves; HTTPS enforced.
- [ ] **Android manifest audit** — every emitted deep-link host/path declared
      in an intent-filter (matters once App Links ship).

## Submission order (lowest-latency first)
1. **Web** — no gate. Push to `main` → GitHub Pages. Ships continuously; it is
   the share-link landing twin for the native apps.
2. **iOS / iPadOS** — archive → TestFlight → App Store review (~1–3 days).
3. **tvOS** — same target; needs the layered icon + Top Shelf image + an
   on-device test (the simulator hides the writable-dir crash class).
4. **Android** — closed test (12 testers / 14 days on personal accounts) →
   production.

## After approval
- Record the submitted build number in `SCRATCHPAD.md` ("which build is in
  review" recurs weekly otherwise).
- Keep `docs/*-listing.md` the source of truth; update URLs if a domain lands.
