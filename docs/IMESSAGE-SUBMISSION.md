# Shipping the iMessage app

The extension ships **inside the existing iOS app** — same app record, same
submission, same version. There is no second app to create and no second review.

What it does add is a **required, separate screenshot section** in App Store Connect.
A build with an iMessage extension and no iMessage screenshots cannot be submitted:
Connect blocks it with *"You must upload an iMessage screenshot"*
([forum thread 681289](https://developer.apple.com/forums/thread/681289)), and that
error appears at the moment you press Submit, not when you upload the build.

---

## What is already done in the repo

| Item | State |
|---|---|
| `TidbitsMessages` target (`app-extension.messages`, iOS-only) | ✅ in `project.yml` |
| Embedded in the app as `Tidbits.appex`, `platformFilter: iOS` | ✅ verified in the built product |
| `NSExtensionPointIdentifier = com.apple.message-payload-provider` | ✅ verified in the built `Info.plist` |
| iMessage App Icon set (9 sizes, `.stickersiconset`) | ✅ `TidbitsMessages/Assets.xcassets` |
| 849KB question pack, 3,200 questions, 8 categories | ✅ `tools/gen_imessage_pack.py`, committed |
| Wire-format golden tests (10) | ✅ `TidbitsTriviaTests/RoundStateTests.swift` |
| iMessage screenshots | ⏳ see below |
| Connect's iMessage section filled in | ⏳ **browser-only, owner step** |

The iMessage app **inherits the iOS app's name, description, category and keywords** —
a bundled extension is listed with the same metadata as its host app. There is nothing
separate to write.

## The one thing that is browser-only

Connect's iMessage screenshot well is drag-and-drop in the version page; the API path
exists but the practical route is the browser.

1. App Store Connect → **Apps** → Tidbits
2. Sidebar → the **iOS** version you are submitting (1.6.80 or later)
3. Scroll to the **iMessage App** section, click the disclosure triangle
4. Drag the screenshots from `branding/store-screenshots/imessage-*` into the well
5. Submit as normal

Up to 5 per localization. Apple's guidance for a bundled extension: show the iMessage
experience, and **do not** show the Home screen or the app→extension transition.

## Generating the screenshots

```bash
tools/capture-imessage-screenshots.sh iphone   # then: ipad
```

**The script stages the simulator; it does not take the shots.** Opening the Messages
drawer and picking Tidbits needs taps, and there is no way to send one — `simctl` has
no tap primitive and XCUITest can only drive your own app, not Messages. The only
automated route left would be clicking the Simulator window at guessed coordinates,
which is the same blind-coordinate click the device harnesses in this repo refuse to
do elsewhere, and for good reason.

So it boots the simulator, builds, installs (verifying `Tidbits.appex` is actually
embedded), opens Messages, and prints the four shots to take. About two minutes by
hand — and these are assets worth art-directing anyway.

Capture with `xcrun simctl io <UDID> screenshot <file>.png`, which writes at the
device's native size (1320×2868 iPhone 6.9", 2064×2752 iPad 13"). Apple publishes no
separate iMessage dimensions; Connect accepts the device sizes.

## Verified on device (2026-09-01)

A round plays end to end between a real iPhone and iPad on iOS 26: the round sends,
the bubble opens, questions advance, and the reveal shows the explanation.

**The iOS 26 relaunch bug does not affect this app.** Tapping the bubble opens the
extension reliably and repeatedly. That was the open risk that could have killed the
feature; it is closed by testing rather than by Apple confirming a fix.

Three device-only bugs were found and fixed getting there, all invisible locally:
the extension ran in dark mode (an extension does not inherit its host app's
appearance, so the name field was white-on-white); `MSMessage.url` was silently
stripped because it used a custom scheme instead of a universal link; and answering
required pressing Send because the code used `insertMessage:` rather than
`sendMessage:`.

## Submitted

**1.7.0 (123) is WAITING_FOR_REVIEW** as of 2026-09-01, with the iMessage extension,
8 iMessage screenshots (4 iPhone + 4 iPad) and release notes.

The whole ship is a CLI now — no console session:

```bash
tools/capture-imessage-screenshots.sh all          # render + capture, exact ASC sizes
gh workflow run appstore-build.yml -f platform=ios # build + upload the binary
gh workflow run imessage-screenshots.yml \
  -f mode=upload -f create_version=1.7.0 -f attach_build=123 \
  -f release_notes="..." -f submit=true
```

`-f mode=status` reports what a version is still missing (state, attached build,
per-set screenshot delivery) — worth running before submitting.

### Three blockers, none of which fail at build time

All three archived green and surfaced only at upload or submit:

1. **A new extension target needs its App ID registered.** Signing died with "bundle
   id not found in App Store Connect: ...Messages (register it first)".
   `asc_profiles.py` now registers it. Apple rejects `.` and `_` in a bundle id's
   NAME (the identifier itself is fine).
2. **The icon set needs `"platform": "ios"`** on its `universal` and `ios-marketing`
   entries, or actool silently drops them and no `MSMessagesExtensionStoreIconName`
   is written. `MessagesIconTests` pins it.
3. **`POST /v1/appStoreVersionSubmissions` is deprecated** (403, "Allowed operation
   is: DELETE"). Submission is now `reviewSubmissions` -> `reviewSubmissionItems` ->
   PATCH `submitted: true`.

Also worth knowing: **a TestFlight upload does not open an App Store version.** 1.6.80
had builds uploaded and no version record at all, which is why the first screenshot
run found only a READY_FOR_SALE 1.6.73.

## Review notes worth pre-empting

- **No account, no purchase, no network.** The extension is entirely offline: a
  bundled question pack and message-passing. Nothing for a reviewer to sign into.
- **Guideline 4.7 / mini-apps does not apply** — questions ship in the binary; nothing
  is downloaded or executed.
- **Privacy.** The extension reads `localParticipantIdentifier`, an opaque
  per-conversation UUID, and stores only a display name in `UserDefaults`. No
  contacts, no identifiers for tracking, nothing leaves the device. The existing
  privacy nutrition labels do not need to change; `PrivacyInfo.xcprivacy` needs no new
  reason codes.
