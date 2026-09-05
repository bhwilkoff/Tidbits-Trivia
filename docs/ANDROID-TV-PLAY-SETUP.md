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
| Launcher banner (320x180) | `android/app/src/main/res/drawable-xhdpi/tv_banner.png` | `android:banner`, ships INSIDE the APK |
| Play listing banner (1280x720) | `docs/store/android-tv/tv_banner_1280x720.png` | store asset — a DIFFERENT thing |
| TV screenshots (6) | `docs/store/android-tv/0*.png` | 1920x1080, 16:9, 24-bit RGB |

**The two banners are not the same asset.** The 320x180 drawable is the TV
launcher tile; Play's listing `tvBanner` must be **1280x720** and rejects the
320x180 outright ("Invalid dimensions - expected width: [1280]"). Uploading the
launcher banner to the listing fails, which is how the distinction surfaced.

The whole set has been validated against the live API — staged into an edit,
uploaded, `edits().validate()` passed, then the edit was **deleted**, so the
upload path is proven end to end with nothing published:

```bash
# see the validation block in the wave-5 commit; it stages, validates, rolls back
```

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

---

## 6. TV-BN: the rejection that vc93 earned, and how to not earn it again

**versionCode 93 was REJECTED** (2026-09-05) under the Android TV App Quality
Guidelines. It was the first production build carrying `LEANBACK_LAUNCHER`, and
that is what put it in front of a TV reviewer at all.

> Issue found: No full-size app banner and/or icon
> Your icon does not fill the entire icon space.
> TV-BN: The app launch banner contains the name of the app.
> Version code 93: In-app experience: Please see attached screenshot

**A TV rejection blocks the WHOLE app update, not just the TV form factor.**
"Changes to your app weren't published" — phone and tablet users did not get
1.7.1 either. The TV opt-in is not a side channel; it is a gate on every ship.

### What was actually wrong

Both assets were the right SIZE and the wrong SHAPE. Nothing in the pipeline
measured them, because "320x180 exists in drawable-xhdpi" was treated as the
requirement:

| Asset | Was | Requirement |
|---|---|---|
| `tv_banner.png` | 320x180, but its artwork filled **79.7% x 57.8%** — 38px of dead cream top and bottom | Artwork to all four edges |
| launcher icon | adaptive foreground fills **62%** of its canvas | Fills the icon space |

The 62% is *correct on a phone* — it is the adaptive-icon mask safe zone. It
reads as "doesn't fill" on a TV that draws the icon without that viewport. The
fix therefore must not touch the phone icon.

### The fix

`python3 tools/branding/make_tv_assets.py` generates all three, full-bleed:

- `res/drawable-xhdpi/tv_banner.png` — 320x180, artwork edge to edge, app name in
  ink on the coral field (ink-on-coral is 6.5:1; cream-on-coral is 2.3:1 and is
  not a ten-foot pair).
- `res/mipmap-television-{xhdpi,xxhdpi}/ic_launcher.png` — 512x512, tile at 0.70
  of the frame. **The `television` UI-mode qualifier outranks density and version
  in resource resolution**, so a TV takes these bitmaps while every phone keeps
  the adaptive icon in `mipmap-anydpi-v26`. That is what makes a TV-only icon
  possible without a second app.
- `branding/play-tv-banner-1280x720.png` — the Play listing banner.

The generator auto-fits the wordmark to the frame. The first cut hard-coded a
point size and rendered a banner reading **"TIDE"** — the frame ran out before
the word did, and no check could have caught it, which is exactly why the fit is
computed rather than tuned.

### Verifying it — and the cache that will fool you

Read the artifact, then the glass:

```bash
unzip -l app-debug.apk | grep -E "tv_banner|television"   # is it even in there?
adb -s <tv> uninstall com.tidbitstrivia.app.debug          # NOT just install -r
adb -s <tv> install -r app-debug.apk
```

**The Google TV launcher caches banners.** After `install -r` the row kept
showing the OLD banner while the APK provably contained the new one (md5 against
the source). Only uninstall + install refreshed it. Do not clear the launcher's
data to force this — on the owner's real TV that resets their Favorite Apps.

Then photograph the apps row and compare against the neighbouring tiles. Every
compliant neighbour (Netflix, tivimate, Archive Watch) is edge-to-edge artwork;
if ours is a small mark floating in a flat field, it fails, whatever its pixel
dimensions say.

### Where the reviewer's evidence lives

The rejection email carries a screenshot (`IN_APP_EXPERIENCE-*.png`) that names
the surface, and the Play API cannot see any of it — `edits.tracks` shows
`status=completed versionCodes=['93']` for a build that was rejected. The email
is the only source. Its attachment is on disk under
`~/Library/Mail/V10/*/[Gmail].mbox/.../Attachments/` when Mail has synced it.
