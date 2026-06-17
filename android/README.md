# Android module — QuadAppTemplate

Native Kotlin + Jetpack Compose codebase for the Android client.
Lives under `/android/` in the same monorepo as web (`/`, `/css/`,
`/js/`) and iOS (`/ios/`).

## First-time bootstrap

```sh
# 1. Generate the Gradle wrapper jar (committed gradle-wrapper.properties
#    points to Gradle 8.13; the .jar is generated on first run).
cd android
gradle wrapper --gradle-version 8.13

# 2. Drop your secrets into ~/.gradle/gradle.properties (or this dir's
#    gradle.properties + add it to .gitignore):
#       GOOGLE_WEB_CLIENT_ID=...
#       UPLOAD_KEYSTORE_PATH=...
#       UPLOAD_KEYSTORE_PASSWORD=...
#       UPLOAD_KEY_ALIAS=...
#       UPLOAD_KEY_PASSWORD=...

# 3. Open in Android Studio (Panda or newer):
studio .

# 4. First build (downloads SDK + AGP + Compose + Kotlin):
./gradlew :app:assembleDebug
```

If `gradle wrapper` isn't installed locally, install via Homebrew
(`brew install gradle`) once — the wrapper script self-bootstraps
after that.

## Open in Android Studio without the Gradle CLI

After cloning, point Android Studio at the `android/` folder
(File → Open → `android/`). Android Studio handles the wrapper
generation automatically the first time you sync.

## Versioning

`app/build.gradle.kts` defines `versionCode` + `versionName`. Bump
on every ship — same idiom as iOS `AppVersion.xcconfig`. CI should
fail the build if either field hasn't moved since the last tag.

## Gradle conventions

- **Version catalog only.** All dep versions live in
  `gradle/libs.versions.toml`. Build files reference `libs.foo.bar`.
  Never hardcode a version string in a `build.gradle.kts`.
- **Type-safe `R` references** (`android.nonTransitiveRClass=true`).
- **Configuration cache** + parallel + cache all on. CI can override
  with `--no-configuration-cache` if needed for debugging.

## Modular split — next steps

The template ships single-module to keep the bootstrap minimum.
When the app crosses ~10 screens or build times get painful, split:

```
android/
├── app/                         # composition root, manifest
├── baselineprofile/             # Macrobenchmark module
├── core/
│   ├── ui/                      # design system + primitives
│   ├── data/                    # repositories, Room
│   ├── domain/                  # PURE Kotlin — seed for KMP :shared
│   └── network/                 # Ktor + API wrappers
├── feature/
│   ├── home/
│   └── profile/
└── build-logic/                 # convention plugins
```

Update `settings.gradle.kts` with the `include(...)` lines and move
existing code into the new modules incrementally — never as one
big-bang refactor.

## What the template intentionally does NOT include

- **No `google-services.json`** — drop it in once Firebase is set up.
- **No keystore** — generate locally; never commit.
- **No third-party-tracked binaries** — keystore, Firebase config,
  Play service-account JSON all live outside the repo.
- **No baseline profile** — generate when the app has a real cold-
  start path worth measuring.

## CI

`/.github/workflows/android-build.yml` (in repo root) runs the
PR build + Play Store upload on tag push. Service-account JSON
lives in GitHub Secrets (`PLAY_SERVICE_ACCOUNT_JSON`). Keystore
creds also in Secrets and reconstructed at build time via
`echo "$KEYSTORE_BASE64" | base64 -d > keystore/upload.jks`.

## Design + engineering docs

- **Binding design rules:** `ANDROID-DESIGN.md` (repo root)
- **Engineering reference:** this README + per-skill triggers
  (e.g. `chrisbanes/skills`, `rcosteira79/android-skills`,
  `Drjacky/claude-android-ninja`)
- **Cross-platform parity:** `PARITY.md` at repo root
