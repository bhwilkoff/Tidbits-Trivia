# Cloud submission runbook — Tidbits Trivia

How to ship Tidbits Trivia to the **App Store** (iOS + iPadOS + tvOS) and **Google Play**,
built in the cloud. This is the build/submit PIPELINE; listing copy lives in
`docs/app-store-listing.md` + `docs/play-store-listing.md`.

> **Why cloud:** the dev Mac runs a *beta* macOS, so a local `xcodebuild` archive is rejected by
> App Review (**ITMS-90301** — "built with this version of the OS"); Apple also keeps raising the
> required Xcode floor (**ITMS-90111**). Building on a GitHub-hosted **`macos-26`** runner (released
> macOS + Xcode 26.6) clears both, and it's **free** for this public repo. This is the same pipeline
> Archive Watch uses.

---

## Apple App Store (iOS + tvOS) — DEFAULT

1. **Bump the version + push.** Edit `AppVersion.xcconfig` (`MARKETING_VERSION` and
   `CURRENT_PROJECT_VERSION` +1 — never via the Xcode identity panel), commit, push. The runner
   builds the committed version; the build number must be ahead of the last upload.
2. **Run the workflow:**
   ```
   gh workflow run appstore-build.yml -f platform=all     # or ios | tvos
   gh run watch $(gh run list --workflow=appstore-build.yml -L1 --json databaseId -q '.[0].databaseId')
   ```
   `.github/workflows/appstore-build.yml` (runner `macos-26`) selects Xcode 26.6, imports the signing
   `.p12`s from repo secrets into a temp keychain, and runs `tools/submit-appstore.sh all` — which
   archives the **`TidbitsTrivia`** scheme for iOS and tvOS, creates App Store provisioning profiles
   for `com.learningischange.tidbitstrivia`, and uploads both to App Store Connect.
3. **Finish in App Store Connect (web):** each build processes (a few min), then on the Tidbits record
   → the iOS and the tvOS platform → **select the build** → **Submit for Review**.

**Signing** is MANUAL via `.p12` secrets (cloud-managed signing fails for this team's API key). The
secrets are **shared across the team's apps** (team `L2G756LY8N`) and are already set:
`APPLE_DIST_P12`, `APPLE_INSTALLER_P12`, `APPLE_P12_PASSWORD`, `APPLE_DIST_CERT_ID`, `ASC_KEY_P8`,
`ASC_KEY_ID`, `ASC_ISSUER_ID`. To re-seed (if a cert changes): `tools/ci_make_signing_p12.py
distribution out.p12 <pw>` → `gh secret set APPLE_DIST_P12 --body "$(base64 -i out.p12 | tr -d '\n')"`.

Local `tools/submit-appstore.sh ios` works too, but ONLY on a machine running a released macOS — it is
rejected ITMS-90301 on the beta box. Use the cloud workflow.

---

## Google Play

> **Play package = `com.tidbitstrivia.app`** (the listing the owner created 2026-06-30). This is the
> Android `applicationId` + the Play `packageName` — it is DIFFERENT from the iOS bundle id
> (`com.learningischange.tidbitstrivia`); the Kotlin namespace/code package also stays
> `com.learningischange.tidbitstrivia` (applicationId ≠ namespace is fine on Android).

**Signing (wired 2026-06-30, first beta).** The release AAB is signed by a dedicated Tidbits
**upload key** at `~/keystores/tidbits-upload.jks` (alias `upload`, SHA-256
`3E:DE:FF:71:BE:BD:D9:92:AC:B2:3E:BE:39:8D:03:59:BF:88:5D:B9:53:46:87:AD:32:C1:18:33:CE:F7:FD:38`) —
**back this keystore + its password up; losing it locks out all future updates.** `app/build.gradle.kts`
resolves the signing config from `android/keystore/signing.properties` (gitignored) for local builds,
falling back to the CI-injected `UPLOAD_*` project properties; the file wins when present so a local
build never picks up a sibling app's `UPLOAD_*` from the shared `~/.gradle/gradle.properties` (which is
Archive Watch's). **Play API auth reuses the Archive Watch service account**
(`~/.config/play/archivewatch-play.json`, `archivewatch-ci@archivewatch-play.iam.gserviceaccount.com`) —
it has release permission on the Tidbits app under the same Play developer account, so pass
`PLAY_SERVICE_ACCOUNT_JSON=~/.config/play/archivewatch-play.json` until a dedicated `tidbits-play.json`
is issued.

Two paths, both via the Play Developer API:

- **CLI (the set-up pathway, production-capable):** `tools/submit-play.sh [--track production|internal]
  [--notes "…"]` builds the release AAB and uploads it via `tools/play-publish.py` (Play Developer API
  v3, `PLAY_PACKAGE=com.tidbitstrivia.app`). Needs the upload keystore in `~/.gradle/gradle.properties`
  and the service-account JSON at `~/.config/play/tidbits-play.json` (or `PLAY_SERVICE_ACCOUNT_JSON`).
- **CI (tag-gated → Internal Testing):** `.github/workflows/android-build.yml` builds the AAB and
  uploads to the **internal** track on a `v*-android` tag push (`r0adkll/upload-google-play`,
  `packageName: com.tidbitstrivia.app`). Secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`,
  `KEY_PASSWORD`, `PLAY_SERVICE_ACCOUNT_JSON`. (The old `com.example.appname` placeholder bug is fixed.)

**Version lockstep:** Android `versionName` tracks the iOS `MARKETING_VERSION` (both now `1.6.1`); bump
`versionCode` +1 every Play upload (`submit-play.sh` does this automatically).

### App content + store listing via API (no Console for these)

`tools/push-play-content.py` pushes the parts of Play setup that the Developer API *does* expose, so
they don't need the Console:

- **Data safety** — `applications.dataSafety` accepts the Console's CSV as a string. Tidbits collects no
  data, so `tools/play-data-safety.csv` answers only `PSL_DATA_COLLECTION_COLLECTS_PERSONAL_DATA=FALSE`
  (the full 783-row template, every other row blank). Gotcha: with collection FALSE you must NOT answer
  `PSL_SUPPORTED_ACCOUNT_CREATION_METHODS` — the API 400s ("you cannot answer …"). The CSV column schema
  comes from the Console's downloadable template (mirrored by owenbean400/fastlane-plugin-google_data_safety).
- **Store listing** — `edits.listings` (title/short/full, en-US) + `edits.images` (phone screenshots).
  Screenshots live pre-padded in `branding/play-screenshots/` (1311×2622, exactly 2:1); the iPhone-native
  `branding/screenshots/` shots are 1206×2622 ≈ 2.17:1 and Play rejects them (phone max aspect ratio 2:1).

Run: `PLAY_SERVICE_ACCOUNT_JSON=~/.config/play/archivewatch-play.json tools/push-play-content.py`.

**Still Console-only (no API endpoint exists):** content rating (IARC questionnaire), target audience &
content, privacy policy URL (not in `edits.details` or `Listing`), ads declaration, and App access
(reviewer test credentials). These must be completed by hand before a production release.

---

## House rules that still apply
- Versions via `AppVersion.xcconfig` (iOS) / `android/app/build.gradle.kts` (Android) — never the Xcode
  identity panel. Bump on every ship.
- iOS 26 / tvOS 26 baseline; no third-party Swift packages. Keep iOS + tvOS at parity (`PARITY.md`).
- The submission tooling (`tools/submit-appstore.sh`, `asc_certs.py`, `asc_profiles.py`,
  `ci_make_signing_p12.py`, `submit-play.sh`, `play-publish.py`) is shared with Archive Watch — see its
  `apple-app-store-cli-submission` skill + `docs/macOS-DESIGN.md` §C for the deep details.
