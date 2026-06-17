# Deep links — the cross-platform contract

A URL is a string that has to mean the same thing on every platform.
This doc is the contract. Pick the routes ONCE at project start;
every web view, Apple `View`, and Android `composable(...)` reads
from the same table.

## URL shapes

Pick path-prefix scoping (one path per resource type) — Android
`autoVerify="true"` and iOS `appID...paths` both need explicit
prefix lists, and a flat structure makes the lists short.

| Resource | URL shape | Owner |
|---|---|---|
| Public profile | `https://app.example.com/u/{username}` | Web renders; iOS + Android open the in-app view |
| Single item detail | `https://app.example.com/item/{id}` | All platforms render in-app; web is the landing twin |
| Settings deep entry | `https://app.example.com/settings/{section}` | All; web routes via `?view=settings&section=...` |
| OAuth callback | `appname://oauth/callback?...` | Custom scheme only — never HTTPS (provider redirects break otherwise) |

**Add a row to this table BEFORE adding a deep link in code.** New
routes that aren't documented here become orphans the next time a
platform adds support — discovery cost compounds.

**The canonical-twin rule**: every custom-scheme link a native app
emits (`appname://item/x`) has an HTTPS twin
(`https://app.example.com/item/x`) that the WEB app renders — so a
share always lands somewhere meaningful, even for recipients
without the app. On a static host, a `404.html` forwarder that maps
`/item/{id}` into the web app's router makes the twins real before
server-side routes exist.

## Per-platform wiring

| Platform | Where to register | Where to dispatch |
|---|---|---|
| **Web** | Nowhere — URLs are the routing (+ `404.html` forwarder on static hosts) | `js/app.js::init()` reads `location.search` + `pathname` |
| **iOS / iPadOS** | `Info.plist` `CFBundleURLTypes` (custom scheme) + Associated Domains entitlement (Universal Links) | `App.scene.onOpenURL` — fires for BOTH custom and Universal Links on iOS 17+ → post to the intent inbox |
| **tvOS** | `Info.plist` `CFBundleURLTypes` — custom scheme ONLY (no Safari on tvOS → no Universal Links; the scheme is what Top Shelf + Siri use) | same `.onOpenURL` → same inbox (universal target) |
| **Android** | `AndroidManifest.xml` `<intent-filter android:autoVerify="true">` per scheme + path-prefix | `MainActivity.onCreate` + `onNewIntent` → `handleDeepLink(intent)` switches by `uri.scheme` |

**Android manifest audit**: EVERY host/path the app emits anywhere
(share sheets, QR codes, widgets) must be declared in an
intent-filter — an undeclared route fails silently for external
opens while in-app navigation works, which is why it ships broken.
Test each route with
`adb shell am start -a android.intent.action.VIEW -d <url>`.

**Sharing from a TV**: a tvOS app can't invoke a share sheet to
another person — render the HTTPS twin as an on-screen **QR code**.

## Verification files

Both iOS and Android verify HTTPS deep-links via files at
`/.well-known/` **at the domain root** — a project-pages subpath
(`user.github.io/repo/.well-known/`) does NOT work for iOS; you
need a user site or a custom (apex) domain. See
`.well-known/README.md` for the JSON shapes:

- iOS: `apple-app-site-association` (no extension)
- Android: `assetlinks.json`

Common failures, all production-verified:

- **File missing from the published build.** GitHub Pages runs
  Jekyll by default, which silently drops dot-directories — add a
  `.nojekyll` file at the root (or `include: [.well-known]` in
  `_config.yml`).
- **Android: only the upload-key fingerprint listed.** Production
  installs are PLAY-signed: add the Play App Signing SHA-256
  (Console → Setup → App signing) immediately after enrollment, or
  App Links break only in production.
- **iOS: entitlement flipped mid-review.** Adding Associated
  Domains re-signs the app — don't change it while a build is in
  flight.
- Symptoms (disambiguation chooser on Android; URL opens Safari on
  iOS) look like OS bugs; the bug is always the verification file.

## Path-prefix discipline

Each new resource type needs a path prefix added to ALL surfaces in
one PR:

1. `.well-known/apple-app-site-association` — `applinks.details[].paths`
2. `.well-known/assetlinks.json` (the manifest below gates prefixes)
3. `android/app/src/main/AndroidManifest.xml` — `<data android:pathPrefix="/newresource"/>`
4. The Apple `.onOpenURL` dispatcher / intent inbox — add the case
   (one dispatcher serves iOS + tvOS in the universal target)
5. `MainActivity.kt` `handleDeepLink` — add the case + route
6. `js/app.js` URL parser (+ `404.html` forwarder map) — handle the
   new route

The dispatcher logic switches by SCHEME (`https` vs custom), THEN by
path — never by URL shape alone. The hard-won lesson:
`url.scheme == "myapp"` silently drops every HTTPS Universal Link
because the scheme check excludes the wrong half.

## OAuth callbacks specifically

OAuth providers require a redirect URI. On mobile, that's ALWAYS a
custom scheme — HTTPS redirects go through the system browser and
break the back-to-app hop:

- Android: `appname://oauth/callback` in the manifest; Custom Tabs
  handles the round trip.
- iOS: same shape in `Info.plist` `CFBundleURLTypes`.
- Web: `https://app.example.com/oauth/callback` — no special
  handling.
- tvOS: avoid OAuth-in-browser entirely (there is no browser) —
  use Sign in with Apple natively, or a device-code flow if a
  third-party provider is unavoidable.

Don't try to unify the mobile and web callback URLs — the OAuth
spec doesn't, and the providers don't.
