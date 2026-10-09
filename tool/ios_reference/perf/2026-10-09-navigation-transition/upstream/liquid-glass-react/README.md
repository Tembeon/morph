# @liquid-glass/react

Liquid Glass for React, via WebGL2. Reverse-engineered from macOS 26/27's
QuartzCore shaders — see [`../README.md`](../README.md).

```bash
npm i @liquid-glass/react
```

```tsx
import { LiquidGlass, useDiffusion } from '@liquid-glass/react';

function Panel({ bg }: { bg: HTMLImageElement }) {
  const diffusion = useDiffusion(true);          // animated appear
  return (
    <LiquidGlass
      variant="regular"
      backdrop={bg}
      diffusion={diffusion}
      style={{ width: 320, height: 120 }}
    >
      <h3 style={{ padding: 16 }}>Hello</h3>
    </LiquidGlass>
  );
}
```

## `backdrop` is required

There is no way to read live backdrop pixels from a WebGL context — the browser
deliberately does not expose them (cross-origin leak). And `backdrop-filter`
cannot displace sampling per fragment, which is the entire effect.

So pass the backdrop yourself: an `<img>`, `<canvas>`, `<video>` (with
`backdropIsLive`), or an `ImageBitmap`. If you truly need arbitrary DOM behind
the glass, rasterize it (html2canvas or similar) and pass the canvas — slow and
imperfect; prefer designing so the backdrop is something you own.

## Requirements

**WebGL2.** There is no WebGL1 fallback: the blur is `textureLod()` against a mip
chain, which WebGL1 cannot express. `isSupported()` tells you; without it the
component renders a plain CSS blur, which looks like frosted glass, not liquid
glass.

## API

- `<LiquidGlass variant params backdrop backdropIsLive diffusion fallback />`
- `useDiffusion(visible, durationMs)` — drives the appear/disappear ramp
- `LiquidGlassRenderer` — the framework-agnostic core, if you want your own loop
- `preset('regular' | 'clear' | 'macos27')`, `defaultParams()`
- `FRAGMENT_SRC` / `VERTEX_SRC` — the raw ESSL 300, if you'd rather bring your own renderer

## Adaptive tint (chameleon)

The material — and the content on it — shifts with the backdrop, so symbols stay
legible: **dark glyphs over a bright backdrop, light glyphs over a dark one.**

Apple implements this with a GPU reduction (`tile_average_luma` ->
`compute_sum_luma` -> `compute_average_luma`) using **exactly Rec.709 weights**
(0.212646 / 0.715332 / 0.072205 — decoded from the fp16 immediates 0xH32CE,
0xH39B9, 0xH2C9F). The average is remapped through `luminanceColorMap.png`, a
256-entry curve that is a **logistic centred at 0.5 with k = 10.25**, running
0.349 -> 0.800. That is fit here to a closed form (max error 1.4/255), so no
lookup texture ships.

This implementation skips the reduction pass entirely: the average comes from
the **top mip** of the backdrop, which already exists because the blur needs a
full mip chain. Same number, zero extra passes.

Verified: backdrop luma 0.085 -> glass 0.140; backdrop 0.938 -> glass 0.311.

```
backdrop 0.00-0.35  ->  symbol luma 0.94-0.81   light
backdrop 0.50       ->  symbol luma 0.25        flips to dark
backdrop 0.65-1.00  ->  symbol luma 0.12        dark
```

The flip lands at 0.5 because that is where Apple centred the logistic — the
curve's midpoint *is* the decision point.

Use `adaptiveContentLuma(avgLuma)` to tint your own labels and glyphs from the
same curve the material uses.

## Fidelity

Measured against a real `NSGlassEffectView` capture on macOS 26.5.2, fitted by
coordinate descent driving the actual Metal shader headlessly:

| | |
|---|---|
| MAE | 15.0/255 |
| PSNR | **17.53 dB** |
| scale invariance | 240x150 vs 480x300 agree to 1.7/255 |

**This is not 1:1 with Apple**, and two gaps are structural rather than a matter
of more tuning:

1. The corner curve differs — `exponent = 6.5` (superellipse, fitted to 1011
   boundary pixels) against Apple's continuous curve.
2. macOS 27's material recipes live on the **encrypted** IPSW volume, so the
   three subsystems added in 27 (ring shadow, key fill highlight, blur fill)
   have no ground truth to fit against; their values are modelled, not measured.

## macOS 27

A second shader targeting macOS 27 (build 26A5388g) ships alongside the 26 one:
`liquid_glass_27.glsl`, with `params27` bindings. It is not the 26 shader with
features bolted on — it follows macOS 27's own structure, transcribed from the
disassembly of `glass_background_all_lpf` (1527 lines, the only variant that
reads all 63 uniforms).

**Two structural changes from 26:**

1. **Order of operations is inverted.** macOS 26 shades the face and layers the
   shadow on top. **27 computes shadow and ring shadow first**, then shades the
   face over them — so the face colour matrix operates on a surface that already
   carries the shadow.

2. **Runtime bools became compile-time variants.** 12 entry points became 36:
   `glass_background_{minimal,c,e,r,ce,cr,re,all}`. `complex_refraction` is gone
   from the struct entirely; the decision moved into the shader name. Reproduced
   with `LG_R` / `LG_E` / `LG_C` — all 8 combinations build. Worth adopting at
   any version: it removes per-fragment branching.

Also in 27: `aberration_dir` is a `vec2` in the **background** struct (26 had it
foreground-only, as two angle floats), and the HDR path shrank —
`clamp_limit`, `preserve_hue` and `sdr_white_value` are gone, leaving
`holding_tone_opacity` with a single `sdr_shadow_dist0` / `sdr_shadow_inv` pair.

Reference budget: 21 texture samples, 9 mip selects, 6 lens-curve sqrts,
2 fwidth, 2 discards.

### macOS 27 constants: verified, not assumed

An earlier revision of this file said the default constants were "still macOS
26's" because 27's material recipes sit on the encrypted IPSW volume. That gap
is now closed, and the answer is that **there was no gap**.

macOS 27's filesystem was read without booting it. `tart create --from-ipsw`
writes the restored volume to `~/.tart/tmp/<uuid>/disk.img` *before* the boot
step that fails on a macOS 26 host, so the image can be mounted read-only and
read directly:

```sh
hdiutil attach -readonly -nobrowse   -imagekey diskimage-class=CRawDiskImage ~/.tart/tmp/<uuid>/disk.img
# -> /Volumes/Macintosh HD 1   ProductVersion 27.0
```

Result, from the live macOS 27 volume:

| | |
|---|---|
| `platformContentGlass.materialrecipe` | **identical to macOS 26** — same colour matrix, same `blurRadius: 45` |
| recipe files overall | 57 identical, 5 changed, 0 new, 0 removed |
| the 5 changes | all unrelated to glass: `moduleFill` gained `moduleRuleOnDarkSubtle`; four `~appletv` files moved `plusL`/`plusD` to `…IgnoreAlpha` |
| `luminanceColorMap.png` | pixel-identical (`cmp` flags it, but that is PNG metadata) — same logistic k=10.25 centred at 0.500, range 0.349..0.800 |
| glass entry points in the full 157 MB metallib | 36, matching the cryptex slice that was decoded |

So the constants here are macOS 27's, confirmed by direct comparison rather than
carried forward on assumption.

**What remains out of reach** is a *rendered* macOS 27 fidelity fit:
Virtualization.framework will not boot a guest newer than its host, so macOS 27
cannot be made to draw glass on a macOS 26 machine. That mattered only while the
constants were unknown; they are now known to be unchanged.

## UI layer — nav bars, toolbars, controls

The material alone is not a nav bar. These are the pieces around it.

### Scroll edge effect

`scroll_edge.glsl`, ported from QuartzCore's `variable_blur_frag` — the
primitive behind `NSScrollEdgeEffectStyle` / `scrollEdgeEffectThreshold`.
Content scrolling under a bar is progressively blurred toward the edge, so the
bar materialises out of the content rather than sitting on it as a hard rect.

Three things the disassembly settles:

- **The radius is mask-driven, not geometric.** A second texture's `.a` is
  saturated and scaled. One shader therefore serves top/bottom/left/right edges
  and any custom falloff — the ramp is painted, not computed.
- **The mip idiom is the same one the glass uses**: `radius*0.5 + 1.0`, `log2`,
  explicit LOD. Apple reuses a single blur primitive system-wide.
- **The kernel is a 4-tap box at that LOD** (`* 0.25`), repeated for a second
  offset row — a separable cross over the mip chain, not a wide gaussian. The
  mip already did the work.

`uStyle` picks ramp (soft) versus step (hard), which is the whole visible
difference between the `NSScrollEdgeEffectStyle` cases.

### Vibrancy roles

`VIBRANCY` / `VibrancyRoles` carry the six content-tint matrices extracted
verbatim from Apple's `platformFill{Light,Dark}.visualstyleset`:
`primary, secondary, tertiary, quaternary, separator, highlight`.

Light `primary` maps mid-grey to **0.250**; dark `primary` to **0.750**. Tinting
labels and glyphs with flat black or white instead of these is the usual reason
content on glass looks subtly wrong.

### Concentric radii

`concentricRadius(outer, inset)` — nested glass
(`NSContainerConcentricGlassEffectView`) needs `outer - inset`, not the parent's
radius. Reusing the outer radius makes the gap between curves non-uniform and
the corners read as pinched.

### Group splitting

`splitGroups(rects, spacing)` mirrors
`NSGlassEffectContainerViewAutomaticallySplitsGroups`: elements closer than
`spacing` merge into one glass body, beyond it they stay separate. Lets a
container decide how many SDF unions to run instead of merging unconditionally.

### Press state

`pressState(t)` returns a squish scale plus specular and blur boosts. Kept
subtle on purpose — past roughly 4% the squish reads as a bounce rather than a
press.

### Motion-linked specular

On handhelds Apple tilts the specular with device attitude. That is not a gap in
this library: it is a *parameter feed*, not a mechanism. `lightDir` is already
exposed — drive it from CoreMotion or the sensor API of your choice and the
highlight tracks the device.

Desktops have no attitude to read, so on web and WinUI the fixed `lightDir` is
the correct behaviour, not a limitation.

### Mechanism coverage

Complete. Material, adaptive tint, diffusion, morphing, scroll edge, vibrancy
roles, concentric radii, group splitting, press state — every mechanism decoded
from macOS 26/27 is implemented, and the macOS 27 constants are verified
identical to 26 by direct comparison against the live 27 filesystem.
