# Windows — Microsoft Store submission (CLI)

The Windows twin of `docs/CLOUD-SUBMISSION.md` (Apple) and the
`play-cli-submission` skill (Android). Same shape as both: **a manual
bootstrap once, then every ship is a CLI command.**

- **Package + submit:** `.github/workflows/windows-store.yml`
- **Iterate/verify:** `.github/workflows/windows-repl.yml` (Decision 043)
- **Identity:** `windows/Tidbits.App/AppxManifest.xml`
- **Version:** `tools/stamp_msix_version.py` ← `AppVersion.xcconfig`

---

## The shape of it (and how it differs from Apple/Play)

| | Apple | Play | **Microsoft Store** |
|---|---|---|---|
| Create the app | ASC API can | Console only | **Partner Center only** |
| First submission | API | API | **Manual, incl. age ratings** |
| Signing | You sign (.p12) | You sign (upload key) | **Microsoft signs — no cert needed** |
| Beta channel | TestFlight | Internal track | **Private audience + package flights** |
| Later ships | CLI | CLI | **CLI (`msstore`)** |

Two things are genuinely better than Apple/Play: **no signing certificate
to manage** (the Store re-signs), and **flight rollout halt/finalize are
first-class**. One thing is worse: **the API cannot create the app**, and
it refuses to drive submissions until one full manual submission exists.

---

## §0 — Bootstrap progress (updated 2026-07-17)

- [x] App reserved in Partner Center — **Store ID `9NRKS9LDRCWC`**, product type
  "MSIX or PWA game".
- [x] Real identity in `AppxManifest.xml` (Name `LearningisChangeInc.TidbitsTrivia`,
  Publisher `CN=2DCA50F2-F930-495C-BFC0-422E60C371ED`, PublisherDisplayName
  "Learning is Change, Inc.") — verified on a Windows CI package build.
- [x] `MSSTORE_PRODUCT_ID` repo variable = `9NRKS9LDRCWC`.
- [x] https deep-link twin wired end-to-end: appUriHandler in the manifest +
  `/.well-known/windows-app-web-link` (PFN
  `LearningisChangeInc.TidbitsTrivia_fn1p07pbc0hg8`) serving 200 live. (This pass
  also fixed a latent bug — `.well-known` was never deployed, so the Android
  `assetlinks.json` had been 404ing; both serve 200 now.)
- [ ] **Auth spike** (§1.1) — Entra app registration + Manager role + `msstore
  apps list`. NOT done. This is the real risk; do it next.
- [ ] **4 Store secrets** (§1.5) — not set.
- [ ] **First manual submission** incl. age ratings (§1.4) — not done; the API
  refuses to drive submissions until it exists.
- [ ] Verify https external-open on a real Windows box (parser is ready; only the
  OS handoff is unverified).

---

## §1 — Bootstrap (once, mostly manual — OWNER ACTION)

These cannot be automated. Do them in order; step 1 is a spike that
de-risks everything after it.

### 1.1 Spike the auth FIRST (do this before anything else)

There is a live, unresolved Microsoft-side failure (`AADSTS7000118`,
"Resource application 'Spark-PROD' is not allowed to be used by tenant
…") that has been reported since ~July 2025 with no fix other than
Microsoft support intervention. It presents as a correctly-configured app
registration that still 401s. **Find out before investing in listings.**

1. Partner Center → associate an **Entra tenant** (create one free from
   Partner Center if there isn't one). A personal MSA will NOT work.
2. Entra admin center → **Identity → Applications → App registrations** →
   **New registration** (name it e.g. `tidbits-store-ci`). Copy the
   **Application (client) ID**, and the **Tenant ID** from Identity →
   Overview.
3. Partner Center → **Account settings → User management → Microsoft
   Entra applications** → add that app registration and give it the
   **Manager** role. *Skipping this is the #1 silent failure: the token
   issues fine and every API call 401s.*
4. Entra → the app → **Certificates & secrets** → **New client secret**.
   Copy it immediately (it is shown once).
5. Partner Center → **Account settings → Identifiers** → copy the
   **Seller ID**.

Then verify from any machine (the CLI is cross-platform —
`brew install microsoft/msstore-cli/msstore-cli`):

```bash
msstore reconfigure --tenantId <T> --sellerId <S> --clientId <C> --clientSecret <CS>
msstore apps list          # must list your apps. If this 401s, STOP — it's 1.1's bug.
```

### 1.2 Reserve the name

Partner Center → **Create a new app** → reserve **Tidbits Trivia**.

> Reservation holds for **3 months** — this starts a clock, so don't do it
> before the auth spike passes.

### 1.3 Copy the real identity into the manifest

Partner Center → **Product management → View app identity details**. Copy
**Package/Identity/Name**, **Publisher**, and **PublisherDisplayName**
verbatim into `windows/Tidbits.App/AppxManifest.xml`.

> Values are **case- and whitespace-sensitive**, and a mismatch fails the
> upload with a generic error that does not name the offending field. The
> committed `CN=TidbitsTriviaDev` is a dev placeholder for sideload only.

### 1.4 First submission — MANUAL

Build the package (`gh workflow run windows-store.yml`, then
`gh run download <id> -n tidbits-msix`) and upload it by hand in Partner
Center, completing the listing, screenshots, and the **age-ratings
questionnaire**. The API refuses to drive submissions until this exists.

### 1.5 Record the secrets

Repo → Settings → Secrets and variables → Actions:

| Kind | Name | From |
|---|---|---|
| Secret | `MSSTORE_TENANT_ID` | Entra → Overview |
| Secret | `MSSTORE_CLIENT_ID` | the app registration |
| Secret | `MSSTORE_CLIENT_SECRET` | Certificates & secrets |
| Secret | `MSSTORE_SELLER_ID` | Partner Center → Identifiers |
| **Variable** | `MSSTORE_PRODUCT_ID` | Partner Center product URL / `msstore apps list` |

> Client secrets **expire** (≤24 months; MS suggests <12) and will break
> the pipeline silently when they do. `msstore` also supports certificate
> auth (`--certificateThumbprint` / `--certificateFilePath`), which is
> worth moving to if this becomes a recurring interruption.

---

## §2 — Shipping (CLI, every time)

```bash
# 1. Bump the version — the Store reserves the 4th segment, so two builds of
#    1.6.44 are indistinguishable. Every upload needs a MARKETING_VERSION bump.
vim AppVersion.xcconfig
python3 tools/stamp_msix_version.py

# 2. Package only (no Store contact) — verify it builds and installs.
gh workflow run windows-store.yml

# 3. Package + submit as a DRAFT (nothing goes live).
gh workflow run windows-store.yml -f submit=true

# 4. Publish for real.
gh workflow run windows-store.yml -f submit=true -f commit=true
```

`submit` defaults to **false** and `commit` defaults to **false** (draft),
because an accidental publish reaches real users and cannot be un-shipped.

---

## §3 — Beta testing (the TestFlight analogue)

Two mechanisms; use both.

- **Private audience** — the listing is invisible and unavailable to
  anyone outside your group. This is the closest TestFlight equivalent.
  **Partner Center UI only:** Pricing and availability → Visibility →
  Private audience. Add testers by Microsoft account email.
- **Package flights** — different packages to subsets of that audience
  (alpha/beta/prod rings). **Fully CLI-driven:**

```bash
msstore flights create <productId> "Beta" --group-ids <groupId>
msstore flights list <productId>
gh workflow run windows-store.yml -f submit=true -f commit=true -f flight=<flightId>

# Staged rollout, halt, finalize
msstore flights submission rollout update <productId> <flightId> --percentage 25
msstore flights submission rollout halt <productId> <flightId>
msstore flights submission rollout finalize <productId> <flightId>
```

---

## §4 — Gotchas (pre-paid)

1. **`AADSTS7000118` / Spark-PROD** — unresolved Microsoft-side tenant
   enrolment bug; blocks everything, no code workaround. Spike it first (§1.1).
2. **Identity mismatch** → generic error naming no field. Copy verbatim.
3. **`PublishSingleFile` is incompatible with MSIX.** `windows-store.yml`
   publishes multi-file on purpose; `windows-build.yml` keeps single-file
   for the direct-download `.exe`. Don't unify them.
4. **CLI updates are FREE-PRODUCTS-ONLY.** Tidbits is free, so this works
   — but it constrains any future paid tier.
5. **Never edit an API-created submission in the web UI.** It permanently
   breaks API control of that submission and can wedge it into a state
   needing delete + recreate. Pick one control plane: CLI.
6. **4th version segment must be 0**; first segment must be non-zero.
7. **No cert needed** — but the sideload signing in the workflow is what
   makes the artifact installable for testing. The Store discards it.
8. **`msstore init` does not support Avalonia** (WinUI/MAUI/Flutter/
   Electron/RN/PWA/UWP only). We skip `init`/`package` and hand the CLI a
   pre-built `.msix` — this is a supported, documented path.
9. **No crash analytics** unless you ship `.msixupload` with `.appxsym`.
   Accepted for now.
10. **WACK on CI is unverified.** Docs recommend the Windows App
    Certification Kit before submitting, but `appcert.exe` wants elevation
    and there's no official headless-CI guidance. We let Store
    certification be the gate; the first manual submission (§1.4) surfaces
    manifest problems.

---

## §5 — Direct download (unchanged, parallel channel)

The Store is the no-SmartScreen path. `windows-build.yml` still produces
the single-file `.exe` for GitHub Releases; see WINDOWS-PLAYBOOK §6 for
the Velopack/winget plan. The two channels share the app but not the
package: **Store = MSIX (multi-file), direct = single-file `.exe`.**

---

## §6 — After the identity exists: the https deep-link twin

`tidbitstrivia://` is registered today (AppxManifest → windows.protocol).
The **https twin** (`tidbitstrivia.com/live/CODE` opening the app) is
deliberately deferred, because `windows.appUriHandler` needs
`/.well-known/windows-app-web-link` naming the **PackageFamilyName**, and
the PFN is `Name` + a hash of the *real* Partner Center Publisher — it
does not exist until §1.3. Publishing a guessed PFN fails silently and
unverifiably, which is worse than not shipping it.

Once §1.3 is done:

1. Add to `AppxManifest.xml` inside `<Extensions>`:
   ```xml
   <uap3:Extension Category="windows.appUriHandler">
     <uap3:AppUriHandler>
       <uap3:Host Name="tidbitstrivia.com" />
     </uap3:AppUriHandler>
   </uap3:Extension>
   ```
   (add `xmlns:uap3` + `uap3` to `IgnorableNamespaces`)
2. Add `.well-known/windows-app-web-link` to the site root (served as
   JSON, no extension), alongside the existing `assetlinks.json`:
   ```json
   [{ "packageFamilyName": "<PFN from Partner Center>", "paths": [ "*" ] }]
   ```
3. Verify an external open with a REAL link on a REAL Windows box — the
   deep-link parser and inbox (0.4) already exist and are unit-tested; the
   only unverified part is the OS handing the URL over.
