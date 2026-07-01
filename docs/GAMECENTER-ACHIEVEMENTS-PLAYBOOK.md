# Game Center & Play Games — Achievements/Leaderboards Playbook

Official-docs-grounded engineering reference for Tidbits Trivia. Covers
(1) the persistent Game Center "rocketship" access point vs. the transient
sign-in banner, (2) programmatic bulk creation of Apple Game Center config,
(3) the Android/Play Games equivalent, and (4) a unified achievement taxonomy.

All API names below were verified against Apple's `developer.apple.com` JSON
doc endpoints and Google's `developer.android.com` docs (July 2026). Where a
detail could not be pulled verbatim from the rendered docs it is flagged.

---

## PART 1 — The "rocketship" access point vs. the automatic sign-in banner

### What GKAccessPoint is

`GKAccessPoint` is *the persistent floating widget* — the little rocketship/
Game Center badge that sits in a corner of the app on top of your UI.

Apple's own abstract:
> "An object that allows players to view and manage their Game Center
> information from within your game." … "The access point displays a control
> in a corner of your game that opens a Game Center dashboard when the player
> taps or clicks it."
> — https://developer.apple.com/documentation/gamekit/gkaccesspoint

Relevant members (verified):

| Member | Meaning |
|---|---|
| `GKAccessPoint.shared` | The singleton you configure. |
| `isActive: Bool` | **Whether to display the access point.** True = the widget appears (after local-player init, or immediately if already authenticated). False = not displayed. |
| `location: GKAccessPoint.Location` | Which corner (`.topLeading`, `.topTrailing`, `.bottomLeading`, `.bottomTrailing`). |
| `showHighlights: Bool` | Whether to show achievement/rank highlights. **Deprecated.** |
| `isPresentingGameCenter: Bool` | True while the dashboard is on screen. |
| `isVisible: Bool` | Whether the widget is currently visible. |
| `trigger(handler:)` | Programmatically open the dashboard (as if tapped). |
| `trigger(state:handler:)` | Open the dashboard in a specific `GKGameCenterViewController.State`. |
| `trigger(achievementID:handler:)` | Open a specific achievement. |
| `trigger(leaderboardID:playerScope:timeScope:handler:)` | Open a specific leaderboard. |

Sources:
- https://developer.apple.com/documentation/gamekit/gkaccesspoint
- https://developer.apple.com/documentation/gamekit/gkaccesspoint/isactive
- https://developer.apple.com/documentation/gamekit/gkaccesspointlocation

`isActive` doc, verbatim behavior:
> "A Boolean value that determines whether to display the access point." When
> `true`, "the access point appears after you initialize the local player, or
> appears immediately if you've already initialized the player." When `false`,
> "the access point is not displayed."

**So yes — the persistent widget is purely a product of `isActive = true`.**
There is no separate "widget" toggle. Turn it off and no floating control is
drawn.

### The transient "Welcome back" banner is separate

The welcome/notification banner shown at sign-in is part of the **authentication
flow**, not the access point. It is driven by `GKLocalPlayer` /
`authenticateHandler`, which "GameKit calls while initializing the local
player" (https://developer.apple.com/documentation/gamekit/gklocalplayer/authenticatehandler).
GameKit may present a brief system sign-in screen if the player isn't signed in,
and shows the returning-player welcome banner automatically as part of Game
Center enablement — this is described in the WWDC sessions as the badge that
"welcomes the player back" the next time they open the game
(https://developer.apple.com/videos/play/wwdc2022/10064/ "Reach new players with
Game Center dashboard"; https://developer.apple.com/videos/play/wwdc2020/10618/).

The banner fires off the authentication state change, **not** off
`GKAccessPoint.isActive`. Nothing in the `GKAccessPoint` or
`authenticating-a-player` docs ties the welcome banner to the access point.
The two are independent code paths:

- Welcome banner  ← `authenticateHandler` completing for a returning player.
- Floating widget ← `GKAccessPoint.shared.isActive = true`.

**Conclusion for the immediate bug:** set `GKAccessPoint.shared.isActive =
false` (or simply never set it true). You still get the automatic "Welcome
back" banner at authentication because that comes from the authenticate handler,
which you keep. You just lose the persistent on-top rocketship.

### Recommended approach

1. **Authenticate early, do NOT activate the access point.**

```swift
import GameKit

@MainActor
final class GameCenterManager {
    static let shared = GameCenterManager()
    private(set) var isAuthenticated = false

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            // If GameKit hands back a viewController, the player must finish
            // sign-in — present it from the root. Otherwise just record state.
            if let viewController {
                Self.topViewController()?.present(viewController, animated: true)
                return
            }
            if let error {
                print("[GameCenter] auth error: \(error.localizedDescription)")
                return
            }
            self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated

            // DO NOT do this — it draws the persistent floating widget:
            // GKAccessPoint.shared.isActive = true
            //
            // The automatic "Welcome back" banner still appears on its own
            // because it is part of this authentication flow, not the widget.
        }
    }
}
```

Keep `isActive` at its default (`false`). Result: transient welcome banner at
sign-in, then nothing on top of the app.

2. **Give a manual Game Center entry point on the Records screen.** A single
button, no persistent chrome. Two equivalent options:

Option A — briefly flash the access point open, then leave it off:

```swift
Button("Game Center") {
    GKAccessPoint.shared.trigger(state: .dashboard) { }
}
.disabled(!GameCenterManager.shared.isAuthenticated)
```

Option B — present `GKGameCenterViewController` directly (no `GKAccessPoint`
involvement at all; cleanest for a Records screen):

```swift
import GameKit
import SwiftUI

struct GameCenterButton: View {
    @State private var showDashboard = false
    var body: some View {
        Button("Game Center") { showDashboard = true }
            .disabled(!GameCenterManager.shared.isAuthenticated)
            .sheet(isPresented: $showDashboard) {
                GameCenterView() // UIViewControllerRepresentable wrapper below
            }
    }
}

struct GameCenterView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GKGameCenterViewController {
        // .dashboard | .achievements | .leaderboards
        let vc = GKGameCenterViewController(state: .dashboard)
        vc.gameCenterDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: GKGameCenterViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, GKGameCenterControllerDelegate {
        func gameCenterViewControllerDidFinish(_ vc: GKGameCenterViewController) {
            vc.dismiss(animated: true)
        }
    }
}
```

**tvOS note:** the access point is even more intrusive at ten feet; keep it off
there too and use a focusable "Game Center" button that presents the dashboard.
`GKAccessPoint` has an `isFocused` property specifically because on tvOS the
widget participates in the focus engine — another reason to avoid it and use an
explicit button that lives in your own focus order.

---

## PART 2 — Programmatic creation of Apple Game Center config (App Store Connect API)

Yes — the App Store Connect API can create achievements and leaderboards
without hand entry in the ASC web UI. Apple explicitly ships this to
"automate your Game Center configurations outside of App Store Connect on the
web" (Tech Talk 111377,
https://developer.apple.com/videos/play/tech-talks/111377/ "Manage Game Center
with the App Store Connect API").

### Auth

Standard ASC API auth: an ES256 **JWT** signed with your ASC API key
(Issuer ID + Key ID + `.p8` private key), sent as
`Authorization: Bearer <jwt>`. Base URL `https://api.appstoreconnect.apple.com`.
Same key/flow you already use for the cloud App Store pipeline
(`docs/CLOUD-SUBMISSION.md`).

### The resource graph (verified to exist)

From https://developer.apple.com/documentation/appstoreconnectapi/game-center :

- `gameCenterDetails` — the per-app Game Center container. Read the current one
  with `GET /v1/apps/{id}/gameCenterDetail`
  (https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-gamecenterdetail).
  **Everything hangs off this.** If the app has never had Game Center enabled,
  you create/enable the detail first.
- `gameCenterGroups` — optional grouping so achievements/leaderboards are shared
  across related apps.
- `gameCenterAchievements` + `gameCenterAchievementLocalizations` +
  `gameCenterAchievementImages` + `gameCenterAchievementReleases`.
- `gameCenterLeaderboards` + `gameCenterLeaderboardLocalizations` +
  `gameCenterLeaderboardImages` + `gameCenterLeaderboardReleases`
  (+ `gameCenterLeaderboardSets` for grouping boards).

### Gotcha: use the **v2** endpoints

`POST /v1/gameCenterAchievements` and `POST /v1/gameCenterLeaderboards` still
work but are **marked deprecated** in the docs; use `v2`:

- `POST https://api.appstoreconnect.apple.com/v2/gameCenterAchievements`
  (request type `GameCenterAchievementV2CreateRequest`, returns 201 +
  `GameCenterAchievementV2Response`)
  — https://developer.apple.com/documentation/appstoreconnectapi/post-v2-gamecenterachievements
- `POST https://api.appstoreconnect.apple.com/v2/gameCenterLeaderboards`

The verified **v1** achievement body (field names carry over to v2; v2 wraps the
same attributes and requires both `attributes` and `relationships`):

```json
{
  "data": {
    "type": "gameCenterAchievements",
    "attributes": {
      "referenceName": "Category Explorer",
      "vendorIdentifier": "com.tidbitstrivia.ach.explorer",
      "points": 20,
      "repeatable": false,
      "showBeforeEarned": true
    },
    "relationships": {
      "gameCenterDetail": {
        "data": { "type": "gameCenterDetails", "id": "<GC_DETAIL_ID>" }
      }
    }
  }
}
```
Source: https://developer.apple.com/documentation/appstoreconnectapi/post-v1-gamecenterachievements

Verified v1 **leaderboard** body (real example from the doc):

```json
{
  "data": {
    "type": "gameCenterLeaderboards",
    "attributes": {
      "referenceName": "Cortado Temp LB",
      "vendorIdentifier": "CORTADOTEMP_LB",
      "defaultFormatter": "INTEGER",
      "submissionType": "BEST_SCORE",
      "scoreSortType": "DESC",
      "scoreRangeStart": "0",
      "scoreRangeEnd": "100"
    },
    "relationships": {
      "gameCenterDetail": {
        "data": { "type": "gameCenterDetails", "id": "<GC_DETAIL_ID>" }
      }
    }
  }
}
```
Source: https://developer.apple.com/documentation/appstoreconnectapi/post-v1-gamecenterleaderboards

Key enum values seen in the docs: `defaultFormatter: INTEGER`,
`submissionType: BEST_SCORE` (also `MOST_RECENT`), `scoreSortType: DESC`/`ASC`.
Recurring leaderboards add `recurrenceStartDate` / `recurrenceDuration`.

In **v2**, `GameCenterAchievementV2CreateRequest.Data` requires `type`,
`attributes`, and `relationships` (all three confirmed required). The
relationship can attach to the app's `gameCenterDetail` or to a
`gameCenterGroup` when sharing across apps.
⚠️ The exact v2 `relationships` key list could not be pulled verbatim from the
rendered doc — confirm `gameCenterDetail` vs `gameCenterGroup` against
https://developer.apple.com/documentation/appstoreconnectapi/gamecenterachievementv2createrequest
before running the script (owner task).

### Two more gotchas

1. **Localizations are a separate resource.** Creating a `gameCenterAchievement`
   only makes the shell (reference name + points). The player-visible title and
   description come from `POST /v1/gameCenterAchievementLocalizations` (locale,
   name, beforeEarnedDescription, afterEarnedDescription), related back to the
   achievement. Same for leaderboards.
2. **Images upload separately** (like all ASC asset uploads — a
   reserve→PUT→commit dance): `POST /v1/gameCenterAchievementImages` to reserve
   (returns `uploadOperations`), `PUT` the bytes to each operation URL, then
   `PATCH` the image with `uploaded: true` to commit. You cannot inline an image
   in the create call. Achievement images are required before you can **release**
   the achievement to production, but not to create it.
3. **Release is a distinct step.** Achievements/leaderboards are drafts until you
   create a `gameCenterAchievementRelease` / `gameCenterLeaderboardRelease` tied
   to the `gameCenterDetail`'s version. Bulk-create can leave everything in draft
   for one human "Save/Submit" pass, or automate the release too.

### Rate limits

ASC API is throttled per Apple's standard policy (HTTP **429** with a
`Retry-After`; the v2 endpoints explicitly document a 429 response). Treat ~50
requests/sec as the ceiling and back off on 429. For a ~15-achievement +
4-leaderboard batch this is a non-issue; just handle 429 defensively.

### Script outline (Python)

Spec file `game-center-spec.json` (shared with Android — see Part 4):

```json
{
  "achievements": [
    { "id": "com.tidbitstrivia.ach.first_correct", "name": "First Light",
      "points": 5, "hidden": false, "repeatable": false,
      "beforeEarned": "Answer your first question correctly.",
      "afterEarned": "You answered your first question correctly." }
  ],
  "leaderboards": [
    { "id": "com.tidbitstrivia.lb.total_correct", "name": "Lifetime Correct",
      "formatter": "INTEGER", "submissionType": "BEST_SCORE", "sort": "DESC" }
  ]
}
```

Steps:
1. Build ES256 JWT from `.p8` (PyJWT). `aud=appstoreconnect-v1`, 20-min exp.
2. `GET /v1/apps/{appId}/gameCenterDetail` → capture `GC_DETAIL_ID`. If absent,
   enable Game Center for the app first.
3. For each achievement: `POST /v2/gameCenterAchievements` (attrs +
   `gameCenterDetail` relationship) → capture achievement `id`; then
   `POST /v1/gameCenterAchievementLocalizations` for `en-US`; optionally
   reserve+upload the image; optionally create the release.
4. For each leaderboard: same pattern via `/v2/gameCenterLeaderboards` +
   `gameCenterLeaderboardLocalizations`.
5. Wrap every call with a 429/`Retry-After` retry loop; log created IDs to a
   `.state.json` so re-runs are idempotent (skip existing `vendorIdentifier`s).

This is a real, supported automation path — Apple built the endpoints for
exactly this, and demoed it in Tech Talk 111377.

---

## PART 3 — Android equivalent (Play Games Services Publishing API)

Yes — Google has a mirror-image REST API: the **Google Play Game Services
Publishing API** (a.k.a. Games Configuration API). It "provides functions
similar to those available through the Google Play Console, such as creating
and editing achievement listings, creating and editing leaderboard listings,
and automating frequent tasks."
- Overview: https://developer.android.com/games/pgs/publishing/publishing
- API ref: https://developers.google.com/games/services/publishing/api
- Achievements: https://developer.android.com/games/services/publishing/api/achievementConfigurations
- Leaderboards: https://developer.android.com/games/services/publishing/api/leaderboardConfigurations

### Auth

**Service account** (OAuth 2.0 server-to-server), scope
`https://www.googleapis.com/auth/games`. The service account must be linked to
the game in Play Console with the right permission. Base host
`https://www.googleapis.com`.

### achievementConfigurations (verified)

Base: `.../gamesConfiguration/v1configuration/games/{applicationId}/achievements`

| Method | HTTP | Notes |
|---|---|---|
| insert | `POST .../achievements` | create new achievement config |
| get | `GET .../achievements/{achievementId}` | metadata |
| list | `GET .../achievements` | all configs for the app |
| update | `PUT .../achievements/{achievementId}` | edit metadata |
| delete | `DELETE .../achievements/{achievementId}` | remove |

Resource body (verified fields):

```json
{
  "kind": "gamesConfiguration#achievementConfiguration",
  "id": "CgkI...",
  "achievementType": "STANDARD",            // or "INCREMENTAL"
  "initialState": "REVEALED",               // "HIDDEN" | "REVEALED" | "UNLOCKED"
  "stepsToUnlock": 10,                       // INCREMENTAL only
  "draft": {
    "kind": "gamesConfiguration#achievementConfigurationDetail",
    "name":        { "translations": [ { "locale": "en", "value": "Category Explorer" } ] },
    "description": { "translations": [ { "locale": "en", "value": "..." } ] },
    "pointValue": 20,
    "iconUrl": "https://...",   // READ-ONLY, ignored on write
    "sortRank": 1               // READ-ONLY, ignored on write
  }
}
```

- `achievementType`: `STANDARD` (locked/unlocked) or `INCREMENTAL`
  (progress-based; requires `stepsToUnlock`).
- `initialState`: `HIDDEN` | `REVEALED` | `UNLOCKED`.
- Localized strings via `name.translations[]` / `description.translations[]`.

### leaderboardConfigurations (verified)

Base: `.../gamesConfiguration/v1configuration/games/{applicationId}/leaderboards`
with the same insert/get/list/update/delete method set. Config carries score
order (`scoreOrder: LARGER_IS_BETTER` / `SMALLER_IS_BETTER`), the localized
`name`, and score formatting. **Max 70 leaderboards per game**
(https://support.google.com/googleplay/android-developer/answer/2990418).

### Images

Icons are **not** inline. `iconUrl` is read-only; you upload artwork through the
**`imageConfigurations`** resource (`.../imageConfigurations/{resourceId}/{imageType}`
`upload`), analogous to Apple's reserve/upload step. Writes to `iconUrl` in the
draft are ignored.

### 2026 status — multiplayer vs. achievements/leaderboards

- **Real-time & turn-based multiplayer APIs are deprecated / removed.** Google
  ended support for these (deprecated Sept 16, 2019; the newer round of shutdowns
  continued after) —
  https://support.google.com/googleplay/android-developer/answer/9469745
  ("Ending support for multiplayer APIs in Play Games Services"). This is the
  reason Tidbits' networked Trivia Night is serverless/local (mDNS+TCP), not PGS.
- **Achievements and leaderboards are fully supported in 2026.** The
  achievements and leaderboards docs were updated in mid-2026; you can still
  create/edit/delete them in Play Console and via the Publishing API.
  Sources: https://developer.android.com/games/pgs/achievements ,
  https://developer.android.com/games/pgs/leaderboards ,
  https://developer.android.com/games/pgs/publishing/publishing

So Part 3 bulk-creation is real and current — same story as Apple.

### Android runtime side (for reference)

Unlocking/incrementing at runtime uses the `play-services-games-v2` SDK
(`AchievementsClient.unlock(id)` / `.increment(id, n)`,
`LeaderboardsClient.submitScore(id, score)`). That's separate from the
Publishing API, which only handles *configuration*.

---

## PART 4 — Unified achievement taxonomy (maps cleanly to both platforms)

Design principle (per this project's learning-orientation test): reward
**breadth, mastery, comeback, and streaks** — depth of engagement — not raw
volume grinding. Each achievement below gets one conceptual definition and two
platform IDs. Use `INCREMENTAL` (Play) / non-repeatable points (GC) where a
counter fits.

**ID convention:** GC vendor id `com.tidbitstrivia.ach.<slug>`;
Play uses the console-generated opaque id but we track by the same `<slug>` in
the shared spec so both platforms stay in lockstep.

### Achievements (13)

| # | Slug | Name | Unlock condition | Type | Pts |
|---|---|---|---|---|---|
| 1 | `first_light` | First Light | Answer 1 question correctly | standard | 5 |
| 2 | `streak_5` | On a Roll | 5 correct in a row (single session) | standard | 10 |
| 3 | `streak_15` | Unstoppable | 15 correct in a row | standard | 25 |
| 4 | `daily_7` | Seven-Day Curious | Play on 7 distinct calendar days | incremental (7) | 20 |
| 5 | `daily_30` | Month of Wonder | Play on 30 distinct days | incremental (30) | 40 |
| 6 | `category_master` | Category Master | 90%+ accuracy over 20 Qs in one category | standard | 25 |
| 7 | `polymath` | Polymath | Reach "mastered" in 5 different categories | incremental (5) | 40 |
| 8 | `breadth_all` | Renaissance Mind | Answer a correct Q in **every** category | incremental (N cats) | 50 |
| 9 | `comeback` | Comeback | Get 5 correct in a row right after a wrong answer | standard | 15 |
| 10 | `perfect_round` | Flawless | Finish a full round with 100% correct | standard | 20 |
| 11 | `deep_dive` | Deep Dive | Answer 100 Qs in a single category | incremental (100) | 30 |
| 12 | `night_owl_earlybird` | Any Hour Learner | Play a session before 7am and after 10pm | standard | 10 |
| 13 | `teach_share` | Pass It On | Host a Trivia Night session (local multiplayer) | standard | 20 |

Notes on learning orientation: #6/#7/#8 reward *mastery and breadth across
domains*; #9 rewards *resilience*; #4/#5 reward *consistent return* rather than
binge volume. #13 ties to the human-connection value (hosting others), matching
the project's "invite participation" test.

### Leaderboards (4)

| Slug | Name | Score meaning | Formatter | Sort | Recurrence |
|---|---|---|---|---|---|
| `lb_total_correct` | Lifetime Correct | Cumulative correct answers | INTEGER | DESC (LARGER_IS_BETTER) | none |
| `lb_best_streak` | Longest Streak | Best single-session streak | INTEGER | DESC | none |
| `lb_weekly_points` | This Week | Points earned this week | INTEGER | DESC | weekly recurring |
| `lb_breadth_score` | Breadth Score | # categories at "mastered" | INTEGER | DESC | none |

`lb_weekly_points` uses GC recurring leaderboards
(`recurrenceStartDate`/`recurrenceDuration`) and a Play leaderboard reset — a
weekly board keeps the competition welcoming for newcomers (no permanent
whale-domination), reinforcing engagement over lifetime volume.

---

## Open questions / owner tasks

1. **Confirm the v2 achievement/leaderboard relationship key.** Verify whether
   `GameCenterAchievementV2CreateRequest` attaches via `gameCenterDetail` or
   `gameCenterGroup` (and same for leaderboards) at
   https://developer.apple.com/documentation/appstoreconnectapi/gamecenterachievementv2createrequest
   before running the bulk script. Docs render client-side; check the live page.
2. **Enable Game Center on the app + capture `GC_DETAIL_ID`.** Run
   `GET /v1/apps/{appId}/gameCenterDetail`. If Game Center was never enabled,
   enable it (ASC UI once, or via the API) so the detail id exists.
3. **Provision ASC API key** for the pipeline (reuse the existing App Store
   automation key/Issuer ID) with the Game Center scope.
4. **Link a Play service account** to the game in Play Console with permission to
   edit game configuration; grant `.../auth/games` scope.
5. **Author `game-center-spec.json`** (single source shared by both scripts) from
   the Part 4 taxonomy, including per-locale strings and icon file paths.
6. **Produce achievement/leaderboard icons** (Apple 512×512 & 1024×1024 PNG;
   Play 512×512). Both platforms require images before you can *release* (not
   create) — budget the reserve/upload step.
7. **Decide draft-vs-release automation.** Bulk-create as drafts for one human
   review pass, or automate `gameCenterAchievementRelease` too. Recommend drafts
   first for the initial batch.
8. **Wire runtime unlocks** (`GKAchievement` on Apple, `AchievementsClient` on
   Play) keyed off the shared slug→platform-id map, and add a Records-screen
   "Game Center" / Play Games button (Part 1). Update `PARITY.md` with an
   Achievements row.
9. **Confirm access point stays OFF on tvOS** and the manual button lives in the
   focus order.

### Primary sources
- GKAccessPoint — https://developer.apple.com/documentation/gamekit/gkaccesspoint
- GKAccessPoint.isActive — https://developer.apple.com/documentation/gamekit/gkaccesspoint/isactive
- GKLocalPlayer.authenticateHandler — https://developer.apple.com/documentation/gamekit/gklocalplayer/authenticatehandler
- WWDC22 "Reach new players with Game Center dashboard" — https://developer.apple.com/videos/play/wwdc2022/10064/
- ASC API Game Center — https://developer.apple.com/documentation/appstoreconnectapi/game-center
- Read app's gameCenterDetail — https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-gamecenterdetail
- POST v2 gameCenterAchievements — https://developer.apple.com/documentation/appstoreconnectapi/post-v2-gamecenterachievements
- POST v1 gameCenterLeaderboards (body example) — https://developer.apple.com/documentation/appstoreconnectapi/post-v1-gamecenterleaderboards
- Tech Talk 111377 "Manage Game Center with the ASC API" — https://developer.apple.com/videos/play/tech-talks/111377/
- Play Publishing API overview — https://developer.android.com/games/pgs/publishing/publishing
- achievementConfigurations — https://developer.android.com/games/services/publishing/api/achievementConfigurations
- leaderboardConfigurations — https://developer.android.com/games/services/publishing/api/leaderboardConfigurations
- Ending multiplayer APIs — https://support.google.com/googleplay/android-developer/answer/9469745
- PGS features / 70-leaderboard cap — https://support.google.com/googleplay/android-developer/answer/2990418
