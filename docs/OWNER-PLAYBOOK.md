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

**Total remaining: about 20 minutes of your attention**, plus waiting on Lemon
Squeezy's store review and Microsoft's certification, neither of which is yours to
speed up. It was 90 minutes when this page was written a few hours ago; the
difference is work I had wrongly filed as yours and have since done — the Firebase
rules deploy, the whole web-push VAPID setup, the Daily publishing decision, and
three items that turned out to be already finished.

| | |
|---|---|
| 🔑 | a key or secret — you create it, you paste it, I never see it |
| 💳 | financial / legal — only you can sign it |
| 🧭 | a product decision — it changes what gets built, so nothing has been |
| ⏳ | waiting on an outside party |

---

# ⏳ WHAT IS ACTUALLY LEFT — 2026-08-04 (verified against each API)

Two items left (was four). **None of them block launch.** Everything else is done and measured.

| # | Item | Why it isn't done | Effort |
|---|---|---|---|
| 1 | ~~`www` CNAME~~ **DONE 2026-08-04** | Record now points at `bhwilkoff.github.io`. GitHub still has to reissue the cert to cover `www` — automatic, but on its own schedule | watch, no action |
| 2 | APNs `.p8` auth key | Not exposed by the App Store Connect API at all (`v1/apnsKeys` → 404). Developer-portal only | ~3 min |
| 3 | ~~LS `order_refunded`~~ **DONE 2026-08-04** | Webhook now listens for 14 events. **But LS scopes webhooks per mode** — this is the test-mode hook; live mode needs its own once the application is approved | recheck at go-live |
| 4 | The two Club subscriptions | `READY_TO_SUBMIT`. **Deliberately parked** — see below | judgement call |

**On #1** — this is the `https://www.` certificate warning; full diagnosis and the
exact record in `docs/DNS-AND-DEEP-LINK-STATE.md`. The Cloudflare migration that
was going to be item #1 turned out to be **unnecessary**: Apple's CDN already
accepts our association file despite the `octet-stream` content type, verified by
reading it back out of Apple's own CDN.

**On #4** — iOS, macOS and tvOS 1.6.73 are all `WAITING_FOR_REVIEW` right now.
Attaching IAPs to an in-flight version pulls the whole build back out of the
queue. The cheap play is to attach them to the *next* version. That is a
sequencing choice, not a blocker, so it is yours to make rather than mine.

## Verified green, 2026-08-04

- Apple: iOS + macOS + tvOS **1.6.73 all WAITING_FOR_REVIEW**
- Web, `assetlinks.json`, AASA, `support.html` — all HTTP 200
- Worker rejects an unsigned webhook with 401; refunds revoke
- Universal Links verified **by Apple's CDN**; App Links verified **by Google's
  Digital Asset Links API** — both read back, not inferred
- CI green across Android, Apple Core tests, and the Pages deploy

---

# ✅ DONE 2026-08-04 (second pass — via the ASC API + Play Console)

- **PUSH_NOTIFICATIONS + ASSOCIATED_DOMAINS enabled** on the App ID, then
  `aps-environment` and `associated-domains` added to `project.yml`. That order
  matters; the reverse breaks the signed build. iOS/tvOS/macOS all build.
- **All 9 Game Center achievements created + localized** (`tools/gc_achievements.py`,
  idempotent). Their 9 vendor ids match the 9 the shipped app reports, exactly.
  Both leaderboards already existed. Images not attached (separate asset flow).
- **Android App Links fixed** — assetlinks.json was missing the **Play App Signing**
  fingerprint and carried only the upload key, so links verified only for locally
  built installs. Both are live now, and Google's Digital Asset Links API reads
  both back.
- **`order_refunded` now revokes** (deployed + proven against the live Worker).
- **`apple-app-site-association` created** and deploying.

---

# ✅ VERIFIED STATE — 2026-08-04, read from the APIs

Everything below was queried live (App Store Connect API via `tools/asc.py`, the
Firebase CLI, the live Worker, DNS), because this page kept going stale. Several
items I had listed as "to do" were already **done by you**:

| Item | Verified state |
|---|---|
| Apple app, all 3 platforms | **1.6.73 WAITING_FOR_REVIEW** — submitted 2026-08-04 |
| `club.lifetime` IAP | **WAITING_FOR_REVIEW** — submitted with the build |
| `club.annual` / `club.monthly` | **READY_TO_SUBMIT** — review notes ✅ and review screenshots ✅ (asset state COMPLETE), but **not attached to any submission** |
| Game Center leaderboards | **Both created** — `tidbits.classic.high`, `tidbits.daily.streak` |
| Game Center achievements | **0 of 9 created** |
| App ID capabilities | `APPLE_ID_AUTH`, `GAME_CENTER`, `IN_APP_PURCHASE` enabled. **PUSH_NOTIFICATIONS and ASSOCIATED_DOMAINS are NOT** |
| Web / Play / Microsoft | web live; Play not public (internal only); Microsoft in certification |

**The one that needs a decision, not a click:** the two subscriptions are fully
prepared but were not included in today's submission — its items are the app
version only. They can't be added to a submission that is already
WAITING_FOR_REVIEW, and creating a *second* in-flight submission risks disturbing
the review you just started. **Recommendation: leave the review alone; attach the
two subscriptions to the next version submission after this one resolves.** If
they're approved without the subs, monthly/yearly simply can't be bought on Apple
until the next release — the lifetime tier still can.

---

# Block A — the three that are actually blocking money

### A1 🔑 Lemon Squeezy webhook — **one secret left, and it's the last thing blocking money**

The three Firebase Worker secrets are **set** (2026-08-04): `FIREBASE_SA_EMAIL`,
`FIREBASE_SA_PRIVATE_KEY`, `FIREBASE_DB_URL`. Only
`LEMONSQUEEZY_WEBHOOK_SECRET` remains, and it can't come from a file — it has to
match a value you create in their dashboard.

1. Generate one and copy it: `openssl rand -hex 32 | tee /dev/tty | pbcopy`
2. Lemon Squeezy → **Settings → Webhooks → +**
   - Callback URL: `https://tidbits-auth.benwilkoff.workers.dev/entitlements/webhook`
   - Events: `order_created` **and all** `subscription_*`
   - Signing secret: paste the value from step 1
3. `cd workers/tidbits-auth && npx wrangler secret put LEMONSQUEEZY_WEBHOOK_SECRET`
   (paste the same value)

**Verify it in one command** — an unsigned POST returns **503** while the secret is
missing and **401 (bad signature)** once it is set. 401 is the success signal here:

```
curl -s -X POST -w "\nHTTP %{http_code}\n" \
  https://tidbits-auth.benwilkoff.workers.dev/entitlements/webhook -d '{}'
```

4. ⏳ Lemon Squeezy's **store application is still under their review** and the
   store is in **test mode**. Live payments start when they approve it and you
   flip test mode off.

**Blocked until done:** a web buyer pays and the entitlement is never written. The
Worker returns 503 rather than dropping it, so the MoR retries — no purchase is
lost once the secret lands — but nobody gets Club in the meantime.

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

# Block B — turn on push notifications 🔑 *(one command left)*

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

### B2 Android FCM — ✅ **DONE 2026-08-04**

Key generated with `gcloud iam service-accounts keys create` against
`firebase-adminsdk-fbsvc@tidbits-trivia-f2ddb` and stored as the
`FCM_SERVICE_ACCOUNT` repo secret. One key does double duty: FCM send **and** the
cron's admin read of the private `pushTokens` tree.

### B3 Web VAPID — ✅ **DONE 2026-08-03**

Keypair generated, public half wired into `js/push.js`, `VAPID_PRIVATE_KEY` and
`VAPID_SUBJECT` set as repo secrets. Verified in Chrome: the "Daily reminder"
toggle now renders in Records → Settings, which it deliberately would not do
while the placeholder key was in place.

---

# Block C — five-minute items with real consequences

### C1 Deploy the Firebase rules — ✅ **DONE 2026-08-03**

`firebase deploy --only database` — the CLI on this box was already authenticated
as you, so this was never an owner step. Rules released to
`tidbits-trivia-f2ddb-default-rtdb` and verified against the live backend (a write
and a delete under `pushTokens/{uid}` both succeed). The App Store 5.1.1(v) /
Play account-deletion blocker is cleared.

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

### D1 Ranked Seasons and Friend Streaks — ✅ **DECIDED 2026-08-03 (Decision 053)**

I stopped asking and re-read the rule. `MONETIZATION.md` R-MON-4 already says it in
so many words: *"Never gate a seat; gate the view from the seat. Playing, ranking,
and being ranked are always free. Understanding, scouting, archiving, curating and
configuring are Club."* There was no open question — only an unapplied rule, which
is the most expensive kind of blocker because nobody re-reads the rule.

| | Free forever | Club |
|---|---|---|
| **Friend Streaks** | keeping a mutual streak, its count, the at-risk nudge | the rivalry view: head-to-head accuracy over time, the archive of past streaks |
| **Ranked Seasons** | a seat every season, ranked play, your tier, promotion/relegation, the live board | season autopsy, rundle history, opponent scouting, defendable-title records |

The one thing R-MON-4 didn't settle I settled and wrote down: **streak insurance is
rejected.** A freeze changes the OUTCOME, so selling it is pay-to-win in a social
feature — and it would mean a paying member's streak survives while their free
friend's dies on the same missed day. Solo freezes are already free; mutual ones
stay free. Club gets the history, never the outcome.

**What's left is build, not decision** — the tracker rows now read UNBLOCKED. Two
features across six platforms is the one genuinely multi-session item in this
document.

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

### D4 tvOS layered icon + Top Shelf art — ✅ **already done (stale item)**

Verified 2026-08-03 by inspecting the asset catalog rather than trusting the note.
`App Icon & Top Shelf Image.brandassets` holds a real parallax stack — opaque Back
layers and **transparent** Front layers at the correct tvOS sizes (400×240 @1x,
800×480 @2x; 1280×768 for the App Store icon) — plus Top Shelf images in both
standard (1920×720) and wide (2320×720) at 1x and 2x. There was never any art
missing. `tools/branding/make_tvos_icon.py` generates it.

What IS still open is the Top Shelf **extension** — the dynamic shelf that reads an
App Group snapshot — which is a code surface, not art, and is tracked in PARITY §11.

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

---

# The Universal Links problem, measured

`apple-app-site-association` now exists and serves 200 — but with
**`Content-Type: application/octet-stream`**, and Apple requires
**`application/json`**. GitHub Pages serves extensionless files as octet-stream
and gives no header control, and DNS is on WordPress.com nameservers pointing
straight at GitHub's IPs, so there is no proxy in front to fix it.

So iOS Universal Links cannot work as currently hosted, independent of the
Associated Domains capability. Three ways out, in the order I'd pick them:

1. **Move DNS to Cloudflare** (free) and proxy the apex. A Transform Rule or a
   Worker route can then serve that one path as `application/json`. Also buys
   header control for everything else. Owner-level: it's a nameserver change.
2. **Serve the site from Cloudflare Pages** instead of GitHub Pages. Bigger move.
3. **Accept it.** The custom scheme (`tidbits://`) works today and an https link
   opens Safari, which renders the web twin — the degraded path is genuinely fine.
   Universal Links stay a ⏳ row.

I would take (1) when there's an appetite for a DNS change, and (3) until then.
This is the only launch item where the blocker is infrastructure rather than a
click.
