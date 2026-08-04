# Lemon Squeezy store review — reply pack

**Their ask (2026-08-04, Namratha):** pricing breakdown, a demo video, and a
specific description of what we sell — what it is, how it is made and licensed,
who it is for, and one-time vs subscription.

Everything below is written to be **pasted into a reply**. The demo video is at
`build/lemonsqueezy/tidbits-demo.mp4` (25s, 250 KB, 1280px) — attach it, or upload
it somewhere linkable and paste the URL where the draft says so.

Facts here were read off the live store and the live app on 2026-08-04, not from
memory: three products **Published**, store in **test mode**, application under
review, 0 sales.

---

## The reply (paste this)

> Hi Namratha,
>
> Thanks for the quick review. Details below, and I've attached a short demo
> video showing the product and the purchase surface.
>
> **What Tidbits Trivia is**
>
> Tidbits Trivia is a trivia game built by Learning is Change, Inc. It ships as a
> web app (tidbitstrivia.com) and as native apps for iPhone/iPad, Mac, Apple TV,
> Android and Windows. The game itself — every question, every mode, and the
> ability to host a trivia night — is **free forever**, with no ads and no
> account required.
>
> **What we sell**
>
> One digital product, "Tidbits Club", sold in three ways. It is a **feature tier
> inside our own software** — not a physical good, not a downloadable file, not a
> license we resell on anyone's behalf. It unlocks four features for players who
> want their play to accumulate into something:
>
> - **Ranked Seasons** — three-month competitive arcs
> - **Knowledge Atlas** — a map of what you actually know, by subject, over time
> - **Story Archive** — every fact you've learned, kept and searchable
> - **Expeditions** — multi-week themed campaigns
>
> **Pricing**
>
> | Product | Price | Type | Billing |
> |---|---|---|---|
> | Tidbits Club (Monthly) | $3.99 USD | Subscription | Auto-renews monthly, cancel anytime |
> | Tidbits Club (Yearly) | $29.99 USD | Subscription | Auto-renews annually, cancel anytime |
> | Tidbits Club — Founding Member | $79.99 USD | One-time | Lifetime access, does not renew |
>
> All prices are USD and shown inclusive of nothing else — there are no add-ons,
> no consumables, no in-game currency, and no upsells after purchase. The Founding
> Member tier is a launch-window offer.
>
> **How it's made**
>
> We build and operate all of it in-house. The app is our own code. The trivia
> questions are generated from **Wikipedia article content, which is licensed
> CC BY-SA**; we attribute Wikipedia in-app on every question's reveal screen and
> link back to the source article. No third-party paid content, no scraped
> commercial datasets, no user-generated marketplace.
>
> **Who it's for**
>
> People who already play the free game and want to track progress over months —
> pub-quiz regulars, trivia hobbyists, and teachers/parents using it as a
> learning tool. It is a general-audience product with no age-restricted or
> sensitive content.
>
> **How delivery and access work**
>
> Purchase is instant and entirely digital. There are no license keys or
> redemption codes: after checkout, the buyer signs in with the same email in any
> of our apps and the entitlement is applied to their account across every
> platform. That means a single purchase covers all six platforms rather than
> being tied to one device. Subscriptions can be cancelled at any time from the
> purchase-confirmation email or by contacting us; access continues to the end of
> the paid period.
>
> Happy to provide anything else that would help — test access, additional
> screens, or a walkthrough call.
>
> Best,
> Ben Wilkoff
> Learning is Change, Inc.

---

## Live facts backing the above (verified 2026-08-04)

| | |
|---|---|
| Store | `tidbits.lemonsqueezy.com` · Learning is Change, Inc. |
| Products | 3, all **Published** |
| Sales / revenue | 0 / $0.00 (nothing has been sold; store is in test mode) |
| Checkout URLs | wired into the shipped web app (`js/store.js` `CLUB.plans`) |
| Terms / Privacy | linked directly beneath the plans on the paywall |
| Renewal disclosure | shown on the paywall above the fold at purchase time |

The paywall already states, verbatim: *"Tidbits Club Monthly and Yearly are
auto-renewing subscriptions at the prices shown. Each renews automatically at the
end of its period unless you cancel first; cancel anytime from your
purchase-confirmation email. Founding Member is a one-time purchase for lifetime
access — it does not renew."* That is the disclosure MoRs usually ask for next, so
it is worth mentioning if they follow up.

---

## What the demo video shows

`build/lemonsqueezy/tidbits-demo.mp4` — recorded against the **live production
site**, not a mockup:

1. First-run walkthrough (play → learn → compete)
2. The free game: a Daily question with four options
3. Answering it — the correct answer, plus the teaching reveal and the Wikipedia
   source link
4. The Tidbits Club page: the four features, all three prices, the renewal
   disclosure, and the Terms/Privacy links

It is a screen walkthrough assembled from real interaction frames rather than a
narrated product film. If they want narration or a longer cut, the same path is
easy to re-record.

---

## The integration is now live end to end (2026-08-04)

Done while assembling this, so the answer to "does it work" is measured rather
than promised:

- **Webhook created** in Lemon Squeezy → `https://tidbits-auth.benwilkoff.workers.dev/entitlements/webhook`,
  subscribed to `order_created` + all 12 `subscription_*` events — exactly the set
  `workers/tidbits-auth/src/entitlements.js` handles, nothing more.
- **`LEMONSQUEEZY_WEBHOOK_SECRET` set** on the Worker to match. (LS caps the
  signing secret at **40 characters** — a 48-char hex string is rejected. 20 bytes
  of hex fits exactly.)
- **Proved with a signed request:** a real HMAC-signed `order_created` payload
  returned **HTTP 200 `ok`**, and the entitlement landed in RTDB as
  `{"tier":"club","sources":["web"],"ver":1}`. The test record was then deleted.
- Reading that record anonymously returns **Permission denied** — which is the
  rule working: entitlements are readable only by their email-verified owner.

**One gotcha worth knowing:** right after `wrangler secret put`, the probe flaps
between 503 and 401 for ~20 seconds as Cloudflare rolls the new version across the
edge. A single 503 immediately after setting a secret is propagation, not a fault.

**`order_refunded` is now subscribed** (2026-08-04) — the webhook listens for
**14 events**, verified after a fresh page load, and the Worker revokes on it.
That closes the "a refunded lifetime purchase keeps access forever" hole.

**Still open on the money path:** the store is in **test mode** pending their
review, so nothing can be charged for real yet. Note that Lemon Squeezy scopes
webhooks **per mode** — the banner says outright that these only fire for
test-mode data. Re-check that the endpoint and all 14 events exist in **live**
mode the moment the application is approved, or the first real purchase will
grant nothing.

## Not yet answered, if they push further

- **Refund policy** — we have not published one. Lemon Squeezy's default MoR terms
  apply unless we state otherwise; worth deciding before launch.
- **Support contact** — `support.html` ships on the site; make sure the address on
  it is monitored.
- **Test access** — reviewers sometimes ask to try the paid tier. The cleanest
  answer is a test-mode purchase, which works today.
