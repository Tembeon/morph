# Shader performance audit (Fable, 2026-10-05, read-only)

Scope: every shader under lib/src/glass/renderer/shaders (the three
final-render variants over liquid_glass_final_render_core.glsl, the Flutter
GPU geometry / field / material passes, fake_glass_surface.frag) and the
Dart that drives them (rendering/liquid_glass_layer.dart,
internal/flutter_gpu_geometry_renderer_native.dart,
internal/paint_fake_glass_surface.dart). Target: Mali-G78 (Pixel 6a,
Vulkan and the GLES fallback) and Apple A-series Metal. The rule: the same
image, or a stated maximum channel error that the harness in section 5
checks. Nothing here changes a measured value (every optics / color number
stays); the proposals change where and how often the same arithmetic runs.

Items already on the plan elsewhere are cited, not repeated:
flutter-tricks L2 (half precision), L5 (clip buckets), L9 (lite variant),
L10 (RGBA16F field); perf-research X2 (early reject before the material
reads), item 10 (variant specialization). Where this audit adds a bound or
a line-level detail to one of them it says so.

Precision facts this audit relies on (flutter-tricks L2, verified with the
SDK impellerc): `mediump` is dropped on the Metal and GLES runtime stages
and kept as RelaxedPrecision only on Vulkan; explicit float16 types
compile to MSL `half` and break GLES. `VULKAN` is defined only for the
Vulkan stage, `IMPELLER_TARGET_OPENGLES` only for GLES.

## 1. Cost model: what runs, per pixel, how often

Per glass layer per frame (liquid tier):

1. The final pass (ImageFilter.shader over a BackdropFilterLayer) runs over
   the filter clip: the material bounds plus contour, snapped OUT to
   64-device-px buckets (liquid_glass_layer.dart:1256-1261, :1285 via
   snap_rect_to_pixels.dart). Every pixel of the clip executes main();
   pixels outside the matte exit at core.glsl:524-530 after the affine
   mapping (no fetch); pixels inside the matte but outside the shape exit
   at :671-677 after one matte fetch and the decode. Face pixels run the
   whole shader: 1 matte fetch + 1 backdrop fetch (+2 for the in-pass
   soften, +2 for dispersion) + the color model + lighting.
2. The geometry pass (Flutter GPU, geometry_fragment.glsl or
   geometry_field_fragment.glsl) runs only when geometry changes (shape
   rects, lift, DPR, a changed field): every frame while a lens is dragged,
   a button lifts or a menu fuses; never at rest. Its target is the matte,
   RGBA8, bucketed to 64 px; one 4-vertex quad.
3. The material pass (material_gradient_fragment.glsl) runs with the
   geometry pass only for layers whose shapes have DIFFERENT appearances,
   at 1/8 resolution (materialRasterScale 8). Negligible; audited for
   completeness only.
4. The blur pass: layers with frost above 1.25 device px get
   ImageFilter.compose(blur, shader) (liquid_glass_layer.dart:1267-1281):
   bars and menus (frost 2 pt at tint 0, ios27RegularFrost), small lenses at
   rest (unliftedBlurRadius 6). Buttons and large lenses are unfrosted
   (glass_liquid_draw.dart:49-57); the clear lens at 0.35 pt softens in the
   shader (uSoften). The blur is Impeller's own and out of scope here except
   for the margin it imposes.

Which code paths the widget layer actually takes (glass_liquid_draw.dart:
22-74, liquid_glass_settings.dart presets, liquid_glass_appearance.dart):

- color model: iOS 27 regular / toolbar / clear for every control
  (`uAppearanceConfig.x` in {1, 2, 3}); `directShare` is 0, so the
  `directShare > 0.0` block (core.glsl:796-812) never runs for morph's own
  controls and the `directShare < 1.0` block (:813-905) always runs.
- transmissionGamma is 1 in every preset (liquid_glass_appearance.dart:
  15, 30, 42, 53, 79, 90, 116); `surface.transmissionGamma` can override
  it.
- highlightWrap is the constant 0.5 (liquid_glass_settings.dart:411), so
  `wrapExponent` (core.glsl:399) is exactly 1.0 in every draw.
- bevelShadowStrength 0.036 regular, 0 clear (:33, :129); contour 0.43 /
  0.88 / 0.36; dispersion 0 except a lifted lens (-0.25 x lift,
  glass_renderer.dart:214); backdropShrink 0 except lenses.
- shapes: every control capsule / rounded rect is a
  LiquidRoundedSuperellipse (glass_liquid_draw.dart:122-131), a circle is
  a LiquidOval; `exact` rounded rectangles come from plain unions.

Where the time goes on the weak device (from the passport): Pixel 6a
Vulkan liquid raster p95 is 10.6-18.6 ms per scene against flat's
6.6-13.1 ms, so everything liquid adds (flips, subpasses, blur, the final
pass) is 4-6 ms per frame on the big scenes and ~1 ms on the control
scenes. The final pass's share of that is not measured anywhere yet; the
harness (section 5) measures it first. A rough ALU budget: a full-screen
sheet is ~2.6 Mpx; at ~250-350 scalar ops per face pixel the final pass
alone is 0.7-1.4 ms of a Mali-G78 MP20's arithmetic at its mid clock, so
ALU levers matter for sheets, menus and bars, not for buttons.

## 2. Ranked findings

Rank = expected gain on the weak device x confidence that the gain is
real, per effort. Fidelity: IDENTICAL (bit-equal output), NEAR (max
channel error stated, 8-bit output), VISIBLE (changes pixels beyond that;
not proposed, listed for completeness).

| # | finding | where | fidelity | gain (weak device) | confidence | effort |
|---|---|---|---|---|---|---|
| F1 | Fold the uniform-only iOS 27 color-model constants (neutral tint, face transfer, dark-border gain, glint targets) into uniforms for the default and tint variants; keep them per pixel only under SHAPE_APPEARANCE | core.glsl:148-210, 820-862 | NEAR, <= 1 step on < 0.1 percent of pixels (float vs double rounding) | M (60-90 scalar ops + 3-4 divisions off every face pixel) | high | S-M |
| F2 | Deep-interior early return in applySpecularHighlights: when the pixel lies past the glint bleed AND past the bevel band, return baseColor | core.glsl:385-391 (extend) | IDENTICAL (proof below) | M on menus, sheets, alerts, date picker (zero on 44 pt buttons and bars: their center line is at 22 pt) | high | S |
| F3 | Skip pow() whose exponent is exactly 1: the glint lobe at wrap 0.5 and the transmission gamma 1 | core.glsl:399-401, 797-800, 864-872 | NEAR, 0 steps in practice (pow(x,1) differs from x by <= 2 ulp) | S-M (2-8 transcendental ops per face pixel, every control) | high | S |
| F4 | Compute contourCoverage and contourDirection once per fragment and pass them; divide by uEdgeWidth once | core.glsl:272-304, 372, 480, 673, 929-931 | IDENTICAL (same expression, same inputs; the reciprocal is NEAR <= 1 ulp) | S-M if the driver does not CSE across the inlined calls (12 clamps, 12 divides) | medium | S |
| F5 | Decode the surface normal once (decodeDisplacement re-decodes it) | displacement_encoding.glsl:79-95, core.glsl:678-681 | IDENTICAL | S (one normalize, floor/mod chain) | medium (likely CSE'd already) | S |
| F6 | RelaxedPrecision (mediump) for the COLOR section only, Vulkan only; explicit list of what must stay highp (L2 with bounds) | core.glsl:10, 793-937, 352-507 | NEAR, <= 2-3 steps worst case on Mali fp16 (typical < 1) | M-H on Mali Vulkan (fp16 doubles ALU rate), 0 on GLES and Metal from mediump alone | medium | M |
| F7 | Specialize the final shader per preset class (regular: bevel on, no dispersion, no shrink; clear lens: dispersion + shrink + soften, no bevel, no tint tone) instead of uniform branches: fewer live registers, shorter longest path | the three .frag entry points + core.glsl:685-711, 716-791, 415-476, 891-898 | IDENTICAL (same formulas, dead paths removed) | M on Mali (occupancy), S on Apple | medium (malioc decides) | M |
| F8 | Uniform-only expressions evaluated per fragment: hoist to uniforms or to a VULKAN/Metal-friendly form | core.glsl:259-264, 399, 419-428, 516, 543, 661, 683, 706, 821-826; geometry_fragment.glsl:61 | IDENTICAL or NEAR <= 1 ulp | S each; depends on whether the Mali and Apple compilers already hoist (malioc reports "uniform computation") | medium | S |
| F9 | Field texture RGBA32F -> RGBA16F while keeping the shader's own 4-tap bilinear (step 1); hardware bilinear fetch as a separate step 2 | geometry_field_fragment.glsl:39-53, flutter_gpu_geometry_renderer_native.dart:1109-1116 | step 1 NEAR <= 1 step; step 2 VERIFY (fixed-point filter weights on the rim) | L-M only while a menu fuses (halves a per-frame upload) | medium | S / M |
| F10 | fake_glass_surface.frag: `precision mediump float` covers the FlutterFragCoord math and the SDF; on Vulkan that is RelaxedPrecision - a silhouette quantization risk at coordinates > 1024 px. Make it highp with mediump only on lighting | fake_glass_surface.frag:4, 83-84 | fidelity hygiene (bug risk), not perf | - | high that the risk exists; unmeasured whether Mali takes it | S |
| F11 | fake_glass_shape.glsl: replace the atan2 cap test with the dot / cos-span test the geometry pass already uses | fake_glass_shape.glsl:79-84 vs sdf.glsl:107-113 | IDENTICAL except pixels within 1 ulp of the cap boundary, where both branches meet by construction | S (fake tier: first frames, web) | high | S |
| F12 | Mali ternary hygiene: the Vulkan miscompile hit a ternary on a decoded value; decodeSurfaceNormal has the same construct | displacement_encoding.glsl:82-85, core.glsl:253-255, 368, 402, 442, 589, 639, 824 | IDENTICAL (mix with t in {0, 1} is exact) | 0 (risk reduction) | high | S |
| F13 | Geometry pass: superellipse bisection over u = cos^2(x) instead of x (no sin/cos per iteration) | sdf.glsl:39-65 | NEAR, <= 0.02 pt distance, <= 0.05 pt displacement | S (only the arc sector, only when the matte re-renders) | medium | S |
| F14 | Reorder the coverage reject before the material reads (perf-research X2): confirmed IDENTICAL by data dependency | core.glsl:544-658 vs 661-677 | IDENTICAL | S-M for the material variant's exterior pixels only | high | S |
| F15 | Filter clip buckets 64 -> 16/32 px for unfrosted layers (flutter-tricks L5); the outside-matte early-out makes the extra area cheap but the subpass clear / composite is not free | liquid_glass_layer.dart:1256-1261, 1285 | IDENTICAL (unfrosted) | M with many small controls | medium | S |

Not proposed (VISIBLE or outside the rules): a first-order superellipse
distance in the geometry pass (fake_glass_shape.glsl:33-40 style; the
bevel reads the distance 20 pt deep and the 0.12 pt error becomes a
0.3 pt refraction error); an in-pass 9-tap kernel replacing the bar /
menu blur pass (a different kernel than the one the frost was fitted
against); any reduced-resolution final pass (flutter-tricks section 2:
runtime effects re-rasterize at full resolution); the "lite" variant
without dispersion / soften (L9: a policy tier, changes the look).

## 3. Findings in detail

### F1. Uniform-only color-model constants per fragment (core.glsl:813-862)

For morph's controls `colorModelShares` comes from the uniform
`uAppearanceConfig.x` (:543) in the default and tint variants; only the
SHAPE_APPEARANCE variant derives it per pixel from the material map
(:649-653). Everything in :820-862 that depends on it alone is therefore
constant across the draw, yet evaluated per face pixel:

- `darkWeight`, `clearWeight`, `regularDarkWeight` (:821-826): two
  divisions and clamps.
- `ios27NeutralTint(0, w, true, t)` and `ios27FaceTransfer(0, true, t)`
  (:827-833): constants.
- under `clearWeight < 1.0` (:834-850): `ios27NeutralTint(regular...)`
  = `ios27DarkTransmittance` (1 smoothstep, 3 mix, 2 sliderKeyframes with
  their compare + mix), a division `1 / (1 - darkTransmittance)`,
  `mixWash` (a division); `ios27FaceTransfer` = 3 sliderKeyframes; then
  another `mixWash` and a `mix`.
- the dark border gain (:851-857): two more `ios27DarkTransmittance`.
- the glint targets (:858-862): three mixes.

That is roughly 60-90 scalar operations and 3-4 divisions per face pixel,
on every regular and toolbar surface. Proposal: compute `neutralTint`
(vec4), `faceTransfer` (vec2), the contour gain and the three glint
targets on the CPU where the layer already writes `shaderValue`,
`uTintAmount` and `_materialShortSide` (liquid_glass_layer.dart:613-676),
pass them as two vec4 + one vec3 uniform, and keep the per-pixel path
under `#if SHAPE_APPEARANCE` only. The Dart side already carries this
math for fake glass (`colorModel.faceTransfer(shortSide, tintAmount:)`,
paint_fake_glass_surface.dart:98-104, liquid_glass_color_model.dart), so
it is a port, not a reformulation. Fidelity: the GPU evaluates the same
formulas in float; a double-evaluated uniform differs by a few ulp, which
flips an 8-bit channel only when the true value lies within ~1e-6 of a
rounding boundary - NEAR, <= 1 step, well under 0.1 percent of pixels;
hash-equal is not guaranteed, the harness tolerance is 1.

### F2. Deep-interior early return in the lighting (core.glsl:352-507)

The second early return (:385-391) requires `uBevelShadowStrength <
0.001`, so with the bevel shadow on (regular 0.036) no face pixel ever
takes it, however deep. Yet for a pixel with

    inwardDistance >= glintWidth * kGlintBleedReach   (4 x 1.2 pt)
    inwardDistance >= uBevelShadowDepth + max(uBevelShadowOffset, 0)
                                                    (16 + 6 = 22 pt)
    outlineCoverage < 0.01                           (true past 1 pt)

the function returns `baseColor` bit for bit. Proof: `glintProfile` is
exactly 0 (both clamps hit their lower bound), so `glint` = 0.
`shadowShift <= max(uBevelShadowOffset, 0)`, hence `inwardDistance -
shadowShift >= sizeAwareBevelDepth` and `smoothstep` returns exactly 1,
`bevelFalloff` = 0, `bevelBand` = 0, `bevelShadow` = clamp(0 * ...) = 0.
`contourCoverage(sd).y` is exactly 0 inside (every `contourIntegral`
argument is clamped to 0, :273), so `edgeAbsorption` = 0 and `result` =
`baseColor * 1.0 + rgb * 0.0 + t * 0.0` = `baseColor`. Then `result =
max(result - transmitted * 1.0 * 0.0, 0)` = `max(baseColor, 0)` =
`baseColor` because both color paths clamp to [0, 1] (:807, :877, :885,
and the mix of clamped values at :899). Finally `mix(result, target,
0.0)` = `result` and `max(result, 0)` = `result`. The whole bevel block
(4 smoothsteps, the dot products, the luminance and glint target) is
skipped for every pixel more than 22 pt inside the silhouette: on a
250 x 400 pt menu that is ~75 percent of the face, on a sheet or alert
most of it, on a 44 pt capsule nothing. Make the threshold a uniform
(`uBevelShadowDepth + max(uBevelShadowOffset, 0)` and `glintWidth *
kGlintBleedReach`) so the test is one compare on a dynamically uniform
value and the branch stays coherent.

### F3. pow() with exponent 1 (core.glsl:399-401, 797-800, 864-872)

`wrapExponent = exp2(2.0 - 4.0 * clamp(uSpecularWrap))` is exactly 1.0
for highlightWrap 0.5 (2.0 - 2.0 = 0.0, exp2(0.0) = 1.0 on every GPU),
so `lobe = pow(axisAlignment, 1.0)` is a log2 + exp2 pair per face pixel
returning its input to within 2 ulp. Gate it: `uSpecularWrap == 0.5 ?
axisAlignment : pow(...)` (a uniform compare; or pass `wrapExponent` as a
uniform and test `== 1.0`). Likewise `pow(x, uTransmissionGamma)` with
gamma 1 in every preset: one scalar pow in the iOS 27 path (:864), a
vec3 pow in the direct path (:797). Gate on `uTransmissionGamma == 1.0`.
The gate also removes `exp2` at :399 from the per-pixel path (F8). NEAR:
pow(x, 1.0) versus x differs by at most a couple of ulp; after the 8-bit
quantization that is 0 steps except on rounding-boundary pixels.

### F4. contourCoverage three times, contourDirection twice

`contourCoverage(signedEdgeDistance)` is evaluated at :673 (.x), :372
(.y) and :929 (.x); each call is four `contourIntegral` evaluations with
a clamp and a divide by `2.0 * uEdgeWidth` (:274). `contourDirection
(surfaceNormal)` runs at :480 and :931. Drivers commonly CSE pure
expressions after inlining, but nothing guarantees it across three call
sites with an intervening early return; computing `vec2 cover` once after
:670 and passing it into applySpecularHighlights is IDENTICAL by
construction. Replacing the divide by a uniform `0.5 / uEdgeWidth` is
NEAR (1 ulp).

### F5. The normal decoded twice (displacement_encoding.glsl:79-95)

`decodeDisplacement` (:90-95) calls `decodeSurfaceNormal` on the same
`encoded`, and main() calls it again at core.glsl:681. Each decode is two
floors, a divide, two nested ternaries and a `normalize`. Pass the decoded
normal into `decodeDisplacement(normal, encoded, max)`: IDENTICAL. Also the
place to apply F12 (the nested ternaries at :83-84 on a decoded float are
the construct that miscompiled in `decodeSignedEdgeDistance` on Mali
Vulkan; `mix(1.0 - diamond, diamond - 3.0, step(2.0, diamond))` is exact
because the weight is exactly 0 or 1).

### F6. RelaxedPrecision for the color section (flutter-tricks L2, with bounds)

The core declares `precision highp float` (:10) because mediump
coordinate math shimmered on GLES; per L2 that line only matters on
Vulkan, where mediump locals become RelaxedPrecision and Mali runs them in
fp16 at twice the arithmetic rate. What may be mediump (relative error
2^-11 per operation, 0.12 channel step at 1.0):

- `refractColor` after the fetch, `transmittedColor`, `baseColor`,
  `materialTint`, `neutralTint`, `faceTransfer`, `ios27Base`, `tintTone`,
  the saturation / vibrancy / chroma math (:793-905, render.glsl:12-22),
  the lighting scalars `glintProfile`, `lobe`, `glint`, `bevel*`,
  `edgeAbsorption`, `result`, `glintTarget` (:366-506), `finalColor` and
  the premultiplied output (:921-937).

What must stay highp (fp16 cannot hold it):

- `fragCoord`, `screenUV`, `matteCoord`, `geometryUV`, `invUSize` (a UV
  step of 1/2400 has a relative fp16 error of 6e-4, i.e. more than a
  pixel), every sample coordinate, `mirrorIntoBackdrop`,
  `backdropScaleOffset` (:515-530, 683-791).
- the matte decode: `floor(encoded.rg * 255.0 + 0.5)` and the 12-bit
  codes up to 4095 (fp16 is exact only to 2048), `signedEdgeDistance`,
  `displacement`, `surfaceNormal` (displacement_encoding.glsl:79-109).
- `inwardDistance`, `contourCoverage` (sub-pixel ramps; :272-290).

Bound: the color chain is ~25 dependent operations; linear worst case
25 x 2^-11 = 1.2 percent of full scale = 3 channel steps, typical random
accumulation ~0.6 step. NEAR, max 3, to be measured on the Pixel with the
harness; on Metal and GLES the change is a no-op by construction (L2), so
the iPhone gate is "hash-equal" there. Use a header macro as L2 sketches
(`#ifdef VULKAN` -> `mediump`, else `highp`), never explicit float16.

### F7. Preset-class specialization (perf-research item 10, sharpened)

The hot variant (default) still carries every uniform-gated path:
backdrop shrink (:685-711), dispersion (:759-791), soften (:748-758),
the bevel block (:415-476), the tint tone (:891-898, six pow calls), the
direct color path (:796-812). Uniform branches do not diverge, but the
register allocation is for the union of all paths and the longest path
sets the latency; Mali occupancy follows the register count. Two
specializations cover morph's controls exactly: REGULAR (bevel on,
dispersion 0, shrink 1, soften off, tint tone on) and LENS (bevel off,
dispersion and shrink on, soften on, tint tone off since a lifted lens is
clear glass, glass_liquid_draw.dart:71-73). Same formulas, dead paths
compiled out: IDENTICAL. The cost is two more pipelines in the warm-up.
Decide with malioc register / cycle counts before building it.

### F8. Uniform-only expressions per fragment

Each is a few operations; together they are a few dozen per pixel if the
driver does not hoist them. `1.0 / uSize` (:683), `fragCoord / uSize`
(:516, a divide where a multiply by a uniform reciprocal is NEAR 1 ulp),
`colorModelSharesOf(uAppearanceConfig.x)` (:543, three compares),
`contourExtent()` (:259-264), `max(uDisplacementScale, 0.001)` (:661),
`exp2(...)` (:399, F3 removes it), `sizeProgress` / `sizeEnergy`
(:419-428, a smoothstep and a mix per pixel), `1.0 / magnification`
(:706), the weights at :821-826 (F1). The Mali compiler does report
hoisted "uniform computation" separately in malioc output, so the gate is
cheap: compile, read the per-pixel arithmetic cycles, hoist only what the
counts show is not already hoisted. The same applies to the globals at
:57-80 (`uTintAmount` clamp and friends), which are per-invocation
initializers.

In the geometry pass, `sceneBoundsOutsideSquared` (sdf.glsl:338-355)
re-reads every shape's marker to sum the smoothing budget per pixel; the
budget is a uniform-only sum that the packer (liquid_glass_layer.dart:
1547-1640) could write once. IDENTICAL; small (the pass runs only on
geometry changes).

### F9. Field texture format (flutter-tricks L10, with bounds)

The field holds signed distance, gradient and half thickness in logical
pixels (glass_field.dart:14-19), uploaded as RGBA32F (renderer_native.dart:
1114) and read with four nearest fetches plus a manual bilinear
(geometry_field_fragment.glsl:39-53). fp16 bounds: the gradient is in
[-1, 1] (step 2^-11, irrelevant); the distance only matters where the
matte encodes it - within `4 x edgeDistanceRange` = 80 pt (sqrt-compander,
displacement_encoding.glsl:54-69) - and only drives displacement within
the bevel, 20 pt (geometry_field_fragment.glsl:98-101): fp16 step is
2^-11 pt below 1 pt, 2^-7 pt at 8-16 pt, 2^-6 at 16-32. The bevel profile
`1 - sqrt(1 - x^2)` is steepest at the silhouette (slope 7 at x = 0.99),
where the step is 0.001 pt: displacement error <= 0.001 x 7 x (60 / 11)
= 0.04 pt = 0.12 device px at 3x; deeper in, the slope falls faster than
the step grows. Coverage (`sd + 0.5` in device px) sees < 2^-12 pt error
in the AA ring. So step 1 (RGBA16F, same shader) is NEAR <= 1 step and
halves the upload (a 70 x 155-node menu field is 170 KB per changed frame
today). Step 2 (hardware bilinear, one fetch) adds the sampler's
fixed-point weight error - 8 bits on Mali - times the node delta (up to
the 4 pt grid step): 0.016 pt, which the steep end of the bevel turns
into up to ~0.1 pt on the outermost refracted ring. Ship step 1; measure
step 2 on the rim with the harness before deciding. The half thickness
channel (up to ~300 pt, step 0.25 pt) only feeds `min(20, 0.5 x
halfMinor)` and is exact enough wherever the min is not saturated
(below 64 pt its step is <= 2^-5).

### F10. fake_glass_surface.frag precision

`precision mediump float` (:4) qualifies `position = FlutterFragCoord()
- uSize * 0.5` (:83) and the whole SDF. On Metal and GLES it is dropped
(L2); on Vulkan it is honored, and fp16 cannot represent a device
coordinate above 1024 to better than 1 px, nor a distance to better than
2^-11 of its magnitude. If the Mali driver takes the RelaxedPrecision
hint, the fake tier's silhouette and contour band quantize on the lower
half of a 2400 px screen. The fake tier draws the first frames before the
liquid capability resolves and whatever falls back, so this is a
fidelity risk worth a one-line fix: `precision highp float` for the
file and mediump only on the lighting scalars. Verify with the harness
on the Pixel (fake tier, a capsule at y > 1024 px; expect a hash change
only if the driver was using fp16).

### F11. fake_glass_shape.glsl cap test

`atan(relative.y, relative.x)` plus `mod` (:80-82) per pixel; the
geometry pass does the same test as `dot(relative, vec2(0.7071)) >
length(relative) * cosSpan` (sdf.glsl:107-113) with `1 - cos(span)`
packed on the CPU (liquid_glass_layer.dart:1609-1612; the fake path passes
the raw angle, paint_fake_glass_surface.dart:146-150). Port the packing
and the test: one dot, one length, no transcendental. The two tests agree
except within an ulp of the boundary, where the circle and the
superellipse arc are tangent by construction, so no pixel changes by more
than the AA ramp's slope times an ulp. Low gain (fake tier only).

### F12. Ternaries on decoded values (Mali Vulkan)

The passport's Vulkan box bug was a ternary on the sign of a decoded
float inside the full shader, fixed with `step` arithmetic
(displacement_encoding.glsl:104-108). The same shape exists at
displacement_encoding.glsl:82-85 (nested ternaries on `diamond`),
core.glsl:253-255 (`colorModelSharesOf`), :368 (`uHighlightWidth > 0.0 ?
...`), :402, :442, :589-591, :639-641, :824-826. Where both arms are
finite, `mix(a, b, step(edge, x))` is bit-identical to the ternary
(weights exactly 0 or 1). Not a speedup (a select is as cheap as the
arithmetic) but it removes the construct the compiler already got wrong
once; the harness's Vulkan-versus-GLES comparison on the Pixel is the
regression gate.

### F13. Superellipse bisection without trig (sdf.glsl:39-65)

Each of the six iterations evaluates `cos`, `sin` and two `pow` (:49-52),
then two vec2 `pow` (:59-60): ~44 transcendental operations per pixel in
the arc sector of every continuous corner. Reparametrize by u = cos^2(x)
over [0.5, 1]: `cn = u^(n/2)`, `sn = (1 - u)^(n/2)`, `s^2 = 1 - u`, `c^2 =
u`, so each iteration is two pow and no trig (~28 transcendental in
total). The six bisection steps land on different midpoints, so the
result is not bit-identical: the segment projection (:61-64) then bounds
the error by the chord sag of a 1/64-of-the-octant step, about 0.02 pt on
a 20 pt corner, and the bevel turns that into <= 0.05 pt of displacement.
NEAR. The matte re-renders only while geometry moves, so the gain is
confined to lens drags and lifts; measure with the geometry-pass bench
before building.

### F14. Coverage reject before the material reads (perf-research X2)

The reject at core.glsl:671-677 reads `signedEdgeDistance` (matte +
uniforms), `contourExtent()` (uniforms) and `gContourAlpha`, which at that
point is still `uContourColor.a` in the current order as well (its
mutation at :856 comes later in both orders). `appearanceVisibility` and
`colorModelShares` are not read by the test. Moving the block to right
after the matte fetch (:535) is therefore IDENTICAL; it saves the two
contributor fetches, the four dependent lookups and the blend arithmetic
(:574-658) for every exterior pixel of a mixed-appearance layer (the
menu with a tinted item, a prominent button beside a plain one in one
container).

### F15. Clip overdraw (flutter-tricks L5)

The pixels the 64-px bucket adds exit at :524-530 after six multiplies
and two compares, so the shader cost of the padding is small; the
subpass clear, the stencil clip and the composite of the clip rect are
what the bucket costs, and those scale with area. L5's numbers stand
(up to 3.7x area for a 44 pt control at 3x). Nothing to add from the
shader side except that `uGeometryUVScale` already lets the matte be
smaller than the clip, so shrinking the clip bucket needs no shader
change.

### Also checked, nothing to gain

- Texture fetch counts per face pixel: default 2 (+2 soften), tint 3,
  material 8 with four dependent lookups (:604-623, nearest, 1 x 2 texels
  each). The dependent lookups are inherent to the contributor map.
- The dispersion path (:759-791): three backdrop fetches plus three
  `mirrorIntoBackdrop`, uniform-gated by the quarter-pixel threshold
  (:716-719). Only lifted lenses pay it. The in-bounds test is cheap.
- `texelFetch` on the undisplaced face versus `texture` on the bevel
  (:722-747): a divergent branch along the bevel edge only; both arms
  are one fetch. Correct as is.
- The soften kernel (:748-758): two extra bilinear fetches, whole-texel
  offsets, replaces a blur pass; cheaper than any alternative.
- Geometry pass bounds culling (sdf.glsl:320-355, 457-466) and the
  empty-pixel reject (geometry_fragment.glsl:57-65) are in place; the
  loop pattern (`for i < MAX_SHAPES; if (i >= count) break`) is what GLES
  needs. The other agent's MAX_SHAPES / batching work is not touched here.
- Material pass: 1/64 of the pixels; the 16-way `if` chain
  (material_gradient_fragment.glsl:39-56) is GLES dynamic-index hygiene.
- No vertex stage to move work into: runtime effects draw a full quad
  with no vertex program, so the affine `matteCoord` cannot be an
  interpolant. The per-pixel cost of it is six multiplies.
- The blur compose margin (`backdropSamplingReach`, liquid_glass_layer.
  dart:1441-1455) is already the minimum the kernel and the displacement
  need.

## 4. Suggested order

1. Harness first (section 5): the parity test and the K-layer bench on
   the Pixel, plus malioc on the GLES / SPIR-V output. Without them the
   ALU findings cannot be ranked against the pass / flip costs the
   passport already measured.
2. F2, F3, F4, F5, F14 (IDENTICAL or 0-step NEAR, S effort, one PR):
   gate = hash-equal shots on the iPhone and the Pixel for F2 / F4 / F5 /
   F14; F3 within 1 step.
3. F1 (uniform fold): gate = max 1 step, < 0.1 percent of pixels.
4. F6 (Vulkan mediump colour): gate = Pixel shots within 3 steps, iPhone
   hash-equal; GLES unchanged.
5. F7 / F8 as malioc counts justify; F9 step 1; F10 / F11 / F12 as
   hygiene with the parity gate; F13 last.

## 5. Synthetic shader harness

Goal: deterministic inputs through every shader variant, offscreen, on
the device, compared before / after with per-case tolerances, plus a GPU
time per variant. Host paths for exact parity without a phone where they
exist. The gallery audit stays the end-to-end judge; this harness
isolates the shaders.

### 5.1 Files

    example/integration_test/shader_parity_test.dart
        Renders every case of the table at rest, two frames, captures the
        RepaintBoundary (as liquid_exterior_test.dart does), writes
        <case>.png and parity.json (per-case FNV hash, size, tier,
        backend line from the capability probe) into AUDIT_OUT. Also shoots
        every case twice in one run: the two shots must hash-equal, which
        pins the run-to-run noise of the synthetic scene at 0 before any
        before / after number is read.
    example/integration_test/shader_bench_test.dart
        The GPU bench (5.4). Writes bench.json into AUDIT_OUT.
    example/integration_test/support/shader_cases.dart
        The case table (5.2), shared by both tests.
    example/integration_test/support/synthetic_backdrop.dart
        The deterministic backdrop image (5.2), a pure function of
        (width, height, seed); usable from package tests too.
    tool/audit/shader/parity.py
        Compares two AUDIT_OUT directories case by case: max channel,
        mean, count over a per-case tolerance read from shader_cases'
        exported tolerances.json; exit 1 on any case over tolerance.
        shotdiff.py's loop with tolerances instead of the fixed 15.
    tool/audit/shader/bench.py
        Reads bench.json (and optionally a Perfetto trace / xctrace
        export), fits ms per layer from the K series, prints per case.
    tool/audit/shader/offline.sh
        impellerc for each backend + malioc + spirv-cross instruction
        counts for every .frag and every bundle fragment (5.5).
    tool/audit/shader/run_pixel.sh, run_iphone.sh
        Thin wrappers over audit_android.sh / audit.sh with
        AUDIT_TARGET=integration_test/shader_parity_test.dart (or
        _bench_) and AUDIT_REPORT=shader; the device lock protocol of
        spec/README.md applies.

One package change the harness needs, to be done by whoever lands it:
a `@visibleForTesting` override on ShaderKeys (shaders.dart:12-28) so a
build can carry a SECOND copy of a final-render variant
(`liquid_glass_final_render_probe.frag`, listed in the pubspec shaders)
and the test picks the asset by `--dart-define=SHADER_VARIANT=probe`.
Same binary, same launch, two shaders: the only way to compare two
shader texts without the between-launch noise the passport records.

### 5.2 Deterministic inputs

Backdrop: a `ui.Image` decoded from bytes computed by a 32-bit LCG with a
fixed seed, sized to the physical pixels of the test region, drawn with
`canvas.drawImage` at an integer device offset and `FilterQuality.none`
so the backdrop is the SAME texels on every launch of the same device.
Three bands in one image: hard stripes (refraction and dispersion read
as staircases or not), a smooth horizontal gradient (banding and
precision), seeded noise (blur and the soften kernel). The region is
360 x 640 logical pixels, so the clip-bucket and matte-bucket phases are
fixed too.

Glass: the renderer's own widgets from package:morph/src/glass/renderer
(implementation import, as glass_audit_test.dart does), never the
measured controls - no springs, no clocks, no tickers. Each case is
(settings, appearance, shape or field, rect, extra): fixed numbers, two
pumps, shoot.

Case table (the paths of section 1, each with the variant it exercises):

| case | variant | what it pins |
|---|---|---|
| regular-capsule | default | the hot path: ios27Regular, bevel on, no frost, no dispersion; F1 F2 F3 F4 F5 F6 F8 |
| toolbar-dark-blur | default + blur compose | frost 2 pt (a blur pass), contour 0.88, directionality 1 |
| clear-lens-rest | default + soften | ios27Clear, frost 0.35, the three-tap kernel, texelFetch face |
| clear-lens-lifted | default | dispersion -0.25, amount 100, backdropShrink 0.3 with a shrink axis; the three-fetch path, F7's LENS class |
| prominent-tinted | default | tint alpha > 0: ios27TintTone's pow chain (F3 / F6) |
| mixed-pair | material | two shapes with different appearances; the contributor map and dependent lookups; F14 |
| tint-pair | tint | two shapes differing in tint only |
| fused-field | default + field pass | a two-capsule smin field built in the test by the CPU law (deterministic); F9 |
| rse-corner-large | default | a 200 x 120 continuous corner with radius 40: the superellipse arc sector (F13) |
| big-sheet | default | a 360 x 600 regular surface: the deep interior (F2) and the ALU budget |
| visibility-half | default | appearance.visibility 0.5 with uBlurFade both ways: the fades stay linear |
| exterior-contour | default | contourStrength 1, a shape whose silhouette lies at y > 1024 px on the device: F10 on the fake tier, F12 on Vulkan |
| fake-* | fake tier | the same shapes through LiquidGlassLayer(fake: true): F10, F11 |

Every case is shot on the liquid tier and (where meaningful) the fake
tier, in dark and light appearance.

### 5.3 Comparison protocol

`parity.py before/ after/`: per case the max channel difference, the
mean, the count of pixels over the case's tolerance, and the hash.
Tolerances come from the finding being tested, not from the noise floor
(which is 0 here by construction and checked by the double shot):

- IDENTICAL findings (F2, F4, F5, F7, F11, F12, F14, F15): tolerance 0,
  every pixel; a single differing pixel fails.
- NEAR findings: F1 and F3 max 1, over-0 count <= 0.1 percent; F6 max 3
  on the Pixel (Vulkan) and 0 on the iPhone and on the Pixel forced to
  GLES; F9 step 1 max 1, step 2 max 1 outside the outermost refracted
  ring and reported inside it; F13 max 1.

Vulkan versus GLES on the same Pixel (the manifest's
`ImpellerBackend=opengles`, as the passport's Vulkan-box fix was verified)
is a second axis: the two backends must agree on every IDENTICAL case to
0 and on every NEAR case within the same bound, which is how a Mali SPIR-V
miscompile shows up without a reference.

### 5.4 GPU time per variant

FrameTiming's raster duration ends at submit, before the GPU finishes
(Impeller presents asynchronously), so a shader's GPU cost needs either a
GPU timestamp source or saturation. The bench does both:

1. Saturation, backend-agnostic: one BackdropGroup with K full-region
   glass layers of the SAME case (sharing the key, so one flip and K
   shader passes), K in {1, 4, 8, 16, 32}; the backdrop translates by one
   device pixel per frame so the scene repaints while every shader input
   stays constant; 240 frames per K after a 60-frame warm-up. Record the
   vsync-start intervals (the measured cadence, as glass_audit does) and
   the raster p50. Past the budget the cadence steps in whole vsyncs, so
   the slope of frame time against K (ms per layer) is read from the K
   values that run over budget (on the Pixel K = 8 and 16 already do for
   a 360 x 640 region). The difference of slopes between two shader
   variants (via SHADER_VARIANT in the same binary) is the shader's
   cost difference; the fixed cost (flip, clip subpass, composite)
   cancels. Thermal guard and GPU clock sampling as in audit_android.sh
   (AUDIT_COOL_C, AUDIT_GPUFREQ): a bench whose clock histogram differs
   between runs is discarded.
2. GPU timestamps where the platform has them: on the Pixel a Perfetto
   trace with the `power/gpu_work_period` ftrace event (Mali on recent
   Pixel kernels reports GPU active time per uid; audit_android.sh's
   atrace path and atrace_slices.py are the place to add the parser),
   giving GPU ms per frame directly; on the iPhone `xcrun xctrace record
   --template 'Metal System Trace' --device <udid> --launch -- <bundle>`
   and `xctrace export` of the GPU track, which gives per-frame GPU time
   and, in Xcode's GPU frame capture, per-shader time (manual, for the
   final confirmation of a landed change).

bench.json: per case and K the frame count, cadence p50 / p95, raster
p50 / p95, GPU ms per frame when a trace was imported, the clock
histogram; bench.py prints ms per layer per case and the delta between
two result directories.

### 5.5 Offline: instruction counts and Mali cycles without a phone

impellerc is at `<flutter sdk>/bin/cache/artifacts/engine/darwin-x64/
impellerc` (the 3.47.2 SDK is the one `flutter --version` reports, not
the Homebrew 3.19 cask on PATH). offline.sh compiles every runtime-effect
.frag three times (`--runtime-stage-metal`, `--runtime-stage-vulkan`,
`--runtime-stage-gles` with the SKIA stub excluded) and every bundle
fragment with the hook's settings (`glesLanguageVersion: 300`, the
`IMPELLER_TARGET_*` defines), writing SPIR-V and the backend source
(`--sl`, `--spirv`), then:

- `malioc` (Arm Mobile Studio, free) on the GLES ESSL and on the Vulkan
  SPIR-V with `--core Mali-G78`: arithmetic / load-store / varying /
  texture cycles per pixel (shortest and longest path), register count,
  and the "uniform computation" line that answers F8 directly. This is
  the first gate for every ALU finding on the Pixel: a change that does
  not move the longest-path cycle count is not worth a device run.
- `spirv-cross --msl` instruction counts for the Metal path (Apple
  publishes no offline cycle tool; the device bench and Xcode's shader
  profiler are the Metal truth).
- `flutter test --enable-impeller` on the host, if the flag is present in
  this SDK (the renderer comment at flutter_gpu_geometry_renderer_native.
  dart:531 shows flutter_tester runs Impeller Vulkan on SwiftShader): the
  same SPIR-V the Pixel runs, on a software rasterizer - an exact
  parity oracle for IDENTICAL findings with no device, not a timing
  source. VERIFY the flag before relying on it; the Mali driver's own
  compiler is still only observable on the Pixel.
- macOS desktop (`flutter test integration_test/shader_parity_test.dart
  -d macos`, Impeller Metal): the MSL path for fast iteration; AGX and
  A-series agree on the arithmetic the runtime stage emits, so a hash
  change here predicts one on the iPhone.

### 5.6 Running it

Pixel 6a (lock /tmp/morph-native/pixel.lock):

    AUDIT_TARGET=integration_test/shader_parity_test.dart \
    AUDIT_REPORT=shader AUDIT_TIERS="liquid fake" AUDIT_LABEL=shader-base \
    AUDIT_SHOTS=/tmp/morph-perf/shader/base \
      tool/ios_reference/perf/audit_android.sh
    # the change under test, same binary with the probe shader:
    AUDIT_DEFINES="--dart-define=SHADER_VARIANT=probe" AUDIT_LABEL=shader-probe \
    AUDIT_SHOTS=/tmp/morph-perf/shader/probe ...
    python3 tool/audit/shader/parity.py /tmp/morph-perf/shader/base /tmp/morph-perf/shader/probe
    # GLES axis: the manifest's ImpellerBackend=opengles, AUDIT_SUFFIX=-gles
    # bench:
    AUDIT_TARGET=integration_test/shader_bench_test.dart AUDIT_REPORT=shader_bench \
    AUDIT_COOL_C=38 AUDIT_GPUFREQ=1 AUDIT_RUNS=3 ... audit_android.sh
    python3 tool/audit/shader/bench.py tool/ios_reference/perf/<date>-shader-base tool/ios_reference/perf/<date>-shader-probe

iPhone 16 Pro (lock /tmp/morph-native/device.lock):

    AUDIT_TARGET=integration_test/shader_parity_test.dart AUDIT_REPORT=tmp/shader \
    AUDIT_TIERS="liquid fake" AUDIT_LABEL=shader-base tool/ios_reference/perf/audit.sh
    # same with SHADER_VARIANT=probe (audit.sh needs the AUDIT_DEFINES
    # passthrough audit_android.sh already has), then parity.py; for GPU
    # time, xctrace Metal System Trace around the bench launch.

Host, before any device run:

    tool/audit/shader/offline.sh            # impellerc x3 backends, malioc, spirv-cross counts
    flutter test --enable-impeller test/shader_parity_host_test.dart   # if the flag exists

Result directories follow the perf convention
(tool/ios_reference/perf/<date>-<label>/), shots stay out of git.
