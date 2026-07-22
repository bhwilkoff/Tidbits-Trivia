# Tidbits Club — Marketing & Store-Product Copy

**Single source of truth for how Tidbits Club is explained and sold on every
platform.** This is both the marketing narrative and the *fill-in-the-blanks
sheet* for creating the store products. Every store's product name, description,
and price is here with its exact product id — so creating the products (the one
owner-gated step) is copy-paste, not authoring.

Ties to: `docs/MONETIZATION.md` (the strategy, Decision 047), the in-app paywall
views (`ClubPaywallView*.swift`, `js/app.js` `#/club`), and `js/store.js`
`CLUB`. Keep the pitch/pillars/prices in lockstep with `js/store.js` — that file
is the runtime copy; this doc is the store-and-marketing copy. If they drift, the
bug is here or there, not in both.

---

## 0. The one-sentence promise

> **Ranked seasons, a map of everything you know, and a library of every fact
> you've learned.**

Hosting is free forever. Club is for the *player* — the person who wants their
knowledge to accumulate into something.

---

## 1. What's free vs. what's Club

The free/Club line is a **promise**, not a paywall retrofit. Nothing that is free
today becomes paid (there are no existing users to take features from — we
haven't launched; see MONETIZATION R-MON-1).

| Free forever | Tidbits Club |
|---|---|
| The whole trivia game — every mode, every category, 115k+ questions | **Ranked Seasons** — three-month competitive arcs, your live pub nights included |
| Daily Tidbit + Daily Six, streaks | **Knowledge Atlas** — accuracy by domain & sub-domain, over time |
| Hosting a Trivia Night / Tidbits Live (the whole host library) | **Story Archive** — every "story behind the answer," kept forever & searchable |
| Personal records, topic levels, the pie | **Expeditions** — multi-week campaigns that turn a session game into a pursuit |
| Portable identity, cross-device sync, friends, duels | A **Founding Member** badge on your shared profile (lifetime buyers) |

**The rule that governs the whole thing (R-MON-2):** Club unlocks by *account
sign-in only* — never a code, key, coupon, or QR field. Buy on any platform, sign
in anywhere, you're Club everywhere. (This is also App Store 3.1.1 compliance —
no license-key mechanisms.)

---

## 2. The four pillars (the marketing beats)

Use these verbatim in listings, the paywall, and press. Order is deliberate:
two *play* reasons, two *keep* reasons.

1. **🏆 Ranked Seasons** — A calendar-driven climb — and your live pub nights
   count too. *The only feature that creates a recurring, calendar-driven reason
   to return, and the only one that ties solo play to live nights under one
   identity.*
2. **🗺️ Knowledge Atlas** — A map of what you actually know, by domain, over
   time. *The flagship "what do I actually know."*
3. **📚 Story Archive** — Every fact you've learned, kept forever and searchable.
   *The most on-brand idea we have: the fact you learned is yours to keep.*
4. **🧭 Expeditions** — Multi-week campaigns that turn a session game into a
   pursuit. *The substantial new gameplay — a pursuit, not a session.*

---

## 3. The products (identical set on every store)

One entitlement — **`club`** — granted by *any* of these. Same three products
everywhere; each store's native product type differs.

| Product | Price (USD) | Type | Notes |
|---|---|---|---|
| **Founding Member** | **$79.99** | one-time (non-consumable / durable) | Lifetime. **Launch window only — first 90 days.** Carries the Founding Member badge. |
| **Tidbits Club (Annual)** | **$29.99 / yr** | auto-renewing subscription | Best value. The default highlighted plan. |
| **Tidbits Club (Monthly)** | **$3.99 / mo** | auto-renewing subscription | The low-commitment entry. |

Apple subscriptions (annual + monthly) share **one subscription group** so a user
can only hold one and can cross-grade. Lifetime is a separate non-consumable.
Family Sharing is ON for all three.

---

## 4. Per-store product copy (paste-ready)

> Prices below are the US tier; each store auto-generates other currencies. Set
> the US price to the exact value and accept the store's generated matrix.

### 4a. Apple — App Store Connect → Features → In-App Purchases / Subscriptions

**Universal Purchase** — create these ONCE on the shared app record; they apply
to iOS, iPadOS, macOS, and tvOS automatically. Bundle id
`com.learningischange.tidbitstrivia`.

| Field | Founding Member | Club Annual | Club Monthly |
|---|---|---|---|
| **Reference Name** (internal) | Tidbits Club — Founding Member | Tidbits Club — Annual | Tidbits Club — Monthly |
| **Product ID** | `com.learningischange.tidbitstrivia.club.lifetime` | `com.learningischange.tidbitstrivia.club.annual` | `com.learningischange.tidbitstrivia.club.monthly` |
| **Type** | Non-Consumable | Auto-Renewable Subscription | Auto-Renewable Subscription |
| **Subscription Group** | — | `Tidbits Club` | `Tidbits Club` |
| **Display Name** | Founding Member (Lifetime) | Tidbits Club (Yearly) | Tidbits Club (Monthly) |
| **Price** | $79.99 | $29.99 | $3.99 |

**Description (all three, ≤45 words — App Store shows this on the product):**
> Tidbits Club unlocks Ranked Seasons, the Knowledge Atlas, the Story Archive, and
> Expeditions — the ways your trivia becomes a pursuit and everything you learn is
> kept forever. Hosting and the full game stay free.

**Founding Member description tail:** append *"Lifetime access. Founding Member
badge. Available in the launch window only."*

**App Review notes (paste into each product's Review Information):**
> Club is a cosmetic + content entitlement that unlocks Ranked Seasons, Knowledge
> Atlas, Story Archive, and Expeditions. It is unlocked by account sign-in only —
> there is no code/key entry field anywhere in the app (App Store 3.1.1). A web
> purchase, if made, is honored by signing into the same account. To test: sign in,
> open Profile → Join Tidbits Club, purchase in the StoreKit sandbox.

**Screenshot for review:** the paywall (`ClubPaywallView`) — Profile → "Join
Tidbits Club."

### 4b. Google Play — Play Console → Monetize → Products

Two **Subscriptions** (each with one base plan) + one **In-app product**:

| Field | Founding Member | Club Annual | Club Monthly |
|---|---|---|---|
| **Product / Subscription ID** | `club_lifetime` | `club_annual` | `club_monthly` |
| **Base plan ID** | — (in-app product) | `annual-autorenew` | `monthly-autorenew` |
| **Type** | In-app product (one-time) | Subscription | Subscription |
| **Name** | Founding Member (Lifetime) | Tidbits Club (Yearly) | Tidbits Club (Monthly) |
| **Billing period** | — | Yearly | Monthly |
| **Price** | $79.99 | $29.99 | $3.99 |

**Description (Play, ≤80 chars name-adjacent blurb + full):** same paragraph as
Apple §4a. Play groups subscriptions — set both base plans' *renewal type* to
auto-renewing and *grace period* to Play's default.

### 4c. Microsoft Store — Partner Center → Store ID `9NRKS9LDRCWC` → Add-ons

Three **add-ons** (Store add-on = IAP). Product ids as the app reads them
(`ClubProducts` in `Tidbits.Core/Networking/IStoreGateway.cs`):

| Field | Founding Member | Club Annual | Club Monthly |
|---|---|---|---|
| **Product ID (in-app)** | `club.lifetime` | `club.annual` | `club.monthly` |
| **Add-on type** | Durable | Subscription | Subscription |
| **Subscription period** | — | Annual | Monthly |
| **Title** | Founding Member (Lifetime) | Tidbits Club (Yearly) | Tidbits Club (Monthly) |
| **Price** | $79.99 | $29.99 | $3.99 |

**Note:** Store subscription add-ons require the base app to already be in the
Store (it is — first submission in certification). Create these after the app is
published so the add-on associates with a live product.

### 4d. Web — Merchant of Record checkout (owner-created; see §6)

The web app has no native store, so web purchases go through a Merchant of Record
(Paddle or Lemon Squeezy — owner decision). Each plan's `checkout` URL in
`js/store.js` `CLUB.plans` is filled in with the MoR-hosted checkout link. On a
successful purchase the MoR fires an HMAC-signed webhook to the Cloudflare Worker
(`/entitlements/webhook`), which writes `entitlements/{sha256(email)}` — and the
buyer is Club everywhere they sign in.

| Plan | `js/store.js` id | MoR product to create |
|---|---|---|
| Founding Member | `lifetime` | one-time, $79.99 |
| Annual | `annual` | subscription, $29.99/yr |
| Monthly | `monthly` | subscription, $3.99/mo |

---

## 5. Store-listing "In-App Purchases" section (replaces the stale "none")

`docs/app-store-listing.md` and `docs/play-store-listing.md` currently say
"In-app purchases: none (v1)." Update both to:

> **Price:** Free · **In-app purchases:** Tidbits Club — $3.99/mo, $29.99/yr, or
> $79.99 lifetime (Founding Member). Hosting and the full trivia game are free.

And add a listing paragraph (App Store "Promotional Text" / Play "short
description" candidate):

> Play free forever. Or join **Tidbits Club** for Ranked Seasons, a Knowledge
> Atlas of everything you know, a Story Archive of every fact you've learned, and
> multi-week Expeditions. Buy once, on any device — you're a member everywhere.

---

## 6. Owner-only steps (the financial line — Claude cannot cross it)

Everything above is authored and ready. These steps require the owner because
they involve financial/banking/legal identity and must never be automated:

- [ ] **Apple:** sign the **Paid Applications Agreement**; complete banking + tax
  in App Store Connect → Business. *Then* create the three products from §4a.
- [ ] **Google Play:** set up a **payments profile** (merchant account); then
  create the products from §4b.
- [ ] **Microsoft:** the Partner Center account already exists; create the three
  add-ons from §4c after the app is published. (No banking blocker for creating
  them; payout profile needed before first payout.)
- [ ] **Web:** sign up for a **Merchant of Record** (Paddle or Lemon Squeezy) —
  this is a banking relationship. Create the three products from §4d, copy the
  checkout URLs into `js/store.js`, set the Worker's
  `LEMONSQUEEZY_WEBHOOK_SECRET` (or Paddle equivalent) + Firebase admin secrets.

Once the products exist, the code already wired on every platform reads them and
grants Club — no further engineering to "turn it on."
