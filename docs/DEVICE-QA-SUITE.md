# Device QA Suite — real hardware, every platform

**Doctrine:** the app's own claims are never the evidence for what a player
sees; the screen is. Its corollary is what keeps a loop worth running — *an
instrument must say when it is blind*. A null result from a blind instrument is
indistinguishable from a real absence, and a **readable frame of the wrong
screen is worse than a blank one**, because it survives every check and then
answers questions about a screen you are not testing.

Ported from Archive-Watch's three harnesses (2026-08-29). See the memory
`device-harness-port-from-archive-watch` for what transferred and what did not.

---

## 1. The fleet

| Device | Runner | Address | Notes |
|---|---|---|---|
| Apple TV 4K "Ben Bedroom" | `tools/atv_run.py` | `C3FBA9DE-4A60-555B-A65F-80D6809A275B` | wake over pyatv Companion |
| iPad Pro 12.9 (5th gen) | `tools/ios_run.py --device ipad` | `AC5377E9-6053-51DE-8E65-D88A4E9345FA` | no remote wake |
| iPhone 12 | `tools/ios_run.py --device iphone` | `B4E756E2-CBFA-5F63-8CEE-21D226637AF7` | no remote wake |
| Pixel 8a | `tools/adb_run.py --device pixel` | adb `adb-3B211JEKB14516-…_adb-tls-connect._tcp` | **debug build required** |
| Fire TV (AFTKRT) | — | adb `10.0.0.139:5555` | **no Tidbits TV build exists** |
| Android TV dongle (onn 4K) | — | adb `10.0.0.55:5555` | **no Tidbits TV build exists** |

Run everything: `python3 tools/qa_suite.py` (smoke set) or `--full`.
Unreachable devices are reported **SKIP**, never as a pass — silence about an
untested platform is how a green board comes to mean nothing.

---

## 2. Physical prerequisites

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

---

## 3. The two rules that decide whether the loop is worth anything

### 3.1 Calibrate every threshold against a real capture. Never copy one.

Archive-Watch's clipped-text threshold is `x <= 0.010`. On our iPad, Tidbits'
own gutter puts body text at x=0.0116 and bold section headers at x=0.0099 —
that borrowed constant called three correctly-rendered Records headings clipped
on all ten frames. Verified against the pixels, then set to **0.005**.

The same applies to `expect_any`. An assertion written from imagination fails on
correct pixels and teaches you to ignore the loop, which is exactly how a loop
stops being worth its cost. Every regex in `SCENARIOS` was written after looking
at a real capture of that surface, and tolerates the legitimate **empty state**
where one exists (a fresh debug install has no history, so Records correctly
reads "No games yet").

### 3.2 An assertion that cannot fire is not an assertion.

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

---

## 4. How a scenario reaches its surface

Never by pressing blind. Focus lands on the nearest item, not a fixed one, and a
blind press script labels its screenshots wrong.

- **Apple (tvOS/iOS)** — env vars via `devicectl … -e '<json>'`, read by
  `DebugHooks.swift`: `TIDBITS_TAB=play|records|create`, `TIDBITS_SETTINGS=1`,
  `TIDBITS_PAYWALL=1`, `TIDBITS_CLUB=1`, … (52 hooks). iOS can additionally
  launch straight into a deep link with `--payload-url`; tvOS cannot.
- **Android** — intent extras read by `ScreenshotHooks.kt`:
  `--es tidbits_tab <tab>`, `--es tidbits_open <route>`,
  `--ez tidbits_skip_onboard true`. `tidbits_open` accepts `clubHub`, `paywall`,
  `atlas`, `linkWall`, `expeditions`, `storyArchive`, `marathonHistory`,
  `settings`, `profile`, `leaderboard`, `duels`, `online`. An unknown value is
  ignored rather than crashing a sweep — so a typo shows up as "wrong screen".

---

## 5. Known limitations, so they are not re-diagnosed

- **Android paywall prices cannot be verified on the debug build.**
  `com.tidbitstrivia.app.debug` is not a Play-registered package, so
  `queryProductDetailsAsync` returns nothing and the sheet correctly reads
  "Couldn't load plans." The iPad shows no such failure, which is how this was
  told apart from a real regression. The paywall scenario **narrows** its error
  check rather than disabling it — any other error string still fails. Real
  price verification needs a Play-signed internal-track build.
- **Fire TV / Android TV are a missing platform, not a missing harness.**
  `AndroidManifest.xml` declares no leanback feature, no TV launcher intent and
  no banner; Archive-Watch's declares leanback three times. Both boxes are
  reachable and already run Archive Watch. A harness for them is meaningless
  until a Tidbits TV build exists — an owner decision, the way tvOS was.
- **The Apple TV drops remote presses after ~80 automated runs** (F-009).
  Warmed presses mitigate it; `devicectl device reboot` is the only cure. Reboot
  proactively at ~70 runs. This is harness-class — real Siri remotes are fine.
- **tvOS focus has no automated coverage** in either repo. `atv_run.py` drives
  presses; nothing verifies which element *has* focus.

---

## 6. Artifacts

Every run writes `build/qa/<platform>-<date>/<name>-<epoch>/` containing the
PNGs and a `report.json` of every assertion with its evidence. `qa_suite.py`
writes a `summary.json` beside them. Durable, never `/tmp`: background tasks get
reaped, and a capture you cannot return to is a capture you have to take twice.

Because every result is JSON, runs are diffable across time. Archive-Watch's
Android and iOS harnesses print and exit, so nothing there can be compared and
there is no regression baseline at all.
