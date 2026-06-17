# tvOS Production Deep-Dive

The measured values, full implementations, and incident-backed
recipes behind the SKILL.md summary. This file is also the seed for
a project `docs/tvos-playbook.md` — copy it in, then replace the
generic choices with your project's concrete ones (decision
references, commit receipts).

---

## 1. Layout measurements (observed across shipping apps)

Safe area: 90 pt leading/trailing, 60 pt top/bottom — constant at
1080p and 4K (points don't scale). Older TVs overscan 2–5%:
critical content stays inside the safe area; decorative bleed
(hero art, gradients) may extend to edges. Usable width at 1920 pt:
1740 pt.

| Context | Aspect | Size | Notes |
|---|---|---|---|
| Home shelf poster | 2:3 | 200×300 pt | Plex/Infuse |
| Home shelf landscape | 16:9 | 380×214 pt | Apple TV app |
| Sidebar spine poster | 2:3 | 140×210 pt | UHF |
| Detail hero backdrop | 16:9 full-bleed | full width × 45–60% height | render in `.background` |
| Detail poster inset | 2:3 | 260×390 pt | overlaps backdrop |
| Category tile | 4:3 | 260×195 pt | |

Gutters: 30–80 pt between cards (typical 40–60). Minimum 80 pt
between stacked shelves — a 1.1×-focused card must not collide with
the neighbor row. Shelf row height ≈ 400–500 pt with focus headroom.

Card titles: below the poster, 1 line (2 max). 20–22 pt is the
readable floor for card titles at 10 ft; 17 pt is unreadable.
Showing the title **only on focus** (fade in) is the cleanest
treatment in the field study.

## 2. The tvOS type ramp

| Token | Size | Weight | Use |
|---|---|---|---|
| Large Title | 76 | Medium | hero headlines |
| Title 1 | 57 | Medium | shelf/section titles |
| Title 2 | 48 | Medium | subsections |
| Title 3 | 38 | Regular | card headlines |
| Headline | 38 | Semibold | emphasized body |
| **Body** | **29** | Regular | **default — the 10-ft floor** |
| Callout | 31 | Regular | highlighted inline |
| Footnote | 23 | Regular | metadata |
| Caption 1 | 25 | Regular | badges |
| Caption 2 | 23 | Medium | dense metadata |

Rules: titles ≥48 pt; avoid Ultralight/Thin (shimmer at distance);
line-height 1.1–1.25×; serif acceptable as display type but body
stays sans at 29 pt; never place body text on art without a scrim
(target ~7:1 — couch glare eats 1.5–2 stops).

## 3. Canonical motion values

| Transition | Value |
|---|---|
| Focus scale (cards) | 1.08–1.10 |
| Focus scale (buttons) | 1.06–1.08 |
| Focus transition | `.spring(response: 0.4, dampingFraction: 0.82)` |
| Card press-down | `.spring(response: 0.25, dampingFraction: 0.75)` |
| Modal / detail push | `.smooth(duration: 0.5)` |
| Tab switch | `.easeInOut(duration: 0.35)` — no spring |
| Player present | `.spring(duration: 0.6, dampingFraction: 0.78)` + crossfade to black |
| Hero rotation | 7–8 s per item (10 s reads as stalled) |
| Hero crossfade | 0.6–0.8 s |
| Hero Ken Burns | 1.00 → 1.05 over the full dwell |
| Idle CTA pulse | 1.00→1.03→1.00 over 1.6 s, only after 3 s focused idle — never continuous |
| Skeleton shimmer | L→R sweep 1.2 s loop, 20° angle, ~30% card width |

`hoverEffect`: `.highlight` (brighten + scale + specular tracking
the trackpad) for poster art; `.lift` (scale + shadow) for buttons
and text rows. Never stack `hoverEffect` with a custom
`scaleEffect` driven by focus — pick one.

Parallax options, cheap → accurate: `.visualEffect` +
GeometryProxy pseudo-parallax (fine for every grid card) →
layered images + `rotation3DEffect` → `UIInterpolatingMotionEffect`
via UIViewRepresentable (hero only — you can't afford 200 UIKit
parallax layers).

**Performance ranking** (Apple TV HD is an A8 with 1 GB):
opacity/scale/offset effectively free → `rotation3DEffect` cheap to
~50 instances → `shadow(radius:)` expensive (budget ~20 onscreen;
`.drawingGroup()` to flatten) → `blur(radius:)` very expensive,
never animate the radius — prefer `Material` (hardware-accelerated).
tvOS is locked at 60 fps.

Reduce Motion (`accessibilityReduceMotion`): disable parallax, hero
auto-rotate, and replace springs with crossfades. App Store
requirement, not polish.

## 4. Image pipeline — full implementation

Why AsyncImage fails poster grids: downloads start at cell
realization (pop-in), decoded images are discarded on view rebuild,
no prefetch API, decode-at-draw hitches when multiple cells paint.

```swift
actor ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage, Error>] = [:]
    private let session: URLSession

    init() {
        cache.countLimit = 400              // ~3-4 viewports
        cache.totalCostLimit = 150_000_000  // 150 MB decoded (80 MB on ATV HD)
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache.shared
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    func image(for url: URL, targetSize: CGSize, scale: CGFloat) async throws -> UIImage {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        if let task = inFlight[url] { return try await task.value }
        let task = Task<UIImage, Error> {
            let (data, _) = try await session.data(from: url)
            try Task.checkCancellation()
            let image = try await Self.decode(data: data, targetSize: targetSize, scale: scale)
            cache.setObject(image, forKey: url as NSURL, cost: image.estimatedByteCost)
            return image
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        return try await task.value
    }

    static func decode(data: Data, targetSize: CGSize, scale: CGFloat) async throws -> UIImage {
        try await Task.detached(priority: .userInitiated) {
            let maxDim = max(targetSize.width, targetSize.height) * scale
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,   // decode NOW, not at draw
                kCGImageSourceThumbnailMaxPixelSize: maxDim
            ]
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { throw ImageError.decode }
            return UIImage(cgImage: cg, scale: scale, orientation: .up)
        }.value
    }
}
```

The magic line is `kCGImageSourceShouldCacheImmediately: true` —
plus one-pass downsampling at display size (~10× memory saved vs
decoding the raw JPEG).

SwiftUI wrapper: `.task(id: url)` for free cancellation; ALWAYS
render a placeholder Color immediately (a pending load must not
gate layout); never compute URLs in `body` (identity churn =
re-downloads); `.id()` on the container, not the image view.

Prefetch from the data source, not the view: on shelf-array change,
warm the first ~20; on focus at index i, prefetch `[i+1…i+6]` at
high priority, `[i-2…i-1]` low.

Memory budgets: decoded 480×720 poster ≈ 1.4 MB. ATV HD: keep the
decoded cache ≤100 MB; ATV 4K ≤200 MB. NSCache limits are soft —
trust the OS pressure signal.

## 5. Player metadata (the wrong-year incident)

`AVPlayerViewController` shows metadata from BOTH your
`externalMetadata` AND the asset's own embedded tags.

- A stray year above the scrubber is usually the MP4's embedded
  `creation_time`. `creation_time = 0` renders as **1969** in
  negative-UTC zones. Deleting your own metadata does nothing — the
  value is on the asset.
- `externalMetadata` OVERRIDES asset metadata by identifier: to
  blank a date, emit override items with EMPTY values for ALL of
  `.commonIdentifierCreationDate`,
  `.quickTimeMetadataCreationDate`,
  `.quickTimeUserDataCreationDate` (files vary in which they carry).
- Apply metadata to EVERY player surface (movie player AND episode
  player) — the one you forget shows the asset's junk.
- A bare 4-digit year is NOT a valid value for
  `.commonIdentifierCreationDate` — AVKit reinterprets it
  (observed: 2035/2045). Real ISO date or nothing.
- Artwork: `.commonIdentifierArtwork` (JPEG data) feeds Now Playing.

## 6. Remote semantics quick table

| Button | At root | In-app | In playback |
|---|---|---|---|
| Back (short) | exit to Home | pop one level | exit player |
| Back (long) | Home Screen — system, never intercept | same | same |
| Play/Pause | — | activate focused media card | toggle |
| Clickpad center | select | select | pause/resume |
| Clickpad edges | move focus | move focus | scrub |

## 7. Accessibility non-negotiables

Bold Text: automatic with system tokens. Reduce Motion: gate every
spring/parallax/auto-rotate. Increase Contrast
(`colorSchemeContrast`): drop scrims, raise accent opacity.
VoiceOver: `.accessibilityLabel` + `.accessibilityHint` on every
custom focusable; `.isButton` trait on focusable non-Buttons.
Switch Control: free via the focus engine if all actionables are
`Button`s or `.focusable(true)`. Captions: AVKit surfaces embedded
tracks; check `mediaSelectionGroup(forMediaCharacteristic:
.legible)` and tell the user when none exist.

## 8. Top Shelf wiring (when you add the extension)

Second target (`TVTopShelfContentProvider`), `.sectioned` style.
Main app writes a snapshot JSON into the App Group container,
refreshed by `BGAppRefreshTask`; the extension only READS (tight
memory limits — no network, no decode work beyond images by URL).
Deep links from Top Shelf items route through the app's intent
inbox like every other entry point. The extension no-ops gracefully
until the App Group capability exists, so the target can land in
the tree before the human flips the capability.

## 9. NavigationSplitView vs manual HStack (tvOS 17 only)

On tvOS 18+/26, `TabView(.sidebarAdaptable)` is the answer. If you
must target tvOS 17: manual `HStack` with `.focusSection()` on each
child (sidebar ~320 pt) is safer than `NavigationSplitView`, whose
built-in focus assumptions fight custom treatments. Parent HStack
does NOT get `.focusSection()` — only the children.
