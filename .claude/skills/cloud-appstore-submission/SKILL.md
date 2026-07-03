---
name: cloud-appstore-submission
description: Use when submitting any Apple App Store build (iOS / iPadOS / tvOS / macOS), especially from a dev Mac running a beta OS. The DEFAULT venue is a cloud CI runner (released macOS + GA Xcode) because a beta-OS/beta-Xcode dev box is rejected AFTER upload (ITMS-90301, ITMS-90111) while TestFlight still accepts it. Carries the appstore-build.yml workflow, manual .p12 signing (cloud/automatic signing fails for a team ASC API key), the CI secret set, the ES256 ASC-API JWT, the two cert gotchas (raw-PEM CSR, -legacy .p12 PBE), the compile-guard traps on the GA toolchain, and the bump-both-version-numbers rule. Triggers on App Store submission, ITMS-90301, ITMS-90111, appstore-build.yml, ASC API key, notarization, .p12 signing, "beta OS can't submit", cloud build, App Review rejection SDK/Xcode.
---

# Cloud App Store Submission

The end-to-end workflow for building, signing, and uploading an Apple App Store build **from CI**, not from a dev Mac's Xcode GUI. Pairs with `store-submission-playbook` (listing / screenshots / review prep) — this skill is the **build+sign+upload mechanics** and the beta-OS trap that forces them into the cloud.

## When to invoke

- Archiving / signing / uploading any iOS, iPadOS, tvOS, or macOS App Store build
- App Review rejected a build for an SDK / Xcode-version / signing reason
- The dev Mac runs a beta macOS or beta Xcode and can't ship a release
- Setting up or debugging the CI submission pipeline

## Rule 1 — DEFAULT to the cloud; a beta-OS dev box can't ship a release

If the dev Mac runs a **beta macOS or beta Xcode**, a locally-built archive is **rejected AFTER upload**:
- **ITMS-90301** — "not accepting apps built with this version of the OS."
- **ITMS-90111** (recurring) — the Xcode/SDK version is below the current App Store floor.

Crucially, **TestFlight still accepts beta-OS / beta-Xcode builds** — so on-device testing is never blocked; only the App Store *submission* is. The fix is to build on a CI runner with a **released macOS + GA Xcode**. GitHub's `macos-<n>`-style runners are free for public repos. The shipped scaffolding is `.github/workflows/appstore-build.yml`, invoked:

```
gh workflow run appstore-build.yml -f platform=all   # or ios | tvos | mac
```

**The runner label and Xcode version are a moving target** — they must track the current App Store floor each release cycle; re-check before a submission wave (bump the `runs-on:` label and the `xcode-select` path together).

## Rule 2 — Manual .p12 signing (cloud/automatic signing fails for a team ASC API key)

Xcode Cloud signing and `-allowProvisioningUpdates` automatic signing **fail** for a team-scoped App Store Connect API key in this CI shape. Sign MANUALLY: import a `.p12` distribution certificate + the provisioning profile into a temporary keychain in the runner, then `xcodebuild -exportArchive` with a `manual` signing style export options plist. The certs/profiles themselves are minted through the ASC REST API (helper scripts `tools/asc_certs.py` + `tools/asc_profiles.py`), not the Developer portal GUI.

## Rule 3 — The CI secret set

Seven secrets drive the pipeline (names indicative): the ASC API key **issuer ID**, **key ID**, and **.p8 private key**; the distribution **.p12** (base64) + its **password**; the **team ID**; and the **app bundle IDs**. The .p8 signs the ES256 JWT; the .p12 signs the binary. Nothing lands in git — the `.p8` / `.p12` / keychain live only in CI secrets and the ephemeral runner.

## Rule 4 — The ASC API is an ES256-JWT REST API

App Store Connect auth is a short-lived (≤20 min) **ES256 JWT** signed with the `.p8` key (issuer + key-id + audience `appstoreconnect-v1`). Use it for cert/profile creation, build status, and upload housekeeping. Use a **pinned PyJWT in a venv** — a stale/global crypto lib silently emits a bad signature and every call 401s.

## Rule 5 — The two certificate gotchas

- **CSR must be RAW PEM, not base64.** The `csrContent` field of a certificate-create request takes the PEM text verbatim (including the `-----BEGIN CERTIFICATE REQUEST-----` armor). Base64-encoding the PEM again → **409 conflict** / malformed-CSR.
- **The .p12 must use legacy PBE** (`openssl pkcs12 -export -legacy …`). A .p12 written with OpenSSL 3's default (AES/PBES2) encryption fails to import on the runner's `security import` with **"MAC verification failed"**. The `-legacy` flag forces the older RC2/3DES PBE that `security` accepts.

## Rule 6 — Compile-guard traps on the GA toolchain

Code that builds on the beta Xcode can FAIL on the runner's GA Xcode:
- **`#if compiler(>=X.Y)`, not just `#available`.** A symbol that only exists in a beta SDK is invisible to the GA compiler — an `#available` runtime check still fails to *compile* because the symbol doesn't resolve. Gate the whole call site on `#if compiler(>=X.Y)` (or `#if canImport(...)`) so the GA toolchain skips it entirely.
- **No tuple-sort closures.** `sort { ($0.a, $0.b) < ($1.a, $1.b) }` can blow the GA compiler's type-checker (expression-too-complex / timeout). Sort by explicit comparators or precomputed keys.

## Rule 7 — Bump BOTH version numbers every build

Increment **`MARKETING_VERSION` (patch)** AND **`CURRENT_PROJECT_VERSION`** in the shared version config on every submitted build. **Why**: App Review **burns a build number even on a rejection** — reusing it means the next upload collides and is refused. One version config is the single source of truth (never bump through Xcode's identity panel — it creates per-target overrides).

## Scaffolding shipped

- `.github/workflows/appstore-build.yml` — the CI entry point (`-f platform=…`)
- `tools/asc_certs.py`, `tools/asc_profiles.py` — mint distribution certs + profiles via the ASC API
- `tools/submit-appstore.sh` — local driver that dispatches the workflow / polls status
- `docs/CLOUD-SUBMISSION.md` — the full runbook (secret setup, runner-label bumps, troubleshooting)

## See also

- `store-submission-playbook` — listing copy, screenshots, review prep, privacy manifest, the follow-ups this skill's build feeds into
- `play-cli-submission` — the Android/Google Play CLI analog
