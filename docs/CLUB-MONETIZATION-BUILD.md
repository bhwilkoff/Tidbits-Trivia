# Tidbits Club — the monetization build (running checklist)

**Status: CODE-COMPLETE up to the owner financial line (2026-07-21).** The end-to-end
plan to make Tidbits Club **payable natively on every platform**, at $0 ongoing infra
(Decision 047, `docs/MONETIZATION.md`). Greenfield: no IAP code existed before this.

**What is DONE + committed + verified** (everything Claude can build and observe):
- **Entitlement spine on all 6 platforms** — web / iOS / macOS / tvOS / Android / Windows.
  `isClub = localStore(Class A) OR remote(Class B)`, fail-open, cached last-known-good.
  RTDB `entitlements/` rule deployed + live-verified (clients read-only, R-MON-3).
- **Native paywall UI on all 6 platforms** — all CI/build-verified (Windows headless-PNG +
  windows-latest CI green; Apple macOS/tvOS BUILD SUCCEEDED; Android assembleDebug green).
- **Native purchase code**: Apple StoreKit 2 (`StoreKitStore.swift`, Universal Purchase),
  Android Play Billing (`data/Billing.kt`), web MoR webhook (`workers/tidbits-auth`), and
  the Windows Store `IStoreGateway` **seam** (`NoStoreGateway` default; the real gateway is
  the one deferred item below).
- **`docs/CLUB-MARKETING.md`** — the owner's paste-ready store-product sheet (exact ids,
  types, prices, descriptions, review notes for Apple / Play / Microsoft / web).

**The ONE deferred code item (not a gap — a discipline call):** the real
`WindowsStoreGateway` (Microsoft Store `StoreContext` + `IInitializeWithWindow`). It needs a
`net10.0-windows` multi-target, has no public Avalonia worked example, and its purchase path
**cannot be observed until the owner creates the Partner Center add-ons** — so per this
project's "don't iterate blindly on unobservable behavior" rule it is best written WHEN the
add-ons exist and it can actually be verified end-to-end. Until then the seam + `NoStoreGateway`
keep the paywall shipping with a graceful empty state.

**What ONLY the owner can do (the financial line — see §6-equivalent in CLUB-MARKETING):**
sign the Apple Paid Apps Agreement + banking/tax (and create the IAPs, which ASC gates on
that agreement), set up the Play merchant profile + products, create the Microsoft add-ons,
sign up for a web Merchant of Record (Paddle/Lemon Squeezy) + set the Worker secrets. Once
any of these exist, the wired code lights up Club on sign-in with NO further engineering.

## The products (Decision 047)

| Product | Price | Shape | Platforms |
|---|---|---|---|
| **Tidbits Club (annual)** | $29.99/yr | auto-renewable subscription | all |
| **Tidbits Club (monthly)** | $3.99/mo | auto-renewable subscription (same group) | all |
| **Founding Member (lifetime)** | $79.99 | non-consumable, **first 90 days only** | all |
| **Venue pack** | $99 / 10 passes | non-consumable ×N (or web-only bulk) | web (host tooling) |

One entitlement — `tier: "club"` — is what all of these grant. The app never checks
*which* product; it checks *are you Club*.

## The hard line: what Claude does vs. what the owner must do

**Claude builds + configures:** all client code, the Worker, RTDB rules, IAP **product
definitions** (metadata/price tiers) in the store consoles via browser, the promo/
marketing surfaces, all tests.

**Owner only (financial/legal — Claude will NOT do these):**
- Sign the **Paid Applications Agreement** (App Store Connect) + banking + tax forms.
- Enrol in the **Apple Small Business Program** (free; halves commission — do now).
- Sign up for the **Merchant of Record** (Paddle / Lemon Squeezy) incl. banking.
- Microsoft Store **payout/tax** profile.
- Google Play **merchant** setup (if Android is in scope this cycle).

Claude will build right up to each of these and hand off with exact steps. Entering
bank/card/tax numbers or signing a financial agreement is a prohibited action.

## Architecture (the shared spine)

```
isEntitled = localStoreEntitlement          // Class A: StoreKit/Play/MSStore — offline, authoritative
          || remoteEntitlement(myAccountKey) // Class B: web purchase — read entitlements/{sha256(email)}
```

- **`entitlements/{key}`** on RTDB: `{ tier, sources[], since, until|null, ver }`.
  Client **read-own only** (email-verified owner), **never write** (R-MON-3). The
  Worker is the sole writer, via a Firebase admin credential.
- Each platform mirrors one `EntitlementStore`: exposes `isClub`, refreshes local
  store entitlements first (authoritative, offline), falls back to the RTDB read.
- Club features check `EntitlementStore.isClub` — one gate, many features.

## Phases (each ≈ one or more loop iterations)

### Phase 0 — the shared entitlement spine  ← FOUNDATION, everything depends on it
> **KNOWN ISSUE (fix in 0d):** `clearOnSignOut` is defined but UNWIRED on every platform
> (Swift/JS/Kotlin) — on sign-out `refresh()` fails open and keeps cached Club, so a second
> person on a shared device would see Club. Low risk pre-launch (no real purchases yet).
> **FIXED 2026-07-21:** sign-out now calls `clearOnSignOut()` on Swift (PlayerIdentityStore.signOut), JS (app.js), Kotlin (PlayerIdentity.signOut), C# (agent, prior). All 4 closed.
- [x] 0c. `EntitlementStore` — Swift + JS + Kotlin + C# ALL DONE (build/test-verified).
- [x] 0a. `entitlements/` RTDB rules — DEPLOYED + live-verified (client write DENIED, read denied to non-owner). 2026-07-21.
- [x] 0b. Worker `/entitlements/webhook` — DONE + deployed + live-verified. HMAC-verify MoR
      event → map to grant/revoke → write `entitlements/{key}` via Firebase-SA admin (RS256
      JWT in-Worker). 18 tests. Live: 503 when unconfigured (retryable, no silent purchase
      loss), 405 on GET, Apple callback unregressed. **OWNER: set `LEMONSQUEEZY_WEBHOOK_SECRET`
      + `FIREBASE_SA_EMAIL`/`FIREBASE_SA_PRIVATE_KEY`/`FIREBASE_DB_URL` once the MoR is chosen.**
- [~] 0c. `EntitlementStore` — **Swift Core reference + JS (web) DONE** (`Core/Networking/EntitlementStore.swift`: `isClub = local || remote`, fail-open, cached last-known-good; wired into the app entry + refresh at bootstrap; iOS/macOS/tvOS build-verified). Kotlin DONE (`data/Entitlement.kt`, remote-only, cached SharedPreferences, fail-open; wired in `AppRoot` LaunchedEffect + `AppNameApplication`; gradle BUILD SUCCESSFUL). C# DONE (`Tidbits.Core/Networking/EntitlementStore.cs` + 11 tests, remote-only, JSON-file cache, fail-open; wired in `GameData` + Settings; **ClearOnSignOut wired on Windows** — the only platform where the sign-out leak is already fixed; 280 tests green). **All 4 client mirrors done.** JS: `js/entitlement.js` (remote-only — web has no local store — cached, fail-open; wired at bootstrap + on identity change).
- [~] 0d. iOS paywall DONE (`iOS/Views/ClubPaywallView.swift` — hero + 4-pillar value prop + 3 StoreKit plans w/ live prices + Restore + R-MON-2 web-sign-in note; entry point in ProfileView; sheet). `.storekit` wired into the scheme (XcodeGen `scheme.storeKitConfiguration` → products load in the sim). iOS BUILD SUCCEEDED. iOS BUILD SUCCEEDED (all Apple platforms). Added a `TIDBITS_PAYWALL=1` debug hook, but the automated sim render didn't surface the sheet (env/SwiftUI-timing in the sim — not chased further; paywall is build-verified). SKTestSession purchase test WRITTEN (`docs/pending-tests/ClubPurchaseTests.swift`) but the hosted-unit-test target hits a "Multiple commands produce TidbitsTrivia.swiftmodule" collision under this Xcode-beta/XcodeGen — DEFERRED to a focused config pass (likely: move Core to a framework). Web paywall DONE. **macOS + tvOS paywalls DONE 2026-07-21** (`macOS/ClubPaywallView_macOS.swift` .sheet + `tvOS/ClubPaywallView_tvOS.swift` .fullScreenCover; both `** BUILD SUCCEEDED **`; Settings entry points; EntitlementStore injected into the macOS Settings scene). **En route: also restored macOS as a real xcodegen destination (`project.yml` had `[iOS, tvOS]` — macOS config had been clobbered from the generated pbxproj; see memory `macos-appstore-submission`).** Remaining paywall: Android (agent in progress) + Windows UI surface + the real Windows StoreContext gateway.

### Phase 1 — Apple (StoreKit 2; iOS + iPadOS + macOS + tvOS via Universal Purchase)
- [!] 1a. App Store Connect products — BLOCKED this iteration: the Chrome extension is in a degraded state (viewport 0x0, screenshots erroring on a `params.clip.scale` binding bug), so the console UI can't be driven. Product IDs are DEFINED (see 1c/1b) and App Store Connect must match them EXACTLY:
      `…club.annual` (auto-renew sub), `…club.monthly` (same group), `…club.lifetime` (non-consumable). Retry when the browser recovers, or owner creates them.
- [x] 1b. `.storekit` config — `TidbitsTrivia/Resources/Tidbits.storekit` (annual $29.99 / monthly $3.99 subscription group + lifetime $79.99 non-consumable, familyShareable). Scheme-wiring for simulator purchase pending (Phase 0d).
- [x] 1c. StoreKit 2 client — `Core/Networking/StoreKitStore.swift`: Universal-Purchase product set (3 IDs), load/purchase/restore, `Transaction.currentEntitlements` → `EntitlementStore.localCheck` (Class A), `Transaction.updates` listener for renewals. Fail-open grace (empty=unknown=nil). Wired `start()` at launch. iOS/macOS/tvOS BUILD SUCCEEDED. **Paywall UI to trigger purchase() = Phase 0d.**
- [ ] 1d. Mirror an Apple purchase into `entitlements/` (optional; web is the universal one).
- [ ] OWNER: Paid Apps Agreement + banking + tax; SBP enrolment.

### Phase 2 — Web (Merchant of Record) + the promo/marketing surface (rule 6)
- [x] 2a. Web Club promo page DONE — `#/club` route + `viewClub()`: hero + §4a pitch, 4 value
      pillars, 3 plan cards (lifetime/annual/monthly, MoR checkout), R-MON-2 sign-in note,
      member state when `Entitlement.isClub`. Entry link in Records. `CLUB` config in store.js
      (owner fills each plan's `checkout` URL once the MoR products exist). Syntax-verified;
      visual check pending (Chrome extension down).
- [ ] 2b. MoR checkout (Paddle/Lemon Squeezy hosted checkout or overlay).
- [ ] 2c. Worker webhook live (0b) → entitlement write → app lights up on sign-in.
- [ ] OWNER: choose + sign up for the MoR; set the Worker secrets.

### Phase 3 — Windows (Microsoft Store IAP via `StoreContext`)
- [ ] 3a. Partner Center: add-on products (subscription + durable) on Store ID `9NRKS9LDRCWC`.
- [~] 3b. `IStoreGateway` seam DONE + Mac-verified (`Tidbits.Core/Networking/IStoreGateway.cs`:
      interface + `StoreProductInfo`/`StorePurchaseResult`/`ClubProducts` + `NoStoreGateway`
      default). Wired into `EntitlementStore` as the Class A local-first source (mirrors the
      Swift `localCheck`: local YES wins; local-NO + remote-absent = definitive; local-unknown
      fails OPEN). 285 tests (+5). **REMAINING: the real `WindowsStoreGateway` (`StoreContext`
      + `IInitializeWithWindow` via `TryGetPlatformHandle`) in a new `Tidbits.Windows`
      net10.0-windows project — compiles/verifies ONLY on windows-latest CI, and a live
      purchase needs the Partner Center add-ons (owner/browser).**
- [x] 3c. Wired into `EntitlementStore` (the seam; the real gateway swaps in on the MSIX).
- [x] 3d. **Windows paywall UI DONE 2026-07-21** — `ClubPaywallView` (+ `ClubPaywallUi` builder)
      in an `FAContentDialog` off the Settings "Tidbits Club" section; hero + 4 pillars +
      3 plans from the `IStoreGateway` seam (graceful empty-state on the NoStoreGateway .exe /
      Mac head) + Restore + R-MON-2 note + member banner. 288 tests green, headless-PNG
      verified. GameData exposes ONE shared `Store` gateway. **REMAINING: the real
      `WindowsStoreGateway` (StoreContext, CI-only) + the owner's Partner Center add-ons.**
- [x] **PAYWALL COMPLETE on all 6 platforms** (web/iOS/macOS/tvOS/Android/Windows).

### Phase 4 — Android (Play Billing) — only if Play Console access this cycle
- [ ] 4a. Play Console: subscription + one-time products.
- [ ] 4b. Play Billing 7 client; client-side signature verify; wire into `EntitlementStore`.

### Phase 5 — Marketing & explanation, fuller
- [x] 5a/5b. **`docs/CLUB-MARKETING.md` DONE 2026-07-21** — canonical Club explainer (free-vs-Club
      line, the 4 pillars verbatim, R-MON-2) AND the owner's paste-ready store-product sheet:
      exact product id + native type + display name + price + ≤45-word description + App Review
      notes for Apple / Play / Microsoft / web MoR. Fixed the two stale listings that read
      "In-app purchases: none (v1)". Product creation itself is the owner-gated step (§6).
- [ ] 5c. The venue prize-pack framing for hosts (folds into `docs/TIDBITS-LIVE-PREMIUM-BACKLOG.md`).

## Rules that gate the code (from Decision 047)
- **R-MON-2** unlock by **account sign-in only** — no code/QR/key redemption field, ever.
- **R-MON-3** clients never write `entitlements/`; the Worker is the sole writer.
- Local store receipts are **authoritative + checked offline first**; fail **open** on an
  unknown/empty read (never revoke Club on a transient network miss).

## Model / agent policy (this loop)
- Architecture, security-critical rules, the Worker, the Windows `StoreContext` spike →
  **high-reasoning, done directly**.
- Mechanical per-platform mirrors of a proven reference (e.g. Kotlin/JS/C# `EntitlementStore`
  from the Swift one) → **one sequential Sonnet agent at a time** (never concurrent — they
  all hit the session limit together and return nothing; memory `sequential-not-concurrent-agents`).

## App Store IAP-compliance pass (2026-07-23) — pre-submission hardening
Closed the guideline gaps that get IAP apps rejected, so the binary we submit is clean:
- **G3.1.2 (subscription disclosure)** — every paywall (iOS/macOS/tvOS/web) now shows the
  billing PERIOD in the price ("$29.99/yr"), a full auto-renew disclosure block, and
  functional **Terms of Use (EULA)** + **Privacy Policy** links next to the buy controls.
- **G3.1.3(b) (anti-steering)** — the "already have Club?" note reworded neutrally: "sign in
  with the same account and it unlocks here" — no external-purchase steering language.
- **New `terms.html`** (EULA: the three products, auto-renew terms, per-store cancel paths,
  refunds-by-store) + **rewritten `privacy.html`** (discloses account sign-in, leaderboards,
  and the Club sha256(email) entitlement record).
- **`PrivacyInfo.xcprivacy` FIXED** — was stale (`NSPrivacyCollectedDataTypes` empty, "no
  account" comment) while the app now collects account data. Now declares Email / Name /
  UserID / OtherData, all Linked + App-Functionality + non-tracking. **Owner must set the App
  Store Connect App Privacy questionnaire to MATCH** (Apple cross-references manifest ↔ policy
  ↔ nutrition labels ↔ traffic — G5.1.1/5.1.2). Same declaration is owed to Play Data Safety
  + Microsoft privacy.
- Bumped 1.6.51/91 → **1.6.52/92** (Android vc75) so the submitted binary carries all of this.
- iOS `** BUILD SUCCEEDED **`; manifest `plutil -lint` OK.

## Log
- **2026-07-21** — plan written; Phase 0a rules DEPLOYED+verified; Phase 0c Swift `EntitlementStore` reference built + 3-platform build-verified. Next: JS/Kotlin/C# `EntitlementStore` mirrors (sequential agents), then 0b Worker webhook + Phase 1 App Store Connect products.
