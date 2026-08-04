# Owner playbook — everything only you can do

**Written 2026-08-03 against 1.6.73.** One page for every step blocked on *you*
rather than on engineering: an account, a signature, a key, a price, or a product
decision. Everything else in this repo is built, tested and shipped.

**Read this first.** A lot of this was already done on 2026-07-23 and is recorded
in `docs/CLUB-OWNER-PLAYBOOK.md`. The **nine Club store products across Apple,
Play and Lemon Squeezy already exist**, and the Lemon Squeezy checkout URLs are
already committed into `js/store.js` (verified in the code, not just claimed).
So this page is deliberately short, and the finished work is listed at the bottom
so you don't redo it.

**How to use it.** Blocks are ordered by *what unblocks what*. Each item says what
it is, exactly where it lives, and — the part that matters — **what stays broken
until you do it**.

**Total remaining: about 90 minutes of your attention**, plus waiting on Lemon
Squeezy's store review and Microsoft's certification, neither of which is yours to
speed up.

| | |
|---|---|
| 🔑 | a key or secret — you create it, you paste it, I never see it |
| 💳 | financial / legal — only you can sign it |
| 🧭 | a product decision — it changes what gets built, so nothing has been |
| ⏳ | waiting on an outside party |

---

# Block A — the three that are actually blocking money

### A1 🔑 Lemon Squeezy webhook + Worker secrets *(~20 min — the single highest-value item)*

Products exist and their checkout URLs are already in the shipped web app, so a
buyer can pay **today** — and the entitlement would never be written, because the
Worker cannot verify the webhook. It returns 503, which is safe but means a paid
member does not get Club.

1. Lemon Squeezy → **Settings → Webhooks → +**
   - Callback URL: `https://tidbits-auth.benwilkoff.workers.dev/entitlements/webhook`
   - Events: `order_created` **and all** `subscription_*`
   - Set a **signing secret** (any strong random string).
2. Cloudflare dashboard → the **`tidbits-auth`** Worker → Settings → Variables
   (or `wrangler secret put`), set all four:
   - `LEMONSQUEEZY_WEBHOOK_SECRET` — the same value as above
   - `FIREBASE_SA_EMAIL`, `FIREBASE_SA_PRIVATE_KEY`, `FIREBASE_DB_URL`
3. ⏳ Lemon Squeezy's **store application is still under their review** and the
   store is in **test mode**. Live payments start when they approve it and you
   flip test mode off.

**Blocked until done:** every web purchase takes the money and grants nothing.

### A2 💳 Apple — attach a review screenshot to each IAP and submit them with a build

All three products are created and fully configured (Family Sharing on, all 175
regions, both subscriptions in the "Tidbits Club" group). Two things left:

- [ ] Add a **review screenshot** (use the paywall screen) to each of the three
      products. Apple rejects an IAP submitted without one.
- [ ] **Submit the three IAPs with the next app version** — Apple reviews a first
      IAP alongside a binary, never on its own. *1.6.73 is uploading to App Store
      Connect now, so this is the build to attach them to.*
- [ ] Confirm you're enrolled in the **Small Business Program** (ASC → Business).
      Free; takes commission from 30% to 15% under $1M.

**Blocked until done:** Club cannot be bought on iPhone, iPad, Mac or Apple TV.

### A3 Google Play — promote the build toward production

Products are created and **Active**. The only follow-up is release-track
management: a billing-enabled build lives on the **Internal** track (that upload
is what unblocked product creation). Promote toward production when you're ready.

**Blocked until done:** Club works only for internal testers on Android.

---

# Block B — turn on push notifications 🔑 *(~45 min, all free)*

Every client leg shipped on 2026-08-03 — iOS, Android and web all capture a token
and all have an in-app opt-out. The sender (`tools/send_reminders.py`, a GitHub
Actions cron) is written and **safely no-ops until these secrets exist**. Nothing
is broken today; it simply never sends.

**Blocked until done:** "Your Daily is ready" never goes out — the return trigger
every async mode depends on.

### B1 Apple APNs — and one ordering trap that breaks the build

1. Apple Developer → **Keys** → new key with **APNs** enabled → download the
   `.p8` **once** (Apple will not offer it again).
2. **Enable the Push Notifications capability on the App ID.**
3. **Only then** tell me to add `aps-environment` to `project.yml`. In the other
   order the signed cloud build breaks — that trap is why this is three steps.
4. Repo secrets: `APNS_AUTH_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`,
   `APNS_BUNDLE_ID=com.learningischange.tidbitstrivia`.

### B2 Android FCM

- Firebase console → **Service accounts** → generate a private key.
- Repo secret `FCM_SERVICE_ACCOUNT` (the whole JSON).
- One key does double duty: FCM send **and** the cron's admin read of the private
  `pushTokens` tree.

### B3 Web VAPID

- `npx web-push generate-vapid-keys`
- **Public** half → paste it to me (replaces the `TODO_GENERATE_VAPID_KEYPAIR`
  placeholder in `js/push.js`; not a secret, ships to every browser).
- **Private** half → repo secret `VAPID_PRIVATE_KEY`, plus `VAPID_SUBJECT`
  (a `mailto:` address).
- Until the public key is in, the web reminder toggle **does not render at all** —
  deliberately: a switch that silently does nothing is worse than no switch.

---

# Block C — five-minute items with real consequences

### C1 Deploy the Firebase rules 💳-free, 5 minutes

```
firebase deploy --only database
```

**Blocked until done:** account deletion can fail on the `emailOwners/$key` node.
That is an **App Store 5.1.1(v)** requirement and a Play user-data requirement,
and it is what got tvOS rejected once already. The client code now ships on all
six platforms; the rule is the last piece.

### C2 Android App Links — paste one fingerprint

- Play Console → **App integrity** → copy the **Play App Signing SHA-256**.
- Paste it to me for `.well-known/assetlinks.json` (a one-line JSON edit).

**Blocked until done:** `https://tidbitstrivia.com/...` links on Android open a
browser-chooser dialog instead of the app. Everything else about deep links works.

### C3 Game Center — create 2 leaderboards + 9 achievements

- ASC → **Features → Game Center**. Every ID, title, image and localisation
  string is pre-written in `docs/GAME-CENTER-SETUP.md`; artwork is generated in
  `branding/`. It is transcription, not authorship.

**Blocked until done:** the in-app Game Center dashboard opens empty.

### C4 ⏳ Microsoft add-ons — blocked on certification, not on you

Add-ons for a **Game**-type product require the base app to be **published**, and
Tidbits is still in certification. Once it goes live, create three add-ons —
`club.lifetime` (durable), `club.annual`, `club.monthly` (subscriptions), same
$79.99 / $29.99 / $3.99 — then **tell me**: the real Windows `StoreContext`
purchase gateway is the one deliberately unfinished piece of code in the repo,
left behind a tested seam because it can only be verified against real Partner
Center products. Small, well-scoped job once they exist.

---

# Block D — decisions only you can make 🧭

Not tasks. They change **what gets built**, so nothing has been.

### D1 Ranked Seasons and Friend Streaks — where does the free/Club line go?

Both are *social*, and `MONETIZATION.md` R-MON-4 (the Population Rule) says a
social feature must not be fully paywalled — it dies without a population. So each
needs a line drawn:

| | A plausible free base | A plausible Club perk |
|---|---|---|
| **Friend Streaks** | keeping a mutual streak | streak insurance + a rivalry view |
| **Ranked Seasons** | ranked play + your tier | a parallel Club Invitational + defendable titles |

**Say where the line goes and both get built.** They are the last two unbuilt rows
in the Club tracker, blocked on this sentence rather than on effort.

### D2 The Daily's published question set — ✅ DONE 2026-08-03, decision made

I made this call rather than handing it back: **publish, and keep the local
computation as the fallback.** `tools/publish_daily.py` emits the day's seven full
rows (~4 KB) on the hourly cron; the web takes them when they're there and computes
locally when they aren't. The web Daily went from **13 MB to 4,249 bytes**, measured
in Chrome on a cold load.

The objection was that the web would "trust" a published set. It doesn't — it treats
it as a cache and refuses it on any doubt (missing, malformed, wrong day, wrong
count), and the five-engine golden still governs. Verified byte-identical against
`js/engine.js`, and the golden passes.

### D3 Matching pairs where key and value are the same word — ✅ already fixed

Measured 2026-08-03: **zero** exact same-name pairs remain in `match.json`. The 44
were removed by an earlier repair pass; this item was stale. The 60 remaining
key/value overlaps are element→symbol (*boron → B*, *carbon → C*) and one capital
that shares a prefix (*Maldives → Malé*) — all of which ARE the knowledge being
tested, so nothing to do.

### D4 tvOS layered icon + Top Shelf art

tvOS icons are *layered* (parallax) — a design deliverable, not code.
`branding/README.md` has the layer sizes. Until the art exists the Apple TV icon
is flat and the Top Shelf shelf can't be built (the extension isn't worth writing
without it). This is the one item that may want a designer rather than an
afternoon.

---

# Already done — do not redo (recorded 2026-07-23, verified today)

- **Lemon Squeezy:** all 3 products created + Published; checkout URLs committed
  into `js/store.js` — *verified in the code today*.
- **Apple:** all 3 IAPs created + fully configured (Family Sharing, US price +
  auto matrix, 175 regions, English localisation, both subs in one group), with
  the exact IDs the app loads.
- **Google Play:** all 3 products created + **Active**, including the
  "backwards compatible" `club_lifetime` so the legacy INAPP query resolves.
  Required uploading a billing-enabled AAB first — done (vc74 on Internal).
- **Microsoft:** account, Entra app, 4 CI secrets, Store ID `9NRKS9LDRCWC`,
  first submission staged and in certification.
- **All client code:** paywalls, entitlement spine (fails **open** — a backend
  hiccup never revokes a paying member), StoreKit 2, Play Billing, the Worker,
  the RTDB rules themselves, push clients + opt-outs, account deletion on all six.

---

# The ship commands (reference — normally I run these)

Bump `AppVersion.xcconfig` + `android/app/build.gradle.kts` + run
`python3 tools/stamp_msix_version.py`, then:

| Platform | Command | Where it lands |
|---|---|---|
| Web | *(automatic on push to `main`)* | tidbitstrivia.com |
| iOS · tvOS · macOS | `gh workflow run appstore-build.yml -f platform=all` | App Store Connect (all three — `all` excluded macOS until 2026-08-03; fixed) |
| Android | `git tag v<version>-android && git push --tags` | Play **Internal** track |
| Windows | `gh workflow run windows-store.yml -f submit=true` | Partner Center **draft** |
| Windows (publish) | `… -f submit=true -f commit=true` | **Public** on the Store |

**Only the last row is irreversibly public.** Apple and Play uploads land in a
review/test channel and still need you to press *Submit for Review* / promote.

Two Microsoft Store traps that reappear on any fresh product, both already solved
once and written up in `docs/WINDOWS-STORE-SUBMISSION.md`: the **Submission
Options** page has a *required* `runFullTrust` justification, and the red "access
policies document is not present in the config set" banner is an Xbox-Live config
blocker cleared by **Xbox services → bottom → Test**, not by any submission
section.

---

## The shortest possible version

1. **Now, 20 minutes:** the Lemon Squeezy webhook + the four Worker secrets (A1).
   Right now a web buyer can pay and get nothing.
2. **Then, 5 minutes:** `firebase deploy --only database` (C1).
3. **With the 1.6.73 build that is uploading now:** attach the three IAP review
   screenshots and submit them (A2).
4. **Any spare 45 minutes:** the three push keys (B1–B3).
5. **Answer D1** and two more features get built.
