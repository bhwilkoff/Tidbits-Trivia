# Tidbits Trivia — Monetization Strategy

**Status: ADOPTED — owner decisions made 2026-07-19 (§8). Decision 047.** Authored 2026-07-19 from two
research passes: a pricing-landscape survey of ~35 consumer trivia apps, host
tools, and venue networks; and a six-platform IAP/legal mechanics pass. Supersedes
the "decide the paywall later" posture in `docs/TIDBITS-LIVE-PREMIUM-BACKLOG.md`
§Strategy (which was correct at the time — the features now exist, so the decision
is live). Companion: `docs/EVENT-TRIVIA-COMPETITIVE.md` (market map).

Governed by the eight owner rules stated 2026-07-19. Each section names the rule
it serves.

---

## 1. The structural gap (rule 4)

Every vendor in the category monetizes **exactly one side of the room.**

| Who pays | Who charges them | Axis |
|---|---|---|
| The player | Trivia Crack, Trivia Star, Sway, Quizzland, Sporcle app, NYT | lives/energy, or time-based sub |
| The host / venue | Crowdpurr, Kahoot, Slido, AhaSlides, Quizado, Trivnow, Water Cooler | participant cap, host seats, events/mo, venue count |
| The venue (full service) | Sporcle Live, Geeks Who Drink, King Trivia, Buzztime | per night, per attendee, tablet count |

**Nobody bridges them.** The tell is Sporcle: the only company owning both a
consumer trivia subscription ($3.99/mo) *and* a national bar-trivia network
($3/player/night) — run as two unconnected businesses. Players at a Sporcle Live
bar play free and are never converted into app subscribers.

A 40-person bar night is **40 qualified installs of a trivia app**, delivered by
someone who is already paying a human $200 to make those people play trivia. No
one captures this.

### The economic fact that decides our model

- Venues pay hosts **$150–250/night**; venues **make $2,000–4,000** off a trivia night.
- A documented NYC P&L: $175 event fee → **$340 net profit** on ~40 players.
- Therefore **the software is a rounding error against the labor** — a $79/mo pack
  subscription is ~4% of what a venue spends on hosting.

**Conclusion: charging for host software is capturing the least valuable, most
price-resented 4% of the transaction.** The complaint quotes cluster exactly
there ("wildly overpriced" — Kahoot; "$149 and I've not seen the value" —
Crowdpurr; "price gouging" — Wayground).

---

## 2. The model (rules 4, 5, 8)

> ### Hosting is free. Forever. Unlimited players.
> ### Tidbits Club is for players — $29.99/yr.
> ### Venues buy Club passes in bulk and give them away as prizes.

Three sentences. That is the whole model (rule 5).

**Why this is defensible, not just cheap:** giving the host tool away costs us
~$0 (Firebase Spark + GitHub Pages, §5) while deleting the entire revenue basis
of Crowdpurr, Kahoot, Quizado, Trivnow, Slido, and AhaSlides. They cannot follow
us — host software *is* their business. For us it is customer acquisition. Every
night a host runs is 40 people installing a trivia app and creating an identity.

**Why the venue still pays us — and is happy to.** Not a software fee. A **prize
budget**. Venues already buy prizes (bar tabs, gift cards, merch). A Club pass is
a better prize than a $10 tab: it costs the venue less, it lasts a year, and it
brings the winner back next week with a standing to defend. The host's spend is
denominated in **player value, not software seats** — a line item venues already
have and never resent.

This is the two-sided axis nobody occupies (rule 4).

### What it is NOT

- ❌ Not a participant cap. The near-universal formula, and the most complained about.
- ❌ Not per-host-seat. Where the "wildly overpriced" quotes concentrate — a bar
  with two rotating emcees pays double for one weekly night.
- ❌ Not per-event credits. Nickel-and-dimes the occasional host.
- ❌ Not lives / energy / consumables. The highest user-hatred-per-dollar model
  in the category, and it fails rule 1 outright.

---

## 3. What is free forever (rule 1)

**R-MON-1 — the free tier is never reduced.** Nothing currently free may move
behind the paywall, ever. Premium is only ever *newly built* value.

> **Why:** Sporcle's defining complaint is that previously-free stats went behind
> a subscription. That single act generates more anger than the price. We are
> structurally exposed to this because ~everything is already shipped free.

Free forever, on every platform:

- **Daily Tidbits** and the daily archive
- **All game modes** — Quick Play, Closest Call, Ordering, Stake, Versus CPU
- **Records, streaks, personal bests, per-game answer detail**
- **Creating quizzes**, pass-and-play, local Trivia Night
- **Hosting Tidbits Live** — unlimited players, unlimited events, unlimited venues,
  every round type, big screen, tie-break engine, offline + printable fallback
- **Joining any event**, from any platform, with no account
- **Online Quick Match, duels, friends, cross-venue standings** (all shipped free)

This is the NYT Games shape: **Wordle stays free forever; the archive and the
depth are the subscription.** NYT and Sporcle are the two vendors in the entire
survey with pure time-based pricing and the least pricing rage — and NYT's
free-forever core is why.

---

## 4. What Tidbits Club is (rules 1, 5, 8)

**Club is "get better," not "play more."** It never gates play; it adds a layer
that only means something if you play a lot. This is the learning charter as a
business model — the premium tier is literally the *learning* tier.

Because of R-MON-1, **every one of these must be newly built before go-live.**
None may be carved out of what ships free today.

| Club feature | Why it's worth paying for | Charter fit |
|---|---|---|
| **Knowledge map** — your accuracy by domain over time, and what it's doing | The "am I actually getting smarter" answer no trivia app gives | Deepens understanding |
| **Practice your misses** — spaced repetition over questions you got wrong | Turns a game into a study tool; nobody in the category does this | Invites engagement |
| **Season pass** — ranked seasons with placement, history, defendable titles | Ongoing reason to return; ties directly to live nights | Human agency |
| **Story archive** — keep every "story behind the answer" you've unlocked, searchable | The tidbit *is* the product; make it accumulate | Deepens understanding |
| **Host library** — your personal question bank, reuse + avoid-repeats intelligence | The one host feature worth charging for: *their own accumulated craft* | Supports craft |

Note the last row: hosting is free, but a host's **own accumulated work** is Club.
That is the honest line — we give away the tool and charge for the continuity,
on both sides of the room. Same product, same price, one identity.

### Price (decided 2026-07-19)

**$29.99/yr, or $3.99/mo.** One price, one entitlement, six platforms.

- Below NYT Games ($39.99–50/yr) and Sporcle in-app ($59.99/yr).
- **Venue pack: 10 Club passes for $99** (~$10/pass vs $29.99 retail). Cheaper
  per night than every host tool in §1, and it's a prize, not a fee.

### Founding Member lifetime — $79.99, launch window only

Owner decision: ship a lifetime unlock **alongside** the subscription. The risk
is real and named — a lifetime tier cannibalizes exactly the committed users
worth the most over time, which cuts against rule 8. Three constraints keep that
contained, and they are **part of the decision, not optional polish**:

1. **Genuinely time-limited.** Available for the first **90 days** after go-live,
   then withdrawn and never re-offered. If it is ever brought back, it stops
   being a launch instrument and becomes the default price of the product.
2. **Priced at $79.99, not $59.99** — a ~2.7-year breakeven against the annual.
   Buyers past that point are a loss only if they'd otherwise have stayed
   subscribed longer, and at 2.7 years they are the most committed cohort anyway.
3. **Carries a Founding Member badge** on the shared profile. Identity value
   costs us $0 and is a large part of what the cohort is actually buying.

**Mechanically the cheapest thing in the plan.** A non-consumable is exactly what
Apple's Universal Purchase restores across iOS/iPadOS/macOS/tvOS for free, and it
is the one product shape that needs no renewal state machine. Shipping it at
launch also de-risks the subscription: if renewal handling proves fiddly at $0,
the lifetime path is already proven and live.

**Review at day 90.** If lifetime take-up dominates annual, that is evidence the
annual price is wrong, not that lifetime should continue.

---

## 5. Cost to run: $0 ongoing (rule 3)

| Component | Cost | Ceiling behavior |
|---|---|---|
| Firebase RTDB (Spark) | $0 | Hard-stops, never bills |
| Cloudflare Worker (webhook → entitlement) | $0 | 100k req/day, no card |
| Merchant of Record (Paddle / Lemon Squeezy) | $0 base, 5% + $0.50/sale | Purely variable |
| GitHub Pages | $0 | — |
| Microsoft Partner Center | $0 | Registration fee removed 2025 |

**Fixed ongoing cost: $99/yr — the Apple Developer membership already carried.**
Everything else is $0 or purely variable. No metered service is ever enabled
(no Firebase Blaze), consistent with the standing guardrail.

---

## 6. Payments per platform (rule 2)

### The two rules that constrain everything

**Apple Guideline 3.1.3(b)** permits unlocking a purchase made on your website —
*"provided those items are also available as in-app purchases within the app."*
There is no compliant "web-only, apps just unlock it" model. **StoreKit IAP is
mandatory on iOS/macOS/tvOS.**

**Apple Guideline 3.1.1** bans unlocking via *"license keys, augmented reality
markers, QR codes, cryptocurrencies…"* — so:

**R-MON-2 — entitlement is unlocked by account sign-in only.** Never a code,
key, coupon, voucher, or QR the user redeems in-app.

> **Why:** 3.1.1 explicitly prohibits those mechanisms. Our `sha256(verified
> email)` identity spine is already the compliant shape; the risk is someone
> later adding a well-meaning "have a code? paste it here" field and converting
> a compliant app into a rejection.
>
> **How to apply:** venue prize passes are redeemed by **signing in**, not by
> typing a code. The venue assigns a pass to an email; the player signs in and
> it's simply there.

### Fees and mechanics

| Platform | Mechanism | Fee | Notes |
|---|---|---|---|
| iOS / iPadOS / macOS / tvOS | StoreKit 2, **required** | 15% (Small Business Program) | **Universal Purchase = all four are one platform.** Same bundle ID, one IAP product, restores across all. Zero extra work. |
| Android | Play Billing | **10%** service + 5% billing = 15% | Play's base is now the lowest of the three. Consumption-only is *explicitly allowed* — Play does not require us to sell IAP at all. |
| Windows | Microsoft Store IAP, **required** | 12% | Product type is **Game** (verified: Store ID `9NRKS9LDRCWC`, "MSIX or PWA game"). Policy 10.8.1 forces MS commerce and **forbids link-out**. |
| Web | Merchant of Record | 5% + $0.50 | Best margin by far. MoR handles EU VAT / US nexus — worth ~2pts over raw Stripe to avoid filing in ~45 states. |

**Apple Small Business Program: enroll now.** Free, takes effect 15 days after
fiscal-month approval, and turns year-one subscription commission from 30% → 15%.
There is no reason to wait for a product.

**Do not model margin on the US link-out staying at 0%.** It is a live litigation
artifact — SCOTUS granted cert June 2026, argument Oct–Dec 2026, ruling ~June 2027.
Treat today's 0% as upside, assume it reverts to 12–27%.

---

## 7. Entitlement architecture (rules 2, 3)

Verified in code: RTDB rules already enforce `auth.token.email_verified === true`
plus an `emailOwners/{key}` ownership proof. The `sha256(verified email)` spine is
enforced **server-side by rules**, not merely client-side. Entitlement rides it.

**Two classes of entitlement, and they must not be treated alike:**

**Class A — locally provable, authoritative, works offline.** StoreKit 2
(`Transaction.currentEntitlements`, JWS-verified on device), Play (RSA-signed
`Purchase`), Microsoft (`StoreContext`). Each store cryptographically attests the
purchase to the device. *If the local store says entitled, you are entitled* —
never gate this behind a network read.

**Class B — remote assertion, needs a trusted writer.** The web purchase. The
device has no proof, only a claim in a database.

```
isEntitled = localStoreEntitlement        // Class A — offline, authoritative
          || remoteEntitlement(myHash)    // Class B — requires verified sign-in
```

**R-MON-3 — clients never write to `entitlements/`.** A Cloudflare Worker
(holding the MoR webhook secret + a Firebase admin credential) is the sole writer.

> **Why:** `players/{key}` is world-readable and owner-writable by design — it's
> a game profile. An `isPro` flag written by the client is trivially forged by
> anyone with the RTDB URL. `entitlements/` needs `".write": false` for every
> client and read scoped to the requesting hash.

```
entitlements/{sha256(email)} = { tier, sources: ["web","apple","play","msstore"], since, ver }
```

**Cross-store mirroring: don't, at first.** Each store's purchase unlocks its own
ecosystem (Apple's universal purchase already covers four platforms); the **web
purchase is the universal one**. This is clean, secure, and an honest incentive:
*buy on the web, get everything* — which is also our best margin. Revisit only if
users actually ask.

**Family Sharing caveat:** if enabled, one Apple purchase entitles up to 6 people.
Either accept it (generous, on-brand) or gate the mirror on
`transaction.ownershipType == .purchased`. Decide before shipping.

**Fraud, honestly:** account sharing is the only leak that matters at scale, and
every no-server product accepts it. Chasing it costs more than it saves and makes
the product worse for honest households. Signature forgery is infeasible; binary
patching on rooted devices costs one sale from someone who was never paying.

---

## 8. Decisions — 2026-07-19

*Items 1–3 are owner decisions. Items 4–5 are defaults chosen by Claude to
unblock the build; both are cheap to reverse and flagged for owner review.*

1. **Hosting is free forever, unconditional.** ✅ No player cap, no event cap, no
   venue cap, no future "Pro host" tier. This is load-bearing: it is what
   competitors structurally cannot match, because host software *is* their
   business. Treat any later proposal to gate a hosting feature as a violation of
   this decision, not a pricing tweak.
2. **Price: $29.99/yr or $3.99/mo; venue pack 10 passes for $99.** ✅ The venue
   frame is a **prize budget**, not a software fee.
3. **Ship BOTH a subscription and a Founding Member lifetime ($79.99).** ✅ Owner
   chose both over the recommended subscription-only. The cannibalization risk is
   accepted and mitigated by three binding constraints — 90-day window, $79.99
   (not $59.99), Founding Member badge — see §4. **Day-90 review is part of the
   decision.**
4. **Windows stays categorized as a Game.** ⚙️ *Claude's default.* Follows from
   the owner's launch sequencing (build Windows sign-in, then ship all six with
   IAP) — re-categorizing would be a separate fight. 12% and no link-out accepted.
   **Owner review:** the non-game path keeps 100% and allows link-out, so if the
   Avalonia `StoreContext` spike fails, re-categorization becomes the fallback
   *and* a margin win. Worth 30 minutes before the spike, not after.
5. **Family Sharing: ON.** ⚙️ *Claude's default.* Consistent with rule 1 and the
   household framing — a trivia app is played with the people you live with. Cost
   is bounded (up to 6 people per Apple purchase); goodwill likely exceeds the
   leak. **Owner review:** turning it on later is easy; turning it *off* after
   launch takes an entitlement away from real families and would violate the
   spirit of R-MON-1. So this is the one default here that hardens on ship.

---

## 9. Go-live blockers (rule 7)

**Owner decision 2026-07-19: build Windows sign-in FIRST, then launch all six
simultaneously.** Rule 7 is honored in full — no platform ships the paywall
before the others. The consequence is that Windows sets the launch date, so #1
and #3 below are the critical path and should start first.

In dependency order:

| # | Blocker | Why it blocks |
|---|---|---|
| 1 | **Windows has no sign-in** — `PlayerIdentityStore.cs` is local-only ("sync/sign-in layer on top later") | Windows cannot resolve an email-keyed entitlement. Hard blocker. |
| 2 | **Build the five Club features** (§4) | R-MON-1 forbids carving premium out of the free tier, and ~everything is already free. Without new features there is nothing to sell. |
| 3 | **`Tidbits.Windows` IAP spike** — Avalonia + MSIX + `StoreContext` + `IInitializeWithWindow` via `TryGetPlatformHandle` | Every piece is documented; the *composition* has no public worked example. Cannot be validated on the Mac head (Decision 045). Highest-risk item in the plan. |
| 4 | Cloudflare Worker + MoR + `entitlements/` rules | Class B path (§7) |
| 5 | StoreKit 2 / Play Billing / MS Store product setup + SBP enrollment | Store-side config lead time |
| 6 | **Promo surface on the web app** (rule 6) | Must sell without degrading the free web app — additive landing + upgrade surface, never an interstitial |
| 7 | Version bump + six-channel ship | Standing convention |

**#1 and #3 are the real schedule risk.** Both are Windows, and both are only
verifiable through `windows-repl.yml` CI.

### Recommended order of work

1. **Windows sign-in** (#1) — unblocks everything else on Windows and is
   ordinary work: port the existing Apple/Google federated flow already shipped
   on web + Android into `Tidbits.Core`. Gets the riskiest platform to parity.
2. **`Tidbits.Windows` IAP spike** (#3) — do this *early and timeboxed*, because
   its failure mode changes decision 4 in §8 (re-categorize as non-game). Finding
   that out late is expensive; finding it out early is a margin win.
3. **The five Club features** (#2) — the long pole in calendar terms, and the
   only item that is pure product work. Can proceed in parallel with 1–2.
4. **Entitlement plumbing** (#4, #5) — Worker + MoR + `entitlements/` rules +
   store product config + SBP enrollment. Enroll in the Apple Small Business
   Program *now*; it has a 15-day activation lag and no downside.
5. **Web promo surface** (#6) — last, because it advertises whatever 1–4 became.
6. **Six-channel ship** (#7).

**Start #4's SBP enrollment today regardless of everything else** — it is free,
takes 15 days to activate, and halves year-one subscription commission.

---

## 10. Corrections to `docs/EVENT-TRIVIA-COMPETITIVE.md` §I

Applied 2026-07-19 from the pricing pass:

1. Quizado's **$74.99 per-event App Store option is gone** — now subscription-only,
   and the axis is **venue count** (1→3), not player count.
2. Kahoot is **not** "~$10–17/mo" — it's $19–79/mo individual, and Teams start at
   **$6,000/yr with a 25-seat minimum**. The old figure understated it ~2×.
3. Water Cooler Trivia's "~$1/participant" is confirmed — and bills **active**
   participants only, with zero feature gating. It is the only vendor in the
   entire survey with no findable pricing complaint.
