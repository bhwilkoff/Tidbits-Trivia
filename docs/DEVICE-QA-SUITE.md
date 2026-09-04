# Device QA Suite — real hardware, every platform

**Doctrine:** the app's own claims are never the evidence for what a player
sees; the screen is. Its corollary is what keeps a loop worth running — *an
instrument must say when it is blind*. A null result from a blind instrument is
indistinguishable from a real absence, and a **readable frame of the wrong
screen is worse than a blank one**, because it survives every check and then
answers questions about a screen you are not testing.

`docs/AUTONOMOUS-FLEET-TESTING.md` is the METHOD — the part that transfers to
any app. This is the operating manual for *this* fleet: which devices, which
runners, which tier answers which question, and what is known not to work.
Cross-session bench sharing: `docs/DEVICE-LEASE.md`.

Ported from Archive-Watch's three harnesses (2026-08-29); see the memory
`device-harness-port-from-archive-watch`. **Audited against the code
2026-09-03** — every count and address below was read out of the tools, not
remembered.

---

## 1. The fleet

All six shipping platforms plus the web are now driven from this bench.

| Device | Runner (scenarios) | Address | Notes |
|---|---|---|---|
| Apple TV 4K "Ben Bedroom" | `tools/atv_run.py` (15) | `C3FBA9DE-4A60-555B-A65F-80D6809A275B` | wake over pyatv Companion |
| iPad Pro 12.9 (5th gen) | `tools/ios_run.py --device ipad` (6) | `AC5377E9-6053-51DE-8E65-D88A4E9345FA` | no remote wake |
| iPhone 12 | `tools/ios_run.py --device iphone` (6) | `B4E756E2-CBFA-5F63-8CEE-21D226637AF7` | no remote wake |
| Pixel 8a | `tools/adb_run.py --device pixel` (6) | adb `adb-3B211JEKB14516-4M5scf._adb-tls-connect._tcp` | **debug build required** |
| Fire TV (AFTKRT) | `tools/adb_run.py --device firetv` | adb `10.0.0.139:5555` | leanback build; 26/26 by remote |
| Android TV dongle (onn 4K) | `tools/adb_run.py --device androidtv` | adb `10.0.0.55:5555` | slow — poll to 40s, never sleep |
| macOS app | `tools/mac_run.py` (23) | `/Applications/TidbitsTrivia.app` | crops to the app's own window; drives by **pid** |
| Windows 10/11 box | `tools/win_run.py` (6) → `tools/winbox.py` | ssh, `TIDBITS_WIN_HOST=user@host` | whole-desktop capture; needs an Interactive scheduled task |
| Web | `tools/web_run.py` (14 routes) | `https://tidbitstrivia.com` | 375px **and** 1440px |

**The Apple TV has two identifiers and they are not interchangeable.**
`devicectl` wants the UDID `C3FBA9DE-…`; pyatv's Companion wants
`783F0C4E-201E-48FF-8C0D-D45595F4433E`. Using one where the other belongs looks
exactly like an unreachable device.

**The Mac and the web took their own runners** rather than a shared one — the
Mac needs window-bounds cropping and the web needs two viewports, and neither is
expressible as "another device" in the adb/devicectl sense. Both batch their own
scenarios behind `--only`; the device runners take one `--scenario` at a time.

Cross-device multiplayer has its own runner, because no per-device sweep can see
a desync: `tools/multiplayer_run.py --host mac|atv --players …` drives one hosted
room across the whole fleet and grades the **wire** (RTDB `live/{code}`) against
the **glass** (a screenshot of each device). See `docs/GO-LIVE-EVIDENCE.md`.

Run everything: `python3 tools/qa_suite.py` (smoke set) or `--full`.
Unreachable devices are reported **SKIP**, never as a pass — silence about an
untested platform is how a green board comes to mean nothing.

---

## 2. What else is on the bench

The runners photograph; these decide what to photograph, keep the bench sane,
and ask questions a screenshot sweep cannot.

| Tool | What it is for |
|---|---|
| `tools/qa_suite.py` | The matrix. Probes reachability, **shells out** to each runner so one hung device cannot take the sweep down, writes `summary.json`. |
| `tools/play_loop.py` | Coverage as STATE, not a fresh random sample. `build/qa/coverage.json` records per (platform, cell) when it was last verified; each lap takes never-run cells first, then the stalest. A cell is a game **played**, not a screen opened. |
| `tools/multiplayer_run.py` | One hosted room across every device, graded on the wire and the glass separately. |
| `tools/night_matrix.py` | Every platform hosts a Trivia Night, every other joins. Resumable via `build/qa/night-matrix.json`, because ~8 runs × ~8 min outlives any single sitting or background task. |
| `tools/rtdb_join.py` | Scripted anonymous-auth REST joiner — proves a host end-to-end without a second human. |
| `tools/devlease.py` | `~/.device-lease/<device>.json`. Take a lease before touching a device; never steal a live one (reclaim only when the owning pid is dead). |
| `tools/devreset.py` | Return a device to a known empty state, and `label()` it — `TIDBITS_QA_LABEL` renders an on-screen banner, so a photograph of the bench says what each device is testing. |
| `tools/hook_coverage.py` | Which surfaces this system can actually REACH, per platform. A gap here is not a failure — it is an unasked question, which reads identically to a pass. |
| `tools/tv_focus_audit.py` | On a TV: does anything HOLD focus, is the ring VISIBLE (measured as a pixel delta), does CENTER ACT. Android TV / Fire TV only. |
| `tools/atv_prompt_audit.py` | Renders the corpus's longest prompts on the real TV and asserts the text's **tail** reaches the glass. A static audit can say "131 prompts exceed 220 chars"; only this says whether any overflows. |
| `tools/atv_reveal_audit.py` | Drives random corpus rows to REVEAL and asserts the explanation renders — the learn-something-every-round promise, checked where the player sees it. |
| `tools/atv_report.py` | One table for a day of runs: every scenario dir, verdict, failed assertions, evidence path. |
| `tools/mac_keychain_ab.py` | A/B watch for a SecurityAgent password dialog in front of a player. The only evidence that counts is whether the dialog appears. |
| `tools/audit_picture_images.py` | Liveness of all 5,721 picture-round URLs, before a player finds the 404. |
| `tools/tv_store_shots.py`, `tools/capture-screenshots.sh`, `tools/capture-imessage-screenshots.sh` | Store captures, polled on each screen's own text signature rather than a fixed sleep. |

---

## 3. Physical prerequisites

These are not optional; the harness cannot work around them.

- **iPhone / iPad:** passcode **OFF**, Auto-Lock **Never**, device on a charger.
  iOS has no remote wake — `devicectl` cannot wake a locked device and there is
  no Companion protocol to borrow. A black capture is a locked screen, not a
  failed launch, and the runner will refuse to grade rather than guess.
- **Apple TV:** installs work while it sleeps; launches and screenshots do not.
  `atv_run.py` wakes it over Companion and **polls** until the box reports On —
  a launch into the doze window comes up backgrounded, which mimics an app bug.
- **Pixel 8a:** wireless debugging authorised once. The runner sets
  `svc power stayon true` so a long capture does not go dark halfway.
- **Windows box:** OpenSSH with public-key auth, `TIDBITS_WIN_HOST=user@host`.
  An SSH session lands in **session 0** — a phantom 1024×768 desktop where
  `MainWindowHandle == 0` and nothing launched is visible on the real screen.
  `winbox.py` reaches the interactive desktop through a scheduled task with an
  `Interactive` principal; without that you drive an invisible desktop and
  photograph nothing.

---

## 4. Pick the cheapest tier that can answer the question

Real hardware is the truth and it is also the slowest thing here. Most questions
have a cheaper honest answer, and the cost of using the wrong tier is not just
minutes — it is a green result that does not mean what it looks like.

| The question | Tier | Command |
|---|---|---|
| Is the shared logic right? | Unit + golden vectors | `tools/test-apple.sh` (279 `@Test`), `cd windows && dotnet test` (452 facts), Android unit (8 files), `tools/daily-parity/run.sh`, `tools/night-wire/run_golden.sh`, `tools/quiz-wire/` |
| Does the Windows UI render? | Headless Skia on the Mac, then real Windows | `cd windows && dotnet test` → `gh workflow run windows-repl.yml` → `gh run download` → `Read` the PNGs (~2–4 min) |
| Does every mode open at all? | Simulator / emulator sweep | `tools/qa-sweep.sh ios\|ipad\|tvos`, `tools/qa-sweep-android.sh` (log: `docs/QA-SWEEP-LOG.md`) |
| Does a human see it on the product? | **The fleet** | `tools/qa_suite.py`, or a single runner |
| Does it survive Android hardware we do not own? | Firebase Test Lab Robo, **physical devices only** | `tools/testlab-android.sh` — this IS Play's Pre-launch report; a virtual device has no Play Store, so it cannot see Billing, Integrity, Games, or a vendor skin (Decision 055) |
| Does the SHIPPED binary do it? | Read the binary, not the build log | `codesign -d --entitlements -`, `otool -L`, `pdftotext` on the artefact |

**A green build tells you almost nothing.** The tvOS Application Support write
that crashes on device passes on the simulator; the AVKit autolink bug built
green for an entire wave and aborted the app on first render. Compiles is not
works, and the tier that would have caught each of those was one row down.

---

## 5. The three rules that decide whether the loop is worth anything

### 5.1 Calibrate every threshold against a real capture. Never copy one.

Archive-Watch's clipped-text threshold is `x <= 0.010`. On our iPad, Tidbits'
own gutter puts body text at x=0.0116 and bold section headers at x=0.0099 —
that borrowed constant called three correctly-rendered Records headings clipped
on all ten frames. Verified against the pixels, then set to **0.005**
(`CLIP_X_DEFAULT` in `devharness.py`, with the calibration recorded beside it).

The same applies to `expect_any`. An assertion written from imagination fails on
correct pixels and teaches you to ignore the loop, which is exactly how a loop
stops being worth its cost. Every regex in `SCENARIOS` was written after looking
at a real capture of that surface, and tolerates the legitimate **empty state**
where one exists (a fresh debug install has no history, so Records correctly
reads "No games yet").

Two calibrations worth knowing because they look like bugs:
- Windows Records asserts on "Playing as Player", not on the copy the other
  platforms use — "Compete against your past self" is light grey on white and
  that display's OCR does not read it reliably. An assertion resting on it fails
  on a screen that rendered perfectly.
- The web's anchor is the question view's own signature (`1/7 HISTORY …`), not
  the wordmark. The site header is on every page, so anchoring there reports
  15/15 while showing one screen fifteen times.

### 5.2 An assertion that cannot fire is not an assertion.

The first Android calibration pass ran six scenarios and all six **passed** —
while every one of them was sitting on the Home screen. `ScreenshotHooks.apply()`
opens with `if (!BuildConfig.DEBUG) return`, so against the release build every
intent extra is silently ignored. The harness was measuring nothing and saying
it was fine.

**`tools/adb_run.py` therefore targets `com.tidbitstrivia.app.debug`.** If you
point it at the release package the hooks die silently. Install the debug APK
first:

```bash
cd android && ./gradlew assembleDebug
adb -s <serial> install -r app/build/outputs/apk/debug/app-debug.apk
```

Check the APK's date when a run looks wrong — the one on this machine was 24
days stale when the port started, and Archive-Watch once ran a whole session
against a stale APK without noticing.

The same rule applies to an assertion that is *accidentally* about something
else. The Live export receipt sat at the bottom of the builder, below the fold
at the default window height; the assertion on it was really asserting the
window size. **If a check depends on scroll position, it is measuring the
window, not the feature** — and in that case the finding was real: a
confirmation a host has to scroll to find cannot tell them the export worked.

### 5.3 Assert the artefact, not the app's opinion of it.

Where a feature produces a file, grade the file. `mac_run.py`'s print scenarios
assert the real PDF — 34,617 bytes over 2 pages for the host pack, 12,499 over 1
for the team sheet, page counts matched against the receipt — and then run
`pdftotext` over it: "Answer:" appears 10× in the HOST's pack and **zero** times
in the TEAM's sheet. A leak there hands the room the answers, and no assertion
on the SwiftUI page can see it.

The first version of that check used `textutil`, which does not extract PDF
text. It searched compressed bytes and reported "no answers leaked" for *both*
files — including the host pack, which is supposed to contain them. **The result
that proved it was broken was the one that looked like a pass.** If `pdftotext`
is missing, the check now FAILS rather than passing quietly.

Export/import is graded the same way: the export scenarios assert the bytes on
disk (10,275 of event JSON, 3,458 of CSV) and the import scenarios read back
what the exports just wrote, so together they are a **round trip through the
panels** rather than through the parser the unit tests already cover.

---

## 6. How a scenario reaches its surface

Never by pressing blind. Focus lands on the nearest item, not a fixed one, and a
blind press script labels its screenshots wrong.

- **Apple (iOS/tvOS/macOS)** — env vars via `devicectl … -e '<json>'` or
  `SIMCTL_CHILD_*`, read by `Core/Store/DebugHooks.swift` and its Live siblings:
  **79 `TIDBITS_*` hooks**. `TIDBITS_TAB=play|records|create`,
  `TIDBITS_SETTINGS=1`, `TIDBITS_PAYWALL=1`, `TIDBITS_CLUB=1`,
  `TIDBITS_AUTOPLAY`, `TIDBITS_AUTOPILOT`, `TIDBITS_SEED_RECORDS`,
  `TIDBITS_QA_LABEL`, … iOS can additionally launch straight into a deep link
  with `--payload-url`; tvOS cannot.
- **Android** — intent extras read by `ScreenshotHooks.kt` (**17 hooks**):
  `--es tidbits_tab <tab>`, `--es tidbits_open <route>`,
  `--ez tidbits_skip_onboard true`. `tidbits_open` accepts `clubHub`, `paywall`,
  `atlas`, `linkWall`, `expeditions`, `storyArchive`, `marathonHistory`,
  `settings`, `profile`, `leaderboard`, `duels`, `online`. An unknown value is
  ignored rather than crashing a sweep — so a typo shows up as "wrong screen".
- **Windows** — the same `TIDBITS_*` spelling, read from the environment by
  `Tidbits.Core` (**23 hooks**). Windows honours a subset: `TIDBITS_TAB`,
  `TIDBITS_CLUB`, `TIDBITS_LIVE_*`, `TIDBITS_MARATHON_LEN`, `TIDBITS_PARTY`,
  `TIDBITS_PAYWALL`, `TIDBITS_SEED_RECORDS`, `TIDBITS_SETTINGS`,
  `TIDBITS_SKIP_ONBOARD`, `TIDBITS_QA_LABEL`.
- **Web** — routes (`/#/daily`, `/#/live`, …) plus `tidbits_qa_label`, and
  `tools/webdrive.py` (Chrome DevTools Protocol, stdlib only) when a scenario
  must TYPE or CLICK. Driving the real browser was chosen over adding an
  auto-join URL parameter: that would be changing the product to make a test
  pass, and would ship a "join as any name" link for the harness's convenience.

`python3 tools/hook_coverage.py` prints the matrix and currently reports **0
unreachable surfaces** across 13 capabilities. A `-` cell means "no equivalent
on that platform" — a declared claim, worth re-checking when that platform grows
the feature.

**A hook must be able to create the PRECONDITION, not just open the screen.**
The tvOS BUZZ button shipped, built green, and had never been photographed,
because it only renders when a host publishes `buzz == true` and nothing could
make a host do that. It took a hook on the *host* side (`TIDBITS_LIVE_BUZZ=1`
marks round 1 a buzz round on the Mac) before the TV scenario could exist. The
same shape now covers the video round (`TIDBITS_LIVE_VIDEO`,
`TIDBITS_LIVE_STATE=video`) and the board. A screen you can open but cannot put
into the state that renders the element is still an unphotographed element.

**Where the platform blocks scripting, put the seam at the platform edge.**
`NSSavePanel.runModal()` is not scriptable, so `chooseSaveURL` / `chooseOpenURL`
return the panel's answer or `TIDBITS_LIVE_FILE`'s when a harness supplies one,
and `TIDBITS_LIVE_FILEOP` fires one operation on launch. Both are no-ops in
production. Under the App Sandbox a **bare filename resolves inside the app's
own Documents directory** — an absolute path is still honoured and still fails,
exactly as it would for a user.

---

## 7. Known limitations, so they are not re-diagnosed

- **`qa_suite.py` has no Windows row.** `PLATFORMS` covers atv, ipad, iphone,
  pixel, firetv, androidtv, mac and web; `win_run.py` exists and works but must
  be invoked directly. The sweep is therefore *silent* about Windows rather than
  reporting SKIP, which is the one thing this suite is built not to do. Real
  gap, recorded here rather than presented as coverage. The gate that does cover
  Windows is `windows-repl.yml` / `windows-build.yml` on `windows-latest`.
- **tvOS has no focus verification.** `tv_focus_audit.py` is adb-only
  (`firetv`, `androidtv`); `atv_run.py` drives presses but nothing checks which
  element *has* focus on the Apple TV. The MCQ bug it was written to catch —
  six focusable nodes, zero focused, CENTER does nothing — is exactly the class
  tvOS is still blind to.
- **Android paywall prices cannot be verified on the debug build.**
  `com.tidbitstrivia.app.debug` is not a Play-registered package, so
  `queryProductDetailsAsync` returns nothing and the sheet correctly reads
  "Couldn't load plans." The iPad shows no such failure, which is how this was
  told apart from a real regression. The paywall scenario **narrows** its error
  check rather than disabling it — any other error string still fails. Real
  price verification needs a Play-signed internal-track build, or Test Lab on a
  physical device.
- **The Apple TV drops remote presses after ~80 automated runs** (F-009).
  Warmed presses mitigate it; `devicectl device reboot` is the only cure. Reboot
  proactively at ~70 runs. This is harness-class — real Siri remotes are fine.
- **`atv_run` reports "TV dozing" on any static screen.** The heuristic is
  screenshot BYTE SIZE, and a correctly-rendered screen that simply is not
  changing produces identical frames run after run. The first buzz run printed
  it 16 times while the glass held a perfectly good question. Treat it as
  "nothing changed", not "nothing rendered" — read a frame before acting on it.
- **A pinned QA room code is owned by its FIRST host forever.** `live/{code}`
  rules give the host uid sole write access to `meta`/`pub`, so a later host with
  a different anonymous uid is **silently refused** — `net.open()` fails, the app
  shows no error, and every reader sees the ORIGINAL host's payload. QATV is
  squatted this way (created 2026-08-26, `meta.name` still "Trivia Night"). This
  cost a full diagnostic pass: the TV joined correctly, rendered correctly, and
  showed the wrong round, because the room it joined was not the one being
  hosted. Symptom to recognise: `meta.name` is not the event name you launched
  with. Use a FRESH code (the buzz scenario uses QABZ), and check the wire
  before blaming the glass.
- **The outside-container bookmark grant is not automatable at all.** The Mac
  app is sandboxed, so it cannot open a path it was never granted — and a path
  handed in by a harness never has a grant. `TIDBITS_LIVE_AVSELFTEST_PATH`
  pointed outside the container therefore reports FAIL *whether or not*
  `files.bookmarks.app-scope` is set (error -54 is the permission error). That
  is the exact mirror of the flaw it was written to fix: the earlier version
  bookmarked INSIDE the container and reported OK either way. Neither
  distinguishes the case. Both entitlements were confirmed present by reading
  the shipped binary (`codesign -d --entitlements`), which is the check that
  actually answers the question. The `avselftest` scenario now asserts only
  what it can establish — the summary renders, and the in-container case works.
  The entitlement's real exercise is a human picking a file at the panel.
- **`tools/qa-sweep-android.sh` does not cover the Club/dialog surfaces.**
  Android's hook set is smaller than Apple's; that gap is recorded in
  `docs/QA-SWEEP-LOG.md` rather than quietly presented as coverage.

**No longer true** — Fire TV and the Android TV dongle used to be listed here as
"a missing platform, not a missing harness," because the manifest declared no
leanback feature, no TV launcher intent and no banner. It now declares all three
(`LEANBACK_LAUNCHER`, `android:banner`), both boxes run the leanback build, and
26/26 surfaces were verified by remote. They are ordinary fleet rows.

---

## 8. Artifacts

Every run writes `build/qa/<platform>-<date>/<name>-<epoch>/` containing the
PNGs and a `report.json` of every assertion with its evidence. `qa_suite.py`
writes a `summary.json` beside them; `play_loop.py` keeps `build/qa/coverage.json`
and `night_matrix.py` keeps `build/qa/night-matrix.json`. Durable, never `/tmp`:
background tasks get reaped, and a capture you cannot return to is a capture you
have to take twice.

Because every result is JSON, runs are diffable across time. Archive-Watch's
Android and iOS harnesses print and exit, so nothing there can be compared and
there is no regression baseline at all.
