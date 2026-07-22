# Tidbits Club — Owner Go-Live Playbook

**What this is:** the short list of tasks **only you can do** to turn on Tidbits
Club monetization across all platforms. Everything else (client code, the
entitlement Worker, RTDB rules, paywalls, product *definitions*) is already built
and wired. **Once the products below exist, Club lights up on sign-in with no
further engineering.**

**Why only you:** every task here involves a **financial, banking, tax, or legal
identity** — signing agreements, entering bank/card details, or accepting a
Merchant-of-Record relationship. By policy Claude will not cross that line.

**The model (context):** hosting is free forever; players pay. One entitlement —
`tier: "club"` — is granted by ANY of the products below. Prices are the same
everywhere: **$3.99/mo · $29.99/yr · $79.99 lifetime** (Founding Member —
**first 90 days only**). Full rationale: `docs/MONETIZATION.md` (Decision 047).
Exact store-listing copy + review notes: `docs/CLUB-MARKETING.md`.

---

## Critical path (do these in order)

The fastest route to "a player can pay on at least one platform":

1. **Apple → enroll in the Small Business Program** (free, ~15-min form). It
   halves your commission (15%→ effectively lower first-year) and there's no
   reason to wait. Do this first because activation takes a few days.
2. **Pick ONE platform to launch first.** Web (Merchant of Record) is usually the
   fastest to stand up and has the best margin, but Apple reaches the most users.
   You don't need all four live at once — each is independent.
3. **Sign that platform's financial agreement + banking/tax.**
4. **Create the three products** with the EXACT ids in the tables below.
5. **(Web only) set the Worker secrets** so purchases grant entitlements.
6. **Verify** with the checklist at the bottom, then ship the build.

> ⚠️ **Dependency to know:** on Apple you **cannot create the in-app purchases
> until the Paid Applications Agreement is signed** — App Store Connect hides the
> IAP section until then. Sign first, then create.

---

## 1. Apple (App Store Connect) — iOS · iPadOS · macOS · tvOS

One set of products covers all four Apple platforms (Universal Purchase).

- [ ] **Enroll in the Apple Small Business Program** (App Store Connect →
      Agreements). Free. Do it now.
- [ ] **Sign the Paid Applications Agreement**; complete **banking + tax** (ASC →
      Business). *IAP creation is gated on this.*
- [ ] **Create the three products** (ASC → your app → In-App Purchases /
      Subscriptions), ids EXACTLY:

| Plan | Product ID | Type |
|---|---|---|
| Founding Member (lifetime) | `com.learningischange.tidbitstrivia.club.lifetime` | Non-consumable |
| Annual | `com.learningischange.tidbitstrivia.club.annual` | Auto-renewable subscription |
| Monthly | `com.learningischange.tidbitstrivia.club.monthly` | Auto-renewable subscription |

  - Put **annual + monthly in ONE subscription group** (so upgrade/downgrade
    works); lifetime is a separate non-consumable.
  - Prices: $79.99 / $29.99 / $3.99. Mark the products **Family Shareable**.
  - Paste the display names + descriptions + review notes from
    `docs/CLUB-MARKETING.md §4a`.
- [ ] Submit the IAPs for review **with an app build** (Apple reviews the first
      IAP alongside a binary). The StoreKit purchase code is already shipped.

---

## 2. Google Play (Play Console)

- [ ] Set up a **payments profile / merchant account** (Play Console → Setup →
      Payments profile) — banking + tax.
- [ ] **Create the products** (Monetize → Products), ids EXACTLY:

| Plan | Product ID | Type |
|---|---|---|
| Founding Member (lifetime) | `club_lifetime` | One-time product (in-app) |
| Annual | `club_annual` | Subscription — base plan **annual**, auto-renewing |
| Monthly | `club_monthly` | Subscription — base plan **monthly**, auto-renewing |

  - Prices $79.99 / $29.99 / $3.99. Copy listing text from `CLUB-MARKETING.md §4b`.
  - The Play Billing client (acknowledge-not-consume) is already shipped.

---

## 3. Microsoft Store (Partner Center) — Store ID `9NRKS9LDRCWC`

The account + first app submission already exist. Add-ons can be created now;
a **payout profile** is only needed before your first payout, not to create them.

- [ ] **Create three add-ons** (Partner Center → your app → Add-ons), Product IDs:

| Plan | Product ID (in-app) | Type |
|---|---|---|
| Founding Member (lifetime) | `club.lifetime` | Durable |
| Annual | `club.annual` | Subscription |
| Monthly | `club.monthly` | Subscription |

  - Prices $79.99 / $29.99 / $3.99. Listing text: `CLUB-MARKETING.md §4c`.
- [ ] Complete the **payout + tax profile** before the first payout.

> Note: the real Windows `StoreContext` purchase gateway is the one remaining
> code item, deliberately deferred until these add-ons exist (it can only be
> verified against real Partner Center products). Ping to have it finished once
> the add-ons are live — it's a small, well-scoped piece.

---

## 4. Web (Merchant of Record) — the fastest margin, needs a signup

The web app has no native store, so web purchases run through a **Merchant of
Record** (they handle sales tax/VAT worldwide — this is a banking relationship).

- [ ] **Choose + sign up: Paddle or Lemon Squeezy.** (Either works; the Worker
      webhook is written for the Lemon Squeezy event shape by default — tell me if
      you pick Paddle and I'll adjust the mapping.)
- [ ] **Create three products** there (`lifetime` $79.99 one-time, `annual`
      $29.99/yr, `monthly` $3.99/mo) — `CLUB-MARKETING.md §4d`.
- [ ] **Copy each product's hosted-checkout URL** into the `CLUB` config in
      `js/store.js` (one `checkout` URL per plan). *(This one line-edit I can do
      for you once you have the URLs — just paste them.)*
- [ ] **Set the Worker secrets** (Cloudflare dashboard → the `tidbits-auth`
      Worker → Settings → Variables, or `wrangler secret put`):
  - `LEMONSQUEEZY_WEBHOOK_SECRET` (or the Paddle equivalent) — the signing secret
    from the MoR, so the Worker can verify purchase webhooks.
  - `FIREBASE_SA_EMAIL`, `FIREBASE_SA_PRIVATE_KEY`, `FIREBASE_DB_URL` — the
    Firebase service-account creds so the Worker can write `entitlements/`.
- [ ] In the MoR dashboard, point the **webhook** at the Worker's
      `/entitlements/webhook` endpoint.

---

## 5. Flip the switch — verification (any platform)

After a platform's products exist and (web) the secrets are set:

- [ ] Buy the monthly plan on a **real account** on that platform.
- [ ] Confirm the app shows **Club active** after the purchase / on next sign-in.
- [ ] Sign in with the **same account on a different device/platform** → Club
      should carry over (native store receipt on that ecosystem; web purchase via
      the `entitlements/{email}` record everywhere).
- [ ] Confirm a **non-member** still sees every Club feature's *preview* + the
      paywall — never a blank wall (that's the design; report anything that nags).

Once one platform verifies end-to-end, repeat §1–4 for the others at your pace.

---

## What you do NOT need to do

- Write or change any app code, the Worker, or the RTDB rules — all shipped.
- Create the paywall UI or the product marketing copy — done (`CLUB-MARKETING.md`).
- Gate features or "turn on" Club in code — it reads the store products live.
- Redeem-code / key fields — there are none by design (App Store rule 3.1.1;
  entitlement unlocks by **account sign-in only**).

**Reminder on the philosophy (so listings stay on-brand):** we are not upselling.
Every gated feature shows a real preview and a genuine reason to join — never a
wall on core play. Keep that tone in any store copy you edit.
