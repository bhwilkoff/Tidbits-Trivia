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

## §0 — Bootstrap progress (COMPLETE — first submission in certification 2026-07-18)

**The entire one-time bootstrap is done. The first submission is in certification.**
From here, every ship is the §2 CLI command — you never repeat §1.

- [x] App reserved in Partner Center — **Store ID `9NRKS9LDRCWC`**, product type
  "MSIX or PWA game".
- [x] Real identity in `AppxManifest.xml` (Name `LearningisChangeInc.TidbitsTrivia`,
  Publisher `CN=2DCA50F2-F930-495C-BFC0-422E60C371ED`, PublisherDisplayName
  "Learning is Change, Inc.") — verified on a Windows CI package build.
- [x] `MSSTORE_PRODUCT_ID` repo variable = `9NRKS9LDRCWC`.
- [x] https deep-link twin wired end-to-end: appUriHandler in the manifest +
  `/.well-known/windows-app-web-link` (PFN
  `LearningisChangeInc.TidbitsTrivia_fn1p07pbc0hg8`) serving 200 live.
- [x] **Auth spike PASSED (§1.1).** The `AADSTS7000118`/Spark-PROD bug does NOT
  affect this tenant — `msstore apps list` returns the product. Path: the Partner
  Center account was a personal MSA with ZERO associated tenants; fix was to
  associate the auto-created **Default Directory** tenant
  (`b88cf767-bb2e-4929-be56-ca0b22962887`) via a cloud-only Global Admin, then grant
  **Manager(Windows)** to the app registration. Full detail in the memory
  `windows-store-submission`.
- [x] **4 Store secrets set (§1.5)** — `MSSTORE_TENANT_ID`, `MSSTORE_CLIENT_ID`,
  `MSSTORE_CLIENT_SECRET`, `MSSTORE_SELLER_ID` (=`95246400`). **Rotate the client
  secret** once shipping is proven (its value passed through a session transcript).
- [x] **First submission COMPLETE (manual, Chrome-driven) — IN CERTIFICATION.** MSIX
  v1.6.45 Validated + ranked #1 for Win10/11 Desktop; all 7 sections Complete
  (Pricing, Properties, Age ratings, Packages, Store listings, Xbox Creators
  Program, Submission Options). Publishing set to "as soon as it passes cert" — it
  goes live automatically. See §4 gotchas #11–#12 for the two non-obvious blockers
  solved on the way.
- [ ] Verify https external-open on a real Windows box (parser is ready; only the
  OS handoff is unverified) — the sole remaining nice-to-have, not a blocker.

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

### Step 4 is not optional, and skipping it is SILENT

**A run without `-f commit=true` succeeds while shipping nothing.** Between
2026-07-20 and 2026-08-03 four green runs did exactly that. Each one:

1. **deleted the previous uncommitted draft** (`Deleting existing Submission`),
2. uploaded a fresh package, then
3. printed `Skipping submission commit.` and exited 0.

Net effect: the Store served **1.6.45** for three weeks while the repo moved to
1.6.73, and every run in the Actions list was a green check. The owner found it,
not the pipeline. The workflow now states the outcome in the run summary and
raises a warning annotation whenever a run did not actually submit — but the rule
is simpler than that: **`-f submit=true -f commit=true` or it did not ship.**

### …and step 4 still is not the end: the PUBLISHING HOLD

Committing a submission gets it *certified*, not *live*. A submission carries a
`targetPublishMode`, and this product's was **"Don't publish this submission until I
select Publish now."** So 1.6.73 passed certification and then sat at *Update ready to
publish* indefinitely, one manual click short of users — a second silent stall, layered
under the `commit=true` one.

**`msstore` cannot fix this.** The `publish` command's entire option set is
`--inputFile`, `--appId`, `--noCommit`, `--flightId`, `--packageRolloutPercentage` —
there is no publish-mode flag. The mode is submission metadata inherited from the
previous submission, so it must be changed **once, in Partner Center**, and it then
carries forward:

> Product overview → Certification status → **Modify publishing time** →
> *Publish this submission as soon as it passes certification* → **Apply**

Set to automatic on 2026-08-07. The banner is the tell: "will start publishing **as soon
as it passes certification**" (good) versus "when you click on **Publish now**" (stalled).

So the full update recipe, end to end:

1. Bump `MARKETING_VERSION` in `AppVersion.xcconfig`, run `tools/stamp_msix_version.py`.
2. `gh workflow run windows-store.yml -f submit=true -f commit=true`.
3. Confirm the log says `Submission Status - Certification` and `Submission commit
   success!` — not `Skipping submission commit.`
4. Confirm the overview banner says publishing happens automatically.
5. When certification passes, confirm **Manage packages** shows the new version live.

Confirm the real thing afterwards in Partner Center → **Manage packages**, which
shows the version that is actually live. A committed submission logs
`Submission Status - Certification` and `Submission commit success!`; a draft logs
`Skipping submission commit.`

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
11. **Submission Options has a REQUIRED `runFullTrust` justification —
    this keeps the section "Incomplete" until you fill it.** Any packaged
    Win32 / desktop-bridge app (our Avalonia/.NET MSIX) auto-declares
    `runFullTrust`; you cannot remove it, you must justify it. Partner
    Center → the submission → **Submission Options** → "Why do you need the
    runFullTrust capability?" — **500-char cap** (a longer paste truncates
    mid-sentence). An honest one-liner works: it's the standard capability
    for a packaged classic desktop app to run its own managed code; no
    elevation, no access to other apps' data. Filling it flips the section
    to Complete.
12. **The red banner "The access policies document is not present in the
    config set. This document is required for all publish operations." is
    an Xbox-Live-config blocker, NOT a submission-checklist item — and it
    persists through reloads with every section Complete.** It appears
    because the product type is a **Game**, so Partner Center provisions an
    Xbox Live config whose "access policies document" is only generated when
    you publish that config to the private test sandbox. FIX: left-nav
    **Xbox services** → scroll to the bottom → click **Test** ("Success"
    appears; this publishes to the private sandbox only, never retail). The
    "Xbox Creators Program" row reading Complete in the submission checklist
    does NOT cover this. Documented MS cause (Q&A 303156) — not a support
    ticket.

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

---

## §7 — Tidbits Club on Windows

Audited 2026-08-07, then largely unblocked the same day.

**Works today — the web purchase.** `EntitlementStore` Class B is live: buy Club at
tidbitstrivia.com, sign in on Windows with the same verified-email account, and the
remote `entitlements/{accountKey}` read unlocks Club. Nothing blocks this path, and it
is what the paywall's empty state now points at.

**In-app purchase — both halves now addressed:**

1. **`WindowsStoreGateway` is WRITTEN but NOT YET COMPILED INTO THE SHIP.**
   `windows/Tidbits.App/Services/WindowsStoreGateway.cs` exists and is complete, guarded by
   `#if WINDOWS`. It is inert today because both projects still target plain `net10.0`, so
   the symbol is never defined and `GameData.ResolveStoreGateway()` falls through to
   `NoStoreGateway`.

   **Why it is not switched on: the Windows TFM breaks the build, and the build is the
   ship.** Reaching `Windows.Services.Store` needs `net10.0-windows10.0.x`. That was tried
   host-conditionally (Windows gets the Windows TFM, the Mac head keeps `net10.0` so
   Decision 045's headless observability survives) and gated on `windows-latest` across
   four runs. Three traps were found and fixed:
   - `NETSDK1083` — the TFM defaults `RuntimeIdentifiers` to the UWP-era
     `win10-x64;win10-x86;win10-arm;win10-arm64`, RIDs .NET 5 deleted. Fix: name `win-x64`.
   - `CS0104` — WinRT defines its own `StorePurchaseResult`, so `using
     Windows.Services.Store` makes every mention of ours ambiguous and the interface then
     reads as unimplemented. Fix: alias the namespace.
   - `MSB4062 ExpandPriContent` — **UNSOLVED.** The TFM also imports MSBuild's Appx/PRI
     packaging targets, whose task assembly ships with Visual Studio and not with the
     dotnet CLI SDK. `WindowsPackageType=None`, `EnableMsixTooling=false` and
     `EnableDefaultPriItems=false` did NOT stop the import.

   The TFM change was therefore **reverted**, because `windows-store.yml` publishes the
   same way: leaving it in place would have left every future Windows ship broken to buy a
   feature that is blocked on certification anyway.

   **Two candidate routes for the next attempt**, in preference order:
   - Keep hunting the AppX import guard (`AppxPackage=false`, `WindowsAppContainer=false`,
     or an explicit `Import` exclusion). Cheap to try, one CI round trip each.
   - Move the gateway into a small `Tidbits.Windows` class library on the Windows TFM and
     load it by reflection from `GameData` (`IStoreGateway` already lives in Core, which
     both reference). A plain classlib is far less likely to trip the Appx targets than a
     `WinExe` carrying an ApplicationManifest, and it keeps `Tidbits.App` on `net10.0`.

2. **The three add-ons are submitted.** `club.lifetime` (79.99), `club.annual` (29.99)
   and `club.monthly` (3.99) went to certification on 2026-08-07 once the owner
   completed the tax/payout profile. They had sat at `Not submitted` for two weeks
   behind one disabled button.

**The blocker that held #2, and where it hides.** Every add-on section read Complete
while `Submit to the Store` stayed disabled under:

> You need to update your tax and payout information before you can charge money.

That message is **plain text, not a link**. The page is the gear icon (top right) →
**Account settings** → *Payout and tax* — and it is **ACCOUNT-OWNER ONLY**. Signed in as
the CI Entra admin from §1.1 (Manager(Windows)), the node does not appear at all:
Account settings shows only Overview / My learning profile / My access / User management
/ Programs / Agreements / Organization profile, and the Earnings workspace has just
Earnings and Reports. Sign in as the **original personal MSA** that registered the
developer account. When a Partner Center page seems not to exist, check which identity
is signed in before concluding the feature is missing.

**Still unverifiable from here:** a real purchase. `StoreContext` only returns products
to a Store-INSTALLED package, so the gateway's live behaviour cannot be exercised on the
Mac head, in headless tests, or from the direct-download .exe — only by installing the
certified MSIX from the Store on real Windows. Every path in it degrades to "unknown"
rather than "no" precisely because that verification gap exists: a plumbing error must
never un-Club a paying member.
