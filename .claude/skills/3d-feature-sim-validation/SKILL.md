---
name: 3d-feature-sim-validation
description: Use when iterating on 3D / RealityKit / video-render features where you cannot directly see the on-device output. The pattern is to build a tiny offline macOS simulator that mirrors the iOS scene graph, render keyframes to PNG, and inspect them via the Read tool BEFORE shipping anything to the device. Triggers on RealityKit, RealityRenderer, 3D card animation, hero shot video, offline render, video feature iteration.
---

# 3D Feature Sim Validation Loop

## The principle

**Never ship a 3D render change blind.** The cost is enormous: every iteration the user catches a bug becomes an erosion of trust, and 3D bugs are easy to introduce in non-obvious ways (premultiplied alpha gotchas, z-fighting, lighting that washes one orientation but not another, edge cases at rotation extremes).

If you can't SEE the rendered output yourself, you're guessing. Build a tool that lets you see.

The pattern is: **macOS offline RealityFoundation sim → render frames to PNG → Read tool inspection → iterate the sim → only ship to iOS after sim looks right**.

## When to invoke this skill

- Building any RealityKit / RealityFoundation feature that produces an image or video
- Debugging a visual bug a user reported in a 3D scene
- Iterating on lighting, materials, post-processing, camera animation
- Any time you find yourself shipping code changes and asking the user "is this fixed?" without first seeing the output yourself

## When NOT to invoke

- UI bugs that don't involve 3D rendering (use the iOS Simulator directly via `simctl`)
- Backend / data bugs
- Anything where you can already directly observe the output (e.g., logs, plain text rendering)

## Why iOS Simulator falls short for offline 3D renders

iOS Simulator's `RealityRenderer` hangs on offline render (`renderPreviewFrame` → indefinite block). This is a confirmed simulator limitation. You CANNOT use the iOS Sim to validate offline-rendered video output. You must use macOS RealityFoundation as a substitute.

## The sim setup

### Step 1: Create the sim directory

```
tools/<feature-name>Sim/
  sim.swift            # The single-file CLI sim
  test_card.jpg        # Test asset(s) — high-res so they don't introduce
                        # their own resolution artifacts
```

### Step 2: Write the sim as a single-file Swift CLI

The sim must mirror the iOS scene graph EXACTLY:

- Same mesh structure (planes, boxes, custom geometry)
- Same materials (UnlitMaterial, PhysicallyBasedMaterial, CustomMaterial variants)
- Same lighting (directional lights at matching positions + intensities, IBL with same `intensityExponent`)
- Same camera position + FOV
- Same post-processing (EV grade, saturation, contrast, watermark composition)

Use `RealityFoundation` (the macOS framework), NOT `RealityKit` (iOS-only):

```swift
import RealityFoundation
import Metal
import MetalKit
import CoreImage
import AppKit  // For NSGraphicsContext / NSColor on macOS
```

Top-level structure pattern (avoid `-parse-as-library`):

```swift
@MainActor
func run() async throws {
    // ... setup, render, save PNG ...
}

Task { @MainActor in
    do {
        try await run()
        exit(0)
    } catch {
        print("Error: \(error)"); exit(1)
    }
}
RunLoop.main.run()  // Keeps MainActor executor alive
```

### Step 3: Compile with Xcode's Swift toolchain (NOT system Swift)

`DEVELOPER_DIR` must point at Xcode so Metal compiler + RealityFoundation are available:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun -sdk macosx swiftc \
  -O \
  -framework RealityFoundation -framework Metal -framework MetalKit \
  -framework CoreImage -framework AppKit \
  -o sim sim.swift
```

If the feature uses a Metal shader (`.metal` file), compile it separately to a metallib that the sim loads via `MTLDevice.makeLibrary(URL:)`:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun -sdk macosx metal -c <shader>.metal -o /tmp/<shader>.air

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun -sdk macosx metallib /tmp/<shader>.air -o /tmp/<shader>.metallib
```

In the sim, load via `device.makeLibrary(URL: URL(fileURLWithPath: "/tmp/<shader>.metallib"))`.

### Step 4: Render keyframes — pick angles + composite to a contact sheet

For a rotation animation, render at fixed yaw increments (e.g., 12 frames at 0°, 30°, ..., 330°). Single hero-pose isn't enough — bugs hide at rotation extremes.

```swift
for step in 0..<12 {
    let yawDeg = Float(step) * 30.0
    let yawRad = yawDeg * .pi / 180

    let renderer = try RealityRenderer()
    let root = Entity()
    renderer.entities.append(root)

    // Build the scene exactly as iOS does:
    //   – backdrop
    //   – card pivot (with the front + back + edge + overlay children)
    //   – lights
    //   – IBL
    //   – camera at hero pose

    cardPivot.orientation = simd_quatf(angle: yawRad, axis: SIMD3<Float>(0, 1, 0))

    let frame = try renderFrame(scene: ..., size: CGSize(width: 540, height: 960), device: device)
    // Apply the same post-process the iOS path applies
    let processed = applyiOSPostProcess(frame, ev: ..., saturation: ..., contrast: ...)
    rendered.append((processed, label: "yaw=\(yawDeg)°"))
}

// Composite into a contact sheet (e.g., 4 cols × 3 rows)
let sheet = makeContactSheet(tiles: rendered, cols: 4, tileW: 360, tileH: 640)
savePNG(sheet, to: "sim_<feature>_<timestamp>.png")
```

For a camera arc animation, render at start / settle / push climax / end. Same principle.

### Step 5: Inspect the PNG via Read tool

```swift
Read("/path/to/sim_<feature>_output.png")
```

The Read tool decodes PNGs as multimodal image content — you can actually see the rendered output and diagnose visual bugs at every angle. **This is the entire reason the loop works.** Without this, you'd be back to shipping blind.

### Step 6: Iterate the SIM, not the device

When a bug is visible:

1. Form a hypothesis about its cause (e.g., "the back plane wash at yaw=180° is the rim light hitting the back's normal at +0.69 dot")
2. Change the sim code first
3. Recompile + re-render
4. Read the new PNG
5. Confirm fix OR refine hypothesis

Only when the sim looks right do you mirror the changes into the iOS code and ship.

## Common sim-vs-iOS divergences

The sim is APPROXIMATE. Expect ~10% of bugs to manifest differently on device. Things to watch:

- **Metal shader semantics**: `discard_fragment()` from non-uniform control flow may be silently elided on iOS Metal but honored on macOS. Always pair discard with alpha output as belt-and-suspenders.
- **PBR emissive HDR clipping**: a value that renders bright-correct in sim can clip to white on iOS RealityKit's offline render. If you see `emissiveColor` produce a solid-white card in the sim, it's a sign the same will happen worse on device.
- **sRGB vs linear color space**: textures sampled with different filtering on iOS vs macOS. Mipmap LOD selection can differ slightly.
- **`mipmapsMode: .allocateAndGenerateAll`** is honored on both but the mipmap LOD bias may differ.
- **Lighting intensities** in lumens behave consistently across both, BUT the scale of brightness vs HDR clipping may differ. If you see washout on iOS that's mild in sim, drop intensity 30-50% more.

After confirming the sim, do one final on-device round of testing. The sim catches 80-90% of bugs cheaply. The remaining 10-20% need a real device.

## Anti-patterns

### ❌ Shipping changes without rendering them locally

"I'm 95% sure this fixes it." → ship → user reports it's worse. This is the #1 trust-eroding loop. Build the sim ONCE; reuse it for every iteration. The first time costs ~1 hour. Every subsequent iteration is minutes.

### ❌ Sim that doesn't mirror the iOS scene graph

If the sim renders the card with UnlitMaterial but iOS uses CustomMaterial, the sim's output tells you nothing about what iOS will show. Spend the effort to match every node + material + parameter.

### ❌ One-keyframe sim

Rendering only the hero pose hides bugs that only manifest at the rotation transition, the push-climax frame, the edge-on yaw, etc. Render 12 yaw angles, or render the camera-arc keyframes. Always render MORE than feels necessary.

### ❌ Sim that uses different test assets than iOS

If your iOS code loads textures from a remote URL (like an R2 bucket), use a LOCAL test asset that matches the same resolution + aspect ratio. Don't sim with a 2048×2048 test card if the iOS path loads 477×667 — your sim won't reproduce the pixelation that's the actual bug.

### ❌ "Sim says it's fine, let me ship without one more spot-check"

The user is the final reviewer. Always do one device-test before declaring a fix shipped. The sim is 90% confidence, not 100%.

## Real-world example (BOBA Playbook Hero Shot)

The Hero Shot feature in BOBA-Playbook went through 50+ iterations. The breakthrough happened when the rotation-strip sim was introduced (see `tools/HeroShotSim/sim3d.swift` and the `renderIOSv67RotationStrip` function). Specific bugs caught BY the sim (and avoided being shipped):

- **v6.8 edge box at 4× thickness**: the sim render showed a solid magenta rectangle where the card art should have been — because the 0.6mm-thick edge box was z-occluding the front plane at 0.15mm. Without the sim, the user would have woken up to a feature where every card showed as a solid colored block.
- **v6.9 back wash at yaw=180°**: the PBR back with clearcoat 0.20 caught rim light at the perfect specular angle, washing the back center white. Sim caught this BEFORE the user tested.
- **v6.5+ "black/colored sparkles"**: each iteration of the sparkle overlay had a different artifact; the sim's variant grid showed them all side-by-side, enabling decision: drop the overlay entirely.

The pattern is now: any 3D change in HeroShot → sim render → inspect → ship.

## Files this skill expects to exist

- `tools/<feature>Sim/sim.swift` — the single-file CLI sim
- `tools/<feature>Sim/.gitignore` — exclude PNG outputs (they're noise in the repo)
- `tools/<feature>Sim/test_*.jpg` — high-res test assets matching the production tier

## Inspecting your rendered output

```
Read tool → /absolute/path/to/sim_output.png
```

The Read tool decodes the PNG and shows it to you as an image. You can describe what you see — pixelation, color casts, geometry artifacts, lighting wash, alpha issues. This is the corrective lens that lets you iterate without user spot-check.
