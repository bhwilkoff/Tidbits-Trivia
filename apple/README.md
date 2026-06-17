# apple/ — Swift starter for the universal Apple target

One Xcode target builds **iPhone, iPad, and Apple TV** (Decision 013).
This directory holds the starter files; they move into the
Xcode-created group during setup and this directory is then deleted.

## Layout (preserve this split inside Xcode)

```
apple/
├── App/                 ← entry point; #if os branches live here
│   └── AppNameApp.swift
├── Core/                ← compiles for EVERY os() destination
│   ├── Models/          ← data models (platform-agnostic)
│   ├── Networking/      ← APIClient singleton
│   └── Store/           ← @Observable global state
├── iOS/                 ← iPhone/iPad views — #if os(iOS)
│   ├── ContentView_iOS.swift
│   ├── Views/
│   └── Components/
├── tvOS/                ← Apple TV views — #if os(tvOS)
│   └── ContentView_tvOS.swift
├── Assets.xcassets/     ← iOS icon; tvOS needs its OWN brandassets (below)
├── Resources/Fonts/
└── Tests/
```

**The Core rule**: `Core/` never imports per-platform UI and never
contains an `#if os` that selects UI behavior. When Core logic needs
something from the app layer, define a protocol in Core and conform
the app store to it. This single rule is what keeps ~60–70% of the
codebase shared instead of copy-drifting.

**File-suffix convention**: per-platform files end `_iOS.swift` /
`_tvOS.swift` and wrap their contents in `#if os(iOS)` / `#if
os(tvOS)`. Both view trees can then live in the same target without
exclusion lists.

## Creating the Xcode project (once, at M0)

1. Xcode → File → New → Project → **Multiplatform → App**.
2. Product Name: `AppName` — **no spaces** (Xcode Cloud requirement).
3. Save to the **repo root** (not a subdirectory). `.xcodeproj` at
   root is what makes Xcode Cloud auto-discovery work.
4. In the target's **General → Supported Destinations**, confirm
   iPhone + iPad and **add Apple TV** (remove Mac/Vision unless you
   want them).
5. Drag the `apple/` subfolders into the Xcode group for the app,
   preserving the `Core/` / `iOS/` / `tvOS/` split. Delete `apple/`
   when done.
6. Project → Info → Configurations: set `AppVersion.xcconfig` (repo
   root) on both Debug and Release. From now on, version numbers are
   edited ONLY in that file (Decision 003).
7. Build BOTH destinations before the first commit:
   `xcodebuild build -scheme AppName -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
   and `-destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)'`.
   From now on, any change to a `Core/` file means re-building both.

If you're skipping tvOS (Decision 014), still keep the `Core/` /
`iOS/` split — it costs nothing now and is the door left open.

## tvOS specifics the iOS docs won't tell you

- **App icon**: tvOS uses a **layered imagestack** ("App Icon & Top
  Shelf Image" brandassets), not a flat PNG. Layers are LANDSCAPE
  (400×240 / 800×480 / 1280×768 @1x/@2x) — square renders fail
  actool only on CLEAN builds, so verify with a from-scratch build.
  See `branding/README.md`.
- **Persistence**: only `Library/Caches`, `tmp`, and App Group
  containers are writable on device — the simulator is lenient and
  will not catch violations (Decision 017). Build your
  ModelContainer with an App Group `ModelConfiguration` + fallback
  chain (see `AppNameApp.swift`).
- **Focus**: read the `tvos-platform-patterns` skill before writing
  any tvOS view. `ContentView_tvOS.swift` is a focus-correct
  starting shape.
- **Top Shelf** (later): a second target (`TVTopShelfContentProvider`
  extension) reading a snapshot JSON from the App Group that the
  main app refreshes via `BGAppRefreshTask`.

## Versioning

`AppVersion.xcconfig` defines `MARKETING_VERSION` +
`CURRENT_PROJECT_VERSION` for every Apple target (app + any
extensions). Never edit versions through Xcode's identity panel —
it writes per-target overrides into project.pbxproj that shadow the
xcconfig and the targets drift (Decision 003).
