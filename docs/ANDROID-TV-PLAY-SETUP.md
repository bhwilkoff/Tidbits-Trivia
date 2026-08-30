# Android TV on Google Play — what is automated and what is not

The app is TV-ready and verified on real hardware (26/26 surfaces usable by
remote on both the Fire TV and the Google TV dongle — see `PARITY.md`). Getting
it *distributed* to TVs is partly scriptable and partly not, and the split is
not obvious, so it is written down here.

---

## 1. The hard constraint

**The `androidpublisher` v3 API has no form-factor resource.** `edits` exposes
exactly: `apks`, `bundles`, `countryavailability`, `deobfuscationfiles`,
`details`, `expansionfiles`, `images`, `listings`, `testers`, `tracks`. There is
nothing for declaring Android TV support.

So the Android TV opt-in **cannot be automated**. It is a Console action, and it
starts a separate Google review against the TV quality guidelines — which is a
different review from the phone app's, with its own outcome.

Anyone who tells you the TV form factor was "configured via the API" has
configured something else.

---

## 2. What IS automated

`tools/tv_store_shots.py` captures store-ready TV screenshots from a real
device, and the Play images API can upload them plus the TV banner:

```bash
python3 tools/tv_store_shots.py --device androidtv   # 6 verified 1920x1080 shots
```

Assets ready in the repo:

| Asset | Where | Notes |
|---|---|---|
| TV banner (320x180) | `android/app/src/main/res/drawable-xhdpi/tv_banner.png` | also shipped in the APK |
| TV screenshots (6) | `build/store/tv-screenshots/*.png` | 1920x1080, 16:9, 24-bit RGB |

The capture polls for each screen's own text signature instead of sleeping.
Two bugs are baked into that decision and should not be re-learned:

- A fixed 9s sleep produced six files that were **all the Home screen**. The
  Google TV dongle has 2GB of RAM and needs ~18s to draw a pushed route
  (logcat: "Skipped 274 frames", 5s frame times). A screenshot taken early is
  not a screenshot of the surface you asked for.
- The signature must be **unique to its screen**. Seeding records to populate
  the Records tab also puts "12-day streak" on Home, so a `DAY STREAK`
  signature matched the wrong screen and the capture passed its own check while
  being Home. The set is now compared against itself for duplicates, because
  six identical images pass every per-file check.

---

## 3. Owner steps, in order

1. **Play Console → the app → Release → Setup → Advanced settings → Form
   factors → Add form factor → Android TV.** This is the step that cannot be
   scripted.
2. Upload the TV banner and TV screenshots (or approve the API upload — the
   images are staged but **not committed**, because committing an edit
   publishes to the live listing).
3. Answer the TV declaration questions. The app is a D-pad game with no
   touch-only surfaces; free recall uses a self-mark rather than a keyboard, so
   there is no text-entry blocker to declare.
4. Submit for the **Android TV review**. It is separate from the phone review
   and can be rejected on TV-specific quality grounds while the phone app is
   fine.

## 4. Fire TV is a different store

The Fire TV Stick does **not** ship through Google Play. It is the **Amazon
Appstore**, with its own developer console, its own submission, and its own
review. The same APK/AAB is the starting point, but nothing about the Play
setup above carries over. Treat it as a separate channel, planned separately.

Fire TV also has no Google Play Services, so anything that hard-requires GMS
must degrade. The manifest already declares gamepad and touchscreen as not
required.

## 5. Re-verify before any submission

```bash
# 26-surface remote-usability walk; run in batches, a full walk exceeds 600s
python3 tools/tv_focus_audit.py --device androidtv --only home,records,create,settings,paywall,clubHub,atlas,linkWall,expeditions
python3 tools/tv_focus_audit.py --device firetv   --only ...
```

A surface that does not show its own content is FAIL regardless of how healthy
its focus looks — that check exists because an earlier version of this walk
reported 26/26 while every capture was the Home screen.
