---
name: realitykit-3d-card-rendering
description: Use when building or debugging 3D card-rendering features in iOS RealityKit / RealityFoundation — premium card animations, hero-shot videos, trading-card 3D views, etc. Captures hard-learned patterns about material choice (Unlit vs PBR vs Custom), card geometry (front + back + edge box), lighting traps, premultiplied-alpha gotchas, texture pipeline for source-pixel crispness. Triggers on RealityKit, card rendering, card 3D, trading card animation, 3D card video.
---

# RealityKit 3D Card Rendering Patterns

## What this skill covers

The non-obvious patterns and traps when rendering a printed trading card as a 3D mesh in iOS RealityKit. Captured from 50+ iterations of the BOBA Playbook Hero Shot feature — every entry below corresponds to a specific bug that shipped and got rolled back.

**Pair with [[3d-feature-sim-validation]]** — never rely on these patterns blind; always render a sim contact sheet at multiple keyframes before shipping.

## The card geometry

A "trading card" in 3D is rarely a single mesh. The right structure is:

```
cardPivot Entity (rotated around Y for spin)
├── frontPlane (z = +halfThickness, normal toward camera at yaw=0)
├── backPlane  (z = -halfThickness, mirror-rotated so image is right-side-up)
└── edgeBox    (centered at z=0, thin extent on Z axis)
```

Real card stock is 0.3mm thick. Use:

```swift
static let halfThickness: Float = 0.00015   // 0.15mm half-extent → 0.30mm full
```

**Edge box thickness — use `halfThickness * 1.9` (NOT 2.0):**

The edge mesh thickness along the thin axis must be **strictly less than 2 × halfThickness**. If equal (2.0): the edge box's ±Z faces are flush with the front+back planes → z-fighting where the edge color can occlude card art at face-on view. If greater (e.g., 4.0 = 0.6mm): the edge box's +Z face is IN FRONT of the front plane and OCCLUDES the card art entirely with the edge color.

1.9 × halfThickness = 0.285mm, just inside the real-card cap, hides edge box behind planes with ~0.0075mm margin. No occlusion, no z-fight.

**Edge box X/Y dimensions inset by 2 × cornerRadius**:

```swift
MeshResource.generateBox(size: SIMD3<Float>(
    cardWidth - 2 * cornerRadius,
    cardHeight - 2 * cornerRadius,
    halfThickness * 1.9
))
```

Inset is required so the edge box's corners don't poke through the rounded-corner transparency of the front/back planes.

**Front plane orientation (.upright pose)**:

```swift
front.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
front.position = SIMD3<Float>(0, 0, halfThickness)
```

**Back plane — composed rotation flips through to right-side-up image-V**:

```swift
back.orientation =
    simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
    * simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
back.position = SIMD3<Float>(0, 0, -halfThickness)
```

## Material choice — the central tradeoff

There is no perfect single answer. Each material kind has its tradeoff:

### UnlitMaterial

- **Pros**: outputs source color directly, no Lambert math, vivid pigment punch with no washout. No exposure to lighting bugs.
- **Cons**: Source texels render RAW — pixelation visible if source < display pixels. Edge boxes (UnlitMaterial-tinted) read FLAT, don't catch light, look "papery" instead of "3D" at oblique angles. No specular = silhouette can read as a thin line at edge-on rotations.
- **Use when**: source pixels >> display pixels (small framing or high-res assets), you want absolute pigment fidelity, or you don't need lighting effects.

### PhysicallyBasedMaterial — `.pbrMatte` variant

- **Pros**: Lambert diffuse math AVERAGES texture samples within the lighting hemisphere — that's inherent anti-aliasing that masks source-pixel limits. Edges catch light, look 3D. No clearcoat = no specular hotspot wash.
- **Cons**: Lights wash the card. IBL hemisphere ambient is the biggest washer; needs to be cranked low (`intensityExponent` ≤ -5).
- **Use when**: source pixels are smaller than display pixels (the common case for trading-card R2 tiers).

```swift
var mat = PhysicallyBasedMaterial()
mat.baseColor = .init(tint: .white, texture: .init(cardTex))
mat.metallic = 0.0
mat.roughness = 0.95   // matte — no spec
// NO clearcoat — that's the specular layer that washes back at yaw=180°
mat.opacityThreshold = 0.001
mat.faceCulling = .none
```

### PhysicallyBasedMaterial — `.pbrEmissive` variant

- **Pros (in theory)**: Emissive bypasses Lambert/IBL/spec entirely — pure pigment output regardless of lights. Should give the best of both worlds: PBR geometry pipeline + source-vivid output.
- **Cons (in practice)**: On RealityKit's offline render path, `emissiveColor` channel values >1.0 are valid HDR but clip to white in the 8-bit output. A texture mapping to emissive often renders as **solid white card**. Confirmed in sim with v6.x experiments.
- **Use when**: never on iOS RealityKit offline render. May work on visionOS or in interactive ARView render.

### CustomMaterial with surface shader

- **Pros**: Full pipeline control. View-direction-dependent effects (holofoil, fresnel). Time-driven animation via `uniforms.time()`.
- **Cons**: Easy to break. Premultiplied-alpha trap (see below). `discard_fragment()` from non-uniform control flow can be elided on iOS Metal. Custom textures bound to "wrong" PBR slots is unusual and fragile.
- **Use when**: you genuinely need per-fragment custom math (foil shimmer, dissolve, time-driven warp). Last resort, not first reach.

## The premultiplied-alpha trap (CustomMaterial)

RealityKit's CustomMaterial output is **premultiplied alpha**:

```
final_color = base_color × opacity + dst_color × (1 - opacity)
```

Setting `base_color = (0, 0, 0)` + `opacity = 1` premultiplies to **BLACK opaque** — not transparent.

**Wrong** (produced "black sparkle" artifact in BOBA Hero Shot):

```metal
surface.set_base_color(half3(0.0h));
surface.set_emissive_color(shimmer);
surface.set_opacity(sparkleAlpha);   // sparkleAlpha = 1 at sparkle pixels
```

At sparkle pixels: `(0, 0, 0) × 1 + dst × 0 = (0, 0, 0)` = black, not the intended shimmer color.

**Right**: pass the intended visible color through `set_base_color`:

```metal
surface.set_base_color(shimmer);     // intended color of the pixel
surface.set_emissive_color(half3(0));
surface.set_opacity(sparkleAlpha);
```

At sparkle pixels: `shimmer × 1 + dst × 0 = shimmer`. At non-sparkle: opacity=0 → `0 + dst × 1 = dst` (the card behind shows).

**Also**: pair `discard_fragment()` with alpha output as defense-in-depth. iOS Metal may silently elide discards from non-uniform control flow.

## Lighting traps

### The rim-light back-wash bug

A 3-point rig with key + fill + rim lights, where rim is at `(-0.3, 0.4, -0.5)` shining toward the origin:

At yaw=0° (face-on), the front plane's normal is +Z. Rim light direction toward surface is `(0.41, -0.55, 0.69)`. Lambert `dot(N, -L) = 0.69` × rim intensity → contributes to front edge highlight.

**At yaw=180°, the BACK plane has the same +Z normal direction** (now facing camera). Rim light hits the back at the same dot=0.69 → Lambert washes the back center white.

The fix is one of:
- **Remove rim light** entirely. Back at yaw=180° is dim but visible via IBL. This is what BOBA Hero Shot ships.
- Position rim laterally (no Z component) so it doesn't catch either yaw=0 front or yaw=180 back symmetrically.
- Use UnlitMaterial for back (no Lambert math, no wash).

### IBL is the main washer

`ImageBasedLightComponent.intensityExponent` is **base-2**:

- `-3.0` = 1/8 baseline (still significant ambient)
- `-5.0` = 1/32 baseline (subtle)
- `-7.0` = 1/128 baseline (effectively off)

For PBR matte cards, default toward `-5` to `-6`. Higher than `-3` and the card looks bathed in soft light = washed.

### PBR clearcoat is a specular trap on flat surfaces

`PhysicallyBasedMaterial.clearcoat = 0.20` adds a varnish-like specular layer. On a CARD (flat plane), at the angle where the camera + light + normal align for perfect reflection, the clearcoat produces a bright white hotspot. This is the v6.8 BOBA bug — back center went white at yaw=180°.

**Just don't use clearcoat on card surfaces.** Set it to 0 or omit. Roughness 0.85-0.95 + metallic 0 is enough for "matte paper."

## Texture pipeline — source-pixel-to-display ratio

This is the **fundamental driver** of perceived crispness:

- **Source pixels ≥ display pixels** → GPU downsamples → crisp output (anti-aliased)
- **Source pixels < display pixels** → GPU upsamples → visible pixelation (no synthetic detail can be added)

Compute the ratio:

```
display_pixels_height ≈ output_height × (card_height / (2 × camera_distance × tan(FOV/2)))
```

For BOBA Hero Shot at hero pose (`z = 0.34`, FOV 32°, output 1920 tall, card 0.0889m):

```
display ≈ 1920 × (0.0889 / (2 × 0.34 × tan(16°))) ≈ 877 pixels
```

If `/full/` tier source is 477-1040 pixels, then for the smallest cards we're upsampling 1.84× → pixelation. The fix paths are:

1. **Higher source resolution** (best: regenerate the tier at 1500+ px)
2. **Pull camera back** (smaller card on screen = less pixel demand)
3. **Lanczos pre-upscale + mipmaps** to give PBR's sampler a higher-LOD source

Lanczos alone does NOT add detail. Combined with PBR's Lambert filtering, it produces a SOFTER look that reads as "not pixelated" perceptually:

```swift
// Texture-load path:
let upsampled = upsampleAndSharpen(image, scale: 2.0)
let rounded = roundedCorners(upsampled)
let tex = try TextureResource(image: rounded.cgImage!,
    withName: nil,
    options: TextureResource.CreateOptions(
        semantic: .color,
        mipmapsMode: .allocateAndGenerateAll
    ))
```

Where `upsampleAndSharpen` is `CILanczosScaleTransform` + `CISharpenLuminance` at 0.4.

**Combine Lanczos + mipmaps + PBR matte material**. The trifecta:
- Lanczos gives mipmap chain a higher-LOD source.
- Mipmaps let GPU pick the right LOD for the screen-space sampling rate.
- PBR's Lambert averages multiple samples → final anti-aliasing pass.

Result is "soft but vivid" rendering. The BOBA user's perception was "no pixelation" — even though physically the source is still under-resolved.

**Anti-pattern**: Lanczos with UnlitMaterial. The synthetic upscale produces soft texels that UnlitMaterial then renders RAW — soft pixelation. Net negative.

## Animation traps

### The edge-on physics problem

A 0.3mm-thick card rotated to yaw=90° is PHYSICALLY a thin vertical line. This is real geometry, not a rendering bug. Every 3D card animation has to accept this.

Acceptable mitigations:
- **Smoothstep velocity** through edge-on angles so the eye reads "spin" rather than "card vanished" — fast in/fast out at 90°.
- **Avoid the rotation entirely**: use a sway motion (e.g., ±30° around face-on) instead of a full 360° spin. Card never goes edge-on.

Unacceptable "fixes":
- Making the edge box >0.3mm thick — unrealistic and produces the z-occlusion bug.
- Hiding the edge mesh entirely — card disappears at 90° (the "card disappears partially" user complaint).

### Camera-arc orbit ≠ card-yaw rotation

Two independent animations contribute to "the card appears to turn":

1. **`cardYaw`**: the card pivot's rotation around Y.
2. **Camera arc**: the camera orbits around the card.

A user complaint about "card disappears as it turns" could refer to either. When debugging, render both KEYFRAMES of camera arc AND yaw angles independently to isolate which is the cause.

## Post-process: keep it minimal

CoreImage post-process pass (after RealityRenderer outputs to pixel buffer):

```swift
applyExposureEV(image, ev: 0.0, saturation: 1.15, contrast: 1.08)
```

- EV grading: 0.0 is "no change." +0.3 is a mild brightener, but stacking with bright PBR Lambert output causes highlights to clip to white. Default toward 0.0; nudge negative if PBR is bright.
- Saturation 1.15: pigment-punch grade. Above 1.3 produces over-saturated reds/oranges.
- Contrast 1.08: subtle. Above 1.15 produces hard shadows that don't match the smooth PBR shading.

Match the same parameters in BOTH the video render path AND the preview-frame path. Mismatches cause "the preview looked different from the final video" complaints.

## Materials checklist for a new feature

Before shipping a new 3D card feature:

- [ ] Material choice has a justified WHY tied to the source-pixel ratio
- [ ] Edge box thickness ≤ 1.9 × halfThickness (= ~0.285mm)
- [ ] No clearcoat on PBR card faces
- [ ] IBL `intensityExponent` ≤ -5 (or justified higher)
- [ ] Rim light removed OR positioned without Z-component
- [ ] CustomMaterial outputs (if any) verified premultiplied-alpha safe
- [ ] Sim-validated rotation strip at 12 yaw angles (see [[3d-feature-sim-validation]])
- [ ] Post-process EV ≤ 0.0 (or justified higher with PBR loading curve in mind)
- [ ] One on-device test pass

## See also

- [[3d-feature-sim-validation]] — the offline-sim methodology
- [[3d-feature-debug-loop]] — diagnostic-first iteration when bugs return
