# Tidbits Club — the monetization build (running checklist)

**Status: BUILDING (started 2026-07-21).** The end-to-end plan to make Tidbits Club
**payable natively on every platform**, at $0 ongoing infra (Decision 047,
`docs/MONETIZATION.md`). This is the loop's source of truth — every iteration updates
it. Greenfield: no IAP code existed anywhere before this.

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
- [x] 0a. `entitlements/` RTDB rules — DEPLOYED + live-verified (client write DENIED, read denied to non-owner). 2026-07-21.
- [x] 0b. Worker `/entitlements/webhook` — DONE + deployed + live-verified. HMAC-verify MoR
      event → map to grant/revoke → write `entitlements/{key}` via Firebase-SA admin (RS256
      JWT in-Worker). 18 tests. Live: 503 when unconfigured (retryable, no silent purchase
      loss), 405 on GET, Apple callback unregressed. **OWNER: set `LEMONSQUEEZY_WEBHOOK_SECRET`
      + `FIREBASE_SA_EMAIL`/`FIREBASE_SA_PRIVATE_KEY`/`FIREBASE_DB_URL` once the MoR is chosen.**
- [~] 0c. `EntitlementStore` — **Swift Core reference + JS (web) DONE** (`Core/Networking/EntitlementStore.swift`: `isClub = local || remote`, fail-open, cached last-known-good; wired into the app entry + refresh at bootstrap; iOS/macOS/tvOS build-verified). Kotlin + C# mirrors NEXT (sequential agents). JS: `js/entitlement.js` (remote-only — web has no local store — cached, fail-open; wired at bootstrap + on identity change).
- [ ] 0d. A single `isClub` gate + a reusable "Club" upsell/paywall surface per platform.

### Phase 1 — Apple (StoreKit 2; iOS + iPadOS + macOS + tvOS via Universal Purchase)
- [ ] 1a. App Store Connect: subscription group + annual/monthly + non-consumable
      lifetime, prices, localizations. (Claude via browser.)
- [ ] 1b. `.storekit` config for local testing.
- [ ] 1c. StoreKit 2 client: products, purchase, `Transaction.currentEntitlements`,
      restore, fail-open grace. Wire into `EntitlementStore`.
- [ ] 1d. Mirror an Apple purchase into `entitlements/` (optional; web is the universal one).
- [ ] OWNER: Paid Apps Agreement + banking + tax; SBP enrolment.

### Phase 2 — Web (Merchant of Record) + the promo/marketing surface (rule 6)
- [ ] 2a. Promo-forward "Tidbits Club" section on the web app — sells without degrading
      the free experience (additive, never an interstitial).
- [ ] 2b. MoR checkout (Paddle/Lemon Squeezy hosted checkout or overlay).
- [ ] 2c. Worker webhook live (0b) → entitlement write → app lights up on sign-in.
- [ ] OWNER: choose + sign up for the MoR; set the Worker secrets.

### Phase 3 — Windows (Microsoft Store IAP via `StoreContext`)
- [ ] 3a. Partner Center: add-on products (subscription + durable) on Store ID `9NRKS9LDRCWC`.
- [ ] 3b. `IStoreGateway` in `Tidbits.Core` + `WindowsStoreGateway` behind the Win TFM
      (`StoreContext` + `IInitializeWithWindow` via `TryGetPlatformHandle`) + fake for tests.
      **Highest-risk item — no public Avalonia worked example; CI-only verifiable.**
- [ ] 3c. Wire into `EntitlementStore`.

### Phase 4 — Android (Play Billing) — only if Play Console access this cycle
- [ ] 4a. Play Console: subscription + one-time products.
- [ ] 4b. Play Billing 7 client; client-side signature verify; wire into `EntitlementStore`.

### Phase 5 — Marketing & explanation, fuller
- [ ] 5a. The "why Club / what you get" explainer (the six pillars, §4a), per platform idiom.
- [ ] 5b. Store listing copy for the Club (App Store / Play / MS Store subscription text).
- [ ] 5c. The venue prize-pack framing for hosts.

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

## Log
- **2026-07-21** — plan written; Phase 0a rules DEPLOYED+verified; Phase 0c Swift `EntitlementStore` reference built + 3-platform build-verified. Next: JS/Kotlin/C# `EntitlementStore` mirrors (sequential agents), then 0b Worker webhook + Phase 1 App Store Connect products.
