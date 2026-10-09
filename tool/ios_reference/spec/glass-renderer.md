# Glass renderer passport (MorphGlassRenderer, tiers, adaptive policy, outline as truth)

Status: implemented in the package (owner decision 2026-10-03: the old
"no shader in the package" rule is CANCELLED); optics measured on the
device (see [glass-optics.md](glass-optics.md)); tier costs measured on the
iPhone 16 Pro. The tier POLICY numbers are engineering defaults, not
measurements.

## Contract (the seam)

- `MorphGlass(painter:)` installs a `MorphGlassPainter`; every control
  describes its glass surfaces (`MorphGlassKind`: track, lens, knob, thumb,
  button, bar, menu) every frame behind its content. Multi-surface
  controls hand them to `buildLayer(surfaces, content:)` (segmented labels
  and the tab row ride in as `content`, the menu hands button + platter
  in one call; options `spacing:`, `contentSlots:`, `outline:`); single
  surfaces to `buildSurface` (alert, date picker, sheet, search bodies) or
  `buildFill` (stepper), placed at `MorphGlassSurface.bounds`; `buildGlow`
  draws touch glows (tab-bar.md). Every call goes through a
  `MorphGlassHost` (`MorphGlassLayer` for the frames-driven layers): see
  "The surfaces channel" below.
- `MorphGlassSurface.glass` is false for plain fills (segmented, switch and
  slider tracks, stepper); every painter draws those flat through
  `buildFill`. The default `buildLayer` routes glass to `buildSurface` and
  plain to `buildFill`, so a painter overriding only `buildSurface` works.
- A surface carries the deformed shape, the flat color as a tint,
  brightness, lift, `opacity` (fade glass through it, never through an
  Opacity above the glass) and `MorphGlassOptics` (UIKit's refraction
  values `small` / `large`; `displacementAt` / `blurRadiusAt` interpolate
  by lift). Without a painter: flat fills.
- OUTLINE IS TRUTH: the package computes every shape once and FUSES; the
  renderer only SHADES the outline it is given (its own blend groups are
  gone). `MorphGlassLayerParts` sorts a layer into plain fills, separate
  glass bodies, FUSED bodies and floating lenses. A fused body is a
  `MorphGlassOutline` (glass_outline.dart: `path` + an internal sampled
  distance field `GlassField`): the menu's blurred-SDF silhouette
  (menu-button.md), or the groups a glass container fuses
  (`buildLayer(spacing:)`, skin merge law, gap < spacing - 0.5, step 2;
  `morphGlassContainerOutline`, memo of 4).

- OVERLAYS: a control whose glass flies into an overlay or a route
  carries the painter it resolves at its source; an overlay above the
  installing MorphGlass otherwise draws the flat fallback. `MorphGlass`
  is an InheritedTheme and the package carries the source's
  InheritedThemes (`MorphThemeCarrier`): engine flights (`showMorph*`,
  `showMorphRoute`, `MorphAnchor`, the context menu) wrap the whole
  shuttle and the settled route page, so a glass control used as a
  `MorphTag` source draws its ghost, and the dialog or sheet content
  draws its glass, with the source painter, following a tier switch one
  frame late; alerts, action sheets, sheets (and their content) and the
  date picker overlay capture from the presenting context; the zoom
  replica from its source tag. Menus and bar button menus also pass
  `MorphMenuHost.menuGlass` (test/glass_carry_test.dart,
  test/flight_theme_carry_test.dart). Closed 2026-10-05: no residual.
- Flutter GPU data passes (geometry, field, material) run with blending
  disabled: impeller's ColorAttachmentDescriptor default, unchanged by
  flutter_gpu unless setColorBlendEnable is called (Flutter 3.47.2).

## Packaging

- whynotmake-it's `liquid_glass_renderer` (Apache-2.0, upstream 3cec75ed)
  lives at lib/src/glass/renderer (LICENSE, NOTICE, VENDORED lists every
  local patch; analyzed with the package's lints). Shaders are package
  assets (pubspec `flutter: shaders:`); hook/build.dart builds its Flutter
  GPU bundle (morph_glass.shaderbundle.json -> build/shaderbundles/, an
  asset dir analysis ignores until the hook writes it).
- ONE public entry: `MorphGlassRenderer` (glass_renderer.dart), a
  MorphGlassPainter with `tier` (`MorphGlassTier` flat / fake / liquid)
  and the liquid settings (`MorphGlassMaterial`, blur, refraction, light,
  tint, frostControls); `liftedOptics` per control; `precache()`.
- WEB: the liquid capability sits behind a conditional import
  (glass_liquid.dart -> _native / _web; the web stub never touches
  Flutter GPU, `liquidAvailable` false, liquid draws fake glass); the
  layers themselves live in glass_liquid_draw.dart, shared by both, and
  LiquidGlassLayer takes its fake path there; the three final-render
  .frag files compile to an empty stub under SKIA_GRAPHICS_BACKEND ("Only
  simple shader sampling is supported"), so the web builds with nothing
  removed.
- Package tests set the renderer's `isLocalTest` (root-package asset keys).

## Upstream sync (2026-10-07)

The vendored library tracks upstream main through 3cec75eda468f9c6e481bd90b7533dcb5e997b8e
(2026-10-06), with Morph's local renderer patches preserved. The two
upstream commits after ab1c2d2 change only the real layer, the fake layer
and their shared render base; GPU geometry and shader sources do not change.
The compositor poll now compares the committed frame rather than the last
encode, so hidden glass settles instead of repainting on continuing app
frames. The shared shadow pass returns before saveLayer without shadows.
Fake appearance overrides use separately clipped backdrop transfers and
one source key with the shared filter; they still draw when the default
transfer is identity. Only matching, fully visible shapes use the shared
transfer. Morph's fused outline remains the outer clip, with inverse clips
excluding shapes served separately; no path Boolean operation is used.

Morph layer builders explicitly set their surface palette; containers
resolve the installed Morph brightness instead of relying on the
renderer's system-brightness default. Otherwise identical dark surfaces
inside a light-system host would all become individual override passes.
Container and list-stage tests retain the one-filter grouping contract.

`test/glass_upstream_sync_test.dart` covers hide/unhide while frames keep
running, separate transfer/key ownership, fused-outline exclusions and an
identity shared transfer. This is a correctness sync, not a measured GPU
or energy optimization. Native optical shaders remain unchanged.

## Tiers

- Tier 0 (flat) fills the outline.
- Tier 1 (fake) is the liquid layers through the renderer's FakeGlass
  (`LiquidGlassLayer(fake: true)`, the consolidated layer): the face
  transfer as one backdrop color matrix over the frost, rim / bevel /
  highlight from an analytic SDF per shape, no refraction, no lens
  magnification or backdrop shrink (the lens content copy is not grown to
  compensate); resting platters stay opaque fills. Needs no Flutter GPU:
  liquid draws it before the capability resolves and when it fails, and
  the web draws it. Replaced the frosted tier on 2026-10-05 (owner
  decision; frosted's history stays in the sections below).
- Tier 2 (liquid) shades it from the field: LiquidGlassLayer(field:)
  switches the geometry pass to shaders/gpu/geometry_field_fragment.glsl
  (same matte encoding; distance / gradient / half thickness interpolated
  bilinearly from an RGBA32F texture sampled nearest, a ring of
  host-visible textures rewritten 3 frames after last use; the material
  pass still reads the shapes). A body that fuses and comes apart (the
  menu) keeps ONE layer key ('body'), so its glass never restarts; the
  old interim (liquid shapes clipped to the outline, frost in the neck)
  survives only for an outline built from a path alone. The field's half
  thickness blends button -> menu by the nearer shape over the blur
  radius; the menu field is blurred at least 24 pt deep
  (`MorphMenuFusion.shadedDepth`, the bevel depth) and kept at every 2nd
  trace node below a 4 pt step. The field's gradient is the field's own
  normal TURNED to the optical corners: the analytic shapes take their
  normals from a 1.5x corner radius (`kOpticalCornerRadiusScale`), so
  each field node turns its gradient by the angle between the nearer
  shape's exact and optical normal (blended across shapes like the half
  thickness; `morphOpticalCornerScale`), and a fused corner lights where
  the same shape alone does (glass_renderer_test pins the angle).
- PLAIN UNIONS ARE EXACT (2026-10-05, owner decision: invisible pixel
  changes that save work are allowed): an outline at container spacing 0
  (`morphGlassContainerOutline(shapes, 0)`: the menu's silhouette once
  the fusion radius is under 1 pt - the settle tail, every resize - and
  every submenu card) is no longer a sampled field. Its edge is the path
  union of the boxes (Path.combine; a box inside another adds nothing),
  and the liquid tier shades each box as its own circular rounded
  rectangle (`LiquidRoundedRectangle`, not the continuous corner of a
  plain glass surface), nearest box wins - the law the sampled field
  approximated on a 2 pt trace grid and a 4 pt field grid, with the same
  layer, one body shadow outside the union and no primitive shadows. The
  blurred neck (radius >= 1 pt) and container fusion at a spacing keep
  their fields. Work: perf_counts 'traces' (outlines traced from sampled
  fields per animated frame) menu-card 1.4 -> 0.4, menu-held 0.9 -> 0.4
  on every tier. Device (tool/ios_reference/perf/2026-10-05-q-base ->
  -q-i1, 5 runs, median, p95 build ms): menu liquid 2.34 -> 1.87,
  frosted 3.41 -> 1.91, flat 4.03 -> 4.03 (its p95 frames are the
  blurred trace at radii >= 1 pt); raster and every other scene within
  noise. Shots: the resting open menu differs only on the antialiased
  rim - mean 11 (liquid) / 21 (frosted) channel steps on the rim pixels
  that changed at all, a sub-pixel edge move - plus single-pixel maxima
  87 / 107 / 54 (liquid / frosted / flat) at 0.0018 / 0.0034 / 0.0002
  percent of pixels over 15 - within the noise of this shot, which moved
  by 205 at 0.053 percent between two launches of the SAME app (q-i1 vs
  q-i1r); every other resting shot within the run-to-run noise; the
  timed tall-menu close and open shots move between launches, as before.
- GLASS SHADOWS WITHOUT A LAYER (2026-10-05): a glass surface's offset
  shadow (`GlassShadow`, every button / menu / lifted lens on the liquid
  tier) and a fused body's (`MorphGlassBodyShadow`) used a saveLayer
  each, the glass cut out with dstOut - an offscreen pass per shadowed
  surface per frame. Both now clip to an even-odd path of the shadow's
  3-sigma bounds and the shape (deflated half a pixel for a surface, as
  the cut was; the outline itself for a body): no offscreen pass and
  still no shadow under the translucent glass; only the cut's
  antialiasing differs (flutter_test raster vs the layered painters:
  <= 1 channel off the edge, <= 9 on it; test/glass_body_shadow_test.
  dart). Device (2026-10-05-q-i1 -> -q-i2 and the repeat -q-i1r ->
  -q-i2r, liquid, p95 raster ms): controls 3.05 -> 2.57 / 3.02 -> 2.57,
  segmented 2.06 -> 1.66 / 2.07 -> 1.65, sheet 3.35 -> 2.97 / 3.45 ->
  3.00, menu 3.30 -> 3.05 / 3.38 -> 3.00, tab bar 2.80 -> 2.79 / 2.92 ->
  2.73, home scroll ~ -0.1; frosted and flat (no glass shadow) within
  noise. Shots: resting glass with shadows (controls, menu, segmented,
  tab bar) max 10 channel steps, no pixel over 15; the held slider
  thumb's rim moves by up to 236 between launches of the SAME build, so
  its 174 is noise.
- FAKE GLASS (the fake tier; also tests, the first frames, devices
  without Flutter GPU) draws the fused outline too: `GlassField.outline`
  - or, for a plain union without a field, the outline itself
  (`LiquidGlassLayer.outlineOf`) - reaches ConsolidatedFakeGlassLayer,
  which clips its backdrop and surfaces to it. Each region of the body
  draws the face of its LARGEST shape only (the others are clipped to
  outside it, a tie to the later one), so a menu's shrunken button
  leaves no rim inside the menu; the neck is the outline clipped outside
  every shape in turn (no path boolean - Skia's path ops refused an
  outline running along its capsules - and no even-odd union, which
  tinted shape overlaps twice). An outline built from a path alone
  (public `MorphGlassOutline(path)`) has no field for liquid to shade, so
  it is fake glass on both tiers.
- FAKE FACE: the face transfer `Y + lift * Y * (1 - Y)` becomes a line in
  the color matrix; it is exact at black and least-squares over (0, 1]
  (white stays exact through the clamp). The unanchored least-squares
  line lifted black by lift / 6 and made dark fake glass 15 - 24 channel
  steps brighter than liquid over the gallery's black page.

## Adaptive policy (`MorphAdaptiveGlass`, glass_tier.dart)

Installs the renderer at ONE tier for the session (owner decision
2026-10-05: the glass never switches tier while the app runs). An
explicit `tier` wins; else `MorphAdaptiveGlass.tierFor(deviceClass,
best)`, a pure function, decides once the liquid capability resolves
(`MorphGlassRenderer.precache` before `runApp` makes that the first
frame; without it the first frames draw the fake glass fallback):

- `best` below liquid (no Flutter GPU, the web, a renderer pinned lower)
  -> `best`.
- `MorphGlassDeviceClass.capable` (Vulkan / Metal, Apple A13+) and
  `unknown` -> liquid.
- `gles` (Flutter GPU `doesSupportFramebufferRenderMipmap` false - only
  the GLES backend lacks it) and `appleBeforeA13` (iOS and
  `supportsTextureCompression(astcHdr)` false - Metal reports HDR ASTC
  from GPU family Apple 6 = A13 on) -> `MorphAdaptiveGlass.cheapTier`,
  ONE constant, flat (fake glass measured and rejected for it, below).

Why flat and not frosted as the cheap tier: Pixel 6a forced to GLES
(pixel6a-gles, 60 Hz, medians of 5 runs, frames over the 16.7 ms budget
per scene home / segmented / tab bar / controls / menu / sheet): liquid
11 / 11 / 82 / 64 / 69 / 47, frosted 23 / 17 / 96 / 132 / 59 / 56, flat
6 / 0 / 2 / 0 / 20 / 0; on Vulkan liquid is 1 / 0 / 13 / 13 / 22 / 5.
Frosted blurs every glass surface and costs MORE than liquid on GLES and
on four of six scenes on the iPhone 16 Pro (controls 3.65 vs 2.88,
sheet 3.92 vs 3.21, segmented 2.29 vs 2.00, home scroll 2.51 vs 2.14
raster p95 ms). The pre-A13 branch is unmeasured (no such device).
Fake glass is no cheaper there either (next section): its cost on GLES
is the backdrop read itself, so flat stays the cheap tier.

The probe (glass_device_native.dart) reads `gpu.gpuContext` only after
the liquid capability is true (reading it earlier blocks the UI thread
on Android). `supportsTextureFormat` is useless as a probe (true for
every uncompressed format). Removed with this decision: the frame-timing
governor (`MorphGlassTierGovernor`, `MorphGlassTierPolicy`,
`onTierChanged`); on the Pixel 6a (Vulkan, auto) it flipped flat /
liquid six times in one audit (pixel6a-base, pixel6a-head
`tier_changes`) on the menu's bursts, which miss the budget on flat too
(10 frames). Pinned in test/glass_renderer_test.dart ('the adaptive
tier'). Device check
(pixel6a-devclass, 2026-10-05, GALLERY_GLASS=auto, one run): Vulkan ->
`capable`, liquid for the whole audit; the same APK forced to GLES
(manifest `ImpellerBackend=opengles`) -> `gles`, flat from the first
glass frame. The measured cadence (10th percentile of vsync-start
intervals) read 16.66 / 16.64 ms, matching the 60 Hz the display
reports, so the Pixel gives no evidence against `MorphClock`'s
refresh-rate-based sub-clock rate; it stays as is.

## Fake tier vs liquid, frosted, flat (2026-10-05, perf/2026-10-05-fake-*)

Glass audit, 5 timed runs per scene, medians, profile, dark. Builds:
exp/fake-tier 36aab65 (`fake3` in the result files: the fake tier with
the face line and the fused-body fixes; `fake` = 99e266b before them,
iPhone only) - liquid / frosted / flat from the same commit. Pixel 6a
(60 Hz) on Vulkan and forced to GLES (manifest
`ImpellerBackend=opengles`, not committed), iPhone 16 Pro (120 Hz).
Scenes controls / home scroll / menu / segmented / sheet / tab bar.

Raster p95 ms and frames over budget:

| device | fake | liquid | frosted | flat |
|---|---|---|---|---|
| Pixel GLES p95 | 20.6 / 16.3 / 33.1 / 15.2 / 27.9 / 19.3 | 22.4 / 15.9 / 28.8 / 14.5 / 21.4 / 20.0 | 20.4 / 17.5 / 25.6 / 16.4 / 22.8 / 19.2 | 9.0 / 14.7 / 20.2 / 9.6 / 10.7 / 13.9 |
| Pixel GLES missed | 112 / 20 / 84 / 7 / 76 / 56 | 83 / 14 / 75 / 6 / 54 / 73 | 154 / 29 / 74 / 17 / 83 / 115 | 0 / 5 / 20 / 0 / 1 / 3 |
| Pixel Vulkan p95 | 15.3 / 11.8 / 19.6 / 12.2 / 16.9 / 14.6 | 16.1 / 11.2 / 18.6 / 10.6 / 16.2 / 14.4 | 13.8 / 11.5 / 17.4 / 11.4 / 13.1 / 16.1 | 6.6 / 10.3 / 13.1 / 6.7 / 7.9 / 10.1 |
| Pixel Vulkan missed | 9 / 2 / 22 / 0 / 15 / 7 | 19 / 2 / 26 / 0 / 12 / 17 | 1 / 2 / 20 / 1 / 1 / 15 | 0 / 1 / 14 / 0 / 1 / 0 |
| iPhone p95 | 3.71 / 2.40 / 3.69 / 2.03 / 3.25 / 3.22 | 2.58 / 2.25 / 3.17 / 1.61 / 2.92 / 2.75 | 3.05 / 2.61 / 3.38 / 2.13 / 2.72 / 2.70 | 0.79 / 2.04 / 1.76 / 0.80 / 1.00 / 1.64 |

Build p95 (UI thread) of fake is liquid's minus the field work (iPhone
2.27 / 1.41 / 1.84 / 1.25 / 1.35 / 1.34 vs liquid 2.51 / 1.41 / 2.05 /
1.36 / 1.50 / 1.58). Reading: fake glass costs about what liquid costs
on every device - more raster on the iPhone, as much on the Pixel - so
it is NOT a cheap tier; on GLES only flat holds the budget.

Distance to liquid (shotdiff.py, 18 audit shots, median over shots of
the mean channel difference / percent of pixels over 15):

| device | fake | frosted | flat |
|---|---|---|---|
| iPhone 16 Pro | 0.64 / 0.44 | 1.73 / 4.40 | 1.39 / 1.94 |
| Pixel GLES | 0.67 / 0.86 | 1.73 / 4.14 | 1.28 / 1.88 |
| Pixel Vulkan | 2.78 / 9.22 | 3.81 / 12.86 | 3.48 / 9.44 |

Fake is the closest look on every shot but the sheet's mean (7.44 vs
flat 5.57 on the iPhone; its over-15 share 0.49 vs 5.79 percent).
Before the face line and fused-body fixes it was the farthest on the
menus (iPhone menu-open mean 9.25, 38.9 percent over 15). The Vulkan
row is inflated for every tier by the liquid tier's clip-sized gray box
on that backend (pixel6a-attrib), so the GLES row is the Pixel's
reference. Contact sheets (liquid | fake | frosted | flat):
`2026-10-05-fake-*/contact/<shot>.jpg`; `contact.py` makes them.

## Liquid tier layering (the former gallery painter, optics unchanged)

- Body surfaces in one layer reading the nearest BackdropGroup's shared
  copy (root group in GalleryApp, own groups for the glass page's scene
  and card); bar and menu kinds take their own copy on the liquid and
  fake tiers, through buildLayer, buildBody and buildSurface alike.
  The navigation bar and toolbar (button-kind capsules) share one group
  of their own per screen (`MorphChromeBackdrop`, keyed by the stack's
  or scaffold's `MorphChromeBackdropScope`; a bar alone gets its own),
  as do the search tab bar and a sheet's content. A bar's capsules fuse
  at the bar's container spacing (12: groups 12 apart stay separate).
- A resting lens/knob/thumb is an opaque platter; lifted it is clear glass
  in its own INDEPENDENT layer (own backdrop copy) above body + content.
  The lens shows the content once more inside its outline, each item
  scaled about ITS OWN slot (`buildLayer(contentSlots:)`, the segment /
  tab boxes) and clipped to slot AND lens (scaling about the lens center
  slid the label with a dragged lens - the owner's Day/Night report), cut
  out of the plane; the copy sits BELOW the lens glass (the renderer never
  enlarges its backdrop).
- GLASS ON GLASS (the tab bar lens "not liquid"): the copy used to paint
  OVER the lens, the lens wore the regular wash + a white tint (a milky
  blob) and bent by the button's 60 against a bevel of 20 (ratio 3: the
  rim mirrored the labels). Now the lens is clear, bends by UIKit's
  displacement x 2 (18 lifted) with dispersion -0.25, and refracts the bar
  glass + the magnified labels beneath it.
- Bevel: quarter circle, bevel min(20, halfMinor / 2), amount 18; it pulls
  the backdrop INWARD near the rim while UIKit's minification is outward.
- RIM-WEIGHTED SHRINK: UIKit minifies by DEPTH BELOW THE RIM, not by
  distance from the center - a capsule shrinks across its straight part
  and radially about the centers of its round ends (the segmented track's
  end moves 6.5 px at depth 35 px where the top edge moves 8.5 at 26.5:
  linear in depth, zero on the center line; the switch knob agrees, 7.5
  vs 7.5 px). LOCAL PATCH `backdropShrinkRim` (0..1, default 0 = upstream
  bit for bit; its own commit, see VENDORED) shrinks about the nearest
  point of the long center line, rim x (long - short side) long;
  `liftedOptics` returns `rim`: segmented and knob 1 (`lensShrinkRim`), tab
  bar 0.75 (`tabBarShrinkRim`: the swollen bar's end inside an end-item
  lens moves 11 px on the reference, 8 at 1, 20 at 0). Device audit:
  segmented end 0.960 vs 0.962 (was 0.800), knob 0.869 vs 0.870 (was
  0.766), tab bar 10 vs 11 px (was 19); every other audit shot
  pixel-identical or at run-to-run noise.
- The content copy is pre-grown against the same warp by `backdropScale` =
  1 + (1 / (1 - shrink) - 1) x visibility in THREE STRIPS cut at the
  line's ends (`_Magnified`: radial about each end beyond it, across the
  line beside it - each strip exact), keys 'start' / 'band' / 'end'; the
  renderer fades the shrink with the glass's visibility. The stillness
  tests in test/glass_renderer_test.dart measure the label AS SEEN THROUGH
  that warp (shrink, rim and visibility read from the LiquidGlassLayer /
  LiquidGlass they render with, the text read in the strip holding its
  center).

## Backdrop groups (2026-10-05, Flutter 3.47.2, engine a804b26164)

- ENGINE: a keyed backdrop filter whose key has more than one use in the
  frame does the readback ONCE (impeller/display_list/canvas.cc
  SaveLayer: the first use calls FlipBackdrop and keeps the texture in
  `BackdropData::texture_slot`, every later use filters that slot). On
  Metal `EntityPassTarget::Flip` returns the CURRENT resolve texture
  (`supports_read_from_resolve_`), which every later pass resolves into
  again, so a later member reads the pass texture as it stood at the
  LAST backdrop flip of any filter before it - not at the first member,
  not at itself. Glass in one group therefore misses everything painted
  since the previous backdrop flip.
- DEVICE REPRO (example/integration_test/backdrop_group_test.dart,
  liquid, dark): a resting body glass button painted first, red/green
  stripes after it under the navigation bar and toolbar, the bars over
  a hard scroll edge effect. Variants: button in the root group, no
  button, button in its own group. Before the fix the root-group
  variant's navigation bar capsule showed the stripes RAW - sharp, no
  edge effect - (max channel diff 58 to the no-button scene inside the
  capsule; the toolbar matched, its last flip came after the stripes);
  no button and own group were identical (diff 0). After the fix all
  three are identical in both bars (diff 0). UIKit's glass always reads
  what lies under it, so the no-button scene is the reference; no
  native probe was needed.
- The same law bit a sheet's content: its glass buttons shared the root
  group with the page's buttons. Once the sheet surface read its own
  copy (a flip just before the sheet paints), they showed the page
  through the sheet; the sheet's content now has its own group.
- FIX (cheapest correct grouping): bar / menu kinds never take the
  shared key on either tier (buildSurface used to pass it on liquid,
  the frosted tier passed it for everything); the navigation bar and
  toolbar share one chrome key per screen (`MorphChromeBackdropScope`
  above the stack's or scaffold's bars; a bar alone keys itself), the
  search tab bar and a sheet's content get a group of their own. Cost:
  a page whose body holds no glass pays nothing (the root key then has
  no member); a page with resting body glass pays one capture more for
  its bars. Counts (test/perf_counts_test.dart, pinned): captures
  unchanged except tab-bar/frosted 1 -> 2 (the bar copy); builds
  nav-scroll +0.1 per frame (the group's element), sheet/frosted
  9.9 -> 10.0. Device audit (5 runs, median, 2026-10-05-bdg-base at
  aa3105a vs 2026-10-05-bdg-fix, p95 build / raster ms): liquid within
  noise on every scene (controls 2.46/2.98 -> 2.34/3.01, sheet
  1.33/3.19 -> 1.34/3.32, menu 2.13/3.08 -> 2.09/3.13); frosted menu
  raster 2.40 -> 2.79 (the card's own copy), sheet 3.93 -> 2.63,
  segmented 2.55 -> 2.11, the rest within noise. Shots that changed
  beyond noise: sheet-medium (both tiers: the floating sheet now reads
  the page through it, as the UIKit reference does - it used to read a
  dark copy), frosted tab bar (the bar now tinted by the rows under it,
  as on liquid), frosted tall menu (the card now blurs the button under
  it); everything else within the run-to-run noise above.

- OVERLAYS AND LENSES (2026-10-05, example/integration_test/
  backdrop_overlay_test.dart, liquid and frosted, dark): a resting glass
  button in the root group painted first, red/green stripes, then the
  scene; variants shared / none (no first button) / own (the scene in a
  group of its own); max channel difference to `none` inside the scene,
  runs tool/ios_reference/perf/2026-10-05-overlay-groups/before3 and
  after (screenshots not committed, diff.py there):
  - context menu hero (glass button as hero, menu open): shared 72
    (liquid) / 46 (frosted) - the lifted hero showed the stale dark copy
    instead of the dimmed stripes; wrapping the SOURCE in a group did not
    help (the open hero is a copy in the overlay). Fixed: the hero copy
    and both satellites each sit in a `MorphChromeBackdrop`; after: 0 / 0.
  - lifted slider thumb: liquid 0 (lenses read their own copy); frosted
    226 - the lens showed no stripes and no track. Fixed: on the frosted
    tier lens / knob / thumb never take the shared key; after: 0.
    Cost: perf_counts controls-page/frosted captures 1 -> 2. Device
    audit (tool/ios_reference/perf/2026-10-05-ovg-base, -base2 at 8c15be5
    vs -ovg-fix, -fix2; 5 timed runs each, p95 build / raster ms): frosted
    controls 1.70/3.83, 1.72/3.80 -> 1.76/3.26, 1.79/2.96; frosted menu
    3.27/2.75, 3.35/2.80 -> 3.56/3.62, 3.26/3.26 (+0.5 - 0.9 raster);
    every other frosted scene and every liquid scene within +-0.2.
  - alert: 0 - 10 (a one-pixel rim row that flips between runs, timing):
    its platter is menu kind and reads its own copy; alerts host no
    other glass. No change.
  - glass button inside a morph dialog's content: liquid 7, frosted 18
    on 99 px (no stale backdrop visible; dialogs paint an opaque
    surface). No change.
  - STILL WRONG, not changed (it is the root group's design, owner
    decision): a SECOND resting body glass over content painted after
    the first one (`body` scene) - 72 liquid / 43 frosted, the button
    shows the dark page instead of the stripes under it. Correct
    grouping costs a capture per body glass control.

- SECOND RESTING BODY GLASS (the `body` scene above) - OPTIONS, NOT
  CHANGED (2026-10-05). Wanted: a body glass surface gets a group of its
  own only when content is painted between it and the previous member of
  the root group, so ordinary screens pay nothing. Not reliably
  detectable: the member's key is fixed when its layer is painted, and
  what lies between two members in paint order is only known as
  PictureLayers whose bounds are the whole repaint boundary's (a ui.Picture
  carries no drawn bounds), so any label between two controls on a page
  reads as "content under the later one". Options and costs:
  (A) a group per resting body glass control (always correct): +1
  full-screen readback per such control while anything animates;
  perf_counts captures per frame controls-page liquid 5.5 -> 7.5, frosted
  2.0 -> 4.0, nav-scroll +1.0; device (prototype at ce95277 vs
  2026-10-05-q-i2, 5 runs, p95 raster ms) liquid controls 2.57 -> 3.49,
  frosted controls 3.47 -> 3.97, frosted sheet 2.80 -> 4.37, frosted
  segmented / tab bar +0.4, the other liquid scenes within noise
  (raster p95 moves up to +-0.5 between runs of unchanged code).
  (B) composite-time detection (a root layer re-keying a member after
  any picture painted since the previous one): no spatial test is
  possible, so it fires on nearly every page (cost close to A) plus a
  layer walk and retained-layer churn per frame, and still misses
  content painted inside an earlier member's own subtree.
  (C) opt-in: the app wraps a section painted over earlier glass in its
  own `BackdropGroup` - free by default, correct where the app asks.
  (D) status quo (72 / 43 max channel in the repro).
  DECIDED (owner, 2026-10-05): C. The package groups nothing on its own;
  the recipe lives in MorphAdaptiveGlass's dartdoc (pointed to from
  MorphGlassRenderer's): a section whose glass paints after other content
  (a card over a list, a second control row over content painted after
  the first) goes in `BackdropGroup(child: section)`, which gives it a
  copy taken where it paints, for one more full-screen readback per
  frame while anything in it moves. A plain BackdropGroup (a fresh key)
  is the whole API - a helper would only rename it.
  test/backdrop_section_test.dart pins it: the second button of a page
  reads the page's key, wrapped it reads its own.
- SCROLL EDGE EFFECT IN THE BARS' GROUP - MEASURED, REJECTED (2026-10-05,
  audit PF9 / research G14b): the navigation bar's edge effect taking the
  stack's chrome key (`MorphChromeBackdropScope`) would save its own
  full-screen readback, but as the group's first member it takes the copy
  BEFORE it draws, so the bar capsules above it read the page without the
  edge effect's blur and fade. Device (example/integration_test/
  edge_effect_group_test.dart: a MorphNavigationStack over red / green /
  white / black stripes scrolled under the bars, dark, two shots per
  tier; build at b0f79b1 vs the same plus the key): the navigation bar
  capsules change - the unfaded stripes and a sharp band edge show
  through the glass - max channel difference 33 (liquid, rest) / 49
  (liquid, mid-scroll) / 39 / 35 (frosted), 1.05 / 0.51 / 1.05 / 0.57
  percent of the screen over 15, all inside the navigation bar's
  capsules (frosted: also up to 48 toolbar rim pixels at <= 21, the
  toolbar now reading the edge effect's flip). Native glass samples the blurred band, so
  this is a visible fidelity loss: not adopted, the edge effect keeps its
  own copy.

## The surfaces channel (2026-10-05, glass_channel.dart)

- Every painter call of a control goes through a `MorphGlassHost`
  (layer / surface / fill / body). With `MorphGlassRenderer` itself the
  host builds its tree once per STRUCTURE (`structureOf`: tier, surface
  roles and counts, visible, glows, platters, lifted lenses, fused
  outline kind) over a `MorphGlassChannel`; every frame that keeps the
  structure is pushed and its render objects follow through their own
  setters (`GlassLiveBinding`): `MorphLiveStack` / `MorphLivePositioned`
  (the `Positioned.fromRect` boxes), live ClipRRect / ClipRSuperellipse
  radii, live clippers keyed on what they clip, live BackdropFilter
  filters, DecoratedBox decorations, ColoredBox colors, Opacity, painters
  repainting on a key of what they read, and in the renderer
  `LiquidGlass.live` / `LiquidGlassLayer.live` (RenderLiquidGlass, the
  glass shadow, the shape clip, RenderFakeGlass, the layers; VENDORED).
  A host its parent rebuilds (menu face and cards, bar capsules, alert,
  date picker, sheet, search bodies, stepper) pushes from `update` without
  building; a frames-driven host (segmented, tab bar, switch, slider,
  glass button) builds once per frame and returns the same tree. Other
  painters are called every frame as before.
- SAME PIXELS: test/glass_frames_test.dart records every perf-counts
  scene on every tier (63 scene/tiers, every third frame) with the
  channel and with `debugMorphGlassRebuildEveryFrame`, and compares them
  bit for bit; the 2874 frame hashes of the channel are also identical to
  the parent commit's (flutter_test draws the liquid tier through the fake
  layer). Device audit shots (Impeller, the real liquid path) against the
  parent commit: every resting and held shot within the run-to-run noise
  (<= 90 max channel at <= 0.02 percent over 15); the tall menu's open and
  close-0/1 shots moved one device pixel down as a whole (text included,
  flat tier too) - the documented launch-to-launch flip of that shot.
- Work per animated frame, perf_counts (component builds; paints and
  pictures unchanged in every scene): liquid segmented 11.6 -> 1.3, lens
  held 15.7 -> 1.5, tab bar 23.7 -> 2.6, switch 9.8 -> 1.4, slider 17.4 ->
  8.2, controls page 20.1 -> 10.9, menu card 41.6 -> 23.7, sheet 18.9 ->
  9.1, density wave 16 199 -> 31; frosted segmented 5.0 -> 1.1, tab bar
  7.7 -> 2.2; flat segmented 4.0 -> 1.1, tab bar 5.8 -> 2.1. What builds
  now is the control's own content and the hosts.
- Device (iPhone 16 Pro, audit.sh, 5 runs, median; base = 7f46071, after
  = 2689305, base2 = the base app again for noise): liquid build p50
  segmented 1.18 -> 1.13, tab bar 1.20 -> 1.12, controls 1.45 -> 1.37,
  menu 1.34 -> 1.36, sheet 1.00 -> 1.00 (base2 within +-0.05 of base);
  build p95 within +-0.08 except liquid menu 2.28 -> 2.66 (its five runs
  spread 1.88-2.85 before and 1.97-2.75 after); raster unchanged; frosted
  and flat within noise. Where the UI thread goes
  (example/integration_test/glass_phases_test.dart, FlutterTimeline
  blocks per composited frame, liquid, base -> after): segmented BUILD
  0.185 -> 0.120, LAYOUT 0.455 -> 0.329, PAINT 1.117 -> 1.064; tab bar
  BUILD 0.251 -> 0.179, PAINT 1.237 -> 1.271; flat segmented BUILD 0.081
  -> 0.046, PAINT 0.32. The liquid tier's UI cost per moving control is
  PAINT (the renderer's paint-time work: geometry matte encoding,
  filter rebuilds, composition polls, about 1.1 ms for one segmented
  control), not widget builds: the channel took a third of BUILD and a
  quarter of LAYOUT, 0.1 - 0.2 ms per moving control on this phone. The
  next UI-thread lever on liquid is the layer's paint.

## Glass density (2026-10-05, glass_density_test.dart)

N standalone `MorphGlassButton`s (80 x 44, one plane, a 4-column grid)
over a scrolling list of coloured rows, dark, 5 runs, median of the runs'
percentiles over active frames. `-rest`: the buttons rest while the page
scrolls under them; `-wave`: finger i lands 2 frames after finger i - 1
and lifts 25 frames later (at most ~13 pressed at once), the page rests.
Build / raster p95 ms, base -> after the channel:

| tier | variant | N=1 | N=4 | N=8 | N=16 | N=32 |
|---|---|---|---|---|---|---|
| liquid | rest | 0.52/1.04 -> 0.53/0.99 | 0.62/1.30 -> 0.60/1.32 | 0.76/1.89 -> 0.79/1.86 | 1.20/2.96 -> 1.24/2.92 | 1.63/4.05 -> 1.58/3.95 |
| liquid | wave | 0.68/1.24 -> 0.63/1.31 | 1.28/2.23 -> 1.20/2.22 | 2.24/3.43 -> 2.12/3.18 | 2.86/3.81 -> 2.72/3.81 | 1.10/2.04 -> 1.07/1.99 |
| frosted | rest | 0.45/1.21 -> 0.44/1.19 | 0.49/1.30 -> 0.47/1.25 | 0.49/1.46 -> 0.49/1.42 | 0.52/1.83 -> 0.52/1.71 | 0.57/2.42 -> 0.57/2.31 |
| frosted | wave | 0.57/1.69 -> 0.52/1.57 | 0.96/1.92 -> 0.94/2.27 | 1.48/2.60 -> 1.50/2.39 | 2.73/3.24 -> 2.61/3.36 | 3.07/3.56 -> 3.26/3.71 |
| flat | rest | 0.44/0.63 -> 0.42/0.65 | 0.44/0.69 -> 0.44/0.68 | 0.45/0.70 -> 0.45/0.71 | 0.45/0.79 -> 0.46/0.79 | 0.50/0.91 -> 0.50/0.93 |
| flat | wave | 0.45/0.87 -> 0.44/0.87 | 0.66/1.24 -> 0.66/1.43 | 0.99/1.70 -> 1.00/1.73 | 1.50/2.64 -> 1.51/2.60 | 2.44/3.51 -> 2.52/3.45 |

- Scene layers (the profile build's layer tree, counting only backdrop
  filters the scene holds - a glass layer's opacity probe leaves it
  unless an ancestor fades): liquid N buttons = 1 backdrop capture (the
  root group) and N filter passes, resting or pressed; frosted the same;
  flat none.
- Kill criterion K1 (tool/audit/unified-canvas-fable.md section 8): at
  rest while the page scrolls, liquid raster p95 N=16 is 1.6 ms above
  N=4 (2.92 vs 1.32; ~0.13 ms per resting button, all of it filter
  passes - the capture is shared): K1 does NOT fire, the per-control
  passes are a real cost on liquid, so the container prototype (design
  B) is worth measuring. Frosted (+0.46) and flat (+0.11) stay within
  1 ms. GPU frame time (Metal System Trace) was not recorded.
- Open: liquid N=32 wave measures cheaper than N=8 and N=16 on both
  builds (build p50 0.8 vs 1.6 / 1.9 ms), frosted N=32 barely above N=16,
  flat grows as expected - some liquid buttons probably stop animating
  at 32 layers on the device (no shots were taken in that window); look
  before trusting the N=32 wave column.

## Glass container (2026-10-05, glass_container.dart)

`MorphGlassContainer` is UIKit's `UIGlassContainerEffect` for glass that
does not fuse (fable alternative B, astra step 1): one `LiquidGlassLayer`
at the container's place in paint order, and every glass host below it
whose glass would look the same registers its shapes with that layer
instead of building a layer of its own - one geometry pass and one
backdrop filter for the lot. Opt-in; the package groups nothing on its
own (the BACKDROP GROUPS decision stands). Contract: everything inside the
container is content above its glass.

- A host joins (`MorphGlassContainerLink.admit`, decided in the host's
  structure, so a change rebuilds its tree once) only when: the painter is
  `MorphGlassRenderer` itself on liquid or fake; the control declares
  itself still (`MorphGlassLayer.still`, the glass button's
  `MorphGlassButtonMotion.isSettled`: no lift, lean, glow or scale in
  motion); its glass is separate body glass (no fused body, no floating
  lens, no bar or menu kind) with `lift` 0, the container's resting-button
  settings and the tint of the glass already in the container (one
  appearance: no material map, the same final shader); nothing between
  the container and the host fades, clips, filters or scrolls
  (`morphGlassContainerReaches`: Opacity, AnimatedOpacity, Offstage,
  Visibility, any Clip*, ShaderMask, BackdropFilter, ImageFiltered,
  ColorFiltered, a viewport, a follower layer; a MorphTag's own opacity is
  seen through while the tag shows, and a tag hiding for its flight sends
  the source back into its own layer - see "Backdrop filter attribution"); and the layer
  holds at most 32 shapes. A pressed button leaves (its rim lights up, a
  per-layer setting) and comes back when it has settled.
- Why "still": a member that moves relative to the container makes the
  container re-encode its matte every frame, while its own layer would
  ride the transform. Taking members back at lift 0 (the scale spring's
  undershoot clamps lift to 0 while the button still moves) cost
  COMPOSITING 0.66 -> 1.22 ms per frame on the n1 wave; with `still` the
  phases match the status quo (BUILD / LAYOUT / PAINT / COMPOSITING n4
  wave 0.65/1.16/3.70/1.08 -> 0.69/1.27/3.58/1.11 ms).
- MAX_SHAPES 16 -> 32 in the renderer (VENDORED). Shots of the status quo
  with and without the change are identical (Pixel 6a, 0 difference).
- Device (Pixel 6a, Vulkan, 60 Hz, profile, glass_density_test.dart with
  `DENSITY_CONTAINER`, 5 runs each, median of the runs' percentiles over
  active frames; two interleaved pairs status quo / container after
  cooling to 36 C, GPU clock median 251 MHz in all four,
  perf/2026-10-05-pixel6a-container-final; raster p50 / p95 ms, the
  pairs' mean):

| scene | status quo | container | raster p50 | over budget |
|---|---|---|---|---|
| n1 rest | 5.96 / 7.42 | 5.77 / 7.32 | -3% | 0 -> 0 |
| n4 rest | 7.83 / 9.43 | 6.42 / 7.91 | -18% (-1.41 ms), p95 -16% | 0 -> 0 |
| n8 rest | 9.05 / 11.63 | 7.08 / 8.64 | -22% (-1.97 ms), p95 -26% | 0 -> 0 |
| n16 rest | 10.43 / 13.53 | 8.07 / 9.96 | -23%, p95 -26% | 1 -> 0 |
| n32 rest | 11.48 / 14.85 | 9.17 / 11.62 | -20%, p95 -22% | 6 -> 0 |
| n1 / n4 / n8 wave | 7.06 / 8.85 / 10.67 | 6.86 / 8.94 / 10.75 | within pair spread | 0 -> 0 |

  Build p50 at rest drops too (n32 2.27 -> 1.54 ms: one layer to poll).
  Waves: build and raster p50 / p95 move by -0.29 to +0.25 ms on N = 1 -
  8, inside the spread between the two status quo runs (up to 0.45 ms);
  all pressed buttons are out of the container, so the wave is the status
  quo by construction. Scene layers: N resting buttons are 1 backdrop
  filter instead of N; 96 stress buttons are 65 (32 joined).
- Gallery (glass_audit_test.dart, the controls page's button row, the
  glass page's buttons and the sheets page's button column in containers,
  one run of 5 each, perf/2026-10-05-pixel6a-container gamain / gaexp2):
  raster p50 controls 9.46 -> 9.15, sheet 11.13 -> 10.47 (-3 and -6
  percent: five resting buttons are a small part of those frames), every
  other scene within its run noise.
- Pixels: on whole device pixels the container draws what each button's
  own layer draws (n8-aligned, max channel 1). Off the pixel grid a
  standalone layer's matte is rasterized on device pixels anchored at its
  own origin and sampled nearest, so its rim reads the shape up to half a
  device pixel off; the container used to rasterize every member on its
  own grid instead: resting shots differed by up to 45 - 53 on rim pixels
  (0.01 - 0.36 percent of the screen over 15), the audit's
  controls-resting and sheet-medium shots 76 / 70. Fixed 2026-10-06 (see
  "Container raster phase" below): the container now matches. flutter_test: hidden, half faded and
  clipped buttons in a container render exactly as without it
  (test/glass_container_test.dart).
- Kill criteria (task gates): raster >= 15 percent and >= 0.3 ms on two
  intended workloads - resting button clusters over moving content, n4
  and n8 - met; no regression > 0.2 ms on N = 1 - 8 beyond run noise; the
  gallery scenes gain less than 15 percent. Fable K2 (>= 30 percent GPU
  time at N = 16) is not met by raster (-23 / -26 percent); GPU time was
  not recorded.

### Container raster phase (2026-10-06, raster_phase.dart)

- The joined host's shapes sit under a `GlassRasterAnchor` (where the
  host's own layer would sit). When the container's layer encodes its
  matte it shifts each anchored shape by `glassRasterPhase(container) -
  glassRasterPhase(member)` device pixels (`0.5 - frac(0.5 - origin)`:
  where a nearest-sampled matte reads a pixel, relative to its center), so
  every member's rim samples the same SDF points as in its own layer. Only
  translations count (a scaled or rotated pass or member gets no shift);
  the matte grows half a device pixel when anything shifts, the geometry
  pass's contour extent does not (growing it too changed every rim by 9 -
  11). The pass phase is remembered: a paint at another sub-pixel phase
  encodes again, and a shifted matte is never reused by translation. Pure
  compositor motion of the container (a scroll, a route transition) moves
  the phase without a paint: until the next paint the members can be off
  by the old difference. Ties (a grid within 1/64 device pixel of the
  pixel centers) and scaled containers: see "Raster ties, scaled
  containers" below.
- Device (density shots, buttons 0.17 pt off the grid with DENSITY_SHIFT,
  resting / one held; status quo = own layers, max channel / share over
  15): Pixel 6a (2.625x) container before the fix 48 / 0.04 - 0.10
  percent, after 1 - 2 / 0 (n8-aligned noise 1); iPhone 16 Pro (3x)
  before 72 - 73 / 0.08 - 0.39 percent, after 2 - 3 / 0 (aligned noise
  2). Held shots (button 0 pressed, out of the container) 21 - 53 on <= 9
  pixels at neighbouring rims, before and after alike: the pressed button
  takes its own copy, a backdrop-order effect, not the raster phase.
  Shots in /tmp (not committed), shotdiff.py. Gallery audit on the Pixel
  (the controls row, glass page and sheet buttons in their containers
  against a build whose MorphGlassContainer adds nothing): controls-resting
  max 54 before, 1 after; sheet-medium 6 both
  (perf/2026-10-06-pixel6a-batch-gallery; one uncooled run each, its
  timings are not a measurement).

- Analytic geometry (MORPH_ANALYTIC_GEOMETRY, 2026-10-09): an analytic
  frame evaluates every shape where it is, with no matte grid, so the
  container applies no raster-phase shift or bias and there is nothing to
  tie. A member then matches its own layer NEAR, not bit for bit: host
  (example/test/raster_phase_host_test.dart, 3x, origins 60.49 - 60.51
  device px) max channel step 1 at 60.49, 60.499, 60.4999 and 60.51, 0 at
  60.5 - 1e-9 through 60.5001; the matte path stays 0 at every origin.

### Package stages (2026-10-06, `MorphGlassStage`)

A stage is a glass container a package widget owns: it is open only while
nothing the widget does to its members (a fade, a scale, a blur) changes
how their glass would look in layers of their own, and closes in the same
frame otherwise (an InheritedWidget flag; members rebuild into their own
layers). Its fades go through `MorphGlassStageFade`, an Opacity the reach
check sees through - legal only because the stage closes whenever one is
below 1. A host under a `BackdropGroup` with another key than the
container's never joins (a bar floats in its own group; it would read the
page's copy in a container).

- Signals: the search capsule tells `still` on a notifier that flips only
  when the field settles or starts to move (perf counts search-press:
  paints +0.5 - 0.6 per frame on every tier, two repaints per press); a
  bar's capsule host is still while its motion, presses, hold and menu
  rest and no drift runs.
- MorphSearchToolbar (KEPT): open at rest (no search, progress 0), the
  field and its side buttons in one layer. Density audit DENSITY_SEARCH
  (one leading, one trailing button, rows scrolling under), same binary
  with DENSITY_STAGES_OFF as the reference, ABAB launches, 5 runs each,
  raster p50 / p95 ms: Pixel 6a (perf/2026-10-06-pixel6a-batch-search,
  cooled to 38 C) 6.09 / 7.58, 5.36 / 7.21 -> 4.47 / 6.44, 4.45 / 6.30
  (-1.3 / -1.0 ms), build p95 1.68 -> 1.56; app GPU active time over the
  launch 5.03 / 5.04 -> 4.64 / 4.58 s (-8 percent, gpu.txt). iPhone 16 Pro
  1.10 / 1.31, 1.07 / 1.28 -> 0.94 / 1.17 twice (-0.14 ms, -12 percent).
  Layers 3 filters -> 1, captures 1 both. Shot max 3 (iPhone) / 8 (Pixel,
  built before the contour fix above).
- Navigation stack chrome (fable R3, REJECTED): the navigation bar and
  toolbar capsules in one container in the stack's chrome group (the
  prototype dropped the edge effect in both arms - in the container it
  would paint over the capsules). Gallery home with a three-button
  toolbar, home-scroll, ABAB (perf/2026-10-06-pixel6a-batch-r3): raster
  p50 / p95 7.00 / 8.80 -> 6.60 / 8.40 (-0.4), build p95 4.98 -> 6.41
  (+1.4), GPU active 7.43 -> 9.17 s per launch (+24 percent: a
  screen-high matte and filter clip for two bands). K-R3 fires (GPU rises
  more than raster falls); iPhone 16 Pro raster p50 1.50 both, shots
  equal. Distant chrome stays two layers: each bar already shades all its
  capsules in one.
- Not stages, by construction: a toolbar or navigation bar alone (one
  host for all its capsules already); a sheet's content and every other
  app section (option C: the package cannot see what an app paints
  between two controls - `MorphGlassContainer` stays the explicit tool);
  the search tab bar (its tab bar is bar kind, its search button button
  kind). List sections ARE one since 2026-10-06 (below).
- Checked and left alone (2026-10-06): alerts and action sheets (one menu
  kind surface each; their buttons are fills on it, no glass of their
  own), the date picker (one menu kind overlay), sheets (one menu kind
  surface; their content is app content), the toolbar's and navigation
  bar's groups (each bar shades all its capsules in one host already).
  `MorphNavigationScaffold` gets no `glassContainer` flag: its body is a
  scroll view, and a container above a viewport joins nothing inside it
  (test/glass_inspector_test.dart, "a container around a scroll view");
  the container belongs inside the scroll content, around the cluster.

### List sections (2026-10-06)

`MorphListSection` puts a `MorphGlassStage(sharpOnly: true)` over its card
fill, inside the card clip: the resting glass of every row's accessories
(glass buttons in a trailing or leading slot) is shaded in one layer.
Why nothing between the stage and a member is read (lists.md "Glass in
rows"): resting unfrosted glass samples only inside its own outline, and
the only thing a row paints inside an accessory is its highlight - a row
whose highlight shows wraps its content in a closed
`MorphGlassContainerBarrier` (an InheritedWidget the reach check depends
on, like MorphTagVisibility), so its accessories draw their own layers
for exactly as long; the other rows stay joined. `sharpOnly` closes the
stage while the container's settings frost (`frostControls`): a blur
would read the text and separators around the rim.

- Empty sections: the stage's LiquidGlassLayer is a repaint boundary
  around the card. A section without glass gains the boundary, and its
  rows are no longer re-recorded on every frame its scroll view moves it
  (flutter_test, gallery home, 30 scroll frames: 720 -> 18 paragraph
  paints). Until the renderer fix of the same day an EMPTY
  RenderLiquidGlassLayer repainted itself on every transform change
  (onTransformChanged with no reusable geometry) and so lost exactly
  that; it now returns while no shape is registered (VENDORED).
- Device (Pixel 6a, liquid, profile, energy_android.sh, cooled to 38 C,
  AUDIT_SCENES=home-scroll,list, AUDIT_RUNS=5; variants: nostage = this
  commit with HEAD's list.dart, on = the stage without the renderer fix,
  off = on with AUDIT_STAGES_OFF (every member its own layer, the empty
  stage mounted), on2 = the landed state; launches interleaved, nostage
  6, on2 3, on / off 3 each; medians of launches, mW over the scene
  window, ms; perf/2026-10-06-pixel6a-list-stage-energy):

| scene | variant | power mW | GPU rail mJ | build p50 / p95 | raster p50 / p95 | over budget |
|---|---|---|---|---|---|---|
| list (12 resting buttons, scrolled) | nostage | 1038 | 18775 | 4.8 / 9.9 | 11.8 / 14.6 | 4 |
| | off | 1039 | 18317 | 5.1 / 9.6 | 11.9 / 14.8 | 4 |
| | on | 959 | 16009 | 2.8 / 5.2 | 10.2 / 12.5 | 1 |
| | on2 | 952 (-8.3 %) | 16042 (-15 %) | 2.7 / 5.2 | 10.1 / 12.7 | 1 |
| home-scroll (no glass in the list) | nostage | 845 | 12634 | 3.2 / 6.5 | 8.8 / 11.5 | 2 |
| | on | 863 | 12724 | 3.1 / 6.8 | 8.5 / 11.2 | 2 |
| | on2 | 822 (-2.7 %) | 12087 | 1.6 / 3.8 | 8.7 / 11.4 | 2 |

  Census (AUDIT_CENSUS_OWNERS, one launch each, perf/2026-10-06-pixel6a-
  list-stage-census): list backdrop filters per frame 13.8 -> 3.8
  (12 MorphGlassButton layers -> 2 MorphListSection stages), offscreen
  passes 14.0 -> 4.0, captures 3.8 both; home-scroll filters 1.73 both,
  pictures 6.6 -> 8.1 and layers 36 -> 42 (the boundary's own layers).
  The list scene's build drops with the layers (one structure per
  section instead of a host per button). Shots (shotdiff): list-resting
  and list-row-held on vs nostage max 2, on vs off max 8; the landed
  state against nostage (perf/2026-10-06-pixel6a-list-stage-shots, -shots2) list
  max 8, the home list held mid-scroll max 2 and at rest after a scroll
  0 (nostage against itself: 1 / 220 mid-scroll / 0). Noise <= 19.
- Gates: raster p50 -1.6 ms, p95 -1.9 ms on the intended workload (above
  the 0.3 ms per filter estimate: 10 filters fewer, and the build win);
  energy lower in both scenes; resting and held shots within noise.

## First use: pipeline warm-up (2026-10-05, glass_warm_up.dart)

`MorphGlassRenderer.precache()` (morphPrecacheLiquidGlass), after the
liquid capability resolved, draws every pipeline the first glass frame
needs, offscreen:

- Liquid, only when `MorphAdaptiveGlass.tierFor(deviceClass, liquid)` is
  liquid (not on GLES or pre-A13, which draw flat): two 8 x 8 geometry
  renders through the real `FlutterGpuGeometryRenderer.render` - shapes +
  full material map, then field + tint-only map - which fetch all four
  Flutter GPU pipelines (geometry, field, material gradient, tint
  gradient; RGBA8, one sample, the real descriptors). Flutter GPU creates
  a pipeline at its first draw and waits for it on the UI thread (engine
  lib/gpu/render_pass.cc). Then one `OffsetLayer.toImage` scene at the
  view's pixel ratio: a backdrop picture (even-odd cutout clip,
  mask-blurred rounded rect and superellipse in a bounded saveLayer: the
  glass shadows), and per final shader (plain, material, tint, samplers
  bound to the warm-up mattes) a ClipRectLayer > BackdropFilterLayer with
  the shader alone and composed over a mirror blur at sigma 1 / 2 / 8 /
  14 (each downsample class), plus the bare blurs; one row without and
  one sharing a BackdropKey. A snapshot renders through the same canvas
  into an MSAA + stencil target like the screen, so the filter subpasses
  get the variants the screen uses; every clip is non-empty (a
  clipped-away filter is skipped).
- Frosted (Impeller only, `isShaderFilterSupported`; a no-op under Skia,
  the web and flutter_tester): the same two-row scene with blurs at each
  frost inside an antialiased ClipRRect and an outline ClipPath, with the
  tint fill, highlight gradient and rim stroke over them.
- Failures are swallowed (debug print): the real frame then pays what it
  paid before; the capability and its reason are unchanged. A scene that
  takes over 2 s stops being awaited.

Pixel 6a (Vulkan, 60 Hz, profile, 432e94b vs + bfbc081, one launch each;
pixel6a-warmup-cold = pm clear, -warm = the next launch; home-scroll
first use = runApp to the first timed run, which holds the first glass
frame; worst UI / raster ms):

| build | precache ms cold / warm | cold UI / raster | warm UI / raster | am start TotalTime ms |
|-------|------------------------:|-----------------:|-----------------:|----------------------:|
| liquid before | 3.1 / 3.0 | 102.0 / 73.6 | 131.2 / 48.5 | 457 / 505 |
| liquid after | 367 / 344 | 5.0 / 11.1 | 5.0 / 10.6 | 595 / 540 |
| frosted before | 3.0 / 3.3 | 2.4 / 64.1 | 2.8 / 73.3 | 341 / 375 |
| frosted after | 327 / 433 | 4.8 / 18.9 | 6.9 / 24.6 | 610 / 651 |

Traces (pixel6a-warmup-trace, liquid, cold, TraceSystrace builds):
before, the first app frame's PAINT held the UI thread 125 ms and its
raster 106 ms, 83 ms of it one PipelineVK::Create under a saveLayer.
After, precache holds the UI thread 272 ms (the Flutter GPU pipeline
waits) and the raster thread 173 + 22 ms (the two snapshots, a 67 ms
pipeline creation inside the first), and the first app frame creates no
pipeline (raster 25 ms, 9 of them the first glyph atlas). Later
creations (17 s on: menu and sheet chrome, 1-3 ms each) are unchanged;
frosted's first frame keeps 19-25 ms raster against 11 on liquid, a
residue not traced. The trade: 0.3 - 0.45 s more behind the splash
(launch to first frame +90 to +270 ms), the first glass frame pays
nothing. The Vulkan pipeline disk cache does not remove the cost (warm
before: 131 ms UI).

iPhone 16 Pro (Metal, iOS 27, profile, the same two commits, one launch
each; iphone-warmup-cold = uninstall + install, -warm = the launch after
a full run of the same build; worst UI / raster ms of the first glass
frame as above):

| build | precache ms cold / warm | cold UI / raster | warm UI / raster |
|-------|------------------------:|-----------------:|-----------------:|
| liquid before | 470 / 0.9 | 68.9 / 362.0 | 0.3 / 19.6 |
| liquid after | 851 / 20.6 | 2.0 / 41.8 | 0.5 / 13.3 |
| frosted before | 312 / 0.8 | 1.6 / 60.1 | 0.4 / 21.3 |
| frosted after | 856 / 16.9 | 1.7 / 9.7 | 0.4 / 11.1 |

On Metal the cost is a first-launch cost: a fresh install pays 0.3 -
0.5 s of precache already (runtime stages compile at load) and the
warm-up adds 0.4 - 0.55 s to it, while a later launch reuses the
driver's cache and the warm-up costs 17 - 21 ms. The cold liquid frame
keeps a 42 ms raster residue (not traced; 362 before); every other
first frame is at steady-state worst. Launch to first frame is not
recorded on iOS (devicectl reports no launch time).

## Startup and queue bounds (2026-10-05, the macOS hang)

Symptom: the example hung at launch on macOS, Not Responding, not on
every launch (one spindump, morph_example 2026-10-05 16:41, main thread
blocked 1.6 s after launch for the remaining 471 s). Every thread idle
except the main (= UI) thread:

    InternalFlutterGpu_CommandBuffer_Initialize   (command_buffer.cc:202)
    impeller::ContextMTL::CreateCommandBufferInQueue
    -[AGXG15XFamilyCommandQueue commandBuffer(WithDescriptor:)]
    -[_MTLCommandBuffer initWithQueue:retainedReferences:...]
    _dispatch_semaphore_wait_slow / semaphore_wait_trap

Cause: Impeller's Metal queue is `newCommandQueue`, 64 uncompleted
command buffers; one more blocks until a buffer completes. Geometry
passes recorded during paint were held unsubmitted until the scene build
with no bound, so a frame with about 62 passes waited on slots only its
own unsubmitted passes could free - forever. Reproduced in a release
build on the Mac (M3, Flutter 3.47.2): 72 standalone glass buttons
(glass_density_test's page) hang on the first frame with 62 passes held,
the stack above; 62 raw `gpuContext.createCommandBuffer()` without a
submit block on the 63rd; 48 buttons pass (47 held). The gallery home
holds at most 1 pass and the autodemo at most 11, and 40+ launches of
the gallery (release, profile, debug, `open -n`) did not hang on this
Mac, so the owner's launches crossed the bound some other way than the
home page alone; the mechanism and the stack are the ones above.

Bounds since 50a4491:
- `MorphDeferredSubmissions` submits the held passes every 16 (2 per
  layer at most, the raster thread keeps the rest of the 64); 72 and 200
  buttons draw their first frame. A failed submission is reported and no
  longer strands the batch (before, a throwing `submit()` left the list
  uncleared and every later flush threw on it again while the list
  grew). A render that throws before its pass is recorded (a field
  upload or uniform write) no longer leaks an uncommitted buffer, which
  would hold a slot until the GC.
- `precache()` holds the launch at most `morphPrecacheBudget` (1 s,
  above the 0.35 - 0.86 s measured cold); past it the capability and
  warm-up finish in the background and glass drawn meanwhile is fake.
  A synchronous engine wait (reading `gpu.gpuContext` on Android before
  the engine created the context) is not bounded by it.
- GLES (Pixel 6a forced with `ImpellerBackend=opengles`, profile; the
  manifest key is ignored in release): before 58735ef every launch
  crashed before the first frame - the fake warm-up's
  `OffsetLayer.toImage` snapshot hit a null dereference on the raster
  thread (`BlitCopyBufferToTextureCommandGLES::Encode` <-
  `ReactorGLES::FlushOps` <- `SnapshotControllerImpeller::
  MakeImpellerSnapshot` <- `Picture::DoRasterizeToImage`). The warm-up
  now runs only on the `capable` class; GLES precache 3 ms, first frame
  13 ms, 6/6 launches; Vulkan precache 0.52 - 0.58 s as before. A
  Motorola on GLES matches this crash better than a hang; unconfirmed.
- Not a hang, found on the way: Flutter GPU's HostBuffer throws
  `Failed to write range (offset=79616, length=2352)` when an emplace
  straddles the end of a block (its check ignores the write's length);
  the 32-slot block fits about 31 geometry renders a frame, the rest
  fall back with "geometry render failed". FIXED (2026-10-05): the
  renderer no longer uses HostBuffer; `MorphUniformArena` (same file)
  bump-allocates the uniforms over blocks of 32 slots, starts the next
  block of the frame when a write would cross the end (reused from an
  earlier cycle, else allocated), cycles four frames like HostBuffer, and
  throws instead of returning a view it failed to write. HostBuffer also
  allocated a fresh block on every later overflow and never reused it,
  so the old path grew without bound once it overflowed. Where it bit:
  the block is 32 x the geometry uniforms (2352 bytes) rounded up to the
  uniform alignment. With 256-byte alignment (the Mac's Metal) the 32nd
  render of a frame crosses the end; with 16 (Pixel 6a, Vulkan:
  geometry uniforms 2352, field uniforms 80, alignment 16) plain renders
  fit exactly and only a frame mixing field bodies crosses it. Pixel
  probe (a scratch profile app, not committed: 100
  renders in one frame, every other one with a field): HostBuffer fails
  at render 31 (`offset=74192, length=2352`), the arena takes all 100 in
  4 blocks; plain renders 100 / 100 on both. Regression:
  test/glass_uniform_arena_test.dart (200 emplaces in one frame, every
  one inside its block and aligned; 40 frames of 100 reuse at most 4
  blocks per frame slot; an oversized write gets its own block; a failed
  write throws) and glass_density_test.dart's stress phase (96 buttons
  on one screen pressed in the same frame, `geometry_failures` in the
  report must be 0; on the Pixel 0 before and after, as the probe
  predicts for plain buttons). Density timings before / after on the
  Pixel (one run each, perf/2026-10-05-pixel6a-hostbuffer) within run
  noise.

## Vulkan exterior boxes (Pixel 6a, 2026-10-05, Flutter 3.47.2)

Symptom: on the Pixel 6a (Mali-G78, Impeller Vulkan) every liquid
surface sat in a box the size of its filter clip, half its own interior
color (20,20,21 around a dark button over black, dark blue around a
prominent one; perf/2026-10-05-pixel6a-attrib). Not on GLES on the same
GPU, not on Metal, not on the flat or frosted tiers.

Root cause: the final pass's `decodeSignedEdgeDistance`
(shaders/gpu/displacement_encoding.glsl) chose its branch with a ternary
on the sign of the centered distance. Compiled into the whole final
render shader, the Vulkan pipeline returned 0 for every exterior texel
(b < 0.5, including the empty matte, b = 0) instead of
-(magnitude x exterior range), so each exterior pixel read as lying on
the silhouette: material alpha 0.5, glass color at half weight, over the
whole matte inside the clip. The layer chain is innocent. Bisected with
probe builds of a minimal scene (raw LiquidGlassLayer + LiquidGlass and
MorphGlassButton over black): removing the opacity probe, the retained
effect OffsetLayer, the filter ClipRect or the shadow picture changed
nothing; writing the decoded values out of the full shader showed sd = 0
and material alpha 0.5 on exterior texels with b = 0, while the same
decode written out of a shader whose later code was dead (so the
compiler dropped it) gave the correct -3 px; the geometry texture,
uniforms (contour extent 2.98 px) and the sampled b were right in every
build. The SPIR-V path is the only one that differs from GLES on the
same GPU, so this is a shader-compiler fault (Mali Vulkan driver or the
Vulkan SPIR-V impellerc emits), not engine compositing.

Fix: the decode selects with `step(0, centered)` and arithmetic instead
of the ternary. Exact for every input (step is exactly 0 or 1, so the
products and the subtraction are exact and the result equals the old
branch bit for bit): Metal and GLES output is unchanged
(test/glass_frames_test.dart hashes identical before and after; it runs
the fallback there, the identity on Metal is by that arithmetic). On
the Pixel the probe scene's Vulkan frame is pixel-identical to GLES
after the fix (0 differing pixels over the scene).
perf/2026-10-05-pixel6a-attrib/vulkan-boxes-fix-vk-before-after-gles.png:
the probe scene on Vulkan before, Vulkan after, GLES after. Regression:
example/integration_test/liquid_exterior_test.dart (on device; fails
before the fix with 1646 lit exterior pixels, max channel 21, passes
after).

## Device numbers (iPhone 16 Pro, 2026-10-03 and 2026-10-05, profile)

- 2026-10-05, tool/ios_reference/perf/audit.sh (5 timed runs per scene,
  median, active frames only, screenshots outside the timed windows),
  p95 build / raster ms, scenes segmented / tab bar / controls / menu /
  home scroll under bars / sheet:
  liquid 1.47/2.00, 1.58/2.74, 3.25/2.88, 2.16/2.92, 1.28/2.14, 1.36/3.21;
  frosted 1.20/2.29, 1.00/2.71, 2.27/3.65, 3.77/2.25, 1.35/2.51, 0.90/3.92;
  flat 0.53/0.78, 1.06/1.47, 2.52/0.80, 4.15/1.63, 1.14/1.83, 0.70/0.95.
  The identical-output batch (content source boundary, lazy uniforms,
  field upload reuse, outline translation memo, repaint boundaries) left
  every percentile within +-0.1 ms of the 2026-10-05-baseline run; its
  shots are within run-to-run noise (the tall menu's open shot flips by
  one device pixel between launches of the SAME app). Raster cost is
  captures and blurs: liquid raster is ~3x flat on every scene.
  Outline fusion: menu blur 4 pt 1.13 ms (0.71 on 2026-10-03 - not
  explained then: see phase 2), 10 pt 0.60, 20 pt 0.37, bar capsules 0.12.
- 2026-10-05 phase 2 (audit without the semantics tree; build p95
  p2-base -> p2-head2, same order as above): liquid 1.36 -> 1.41,
  1.54 -> 1.48, 3.05 -> 2.34, 2.01 -> 2.02, 1.26 -> 1.26, 1.33 -> 1.34;
  frosted controls 1.93 -> 1.51, menu 3.95 -> 3.87; flat controls
  2.42 -> 1.68, menu 4.27 -> 3.85; raster unchanged within noise; every
  audit shot within the run-to-run noise of the identical batch (resting
  shots <= 56 max channel at <= 0.003 percent, the timed tall-menu close
  and held shots move between launches of one app). Findings:
  - The "4 pt 1.13 ms" was harness order, not code: timed three times in
    one launch after the scenes the 4 pt case reads 1.147 / 0.666 /
    0.667 ms; ~45 ms of one-time work lands on the first case. The audit
    now times a warm-up pass first (kept as '-cold'). Steady: 4 pt 0.67,
    10 pt 0.62, 20 pt 0.36, plain union (260 x 600 menu over its button,
    spacing 0, fused every frame of the menu's settle tail) 0.73 -> 0.49
    (field from the box distances it has, grids kept across calls), bar
    capsules 0.12. The JIT microbenchmark does not track the device
    here (7182ca4 sped r4 up and slowed r20 down under JIT; the device
    moved neither).
  - Where the flat menu's p95 goes (device timeline, three opens): the
    silhouette, 2.5-3.8 ms per frame at fusion radii 2-9 pt and 1.5-5 ms
    per frame of the r < 1 tail on the gallery's rich menu, plus
    old-generation GC mid-frame (incremental marking 22 ms per three
    opens, 3.1 ms in one frame); keeping the container grids took GC to
    2 collections / 1.7 ms. The menu's cards and motion getters cost
    <= 0.01 ms per frame (M9 has nothing to win). Field-only work (half
    thickness, optical turn, samples) is 10-16 percent of a fusion: a
    lazy field for the flat and frosted tiers is not worth its
    complexity.
  - Chrome capture sharing (V1a): MorphNavigationStack's bar and toolbar
    capsules are `button` glass and read ONE capture - the root
    BackdropGroup's - with the page's body glass. That was a fidelity
    bug, fixed 2026-10-05 (below).
  - Opacity at full presence (V2): an OpacityLayer at alpha 255 pushes
    no save layer in the engine (flow/layers/opacity_layer.cc,
    LayerStateStack applyOpacity only below 1), so it costs no offscreen
    pass and breaks no backdrop sharing; it is also the only repaint
    boundary segmented, switch and slider have. Nothing to remove.
  - Semantics: testWidgets built the semantics tree in every audit
    (0.25 ms per frame at the median, up to 1.3 ms on the menu and
    controls scenes on the timeline) but FrameTiming.buildDuration ends
    before the semantics flush, so earlier passports were not inflated.
- glass_audit_test per `--dart-define=GALLERY_GLASS=`, p95 build / raster
  ms, scenes segmented / tab bar / controls / menu:
  liquid 1.75/1.80, 2.91/2.52, 3.87/2.67, 3.03/2.90;
  frosted 0.70/1.65, 1.28/2.42, 2.83/3.70, 2.46/3.67;
  flat 0.54/0.76, 0.69/0.92, 3.00/0.79, 3.23/2.35.
  Frosted is NOT cheaper than liquid on controls: it blurs every glass
  surface, liquid frosts only bars, menus and lifted lenses.
- Tier 2 vs the pre-move gallery painter (2b3773c, same audit): resting
  shots pixel-identical, held shots within timing noise (max channel diff
  <= 19, 0.001 percent of pixels over 15); raster p95 equal within noise.
- FUSED OUTLINE COST per frame (profile, UI thread, 10-row menu 260 x 440
  over its 48 pt button, 100-call mean; `--dart-define=AUDIT_OUTLINES_ONLY=
  true` times only this): before the sparse fusion (4a57cb7) blur radius
  4 pt 2.02 ms, 10 pt 0.67, 20 pt 0.31, two fused bar capsules 0.68;
  after it 0.71 / 0.61 / 0.36 / 0.12 (two runs each, +-2 percent). The
  JIT microbenchmark (benchmark/glass_outline_benchmark_test.dart, or a
  warmed 300-call loop in flutter test) tracks the device within ~20
  percent. What remains is the separable blur near corners, the button
  and the neck (~0.4 ms at 4 pt) and the field grid itself; the trace
  (edge-id stitching, quadratic B-spline through the crossings) costs
  0.07 ms.
- Earlier verdicts: LiquidGlassCapture drops whole controls on iOS
  (renders on macOS) - not used; FROST ~1 ms raster per frosted surface per
  frame (Controls page 13-15 ms vs 2.6 ms), so only bars, menus and lifted
  lenses frost unless "Frost controls" is on; an OpacityLayer between
  resting glass broke BackdropGroup sharing (menu-button.md).

## Apple check of the 2026-10-05 batch (iPhone 16 Pro, macOS)

The day's performance changes landed while the iPhone and the Mac GUI were
out of reach; this is their check on Metal. Results in
perf/2026-10-05-apple-verify (macos.txt, the audit and density JSONs, the
shotdiff texts).

- iPhone audit, HEAD f3b812d against 268a8c2 (the commit before 9678703;
  it covers menu fusion, field uploads, retained layers, the Vulkan decode,
  the uniform arena, MAX_SHAPES, the shader audit batch and the gallery's
  glass containers). The fake tier has no 268a8c2 build (it came with
  ae40643), so its base is ae40643, which misses only 9678703. audit.sh,
  5 runs, median, build p50 / p95, raster p50 / p95 ms, base -> head:
  liquid segmented 1.31/1.56/1.54/1.85 -> 1.12/1.32/1.35/1.68, tab bar
  0.93/1.63/2.04/2.72 -> 0.96/1.56/2.06/2.82, controls 1.42/2.74/2.06/2.68
  -> 1.12/2.56/1.55/2.25, menu 1.41/2.28/1.96/3.10 -> 1.25/2.12/2.03/3.05,
  home scroll 0.64/1.33/1.56/2.43 -> 0.70/1.39/1.51/2.32, sheet
  0.95/1.46/2.30/3.00 -> 0.72/1.33/2.10/2.76; flat menu build p95 3.75 ->
  2.57, raster p95 2.45 -> 1.76 (menu fusion), every other flat cell within
  +-0.05; fake controls raster p50 2.52 -> 1.95 (the gallery's button
  container), sheet build p50 0.73 -> 0.60, the rest within +-0.1. A second
  head launch (head2) moves every liquid percentile by <= 0.2 ms except menu
  raster p95 (+0.5). Frames over budget: 0 everywhere on liquid and flat.
  Fake controls and menu have 0 - 4 over-budget frames per run on BOTH
  sides (worst raster 7 - 10 ms); an ABBA of the two scenes alone (ae40643,
  7864ada, HEAD, two launches each, cm-*) counts 12 / 3 / 16 over ten runs
  on controls with the head's second launch at the base's level: launch
  spread, not a regression.
- Shots (shotdiff, base -> head): every resting and held shot within the
  run-to-run noise (liquid <= 110 max channel at <= 0.008 percent over 15,
  fake <= 80 at <= 0.004, flat <= 54 at <= 0.003; the flat segmented shot's
  53 is the gallery's description text, which changed). The timed tall-menu
  shots move as before: the menu one device pixel down as a whole, text
  included, 212 - 223 at 0.15 - 1.1 percent - and 223 at 0.43 percent
  between two launches of the SAME head app. So menu fusion (9678703),
  field uploads (07bb27d), retained layers (e2f9c4e), the decode fix
  (754bdbd), the uniform arena (b3754f9) and MAX_SHAPES (7864ada) draw the
  same pixels on Metal; the controls page's container row is pixel-equal at
  this phone's 3x (max channel 10 on controls-resting).
- Density, liquid, 1 run of 5 each, build p50 / raster p50 ms, 268a8c2 ->
  head -> head with DENSITY_CONTAINER: n4 rest 0.51/1.17 -> 0.46/1.15 ->
  0.41/0.90, n8 rest 0.67/1.66 -> 0.59/1.71 -> 0.47/0.99, n16 rest
  1.17/2.37 -> 0.80/2.50 -> 0.56/1.19, n32 rest 1.10/3.16 -> 0.84/3.53 ->
  0.99/1.46; n1 and every wave base -> head within +-0.1 on build and
  raster p50, and with the container the waves move by -0.55 to +0.05
  (n32 wave raster p95 2.53 -> 3.61 with the container, one run, the
  column "Glass density" already flags). Fake with the container: n8 rest raster
  p50 1.89 -> 1.15, n16 2.60 -> 1.45, n32 3.75 -> 2.27. On Metal the
  container halves resting raster from 16 buttons on (-52 / -59 percent at
  n16 / n32 liquid, against -23 / -20 on the Pixel). Over budget 0 in every
  cell. Stress phase (96 buttons pressed at once): geometry_failures 0 on
  liquid and fake, with and without the container; layers 96 filters, 65
  in the container (32 joined) - Metal's 256-byte alignment, where
  HostBuffer failed at the 32nd render, no longer drops a render.
- liquid_exterior_test on the iPhone (profile, through a wrapper that
  writes the binding's results to the app's tmp, since `flutter test -d`
  needs Rosetta's iproxy on this Mac): success.
- macOS (release, M3, launch_probe.dart): 20 gallery launches, first frame
  in 44 - 70 ms, no hang; 72 and 200 liquid buttons, 5 launches each, first
  frame 52 - 79 ms, no hang, no exception. Counter-check: the same HEAD with
  `MorphDeferredSubmissions.defaultLimit` raised to 100000 hangs at 72 and
  at 200 buttons, main thread in `InternalFlutterGpu_CommandBuffer_Initialize`
  -> `-[AGXG15XFamilyCommandQueue commandBuffer]` -> `semaphore_wait_trap`
  (the stack of "Startup and queue bounds"). At 07bb27d (before both fixes)
  72 and 200 buttons do NOT hang: HostBuffer's write failure ends the
  frame's renders near 31, so too few passes are held; once the arena let
  every render through, the 16-pass bound is what keeps the launch alive.
  The autodemo (release): AUTODEMO done, 0 EXCEPTION.

## UI thread on a weak device (Pixel 6a, 2026-10-05)

Method: Dart CPU samples from the profile build over the VM service,
split by frame (Animator::BeginFrame), atrace slices, glass_phases
blocks; macOS AOT for the fusion micro-timings; device hashes for
identity. All three changes leave every pixel identical.

- Menu: `morphMenuSilhouette` was ~45 percent of the samples in frames
  over 8 ms on BOTH tiers - the menu's build cost is its fusion, not
  rows or text. `morphBoxDistance` added a num `0` to a double, so AOT
  boxed it and called `Double.+` per box distance (visible in the
  optimized flow graph); fixed, plus deduplicated near-block edges, row /
  column split of the optical-corner test and `vm:unsafe:no-bounds-checks`
  on the grid loops: 383 -> 198 us per outline (macOS AOT), menu build
  p95 flat 14.02 -> 11.58, liquid 18.96 -> 14.80 ms. FUSION_HASH over 57
  recorded gallery inputs unchanged on macOS and the Pixel.
- Field uploads: `Texture.overwrite` is a staging buffer plus its own
  command buffer and queue submit per call (engine lib/gpu/texture.cc).
  Fields now copy from a kept staging buffer with `copyBufferToTexture`
  recorded on the geometry pass's command buffer (Vulkan, GLES; Metal
  keeps a separate buffer because its blit encoder opens at record time)
  into device-private textures bucketed to 16 nodes. Menu trace: UI
  QueueSubmit 1236 -> 880, PAINT 1.42 -> 1.16 ms per frame.
- Resting glass: `GeometryTransformTrackingLayer.alwaysNeedsAddToScene`
  forced every ancestor to rebuild its engine layer each frame; dropped
  (the hook already dirties the layer on any change), and the hook's
  second walk to the root for the filter mapping reuses the tracked
  transform. 16 resting buttons over a scrolling list: COMPOSITING
  2.53 -> 1.24 ms (flat 0.49). Moving glass (tab bar) is unchanged: it
  re-renders its matte and filter every frame by design.
- saveLayers (10.4 per liquid frame vs 1.1 flat): one per glass
  layer's BackdropFilterLayer (layer census: 8.8 filters / 8.85 glass
  layers in the menu scene); the opacity seed adds no engine layer while
  unseeded and shadows are clipped, not layered (b0f79b1). None is
  removable with identical output; the lever left is fewer glass layers
  (backdrop sharing), which changes pixels.
- Tried and dropped: a per-frame memo of screen transforms and opacity
  shared by all glass layers (`Map` upkeep cost as much as the walks it
  saved on the device); pairwise row blur passes (slower).

- Round two, the menu (2026-10-06, M3 per-frame dumps; menu-button.md
  "Built ahead of the opening"): the open frame was the worst build of
  each run (28 - 50 ms) and is now built ahead during the press (worst
  46 -> 28 ms liquid, 38 -> 27 fake, 44 -> 28 flat in the audit), but the
  p95 is the menu fusion field: build p95 with it 13 - 14.3 ms (liquid),
  without it 9.2. GC is not in the p95 frames. Over-budget frames stay
  raster-bound (12 - 19 of 15 - 23 per run on liquid).

## Shader harness and the shader audit batch (2026-10-05/06)

The audits (tool/audit/shader-audit-fable.md F1-F15, shader-audit-astra.md
ranks 1-12) proposed cheaper final and fake shaders with the same image.
Every change was judged by a synthetic harness on the devices, never by eye.

Harness (example/integration_test/shader_parity_test.dart,
support/shader_harness.dart): 19 deterministic cases (regular light/dark,
toolbar with blur, slider 0.7, clear, lifted lens with dispersion and
shrink, prominent tints, direct model with gamma 1.4, tint and material
variants, a fused field, a 340 x 600 sheet, a frosted menu, visibility 0.5
unfrosted and frosted, three fake-tier cases) over a seeded three-band
backdrop (stripes, gradient, noise) drawn at device pixel 0 with
FilterQuality.none in a 360 x 640 region. Each case renders offscreen
(RepaintBoundary.toImage) through the package's runtime shaders and through
a FROZEN copy (example/shader_audit/baseline, a64140c plus the 32-shape
decode; `ShaderKeys.debugRuntimeRoot` picks it) in the same app: the
candidate twice (repeat) and remounted (remount), both must be 0 - the
noise floor, 0 on every device - and the per-channel difference from the
baseline. Bench: the same scene with 1 and 6 stacked layers, ABBA blocks,
40 renders per sample; per block one layer's cost is the difference over
5 layers, so backdrop and readback cancel. On the Pixel the bench reads the
kernel's per-app GPU work periods (power/gpu_work_period and gpu_frequency
on the CLOCK_MONOTONIC trace clock, audit_android.sh `AUDIT_GPUWORK=1`,
tool/audit/shader/gpu_work.py): GPU cycles per layer, DVFS-proof. An A/A
run (candidate == baseline) reads within 1.3 percent on the sheet, menu,
material and fake cases and +-5 on the small control cases. Wall time per
render is +-25 percent there (DVFS) and is not used on the Pixel; on the
iPhone it is steady (blocks within a few percent) and is the Metal number.
Host oracle: `flutter test --enable-impeller --enable-flutter-gpu
test/shader_parity_host_test.dart` in example/ (Impeller on SwiftShader;
it ignores RelaxedPrecision and does not show the Mali contraction effects
below; delete build/unit_test_assets after editing a .glsl include).
Offline: tool/audit/shader/offline.py (impellerc Vulkan / Metal / GLES 3
stages, SPIR-V counts with the NDK's spirv-dis, and since 2026-10-06
Arm's malioc for the Mali-G78: see "The Mali offline compiler batch").
Runners:
tool/audit/shader/run_pixel.sh (Vulkan, or GLES forced in the worktree's
manifest), run_iphone.sh; parity.py reads and cross-compares the reports.
Results: perf/2026-10-06-shader-audit/ (traces in /tmp/morph-perf/gpuwork,
430 MB, not committed).

Findings (max channel step vs the frozen baseline over 19 cases, pixels of
1.59 M per case; GPU gain = median paired cycles on the Pixel, wall on the
iPhone; cumulative where marked):

| finding | bound | Pixel Vulkan | Pixel GLES | iPhone Metal | status |
|---|---|---|---|---|---|
| F14 / astra 1 reject before material reads | 0 | 0 | 0 | 2 (33 px, mixed-models) | reverted (c60deca) |
| F4 / astra 2 coverage, contour direction once | 0 | 0 | 0 | 0 | kept |
| F5 normal decoded once | 0 | 1 (53 px) | 1 (53 px) | 0 | reverted (cd33195) |
| F2 deep-interior early return | 0 | 0 | 0 | 0 | kept |
| F12 step picks: shares, return weight, pair repair | 0 | 0 | 0 | 0 | kept |
| F12 step-weighted normal decode | 0 | 1 (~50 px) | 1 (with F5) | - | reverted (9f330b5) |
| astra 3 one palette fetch per row | 0 | 0 | 0 | 0 | kept |
| F10 fake highp | fidelity fix | changed to = GLES | 0 | 0 | kept |
| astra 5 fake exterior-only return | 0 | 0 | 0 | 0 | kept |
| F11 fake cap by cosine | 1 | 0 | 0 | 1 (1 px) | kept |
| F3 no pow at exponent 1 | 1 | 1 (<= 3 px) | 1 (<= 3 px) | 1 (<= 7 px) | kept |
| F6 Vulkan mediump colour | 3 | 2 (6-98 k px) | n/a | n/a | rejected: no gain |

F10, measured: before it the fake tier's Vulkan output differed from GLES
on the same Pixel by up to 157 steps (fake-big-sheet, 28 k px; 20-23 on the
capsules) - the Mali driver took the RelaxedPrecision and placed the
silhouette in fp16; after it Vulkan equals GLES on every case. The liquid
cases were already Vulkan == GLES, pixel for pixel, before and after.

GPU per layer, the final batch (c60deca) against the frozen baseline: Pixel
Vulkan cycles big-sheet +8.1 percent (blocks 2..13), menu-frosted +1.2,
mixed-models +2.0, lifted lens +4.2, control capsules +2.3 (within that
case's +-5 noise), fake 0. Pixel GLES (9f330b5, F14 still in) big-sheet
+5.5, menu +2.5, mixed +14.4. iPhone Metal wall big-sheet +9.4, menu +7.3,
control capsules +10.2, lens +2.8, mixed +1.9, fake -2.4 (fake A/B with and
without F11: both within +-2). Where it comes from: F2 (ad6bad1 big-sheet
+8.2, -2..-1 before it); astra 3 and F14 gave the material case +5..+14 while
F14 was in. F3, F12, F10/F11/astra 5 and F6 do not move the bench beyond
its noise. A sheet-sized face is where the final pass costs; a 44 pt
capsule's layer is ~0.5 ms of mostly fixed cost.

End to end (glass_audit, liquid, 5 runs per launch, two ABAB pairs, before
= HEAD 9f330b5 with the frozen runtime shaders, after = 9f330b5; c60deca
only drops F14): no raster change on either phone. Pixel raster p50 +0.05
.. +0.46 ms (the two before runs differ by up to 0.4 among themselves),
p95 -0.4 .. +1.4, frames over budget unchanged within one or two; iPhone
within +-0.05 ms p50. Raster time ends at submit, so a GPU saving shows
there only where the GPU is the bottleneck; these scenes are CPU raster
bound (passport above). Audit shots: before vs after within the run-to-run
shot noise on both phones (resting states max 10-15, moving states as
noisy as two runs of the same build).

Lessons: a source-level identity (CSE, reordering, a 0/1 select) is not a
pixel identity - Mali and Metal contract and schedule differently per
layout, so the harness on each device is the gate, not reasoning; the host
oracle (SwiftShader) passed all three changes the phones rejected.

Not done: F1 / F8 uniform folds (they change the final shader's uniform
ABI in liquid_glass_layer.dart, which also breaks the same-binary A/B, and
without malioc there is no evidence the drivers do not hoist them
already); F7 specialization (malioc); F9 / astra 11 RGBA16F field and
astra 6 / F15 output buckets (renderer_native and the layer, the
container agent's files that day; astra notes the bucket shrink is
VISIBLE unless the sampling domain is kept); F13 / astra 7 geometry pass.

## Glyph atlas under animated scales (2026-10-06)

Finding (Pixel 6a baseline): traced tab-bar and menu scenes updated
Impeller's glyph atlas ~12 times a second at ~2.5 ms each, on every tier.

Cause (engine a804b26164, impeller/typographer): a glyph is keyed by
font, SCREEN SCALE and x subpixel (4 buckets); the scale is the largest
basis length of the text's transform, device pixel ratio included,
rounded to 1/200 (`TextFrame::RoundScaledFontSize`). Text whose scale
sweeps meets a new key nearly every frame; `UpdateAtlasBitmap`
rasterizes the label's glyphs at it and uploads them. No fontSize
changes anywhere in lib/; no variable-font axis is set on Android. In
place: the audit's new `AUDIT_ATLAS=true` records the engine timeline
(`traceTimeline`, Embedder stream) per timed run and stamps every
update against the run's finger down / up marks. Updates sat in the
first ~400 ms after down (lens lift, bar swell) and after up (lens
set-down; menu open / close), and fell run over run as the visited
scales filled the atlas (iPhone 57 -> 3 per run on the tab bar), slowly
on the Pixel (48 -> 30). Three transforms: the lens content copy
(grow x magnification, 1 -> 1.38 on the tab bar, -> 1.25 segmented;
liquid and fake tiers), the menu content scale (0.05 -> 1.07 -> 1, all
tiers) and the tab bar swell (1 -> 1.04, small, saturates within a few
presses; flat tier 42 -> 1 per run).

Fix (lib/src/widgets/glyph_scale.dart):
- Lens copy: while the lens lifts or sets down (lift < 0.99) the copy's
  slot magnification is adjusted so the copy's SCREEN scale (render
  tree transform x grow x magnification) lands on a grid of 64 steps
  per octave passing through the device pixel ratio
  (`MorphGlyphScale.snap`). Glyphs stay rasterized and crisp; the label
  is at most 0.54 percent off its exact size about its slot center (0.1
  pt for a 20 pt half label); at lift >= 0.99 and at rest it is exact.
  The lift sweep has ~33 grid scales instead of ~200 engine keys.
- Menu: while the content blur is >= 0.5 pt (`MorphGlyphRaster.minBlur`;
  open p <= 0.94, from the first frame of a close) the root rows draw
  from ONE raster at the device pixel ratio, mipmapped under the content
  scale - the glyphs the rest state uses, no new key. Below that blur
  (the open's settle, 1.07 -> 1) the rows are live and exact.
- Tried and kept out: a raster for unblurred text (softer by ~3x the
  1-frame jitter floor in flutter_test); coarser snapping (visible
  steps); the swell (bounded and saturating, labels anchored at the bar
  center would move up to 1 pt per step).

Pixel evidence: test/glyph_scale_test.dart plays each scene exact
(`MorphGlyphScale.debugExact`) and on the grid and compares every frame:
tab bar 120 frames, 33 differ (the lift / set-down), worst frame max 147
on edge pixels, mean 0.019, 0.023 percent of pixels over 15, first and
last frames identical; menu 120 frames, 33 from the raster (all under
the blur): worst max 29, mean 0.04, 0.02 percent over 15; every other
frame identical (0). For scale: in flutter_test a 0.1 percent scale
change of a label already moves single edge pixels by 255 and a 0.1 px
shift by 106. Device shots (perf/2026-10-06-*-glyph-base -> -after):
resting and held shots within run-to-run noise (flat tab bar shots,
which this change does not touch, differ by up to 53); the
timeDilation menu close shots move with the close's timing.

Numbers (5 runs median, AUDIT_ATLAS=true on both sides, ms):

| device / tier / scene | updates/s | update ms/run | raster p95 | raster p99 | over budget |
|---|---|---|---|---|---|
| Pixel liquid tab bar | 6.57 -> 2.33 | 113 -> 13 | 17.99 -> 17.32 | 21.45 -> 19.47 | 51 -> 41 |
| Pixel liquid menu | 12.19 -> 7.50 | 130 -> 41 | 20.67 -> 16.69 | 30.96 -> 25.65 | 29 -> 20 |
| Pixel liquid segmented | 1.77 -> 1.27 | 11 -> 5 | 9.20 -> 9.17 | 10.41 -> 10.68 | 0 -> 0 |
| Pixel flat menu | 9.60 -> 5.14 | 174 -> 51 | 13.45 -> 9.70 | 27.93 -> 13.15 | 15 -> 7 |
| Pixel flat tab bar | 2.24 -> 1.59 | 20 -> 15 | 9.36 -> 9.46 | 10.45 -> 10.46 | 0 -> 0 |
| iPhone liquid tab bar | 5.80 -> 1.15 | 6.7 -> 1.3 | 2.81 -> 2.50 | 4.58 -> 3.05 | 2 -> 0 |
| iPhone liquid menu | 8.43 -> 4.93 | 20.9 -> 3.6 | 3.12 -> 2.83 | 4.97 -> 3.75 | 0 -> 0 |
| iPhone flat menu | 12.18 -> 2.75 | 57.4 -> 6.0 | 2.03 -> 1.42 | 4.26 -> 1.99 | 0 -> 0 |

CreateGlyphAtlas per frame (lookups + updates), Pixel liquid: menu 0.81
-> 0.30 ms, tab bar 0.54 -> 0.20. What remains: the menu's unblurred
settle (scale 1.07 -> 0.998 -> 1, ~38 engine keys, crisp on purpose),
the swell, the menu button's press scale, the first lift on each grid
scale; all bounded sets that fill the atlas and stop.

## Round two levers R1, U2, R4 (Pixel 6a, 2026-10-06)

The levers of tool/audit/round2-fable.md for the shadow saveLayer, the
per-layer UI hygiene and the filter-clip buckets, measured first and then
built. Evidence: perf/2026-10-06-pixel6a-census (the baseline per scene,
eae3c9f) and perf/2026-10-06-pixel6a-r1u2 (traces and timings of every
variant, the same launch session, ABAB, 5 runs per scene).

Measurement (M2 and a light M6): the glass audit marks every timed run
with zero-length timeline slices, `atrace_slices.py <trace> --scenes`
windows a systrace capture by them, and `AUDIT_CENSUS=true` counts the
engine layers of the same frames (support/layer_census.dart). Per raster
frame, liquid / flat:

| scene | saveLayers (trace) | backdrop filters (census) | other offscreen layers | glass shadow pictures | PAINT ms | COMPOSITING ms | frames per scavenge |
|---|---|---|---|---|---|---|---|
| home-scroll | 4.9 / 2.9 | 1.7 / 0.7 | 1.1 / 1.1 | 0 | 1.62 / 1.54 | 0.70 / 0.48 | 45 / 47 |
| segmented | 3.8 / 0 | 1.8 / 0 | 0.2 / 0 | 0 | 1.74 / 0.43 | 1.08 / 0.53 | 25 / 49 |
| tab-bar | 7.9 / 2.0 | 3.9 / 1.0 | 0.2 / 0 | 0 | 2.60 / 1.17 | 1.29 / 0.52 | 17 / 42 |
| controls | 8.2 / 0 | 3.9 / 0 | 0.3 / 0 | 0 | 1.61 / 0.45 | 1.54 / 0.57 | 17 / 66 |
| menu | 18.4 / 0.4 | 9.0 / 0 | 0.2 / 0.2 | 0 | 1.33 / 0.52 | 1.29 / 0.56 | 45 / 40 |
| sheet | 13.7 / 0 | 7.5 / 0 | 0 / 0 | 0 | 0.64 / 0.44 | 1.55 / 0.49 | 70 / 122 |

Impeller's trace records two Canvas::saveLayer per backdrop filter (the
flat tab bar: one filter, two) and one per opacity or image filter layer,
so the trace count is 2 x filters + other offscreen layers in every scene,
liquid and flat: no saveLayer is recorded inside a picture. The renderer's
shadow pictures do not occur in the gallery at all - every glass shadow is
drawn by GlassShadow or MorphGlassBodyShadow, both clipped since b0f79b1.

- R1 (the layer's shadow picture through the even-odd clip): built and
  measured, NOT landed. The saveLayer count per frame did not move in any
  scene (4.93 / 3.79 / 7.95 / 8.19 / 18.40 / 13.67), as the census
  predicted - kill criterion K-R1. The clip form drew the shadows to
  within 1 step off the rim and 9 on the rim row on the host's Impeller
  (35 with a darker test shadow), no shadow inside a shape; a fading or
  overlapping shape needs the layer anyway. It is a lever for apps that
  hand LiquidGlass shapes their own shadows, not for the gallery.
- U2 (per-layer UI hygiene, IDENTICAL, landed): the tracked screen
  transform is no longer cloned and the shader transform is cloned only
  when the pass transform changes it; the coordinate mapping inverts into a
  kept matrix and maps its three points with MatrixUtils.transformPoint's
  own arithmetic; the mapping and sampled-bounds uniforms are written with
  setFloat, without setter closures and lists; the appearance list is
  compared in place and built only on change; the sampled backdrop's
  ancestor clips need no list; the frost blur is kept per sigma and only
  the composition is rebuilt. Identity: glass_frames on the host's Impeller
  (--enable-impeller --enable-flutter-gpu) - the 56 scenes that are
  deterministic run to run are hash-identical to HEAD; the 7 liquid scenes
  whose frames differ between two runs of the same build (lens, tab bar,
  switch, slider, controls, menu) differ from HEAD by as many frames as two
  HEAD runs differ from each other; Skia glass_frames identical. Device:
  within the run-to-run noise everywhere (trace PAINT and COMPOSITING
  +-0.05 ms per frame, timings below). Not done: the shadow picture
  retention (no consumer, see R1) and skipping the compositing poll's
  ancestor walks - an ancestor Opacity changing its alpha neither repaints
  the layer nor moves its transform, so a skipped walk would miss the
  opacity seed.
- R4 (16 px filter-clip buckets for unfrosted layers): built IDENTICAL by
  construction (the fine clip only where the material plus its sampling
  reach already lies inside the 64 px clip, so no sample changes domain)
  and hash-identical on the host, NOT landed: the reach exceeds the coarse
  clip for most layers (refraction samples beyond the material regularly
  reach the 64 px clip's edge and mirror there), so the fine clip applies
  rarely, and the device shows no change.

End to end (mean of two launches each, median of 5 runs; flat floor in the
same session):

| scene | raster p95 base / U2 (flat) | build p95 base / U2 (flat) | over budget base / U2 (flat) | round2 target |
|---|---|---|---|---|
| home-scroll | 11.14 / 11.26 (10.59) | 5.89 / 5.88 (5.51) | 2 / 1 (2) | raster <= flat + 1.0: met |
| segmented | 10.75 / 10.78 (6.85) | 7.66 / 7.58 (3.24) | 0 / 0 | raster <= flat + 1.5: +3.9, not met |
| tab-bar | 15.48 / 15.00 (10.06) | 8.96 / 8.95 (4.00) | 19.5 / 17.5 | raster <= flat + 3.0: +4.9, not met |
| controls | 15.19 / 15.49 (6.78) | 12.77 / 13.00 (7.75) | 14.5 / 14.5 | raster <= flat + 4.0: +8.7, not met |
| menu | 20.25 / 19.83 (13.07) | 14.36 / 15.23 (12.82) | 24 / 25 (11) | raster p95 <= 15: not met |
| sheet | 15.75 / 15.97 (7.88) | 7.26 / 6.89 (3.55) | 8.5 / 9 | raster <= flat + 4.5: +8.1, not met |

Reading: the liquid raster cost is the backdrop filters themselves - two
saveLayers and a submit share each - and the UI thread's liquid PAINT and
COMPOSITING are not allocation-bound; the remaining levers are fewer
filters (R3, the container) and cheaper filters, not bookkeeping.

## Backdrop filter attribution and consolidation (2026-10-06)

Every backdrop filter of the audit scenes named by its owner
(`AUDIT_CENSUS=true AUDIT_CENSUS_OWNERS=true`: the census labels a filter
by the Morph widgets above the render object that paints it, the host
role key and the painter type; painters that keep the filter in a private
handle note it with `GlassLayerOwners`, null and free unless a census
sets it). Pixel 6a, liquid, filters per frame, base (9e2b532) -> after
(perf/2026-10-06-pixel6a-filters-census, -census3):

| scene | owner (why its own filter) | base | after |
|---|---|---|---|
| home-scroll | navigation bar capsules (chrome group, floats over content) | 1.00 | 1.00 |
| | scroll edge effect blur (own copy; in the bars' group REJECTED 2026-10-05) | 0.72 | 0.73 |
| segmented | navigation bar | 1.00 | 1.00 |
| | lifted lens `(glass, 0)` (must refract the body and labels under it) | 0.64 | 0.63 |
| tab-bar | tab bar body (bar kind, own group) | 1.00 | 1.00 |
| | lifted lens (refracts the bar glass) | 0.87 | 0.87 |
| | navigation bar + edge effect (list scrolled under it) | 2.00 | 2.00 |
| controls | button row container (5 buttons) | 1.00 | 1.00 |
| | prominent button (other tint: one appearance per container) | 1.00 | 1.00 |
| | navigation bar | 1.00 | 1.00 |
| | lifted slider thumb / switch knob | 0.89 | 0.89 |
| menu | 8 resting menu buttons, one layer each (MorphTag opacity and no still signal kept them out of any container) | 7.43 | 0 |
| | menu page container (the 8 buttons) | 0 | 1.00 |
| | pressed / landing menu button (out of the container) | 0 | 0.32 |
| | open menu face (MorphMenuLayer, menu kind) | 0.57 | 0.57 |
| | navigation bar | 1.00 | 1.00 |
| sheet | page container (5 buttons) + its pressed button | 1.39 | 1.37 |
| | zoom button (MorphTag) and "Tap me" button, own layers | 2.00 | 0 (in the page container) |
| | sheet surface (menu kind) | 0.76 | 0.70 |
| | the sheet's 3 buttons (own layers, sheet content group) | 2.27 | 2.09 |
| | navigation bar | 1.00 | 1.00 |
| total | home 1.72 -> 1.74, segmented 1.64 -> 1.66, tab bar 3.87, controls 3.89, menu 9.00 -> 2.89, sheet 7.42 -> 5.15 | | |

No filter in any scene is invisible: an empty or fully faded layer already
drops its filter (`drawableEmpty`), a resting edge effect drops its blur
(presence <= 0.001), an unseeded opacity seed adds no pass, and no scene
holds one under an opacity of 0 or fully covered by opaque content (every
cover is glass). The lens, the bars, the edge effect and the menu face
need their own copy (they read glass or blur painted below them).

Consolidations (landed):
- A glass container sees through a showing MorphTag: the tag publishes
  `MorphTagVisibility` right under its opacity (exactly 1 or 0), the reach
  check passes the opacity while the tag shows and depends on the tag, so
  a tag hiding for its flight sends its glass into its own layer in the
  same frame (test/glass_container_tag_test.dart). The resting menu button
  tells when it is still (no menu presented, not landing, motion settled).
- Gallery: the menu page's buttons and the sheet page's whole list in one
  container each.
- A settled glass button and a still menu button draw through an exact
  identity transform: the residual press scale (within 1e-4 of 1) made a
  member read as scaled, and the container then skipped its raster shift
  (a 30-step rim ring on the Pixel's once-pressed menu button). A layer
  that shifts anchored shapes repaints once its compositor motion has
  stopped for a frame if the pass phase moved under it (the documented
  "until the next paint" gap after a push or a scroll).
- Built and REVERTED: the plain sheet's three buttons in a container. The
  floating sheet draws its content scaled to its inset width, and a scaled
  member gets no raster shift: their rims landed up to 171 steps (0.29
  percent of the screen) off their own layers. Re-landed once the sheet
  closed its containers while scaled (Q3 of "Raster ties, scaled
  containers").
- Not changed: the prominent button joining the row needs per-shape
  appearances (the material map shader) in the container - a different
  final shader for every member, not IDENTICAL; measured since (Q4 of
  "Raster ties, scaled containers").

Pixels. flutter_test: the 56 deterministic glass_frames scenes hash-equal
on the host's Impeller, the 7 noisy liquid scenes within their run-to-run
spread, Skia glass_frames identical; tagged and plain buttons in a
container equal to their own layers on the fake tier, resting menu
buttons within 4 steps (the fake tier's round shapes in one layer, the
same as for a circular glass button; 0 on the host's Impeller). Device
shots (shotdiff, base -> after vs base -> base): Pixel 6a menu-resting,
menu-open, controls, segmented within noise; sheet-medium differs only in
the pressed "Medium and large" label (it settles at an exact identity
now), tabbar3-held-over-content by a 1 px scroll offset of the flung list
(both after builds alike, rows only, no glass). iPhone 16 Pro: every shot
within base-to-base noise except menu-resting: the 0.7 menu button's
glass sits one device pixel higher (max 123, 0.02 percent, rim only) - its
origin falls on an exact half device pixel at 3x, the tie of
`glassRasterPhase`, which a container and an own layer break differently.

Timings (median of 5 runs per launch, mean over launches; Pixel 6a, 60 Hz,
cooled to 37 - 39 C, base 9 launches across pairs a - i, after 2 launches
ABBA, flat 1; iPhone 16 Pro base 4, after 2; ms):

| scene | Pixel raster p50 | Pixel raster p95 (flat) | Pixel over budget | iPhone raster p50 | iPhone raster p95 | round2 target (Pixel p95) |
|---|---|---|---|---|---|---|
| home-scroll | 8.16 -> 8.24 | 11.00 -> 11.34 (10.31) | 1.7 -> 2.0 | 1.51 -> 1.52 | 2.29 -> 2.32 | flat + 1.0: +1.03 |
| segmented | 8.40 -> 8.67 | 10.41 -> 10.64 (6.78) | 0 -> 0 | 1.37 -> 1.38 | 1.70 -> 1.69 | flat + 1.5: +3.9, not met |
| tab-bar | 10.86 -> 11.00 | 13.96 -> 13.96 (10.21) | 5.2 -> 5.0 | 2.05 -> 2.05 | 2.53 -> 2.58 | flat + 3.0: +3.8, not met |
| controls | 8.93 -> 9.21 | 15.24 -> 15.56 (6.64) | 14.3 -> 16.0 | 1.56 -> 1.56 | 2.23 -> 2.14 | flat + 4.0: +8.9, not met |
| menu | 10.79 -> 9.15 | 17.46 -> 15.49 (10.44) | 20.4 -> 14.5 | 2.05 -> 1.55 | 2.78 -> 2.48 | <= 15: 15.49, not met (-2.0) |
| sheet | 10.55 -> 9.71 | 15.22 -> 14.11 (7.78) | 7.6 -> 6.0 | 2.09 -> 1.97 | 2.77 -> 2.65 | flat + 4.5: +6.3, not met (-1.1) |

Reading: only the menu and the sheet held filters that could share one
without changing pixels, and they gain what the census predicts (~0.3 ms
raster per removed filter: menu -6.1 filters, p95 -2.0 ms, p50 -1.6; sheet
-2.3, p95 -1.1). The other scenes' filters are each a separate plane; the
Pixel's +0.2 - 0.3 ms on segmented and controls (identical layer trees,
the after launches' home scene up too) is launch-to-launch spread, the
iPhone shows none. What remains of the targets is the cost of the
unavoidable filters (the lifted lens, the bars, the edge effect).
Evidence: perf/2026-10-06-pixel6a-filters-{a..i} (b holds the flat
floor; after = the reverted in-sheet container, after2 = the identity
snap, after3 = the landed state), -filters-census{,3},
perf/2026-10-06-iphone-filters-{base-a..d, after-a/b, after2-a/b,
after3-a/b}; shots in /tmp (not committed).

## Raster ties, scaled containers, and where the rest of the raster goes (2026-10-06)

Four questions left by the consolidation above. Evidence:
perf/2026-10-06-pixel6a-raster-attrib (the ablations, GPU work and traces
of Q1), perf/2026-10-06-pixel6a-tie-gate and perf/2026-10-06-iphone-tie-gate
(base ab36c1a / cand = Q2 + Q3 / cand4 = cand + the tinted member of Q4,
ABBA launches, census, shots in /tmp, not committed).

### Q1: segmented, controls and tab bar against flat

Ablation builds of the Pixel 6a audit (a worktree with a local ABL define,
never committed; raster p50 / p95 ms, mean of 1 - 3 launches of 5 runs,
cooled to 38 C, the launch-to-launch spread of one build is up to 0.5 ms):

| scene | flat | liquid | lens copy off | content clip off | lens / knob / thumb glass off | bar capsules flat | both off | small lens frost 0 |
|---|---|---|---|---|---|---|---|---|
| segmented | 5.53 / 6.54 | 8.07 / 9.93 | 7.90 / 9.94 | 8.04 / 10.25 | 7.92 / 9.58 | 7.35 / 9.51 | 6.56 / 8.27 | (no frost) |
| controls | 5.52 / 6.69 | 8.58 / 14.55 | 8.80 / 14.72 | 8.74 / 14.58 | 8.86 / 10.68 | 8.41 / 15.07 | 8.10 / 9.80 | 9.06 / 12.04 |
| tab-bar | 8.05 / 9.87 | 10.51 / 13.48 | 10.40 / 13.35 | 10.54 / 13.38 | 10.28 / 13.39 | 10.14 / 13.05 | 9.92 / 13.09 | 10.55 / 13.61 |

GPU (the kernel's work periods per scene window, `gpu_scenes.py`): busy 6 /
20 / 8 percent of the segmented scene flat / liquid / both off (1.01 /
3.27 / 1.27 ms a frame at 434 MHz), controls 6 / 32 percent (0.96 / 5.38
ms), tab bar 58 / 69 percent (9.7 / 11.6 ms; the clock rises 437 -> 630
MHz): the GPU is not what the segmented and controls frames wait for, and
the tab bar page is GPU-heavy already flat. Raster thread per frame (one
systrace launch each, self ms; DoDraw inclusive):

| scene / build | DoDraw | SurfaceFrame::Encode | Canvas::saveLayer (count) | QueueSubmit (count) |
|---|---|---|---|---|
| segmented flat | 5.14 | 1.84 | 0 | 1.52 (1) |
| segmented both off | 6.51 | 2.75 | 0.05 (0.3) | 1.66 (1.1) |
| segmented liquid | 8.07 | 3.34 | 0.69 (3.8) | 1.96 (2) |
| controls flat | 5.62 | 2.10 | 0 | 1.60 (1) |
| controls frost 0 | 8.32 | 3.08 | 1.08 (8.2) | 2.09 (2) |
| controls liquid | 9.71 | 3.46 | 1.97 (8.2) | 2.27 (2) |

Reading:
- A backdrop filter costs this phone about 0.75 ms of raster CPU, not
  0.3: the bar's and the lens's filters each add 0.73 - 0.79 ms alone and
  1.5 together. That is its two saveLayers (~0.18 each: Impeller ends the
  pass to read the backdrop), its share of the encode, and - paid once,
  by the first filter of a frame - a second queue submit (1 -> 2 a frame,
  +0.3 - 0.45 ms).
- Segmented, +2.5 ms p50: the navigation bar's filter (0.75), the lifted
  lens's filter (0.75), and ~1.0 ms that the liquid tier spends with no
  filter at all (both off; encode +0.9), of which the lens's content copy,
  its clip and capture are 0.2 - 0.3 (lens copy / clip off, all four off
  7.74 / 9.45); the rest is not attributed further (the platter's opacity
  layer, 0.3 a frame, is the one other offscreen layer).
- Controls, +8 ms p95: the tail is the knob's and thumb's lifted glass
  (p95 14.6 -> 10.7 without it); 2.5 ms of it is the frost's blur pass
  while the small lens lifts or settles (saveLayer self 1.97 -> 1.08 ms a
  frame with the frost at 0; a frost under `shaderSofteningMaxDeviceSigma`
  is already softened in the shader). The p50 does not move.
- Tab bar: no part of the lens moves the p50 by more than the spread; the
  lens's filter and the bar's are the cost, and the GPU is near its clock
  ceiling there.
- Not cut: every filter left in these scenes reads what is painted under
  it (bar over the list, lens over the track and labels, knob over the
  track), and the frost is measured (unlifted blur 6). What would move them
  is engine work - a cheaper backdrop read than a pass break, or a blur
  that does not cost a pass per step on the raster thread - or fewer
  layers by design, not a pixel-identical change in the package.

### Q2: raster ties (raster_phase.dart, landed)

A nearest-sampled matte whose texel edges fall on the pixel centers reads
one texel or the other depending on how the GPU rounds: the host's
Impeller mixed rows of one own layer anywhere from 60.499 to 60.500003
device px (an exact half), and the iPhone's 0.7 menu button (an exact half
at 3x) read the other texel than the container predicted, one device
pixel off (max 123). Now `glassRasterPhase` takes the origin as the final
pass receives it (32-bit) and resolves a pixel center on a texel edge to
the texel before it (as Metal and SwiftShader do), and a layer whose own
grid falls within `glassRasterTieBand` (1/64 device px) of the pixel
centers moves its texel grid onto them (`GlassRasterGrid.bias`) and shifts
its shapes so that they read the phase that rule gives: own layers and
container members are then the same function of the origin on any GPU. A
matte encoded on its own grid that comes to rest within the band is
encoded again (the compositor watch now checks every layer), so the
result does not depend on when the last paint fell. A matte drawn from a
field keeps its grid.

- Host Impeller (example/test/raster_phase_host_test.dart): a container
  member against its own layer at nine origins from 60.49 to 60.51 device
  px: 0 everywhere (86 - 88 at 60.499 - 60.500003 before).
- iPhone 16 Pro, container vs a build whose containers admit nothing:
  menu-resting 123 -> 2 and 9 (two launches; 7 - 9 run to run). Own layers
  change only inside the band: 1 pixel at 51 in controls-resting and
  switch-knob-held, nothing else above the launch noise.
- Pixel 6a base -> cand: controls-resting / slider / switch 53 on 389
  pixels of one container member (0.015 percent), menu-resting 27 on 14,
  sheet-medium 4; segmented-resting 72 on 108 pixels of one glyph (the V
  of the VIP segment, no glass there, both launches alike; not explained).

### Q3: scaled containers (glass_container.dart, sheet.dart, landed)

Under a scale no single shift serves members at different fractions of a
device pixel from the container: a pixel reads the texel before or after
a member's own texel edge depending on where in that texel it falls, and
under a scale that varies pixel by pixel. So containers stay closed while
they are drawn scaled: `MorphGlassContainerGate` (internal) closes every
container below it, and the sheet keeps it open only while it draws its
content unscaled (docked, not zooming, not scrubbed) - a floating sheet's
members draw their own layers, a docked one's share the container, in the
same frame. The gallery's plain sheet has its buttons in a container again
(1198f5c reverted): the audit's medium detent floats, so the census stays
at 5.15 filters a frame and sheet-medium within 1 - 4 of the base (Pixel)
and 0 - 2 (iPhone); at the large detent the three buttons share one
filter. Other package transforms (push zoom, flights, context-menu
previews) scale only while they move: a container in them is off by up to
a device pixel during the motion and lands back on its grid.

### Q4: the prominent button in the row container (landed 2026-10-06)

The layer already has a tint-only variant (per-shape tint in the material
map, SHAPE_TINT). Letting a member join when its appearance differs only in
tint takes the controls row's prominent button into the container: 3.89
-> 2.89 filters a frame, Pixel 6a raster p50 / p95 8.78 / 15.06 -> 8.25 /
14.56 (cand -> cand4, same session), GPU work unchanged (5.37 ms a frame:
the material pass costs what the filter did), iPhone 16 Pro controls 1.56
/ 2.29 -> 1.46 / 2.11. Not exact: host Impeller max 1 on 300 - 900 channels
of every member (the tint read from an 8-bit map instead of a uniform),
iPhone max 7 on ~100 rim pixels of the prominent button (none over 15). Landed by
the coordinator under the owner's rule for the optimization night (a
practically invisible difference that saves work is accepted): a member
whose appearance differs only in tint joins
(`own.copyWith(tint: appearance.tint) != appearance` in
`MorphGlassContainerLink._joinable`); test/glass_container_test.dart pins
the tinted member in the shared layer.

Timings of the landed state (Pixel 6a, 2 launches each ABBA, raster p50 /
p95 ms, base -> cand): home-scroll 8.24 / 11.18 -> 8.30 / 11.15, segmented
8.27 / 10.17 -> 8.47 / 10.55, tab-bar 10.51 / 13.35 -> 10.54 / 13.50,
controls 8.51 / 14.99 -> 8.78 / 15.06, menu 9.08 / 15.85 -> 9.16 / 15.98,
sheet 9.55 / 14.43 -> 9.69 / 14.12: within the launch spread (cand4,
built from the same tree plus Q4, reads 8.12 / 10.20 segmented and 8.96 /
15.88 menu). iPhone 16 Pro within 0.1 ms everywhere.

## Menu fusion: the device gap and the fusion ahead (2026-10-06)

The menu fusion field (`morphMenuSilhouette`) cost the Pixel 6a's menu
p50 2.8 / p95 9 / max 16 ms a fusing frame (liquid; flat p50 3.7, max
30), 4 - 10x its tight-loop time. Evidence: perf/2026-10-06-fusion-probe
(integration_test/fusion_probe.dart over the 108 + 218 fusions the
gallery's rich menu makes per two opens, recorded at the Pixel's and the
iPhone's logical sizes and rates; support/fusion_inputs.dart) and
perf/2026-10-06-fusion-ab (the menu frames A/B below).

WHY THE DEVICE IS 4 - 12x THE BENCHMARK (us per fusion, mean over the
recorded inputs, profile AOT):

| where / how | macOS M-series | iPhone 16 Pro | Pixel 6a |
|---|---|---|---|
| tight loop (warm, back to back) | 187 | 201 | 433 |
| pinned: X1 / A76 / A55 | - | - | 384 - 403 / 700 - 707 / 3390 - 3441 |
| paced: one per frame, app idle | 200 - 1029 | 850 - 888 | 5311 |
| paced, 16 MB of caches evicted first | 205 - 1060 | 719 - 725 | 2293 |
| paced, 4 ms of busy work first | - | 646 | 3194 |

- Core placement and clock (DVFS), nothing else. A paced call's thread
  CPU time equals its wall time (no preemption) and it runs 4 - 12x
  slower than the same call in a loop; on the Pixel `sched_getcpu` puts
  the paced calls mostly on the A55 / A76 cores (by cpu: 5 105x 3.9 ms,
  0 72x 6.1 ms, 4 71x 2.8 ms; the X1 cores 6 / 7 429 / 919 us), and a
  pinned A55 is 8.9x a pinned X1. Work right before the call (a busy
  spin, or the cache eviction loop itself) raises the clock and moves
  the thread up: evicting 16 MB of cache makes the call FASTER (5.3 ->
  2.3 ms), so cache misses are not the gap. Even the Mac shows it once the
  app is in the background (paced 200 -> 1029 us between two launches).
- Not the grid: the grid is in logical pixels, the same at DPR 2.6 and 3.
  Not JIT: every number is a profile AOT build. Not GC: the per-frame
  dumps put no GC in the p95 builds (menu-button.md).
- The benchmark's shapes are cheaper than the menu's: the recorded
  fusions cost 27 - 480 us on the Mac; the dearest are the open's tail
  (radius 1 - 7 pt at the full 256 x 540 menu, the step clamped at 2 pt:
  9k field nodes, 5 - 7k trace nodes, little blur), 2.3x
  `outline_us menu10-r4`.
- Where a fusion's time goes (macOS AOT, address samples): the separable
  blur ~30 percent, the field loop ~30, the near-block loop ~20, the
  trace ~13 (half of it the path's FFI calls), the samples ~6.

THE FUSION AHEAD (`MorphFusionWorker`, menu_fusion_worker_io.dart;
profile and release builds with isolates; debug, tests and the web keep
the frame's own fusion). The motion is a function of time, so each frame
the menu predicts the next three frames' times
(`MorphMenuFusion.prefetchFrames`: the least-squares line through the
trailing frames whose steps are within a quarter of the median step -
frame times jitter around the period, and a dropped frame or a read at
an event's time must not bend the line), peeks its shapes, kicks and
fusion radius there (time and kicks restored), and posts the fusions to
a pool of up to four background isolates. A worker computes the
outline's parts - field samples (sent without a copy) and the contour
loops; dart:ui's Path cannot be built off the root isolate - and the
frame builds the Path from the loops. The frame serves the newest
arrived fusion whose eleven inputs are each within
`MorphMenuFusion.prefetchTolerance` (0.02 pt) of its own and whose radius
samples the same grid with the same kernel (`sameGrid`); otherwise it
fuses its own, exactly as before.
- NEAR, bounded by construction: a served outline is the exact fused
  outline of the motion at the predicted time, a fraction of a
  millisecond from the frame's. Every served frame of one final launch
  per device re-fused on the host from the harness's pairs (menu_frames
  `fusion_calls`, test-only hook `MorphMenuFusion.debugOnFuse`): outline
  distance p50 0.018 / p95 0.023 - 0.024 / max 0.031 - 0.060 pt on the
  iPhone (liquid and flat, 670 + 772 frames; at most 0.18 device px) and
  p50 0.018 / p95 0.023 / max 0.028 - 0.054 pt on the Pixel (372 + 319;
  0.14 device px). An earlier one-ahead run met one 0.28 pt case:
  a neck forming (radius 8.8, the button 20 pt over the menu's top),
  where the exact law itself moves that far between two inputs ~10 us of
  motion apart.
- UI cost of a served frame: the Path from the loops (one quad per
  crossing off the straight runs). Probe, paced (one fusion a frame, the
  next one requested the frame before): iPhone 38 - 45 us against 850 -
  888 us fused in the frame; Pixel 183 - 196 us against 7.5 - 8.4 ms;
  99 - 107 of 108 served.
- Gallery menu (menu_frames: the rich menu opened and closed twice per
  run, 5 runs per launch, two launches each, median per launch; off =
  the same build with `--dart-define=FUSION_PREFETCH=false`), build ms
  p50 / p95, served share:

| device / tier | off | on | served |
|---|---|---|---|
| iPhone 16 Pro flat | 0.74 / 2.45, 0.74 / 2.42 | 0.76 / 1.57, 0.76 / 1.52 | 64 - 66 % |
| iPhone 16 Pro liquid | 1.34 / 2.67, 1.36 / 2.67 | 1.34 / 2.32, 1.31 / 2.28 | 56 - 60 % |
| Pixel 6a flat | 2.51 / 12.03, 2.67 / 12.37 | 2.61 / 11.22, 2.46 / 10.90 | 55 - 56 % |
| Pixel 6a liquid | 5.50 / 13.97, 6.04 / 15.06 | 5.75 / 13.25, 5.97 / 13.62 | 65 - 69 % |

  Raster and frames over budget move within the launch spread. The
  misses: on the iPhone the fast part of an open, where 0.05 - 0.1 ms of
  timing error is more than 0.02 pt of motion; on the Pixel the first
  frames of an open or close, whose fusions come back late while the
  workers wake on slow cores. The Pixel's build p95 frames are mostly
  other work (the opening frames, the rows), so its p95 moves ~1 ms; its
  fusing frames that are served drop from the paced cost above to ~0.2
  ms. Steps that did not help on the Pixel: one prediction a frame (41 -
  55 % served), an adaptive one- or two-frame horizon (45 - 48 %), two
  or three predictions a frame on the plain least-squares line (45 - 55
  %: the line through an open's irregular first frames pointed tens of
  points ahead).
- KERNEL REACH: `reachOf` subtracts 1e-9 before the ceiling. Where the
  step is a third of the radius, 3r / step lands a rounding error either
  side of 9 and the kernel flipped between 19 and 21 taps frame to frame
  (9 of the 326 recorded fusions); the outline moved by up to 0.035 pt on
  those frames (0.23 pt at a neck in the served pairs above). Now 19.
- Resting frames never fuse (radius 0) and are untouched; the timed
  menu shots of the audit already move between launches of one app, so
  the device proof is the re-fused pairs above, not shots.
- Same-pixel changes in the same commit: a straight run of crossings is
  one line instead of collinear quadratics (156 path verbs instead of
  ~745 on the tall menu; same point set), and the optical turn's per-axis
  terms are computed once per column and row (bit-identical fields, 326
  of 326 recorded inputs before the reach fix).
- Tried and dropped: deferring the blur into batched, four-way
  interleaved passes (bit-identical, no faster: 69 against ~65 us a
  fusion, the memo bookkeeping is the work); tracing on the field grid at
  stride 2 (0.1 - 1 pt off at a 4 - 8 pt step); raising the plain-union
  cutoff (0.11 pt at radius 2: over a quarter device pixel); a Flutter
  GPU field pass (the outline path is needed on the CPU the same frame -
  the body shadow, fake and flat glass clip to it - so the field would
  still need a CPU trace or a readback).

## The lifted lens's frost, the segmented remainder, the second submit (2026-10-06)

Three questions left by "Raster ties" Q1. Evidence:
perf/2026-10-06-pixel6a-frost-{seed,seed-parity,final},
perf/2026-10-06-iphone-frost-{seed,final},
perf/2026-10-06-pixel6a-segmented-ablation.

### F1: the small lens's frost (landed)

Not the blur's sigma but where it reads. A blur composed under the glass
shader (`ImageFilter.compose(inner: blur, outer: shader)`) gets no coverage
hint (Flutter 3.47.2: the runtime-effect filter asks its input for a
snapshot without a limit, impeller/entity/contents/filters/
runtime_effect_filter_contents.cc), so the Gaussian downsamples and blurs
the WHOLE pass the backdrop comes from, then re-rasterizes it for the
shader; a lifted knob's frost animates (UIKit's resting 6 pt to 0 over the
lift), so every frame's padding resizes those full-pass targets. Systrace:
frames with the frost spent 3 - 10 ms in that one saveLayer (p90 / p95 of
saveLayer self time per frame 4.4 / 6.6 ms in controls).

A lifted lens, knob or thumb now blurs a copy of its own surroundings
(`LiquidGlassLayer.blursOwnBackdrop`, set by the widget layer on the
lifted glass only): while its frost needs a blur pass, the layer pushes a
clip of the filter clip grown by the blur's reach (1.732 x the engine's
scaled sigma + the texels its downsample adds, on the 64 px buckets) and an
identity color-filter backdrop under it, the same seed the opacity probe
uses; the blur then reads that small pass, and the shader's fragment
coordinates start at the seed pass's origin (floor of the seed clip and
the clips above it in device pixels). Inside a backdrop group or an
opacity-seeded pass it blurs as before. The frost value is unchanged
(UIKit's `unliftedBlurRadius`).

Pixels (shader harness, `SHADER_SEED_AB=true`: the same runtime shaders
with and without the seed; cases lens-frost-rise / -quarter / -half / -late
= lift 0.1 at visibility 0.4, 0.25, 0.5, 0.85, frost 5.4 .. 0.9 pt): Pixel
6a Vulkan max 1 step (3 - 546 pixels of 1.59 M), host Impeller max 3; every
other case 0. The rest of the difference is the downsample grid's phase
(it follows the seed's origin instead of the pass's). Audit shots within
run-to-run noise on both phones (the held shots are fully lifted).
example/test/frost_seed_host_test.dart pins the seed (two filters, a color
filter first) and max 3 on the host.

Timings (raster p50 / p95 ms, over budget, ABBA 2 + 2 launches, mean):

| scene | Pixel base | Pixel after | iPhone base | iPhone after |
|---|---|---|---|---|
| controls | 8.12 / 14.28, 10 | 8.44 / 11.77, 0.5 | 1.49 / 2.11 | 1.51 / 2.22 |
| segmented | 7.92 / 9.92 | 8.16 / 10.04 | 1.37 / 1.68 | 1.35 / 1.65 |
| tab-bar | 10.46 / 13.53 | 10.42 / 13.39 | 2.04 / 2.57 | 2.06 / 2.56 |
| menu | 8.64 / 15.40 | 8.95 / 15.69 | 1.62 / 2.52 | 1.65 / 2.60 |
| sheet | 9.16 / 14.23 | 9.33 / 13.86 | 1.91 / 2.62 | 1.89 / 2.61 |
| home-scroll | 7.83 / 10.73 | 8.14 / 10.68 | 1.49 / 2.24 | 1.51 / 2.28 |

The Pixel's controls tail goes: p95 -2.5 ms, frames over budget 10 -> 0.5,
raster p99 (systrace DoDraw) 17.4 -> 13.3 ms, saveLayer self p95 6.6 ->
2.6 ms, GPU 5.38 -> 5.10 ms a frame; the other scenes are within the
launch spread. The iPhone (Metal) gains nothing: its controls p95 is +0.1
(within its 2.08 - 2.43 base spread), the seed is one more backdrop read
there for a blur Metal already does cheaply.

Rejected:
- Seeding every frosted layer (bars, menus, sheets): GPU -0.7 / -1.0 ms on
  the Pixel's tab bar / sheet, but raster p95 +1.7 (tab bar), +3.3 (menu),
  +6.3 (sheet) on the Pixel and +0.2 - 0.3 on the iPhone: a still frost
  keeps its full-pass targets cached, and the seed is one more backdrop
  read (perf/2026-10-06-*-frost-seed, cand).
- The frost inside the final shader (a few-tap blur over the sampled
  backdrop): the filter input is sampled nearest
  (impeller/display_list/image_filter.cc: the input's sampler is the
  default), so a sigma of 4 - 16 device px needs a 2D kernel; offline
  against a Gaussian a 7 x 7 grid is off by 14 - 33 steps on edges and up
  to 70 on noise, 11 x 11 by 5 - 19 and ~40 (scratch simulation of the
  harness bands and a track edge). malioc (Mali-G78, Vulkan) puts the
  kernel alone at 6.3 / 13.9 / 32.8 texture cycles a fragment for 25 / 49 /
  121 taps at 50 % occupancy: cheap on a 100 x 70 px lens, but not near.
  A separable pair of runtime-effect passes would be near but runs over
  the whole pass for the same missing hint.

### F2: segmented without filters (attributed; the platter landed)

Systrace per build (perf/2026-10-06-pixel6a-segmented-ablation; DoDraw
mean ms a frame, flat 5.39): navigation bar flat + no lens glass 6.12,
then without the lens's content copy 5.83, without its capture 6.16 (noise),
without its clip 5.80, without the platter 5.13 (= flat); navigation bar
and segmented controls flat 5.21 - 5.27. So the remainder is the lens copy
(~0.3, its strips replaying the content) and the platter (~0.7): the resting
platter fades through an opacity layer while the lens lifts or lands - an
offscreen pass that also forces the frame's second queue submit when no
filter does (frames with it 7.1 - 7.2 ms vs 5.5). Nothing else (no shadow,
text, preroll or picture cost) separates the tiers.

The platter now fades by the alpha of its fill and shadow (the opacity
layer only hides it at full glass). Not exact: where the faded shadow
lies under the faded fill the result is darker by shadow alpha (0.1) x
opacity x (1 - opacity) of the backdrop, at most 0.025 x 255 = 6 steps
over white at half opacity, during the first quarter of a lift. Systrace
segmented: saveLayers 3.78 -> 3.49 a frame, encode self -0.3 ms; the audit
p50 / p95 is within the launch spread.

### F3: the second queue submit (engine, not changeable here)

The extra vkQueueSubmit comes from Impeller, not from the renderer's
Flutter GPU work. With any backdrop filter or offscreen layer the frame
renders offscreen first: those command buffers are batched and flushed in
`Canvas::EndReplay` (inside SurfaceFrame::Encode, 1.4 ms on the Pixel),
and the onscreen buffer goes to the swapchain as its final command buffer
at present (0.47 ms); a frame without offscreen work submits once, at
present (1.42 ms) - impeller/display_list/canvas.cc EndReplay,
renderer/backend/vulkan/surface_context_vk.cc SubmitOnscreen. The
geometry passes' Flutter GPU submits are on the UI thread, already at most
one a frame (0.76 a frame in segmented, about 1 ms there), and never
reach the raster thread's batch. Merging them is engine work.

## The Mali offline compiler batch (2026-10-06)

The audit items that waited for Arm's malioc (Mali Offline Compiler
v2026.5.0, Mali-G78 r1p1, driver r51p0; owner approved the install):
F1 / astra 4 (uniform-only color constants), F7 / astra 12 (variants),
F8 (uniform-only expressions). Evidence: perf/2026-10-06-shader-f7-*,
perf/2026-10-06-shader-f1-*, -shader-f1rerun-* (the first F1 Pixel bench
recorded a trace without GPU work periods), perf/2026-10-06-pixel6a-
malioc-f7 (end to end; liquid-before*, -after* = F7, -f1*); GPU work
traces in /tmp/morph-perf/gpuwork, not committed.

OFFLINE GATE (tool/audit/shader/offline.py, malioc on the GLES 3 source
and the SPIR-V of every final, fake, geometry, field and material
variant; `--tree name=dir` compares any shader trees). Baseline before
the batch (e953244), Vulkan, cycles per fragment longest / total
arithmetic, work registers, occupancy:

| shader | A longest / total | registers | occupancy |
|---|---|---|---|
| final (one appearance) | 11.75 / 13.75 | 46 | 50 % |
| final tint | 12.23 / 14.25 | 50 | 50 % |
| final material | 15.38 / 17.38 | 63 | 50 % |
| fake surface | 4.85 / 5.48 | 28 | 100 % |
| geometry (loop) | - / 33.0, LS bound | 64 | 50 % |
| field | 2.73 / 2.88 | 32 | 100 % |
| material gradient | - / 13.25 | 64 | 50 % |
| tint gradient | - / 22.0 | 64 | 50 % |

GLES matches within 0.05 cycles. Every shader reports uniform
computation and the final ones use all 128 uniform registers: the Mali
driver evaluates uniform-only expressions once per draw (they cost
uniform registers, not fragment cycles). The final shaders were at 31 /
32 registers (full occupancy) before the 2026-10-05 audit batch;
feb934d (coverage once) and 5ec645f (step picks) pushed them over 32,
which halves the threads a core keeps in flight. malioc's longest path
takes every uniform branch (dispersion, shrink), which a regular surface
never runs: read the register count and the total, not the longest path,
for those.

F7, KEPT (a34e57b): the one-appearance and tint-only programs compile
one color model family: DIRECT_MODEL (morph's lifted lens, knob, thumb)
or IOS27_MODELS (every other surface); the material variant keeps both.
Five programs instead of three (`ShaderKeys.liquidGlassRenders`, all
warmed). Splitting by optics instead (no dispersion / shrink / soften)
moves only the longest path and leaves the union at 46 registers: the
registers come from the direct and the iOS 27 color paths living side by
side.

| variant | before A / regs / occ | after A / regs / occ |
|---|---|---|
| one appearance, direct | 11.75 / 46 / 50 | 9.25 / 32 / 100 |
| one appearance, iOS 27 | 11.75 / 46 / 50 | 10.50 / 32 / 100 |
| tint, direct | 12.23 / 50 / 50 | 9.40 / 32 / 100 |
| tint, iOS 27 | 12.23 / 50 / 50 | 10.94 / 32 / 100 (GLES 44 / 50) |

Pixels: 0 on every case, Pixel 6a Vulkan and GLES, iPhone 16 Pro Metal,
host Impeller. GPU per layer (median paired, vs the union in the same
app): Pixel cycles regular-dark +5.3, lens +5.4, tint +5.1, big-sheet
+3.5, menu +1.7 percent (mixed-models, whose program did not change,
+2.4; fake -0.5); iPhone wall big-sheet +1.9 (all eight blocks
positive), the small cases within their noise. End to end (glass_audit,
liquid, 5 runs a launch, four ABAB pairs, e953244 vs a34e57b): no raster
change - every scene's p50 / p95 / over budget within the launch spread
(e.g. tab-bar p95 14.48 -> 14.26, sheet 15.25 -> 14.48, menu 15.55 ->
15.45 ms, means of the four launches); the first pair's home-scroll p95
+3 ms did not repeat in the second (11.40 -> 11.37). These scenes are CPU
raster bound, as for the 2026-10-05 batch. Precache 491 -> 601 ms (mean,
spread 399 - 789): two more programs to warm.

F1, REJECTED (6cdd2f3, reverted by cc37658): the iOS 27 one-appearance
and tint-only programs read the untinted wash, the face transfer, the
dark border gain and the glint target from uniforms 65 - 74 resolved by
`LiquidGlassColorModel.faceTransfer` / `contourScale`, written only to
programs that declare them (so the frozen baseline and the material
variant keep their layout and the same-app A/B worked). malioc: -0.025
cycles, no register change - the driver already evaluated them once per
draw. Pixels max 1 step on 1 - 11 pixels (Pixel Vulkan = GLES, iPhone,
host). GPU vs F7 in the same app: iPhone wall big-sheet +2.7, menu +2.3
(7 of 8 blocks each); Pixel cycles regular-dark -9.1, big-sheet +0.7,
menu +1.3, tint +1.6 (unchanged programs -1.7 .. +2.6); end to end within
the spread. No gain on the weak device, so the per-pixel face stays.

F8, REJECTED OFFLINE: `a / uniform` as `a * (1 / uniform)` (screen and
matte UVs, contour integral, glint profile) gives identical malioc
cycles - the compiler already multiplies by a hoisted reciprocal - so no
device run. The geometry pass's per-pixel smoothing budget as a uniform
saves 0.25 load / store cycles a shape on empty pixels (0.72 -> 0.56
shortest path), but the harness cannot A/B the Flutter GPU bundle (both
variants share it) and the pass runs only on geometry changes: not done.

## Energy: ADPF and the fusion workers (Pixel 6a, 2026-10-06)

The owner's criterion: beautiful AND no extra heat or battery drain for
an app using the package; energy is the primary metric, frames second.
Evidence: perf/2026-10-06-pixel6a-energy (fusion workers, this branch)
and perf/2026-10-06-pixel6a-adpf-energy on branch exp/adpf (ADPF, with
its experimental client example/lib/perf/adpf.dart).

METHOD (perf/energy_android.sh, energy_android.cfg, energy.py): every
launch of a profile audit APK under a Perfetto trace of the ODPM power
rails (14 rails polled every 100 ms: CPU big / mid / little, GPU, DDR,
memory interface, fabric, display, ...), cpufreq, cpuidle and sched;
energy.py splits the cumulative rails by the report's scene windows
(`windows_us`, CLOCK_MONOTONIC mapped through the trace's clock
snapshots), and from the same windows the time-weighted cluster clocks
and where the UI (main) and raster threads ran. Variants interleaved
(ABBA), each launch from a skin below 37 C (it ends at 38 - 39), liquid
tier, AUDIT_RUNS=5, no shots. The phone sat on AC with the battery full
and not charging (status 4, level 100); the rails measure the PMIC
outputs either way. Launch spread per scene and variant 1 - 6 percent of
the total (idle up to 26: no app work, background noise).

THE HARNESS IS NOT IDLE: the integration test's live binding
(`LiveTestWidgetsFlutterBinding.handleDrawFrame`) schedules a frame after
every frame, so every audit scene carries ~60 fps of empty frames
between its gestures (1 799 frames in 30 s on a still home page); the
energies below are scene + that floor, on both sides of every A/B.
`AUDIT_IDLE_S=60` measures the real rest: the binding's benchmark policy
for 60 s (no frames scheduled: 14 - 15 frames, the app's threads 3 ms of
CPU) and then 30 s of the live loop. Home at rest 286 mW for the whole
phone (display 133, CPU 50), under the live loop 464 mW: the package
draws nothing at rest.

ENGINE (Flutter 3.47.2, engine a804b26164): no ADPF anywhere (no
APerformanceHint / PerformanceHintManager in the engine or the
embedding). The UI thread is the platform thread (merged since 3.29) with
no affinity request; the raster thread asks for the non-efficiency cores
and setpriority -5 (android_shell_holder.cc). Android 17's HWUI opens its
own hint session (tag 2) on the main thread with its RenderThread, but
reports only HWUI's frames, not Flutter's.

ADPF EXPERIMENT (rejected): two sessions from Dart FFI into libandroid
(the UI thread, `1.raster`), target the measured cadence (16.67 ms), the
build and raster durations of every FrameTiming reported as they arrive
(every 100 ms in profile, every second in release); ~16 500 reports a
launch, 0 errors. `eff` adds setPreferPowerEfficiency. Medians of 4
launches, total mJ / frames over budget / build p95 / raster p95:

| scene | off | on | on vs off | eff |
|---|---|---|---|---|
| idle 60 s (no frames) | 17143 | 18658 | noise (+9 %, spread 26 %) | 17623 |
| idle-frames 30 s | 13932 | 13800 | -1 % | 14715 |
| home-scroll | 29477 / 2 / 6.41 / 11.37 | 29416 / 2 / 6.32 / 10.93 | 0 % | 31665 / 2 |
| segmented | 20855 / 0 / 7.87 / 10.21 | 20483 / 0 / 7.74 / 10.28 | -2 % | 23067 / 1 |
| tab-bar | 84880 / 8 / 9.21 / 14.07 | 82127 / 4 / 9.01 / 13.63 | -3 % | 82001 / 2 |
| controls | 21739 / 2 / 13.29 / 12.11 | 21876 / 1 / 9.87 / 11.80 | +1 % | 24935 / 2 |
| menu | 17465 / 16 / 15.72 / 16.01 | 19068 / 4 / 7.74 / 11.88 | +9 % | 22540 / 4 |
| sheet | 25930 / 6 / 7.52 / 14.48 | 26726 / 2 / 2.66 / 11.94 | +3 % | 29559 / 2 |

- What ADPF does here: it moves the UI thread off the A55s. Menu UI thread
  CPU ms little / mid / big 7490 / 2246 / 668 -> 1817 / 2227 / 2257,
  sheet 4655 / 1478 / 312 -> 0 / 1912 / 1090; the mid and big clusters
  run 540 -> 730 MHz. Fewer CPU seconds on dearer cores: the menu's CPU
  rails 4.1 -> 5.2 J. The frames gain (menu over budget 16 -> 4, build
  p95 halved; sheet 6 -> 2) and the energy rises where the gain is: menu
  +9 percent (the launches do not overlap: 17.3 - 17.8 J against 18.8 -
  19.4), sheet +3 percent. The tab bar's -3 percent is a shorter window
  (fewer late frames, 50.5 -> 48 s) at the same power.
- `eff` (prefer power efficiency) is worse: the work stays on the small
  cores at higher clocks (tab bar little cluster 656 -> 1057 MHz, CPU
  rails 8.8 -> 15.9 J), +6 to +29 percent in every scene but the tab bar
  (-3 percent, its window 50.5 -> 43 s).
- GATE (frames down AND energy equal or lower): fails on the menu and
  the sheet. ADPF stays out of the package; the client and the evidence
  live on exp/adpf. What would have to change for a retry: a report path
  without the second-long release batching (an engine-side session, or
  the UI build timed in-process), and a session that boosts only the
  frames that miss, not the whole menu.

THE FUSION WORKERS (kept, owner's call; perf/2026-10-06-pixel6a-energy):
they run only while the menu fuses (an open or close; resting frames
never fuse). The menu scene alone, 40 transitions a launch, 4 + 3
launches per variant:

| variant | total mJ | worker CPU s | build p95 | over budget | served |
|---|---|---|---|---|---|
| off | 34063, 34241 | 1.3 | 17.23, 16.14 | 20, 18 | 0 |
| on: 3 frames ahead (shipping) | 36098, 35789 | 13.4 | 14.66, 15.17 | 15, 15 | 59 % |
| 1 frame ahead (local build) | 33957 | 5.4 | 17.52 | 18 | 45 % |

- The shipping pool costs 4.5 - 6.0 percent of the menu scene's energy,
  ~40 - 50 mJ a transition, mostly CPU (+0.8 - 1.3 J) and memory (+0.3 -
  0.5 J): the workers burn ~12 s of CPU a launch, about 3.7 ms a
  speculative fusion on the small cores, three fusions a fusing frame of
  which at most one serves; the UI thread's CPU time does not fall
  measurably (20.5 -> 20.4 s). For that: 3 - 5 fewer frames over budget a
  launch (one per 8 - 13 transitions) and build p95 -1 to -2.5 ms.
- One frame ahead costs nothing (-0.8 percent, inside the spread) and buys
  nothing (over budget 18 = off, build p95 not better). The energy is
  the speculation, so the lever if the pool must cost less is the number
  of predictions, not when the pool runs. Left as is: owner's decision.
- Reading for the earlier frame-only A/B ("Menu fusion: the device gap"):
  its build p95 gain holds; it is not free.

PERFETTO TRAP: after a run that wrote tracefs directly (audit_android.sh
`AUDIT_GPUWORK=1`) Perfetto's ftrace data source recorded nothing (no
sched, no cpufreq; the rails still came) until the phone was rebooted.
Check a short `perfetto -t 5s sched freq` trace has sched rows before an
energy run.

## Small blurs: the edge effect's band and the 2 pt frost (2026-10-06)

Found by the g1455 bench (tool/audit/g1455-review.md, idea 1): on the
Pixel 6a the hard scroll edge effect's 2 pt blur cost 7.6 ms of GPU a
scrolling frame (flat 8.48 ms against 0.88 without it), and the bars' 2 pt
frost another ~6.3 ms on liquid. Evidence:
perf/2026-10-06-pixel6a-smallblur-{bench,a,b,energy},
perf/2026-10-06-shader-smallblur-{vulkan,gles}-parity.

Cause, two engine paths (Flutter 3.47.2, gaussian_blur_filter_contents.cc):
- The blur trims its input to the region its output needs grown by the
  kernel (the coverage hint) only when that region lies inside the
  backdrop texture (CalculateDownsamplePassArgs); a band along the screen
  edge needs pixels above the screen, so the WHOLE pass is blurred. Probe
  (bench abl1/abl2, BackdropFilters without a clip blur the whole screen
  too): an unclipped 2 pt blur 8.80 ms, the edge effect 7.97.
- Below a device sigma of 4 sqrt 2 (5.66 px, after the engine's sigma
  correction) CalculateScale rounds the downsample to 1: full resolution.
  2 pt at 2.625 dpr is 5.21 px. The same blur at 2.2 pt (half resolution)
  costs 3.81 ms against 8.80. At 3x (iPhone) 2 pt is 5.96 px, already half
  resolution.
- A frost composed under the glass shader gets no coverage hint at all
  (runtime_effect_filter_contents.cc, F1 above): the whole pass, at full
  resolution, per frosted layer.

What changed:
- The edge effect pushes a clip of its band grown by the kernel's reach
  (`morphBlurReach`: 1.732 x the device sigma + the down/upsample texels,
  in whole device pixels) and an identity color-filter backdrop
  (`morphBackdropSeed`, BlendMode.src) under its blur, so the blur reads
  that band-sized pass: the same full resolution Gaussian over the same
  pixels. An identity MATRIX filter as the seed does not work: the blur
  inside it read an empty pass on Impeller (host harness, unblurred
  band). An identity color filter as the blur's innermost stage instead
  of a seed trims too but leaves a transparent 1 px ring where the trim
  meets the texture edge (Contents::RenderToSnapshot's coverage
  expansion): 39 - 80 steps along the screen sides, rejected.
- A frost just below the half resolution threshold is raised to it, at
  most by 12 percent (`morphHalfResolutionSigma`, renderer
  internal/blur_reach.dart): 2 pt becomes 2.17 pt at 2.625; nothing
  changes at 3x or at 2x (where the raise would be 44 percent). Applied
  to every frost that does not blur its own backdrop (bars, menus,
  `frostControls`, the fake tier); the lifted lens keeps its seeded,
  animated frost. Seeding the bars instead (the lens's
  `blursOwnBackdrop`) measured 4.72 ms against the raise's 4.25 and drew
  the tab bar's rim up to 97 steps off on the device (255 on the host):
  the seed's pass origin is only right for the lens's geometry; not
  pursued.

Pixels (max channel step, bounded / raised against the old blur;
`SHADER_BLUR=true` on the shader parity runner, example/test/
blur_bound_host_test.dart on the host; support/blur_harness.dart):

| case | Pixel Vulkan | Pixel GLES | host Impeller |
|---|---|---|---|
| edge effect hard / soft, top / bottom, faded | 1 - 2 | 1 - 2 | 1 - 2 |
| tab bar (liquid, light, over noise) | 6 | 6 | 6 |
| toolbar / menu / half visible frost, liquid | 13 - 22 | 13 - 22 | 13 - 23 |
| the same, fake tier | 8 - 22 | 8 - 22 | 9 - 23 |
| bench scroll shots (real content): flat / fake / liquid | 1 / 3 / 2 | - | - |
| audit shots: home-scrolled / held, list, resting tab bar | 1 / 2, 0, 19 (A/A 19) | - | - |

The edge effect's 1 - 2 steps are the color matrix's half precision. The
frost's 13 - 23 are aliasing of the half resolution downsample on the
harness's 1 px stripes and noise (a faint moire); on real content 2 - 6.
iOS: untested (iPhone with the owner); at 3x the frost is unchanged and
the edge effect seed is the same Gaussian.

GPU (Pixel 6a, kernel gpu_work_period, ms a frame; bench = one binary,
seeds 20261011 / 20261012, 5 runs each; audit = liquid, 5 runs, ABBA):

| scene | before | after | busy before -> after |
|---|---|---|---|
| bench scroll, flat | 8.47 | 3.71 | 50 -> 22 % |
| bench scroll, fake | 11.31 | 6.44 | 67 -> 38 % |
| bench scroll, liquid | 11.15 | 6.28 | 67 -> 38 % |
| audit home-scroll | 8.14 | 4.46 | 49 -> 27 % |
| audit list | 9.92 | 7.68 | 59 -> 46 % |
| audit tab bar | 11.61 (623 MHz) | 9.33 (447 MHz) | 69 -> 56 %, Mcyc 7.23 -> 4.17 |
| audit controls | 5.00 | 4.97 | no frost, no edge effect |

Ablation (bench abl2, liquid without the edge effect): frost 0 2.83, 2 pt
9.14, raised 4.25, seeded 4.72, seeded + raised 4.10; flat edge effect
seeded 3.70, raised 3.62, both 3.10 (the raise on the edge effect: 10
steps on the device shot, 17 on the harness - kept exact instead).

Frame timings: raster p50 +0.3 (bench liquid) to +0.8 ms (bench flat,
the seed is one more backdrop filter for the raster thread); audit p50
home-scroll 8.16 -> 8.44, list 9.76 -> 9.96, tab bar and controls within
the launch spread; frames over budget unchanged (0 - 7 per run on both).

Energy (perf/energy_android.sh, liquid, ABBA, 2 launches each, median,
whole phone): home-scroll 906 -> 565 mW (GPU rail 11.95 -> 3.91 J), tab
bar 1683 -> 905 mW (54.0 -> 15.6 J), list 954 -> 705 mW (16.0 -> 7.3 J),
controls 623 -> 616 mW; the CPU rails do not rise (home-scroll big / mid
/ little 1.40 / 2.14 / 3.66 -> 0.85 / 1.33 / 2.30 J).

A/B switches: `debugMorphEdgeEffectBoundsBlur`,
`debugMorphHalfResolutionBlur`; the audit's `AUDIT_LEGACY_BLURS=true`.

## Tools

example/integration_test/glass_audit_test.dart (profile, dark; shots of
the reference states and per-scene FrameTimings in `<app tmp>/glass/`).
glass_density_test.dart (N glass buttons, `<app tmp>/glass_density/`) and
glass_phases_test.dart (FlutterTimeline BUILD / LAYOUT / PAINT /
COMPOSITING per frame, `<app tmp>/glass_phases/`) run through the same
audit.sh with `AUDIT_TARGET` / `AUDIT_REPORT`. In flutter_test:
test/perf_counts_test.dart (work counts, ceilings) and
test/glass_frames_test.dart (channel vs rebuild, pixel for pixel; with
`GLASS_FRAMES_OUT=<file>` it writes the frame hashes to compare commits).
`--dart-define=AUDIT_ATLAS=true` adds per-scene glyph atlas work from
the engine timeline (`atlas` in the report).
Scene windows: the audit's `scene:<name>:<run>:begin/end` slices,
`perf/atrace_slices.py <trace> --scenes` (trace_android.sh prints it),
the report's `windows_us` (the same windows on CLOCK_MONOTONIC) and
`perf/gpu_scenes.py <tier>.json` for the GPU work of an `AUDIT_GPUWORK=1`
run per scene,
and `AUDIT_CENSUS=true` for the layer census per scene in the report
(`AUDIT_CENSUS_OWNERS=true` names each backdrop filter's owner).
perf/shotdiff.py compares two runs' shots (mean, max, percent over 15);
the shader harness and its tools are under "Shader harness" above;
perf/contact.py lays several tiers' shots side by side.
Energy: perf/energy_android.sh runs audit APKs under a Perfetto power
trace, perf/energy.py splits the rails by scene (see "Energy: ADPF and
the fusion workers"); `AUDIT_IDLE_S` and `FUSION_PREFETCH` on the audit.
Glass inspector: `MorphGlassInspector` (public, debug and profile) is the
census for app developers - filters, captures, owners and container hints
of the last frame on screen, `MorphGlassInspector.census()` in tests; the
gallery's Glass renderer page toggles it. A release build removes it (the
macOS release App binary holds none of its strings).
Gallery: the root installs `MorphAdaptiveGlass` with the session's
`MorphGlassRenderer` (GalleryGlassSettings / GalleryGlassScope,
glass_settings.dart, tier null = auto, in GalleryApp's State); the Glass
renderer page edits them and shows the tier being drawn.

## Standalone stage measurement stand (2026-10-07)

`example/lib/perf/glass_stage_bench.dart` runs the production renderer in
profile/release without the gallery or integration-test binding. The
stdlib runner in `tool/ios_reference/perf/stage_bench/` restores the gallery
APK and owned device tracing state. GPU and energy have separate launches.
Raw timings include cheap frames; windows, shuffled order, production
filter bounds, pass sigmas and capture keys are retained. No renderer or
cache change. Usage: the stand's README.md; full smoke evidence and limits:
`tool/audit/codex-stage-bench-report.md`.

Pixel 6a Vulkan default smoke, base bdab3cb plus recorded stand source hash,
three repeats, one strip over animated tiles: bare/capture/optics GPU active
0.829/1.733/2.179 ms/frame; raw blur sigma 2/10 2.121/2.140; production
glass frost 2/10 3.570/3.123. All median over-budget counts are 0 at 60 Hz.
Expanded 36-case text/motion smoke confirms four separate filters/captures,
four filters with one shared key, or one merged filter/key. Short windows
are functional coverage, not grouping acceptance. Subtractions change
composition topology and cannot isolate native passes; filter output area
is not capture input dimensions, GPU memory or bandwidth. Glass-over-glass
and intervening content still need their own fidelity experiments.

## Current Android resource study (2026-10-06)

Source 8cfcd21, Pixel 6a Vulkan, 60 Hz. No renderer change. Three-run
separate GPU captures give flat/liquid Mcycles per active frame:
tab 1.050/4.142, controls 0.434/2.153, menu 0.687/3.289,
sheet 0.971/6.002. The liquid sheet clocks higher; compare cycles.
Current menu has mean 2.89 backdrop filters, sheet at most 7 filters
and 4 independent captures. Cached matte does not eliminate per-frame
capture/encoding. Native saveLayer calls/frame: tab 9.70, controls
6.21, menu 6.22, sheet 9.17 (includes picture-internal layers).

Three-run exact analytic-uniform counter probe finds no identical
native encodes. Sheet median is 16 encodes/run, with 51 clean paint
reuses; static retained layers also bypass paint. Field inputs were
excluded from exact duplicate detection. Animated menu ring storage
peaks at 16.22 MiB, broad page container at 16.50 MiB, uniform arena
at 0.57 MiB. Those figures exclude global released textures, fields,
engine targets and driver/scene references. Do not sum as actual RSS.

Inspect field-only unused analytic preparation and byte-budgeted
texture retention next. Same-frame retained picture replay need not
change fidelity, but must preserve current paint order and the full
sample/mirror domain. The existing content snapshot's unsupported-layer
toImageSync fallback is not a free generic backdrop provider. Raster
scheduled time already averages 8-10 ms/active liquid frame here;
CPU/GPU transfers need energy and limiting-stage checks, not equal load.

GC collections in the native trace do not overlap UI BeginFrame slices.
The VM probe reports current heap, not reliable allocation-rate counters.
energy.py now sums every matching app raster thread and flags old caches.
A failed launch left an extra recorder during the exploratory energy
runs; the runner now terminates its own recorder on early exit. Future
acceptance energy runs must start clean. Full protocol, rejected trace,
allocation limitations and evidence: tool/audit/codex-round4-resource-study.md.

## Round 3: flat edge effects and liquid controls (2026-10-06)

Scope: owner-approved flat fade/hairline only, and controls UI profiling.
The installed renderer's effective flat tier skips both the seed copy
and the edge backdrop filter; fake/liquid retain their ordinary blur.
Driven opacity and changes of tier update/release the retained layers.
Pixel 6a census maximum backdrop filters is 0 in all seven audit scenes.
Deterministic hashes change only for nav-scroll/flat, as approved.

Energy A/B/B/A, two launches per variant, five runs per scene, cooled
starts below 37 C VIRTUAL-SKIN, AC at 100 percent, thermal status 0.
Medians of launch medians, base 84997e1 -> flat fade only:

| Scene | power mW | raster p95 ms | GPU rail mJ |
|---|---:|---:|---:|
| home-scroll | 590 -> 465 | 10.88 -> 9.19 | 3653 -> 1231 |
| tab-bar | 661 -> 519 | 10.93 -> 8.47 | 5385 -> 1893 |
| list | 553 -> 447 | 10.98 -> 8.45 | 3977 -> 1369 |

Other scenes have no repeatable power change. Evidence:
perf/2026-10-06-round3-flat-energy (rail/scheduler reductions, reports,
thermal metadata and hashes). Removing the flat blur changes its
appearance; no NEAR bound is claimed for this approved change.
Separate A/B kernel GPU-work launches, five runs per scene, weighted
ms/frame at 434 MHz: home 4.110 -> 2.009, tab bar 5.113 -> 2.413,
list 4.525 -> 2.159 (-51 to -53 percent). Other scenes differ by less
than 0.01 ms. Evidence: perf/2026-10-06-round3-flat-gpu.
One-binary randomized scroll bench, five repeats: Material / morph flat /
flat without edge GPU 0.743 / 0.957 / 0.871 ms/frame (0.322 / 0.415 /
0.378 Mcycles); raster p95 5.85 / 6.40 / 6.01 ms, zero over-budget frames
at the median run. The remaining fade costs about 0.086 ms GPU; flat is
still 29 percent above Material in cycles and 8-9 percent in raster.
Evidence: perf/2026-10-06-round3-flat-bench.

Controls anatomy: menu_frames_test also accepts FRAMES_SCENE=controls
and replays the audit's switch/slider gestures. Three profiler runs per
tier, no per-widget tracing, CPU samples at 250 us. Flat/liquid mean
BUILD 1.027/1.067 ms, LAYOUT 0.531/0.564, PAINT 0.558/1.937,
COMPOSITING 0.710/2.411. Heavy-frame self CPU samples put native
CommandBuffer.submit at 9.2-9.8 percent, RenderPass draw/begin plus
Texture.asImage at 5.4-5.8 percent, getTransformTo at 2.0-2.2 percent.
These sample shares are not durations. Evidence:
perf/2026-10-06-round3-controls-profile (complete frame/VM/CPU data).
Separate native baseline atrace, two ordinary repeats, 800 UI / 801
raster frames: UI QueueSubmit 0.887 calls and 0.915 ms/frame, PAINT self
1.615, COMPOSITING self 1.284, BeginFrame inclusive 6.013 ms/frame.
Raster QueueSubmit 1.998 calls and 2.155 ms/frame, saveLayer 6.206 calls
and 1.153 self ms/frame; Draw inclusive 8.037 ms/frame. Means over all
frames in the scene windows, not p95; nested inclusive values are not
additive. Evidence: perf/2026-10-06-round3-controls-native.

A coordinate-uniform/translation-inverse trial is REJECTED. Ordinary
audit A/B/B/A, two launches each, five runs per launch: build p50
4.96 -> 4.84 ms (within baseline spread), p95 12.32 -> 12.27, raster
p95 11.64 -> 12.49, power 666 -> 645 mW. Separate GPU-work launches:
5.014 -> 4.993 ms/frame, 2.176 -> 2.167 Mcycles/frame (noise). Real
Impeller host before/after maximum channel difference 0 in five cases,
both shader variants; device resting controls max 0, held captures are
not synchronized (slider max 233). The original renderer remains.
Evidence: perf/2026-10-06-round3-controls-{energy,gpu}; rejected patch
and host pixel comparison in the profile evidence. The remaining UI
premium is paint/composition and GPU matte encode/submit, not widget
BUILD. Future exact-input matte reuse must preserve paint dependencies;
native Flutter GPU encode/submit is a separate engine lever.

Full protocol, limitations and verification: tool/audit/codex-round3-report.md.

## Round 5 resource experiments (2026-10-07)

Source c80a905, Pixel 6a, Impeller Vulkan, 60 Hz. Full protocol, original
report/trace hashes, exact windows and reproduction patches:
`tool/audit/codex-round5-optimization.md` and
`perf/2026-10-07-round5/`. Phase PNG readbacks run after timing collection.
The production renderer and dependency graph remain unchanged.

Existing grouping was measured in two GPU and two independent energy
launches, three repeats each, with four equal non-overlapping surfaces
sharing the same background and appearance. Independent/shared/merged
filter/key counts are 4/4, 4/1, 1/1; all 48 native comparisons are
byte-identical. Cluster independent -> merged: GPU 9.716 -> 4.057 ms,
4.239 -> 1.761 Mcycles/frame, whole-phone power 1155.1 -> 841.1 mW,
raster p95 11.280 -> 13.125 ms. Spread: GPU 9.853 -> 4.976,
4.276 -> 2.159 Mcycles, power 1183.5 -> 949.5, raster p95
11.625 -> 12.593. Spread's union/visible area is 5.568; larger union
area can still cost less than repeated filters. These geometry counts
are not captured-input or transient-memory measurements. Keep backdrop
depth and content ordering compatible; never infer a blanket merge rule
from this stand. The earlier navigation/toolbar merge rejection remains.

Field-only preparation skips analytic packing and unused analytic
uniform emplacement. Four native shader/appearance cases are identical;
GPU is unchanged, controls about 4.94 ms and menu about 7.5 ms/frame.
A/B/B/A then B/A/A/B energy, five runs each: controls 683.5 -> 720.3 mW,
menu 804.4 -> 821.4. Controls scarcely use the field path, so this is not
proof of a causal energy regression. There is no repeatable energy win;
the candidate is reverted. The warmed shared uniform arena remains
0.57 MiB; do not claim that skipping preparation reduces its capacity.

The released-texture candidate adds a 16 MiB byte cap to the existing
four-entry pool. A strengthened four-large-layer/single-layer rapid
reopen stress reaches the cap: native phases are identical, held
RGBA8 capacity after close 24.375 -> 12.188 MiB, but process RSS after
five idle seconds rises 387.45 -> 467.04 MiB. Median GPU large stress
11.512 -> 11.630 ms, raster p95 11.735 -> 12.551; energy 1566 -> 1551 mW
is a small short-window difference. Rejected and reverted. Dropped
references await native ownership/finalization; a reusable byte sum is
not a total-memory bound. Age expiry advances with submitted frames and
does not trim the pool while idle. The initial two-layer negative
control did not reach the byte cap and was replaced by this stress.

Haze 0.5.0 (ru-ji/haze, Flutter package) is progressive rather than uniform
blur. Its two sibling custom BackdropFilter layers have up to 128 taps
per direction, without an explicit reduced-resolution pyramid. One
three-repeat tile comparison: sigma 2/10 GPU 11.053/24.257 ms against
stock rectangular Gaussian 2.125/2.155 and production glass 3.423/3.097.
An outer ClipRect reduces Haze to 5.253/10.927 but visibly changes
pixels (max channel error 138-157): not an equivalent optimization.
No Haze production dependency or energy benefit is claimed.

Known-prefix same-frame picture replay is an isolated prototype on
exp/same-frame-backdrop, not a generic backdrop API. Tiles/moving source:
production -> replay GPU 3.423 -> 1.955 at sigma 2 and
3.097 -> 2.117 at sigma 10. UI p95 at sigma 2 rises 5.50 -> 7.09;
raster 10.25 -> 10.97. Static chrome has max 1-2 native channel steps;
translated glass reaches max 7/3 on tiles and 9/3 on a native text smoke,
even with retained actual ImageFilter uniforms refreshed. Coordinates
under movement remain unresolved. The full-DPR image cache adds
9.89 MiB and still gives visibly incorrect filter coordinates
(max 215-231); reject it. Texture/platform-view, glass-over-glass,
transformed retained subtrees, input reach and lifetime contracts are
not established. Details and blur-kernel experiments are in the report.

Current-frame input audit, exact installed Flutter 3.47.2 source:
Texture.fromImage shares a ready ui.Image's GPU storage without copying;
it does not export Impeller's private backdrop. The existing final shader
receives that texture natively as sampler 0. A matrix/runtime-effect
composition probe keeps it inside the native filter graph, with no
per-frame toImageSync or widget replay. The diagnostic input size is
consistent with 270 x 600 at two down levels and 68 x 150 at four, from
1080 x 2400. One-repeat text smoke GPU stock Gaussian 2.545/2.583 versus
chain 3.992/4.519 ms at sigma 2/10; native max error 50/35 is visible.
This proves a reduced-resolution source route, not an equivalent blur
optimization. Separate matrix resamples add work beyond a fused dual
filter. See tool/audit/codex-backdrop-input-review.md for ownership and
public API limits. The initial captured-image Dual experiment is excluded
from algorithm verdicts: duplicate source rasterization, nearest sampling
and unequal actual blur width made it an invalid kernel comparison.
The focused native follow-up has two GPU and two energy launches, three
repeats: Gaussian/chain GPU at sigma 2 is 2.555/4.007 ms and at sigma 10
2.596/4.541. Whole-phone sigma 10 power 718/873 mW; sigma 2 power has
large launch variation, so no repeatable benefit is established.
The same 50/35 max pixel errors repeat. This characterizes an unfused
full-viewport intermediate graph, not the limit of Dual Kawase on a
bounded source texture. The production Gaussian remains.

Dual Kawase follow-up (2026-10-07, Pixel 6a Vulkan, base 620798e):
true bilinear 5/8-tap GPU passes combine scale and kernel over a guarded
ROI, retain intermediate targets and fuse the last upsample into the
visible Canvas shader draw. The same ready source image is displayed
and sampled; source setup occurs before collection. This is owned-input
research on exp/same-frame-backdrop, not arbitrary widget capture.
Two GPU plus two energy launches, three shuffled repeats, text source:
Gaussian/direct Dual sigma 2 GPU 2.030/1.492 ms, power 547/548 mW,
UI p95 1.685/8.569, raster p95 6.216/3.508. At sigma 10 Gaussian is
2.110 ms, 534 mW; a three-level Dual is 1.865 ms, 564 mW, UI p95 11.872;
four levels are 2.176 ms, 639 mW, UI p95 14.053. Max channel errors
9/8/7; native identity copy <=1 after correcting the vertical UV.
The direct large four-level path has eight over-budget frames across
the two GPU launches. Submission wall time averages 0.51-1.46 ms per
pass in a diagnostic smoke; dynamic uniform preparation is ~18-20 us.
Public SDK command buffers cannot safely contain these nested passes,
and each submit clears Vulkan thread-local pool caches. Native-raster
pass images lower UI but raise GPU to 2.098/3.270 ms at sigma 2/10.
The image-surface control accumulates 23-36 textures during short native
runs, while the corrected direct outputs hold three fixed textures.
Raw kernel likeness is not production optics fidelity; lower GPU work
at equal/higher power is not accepted. The old graph's cost is not the
limit of the algorithm. Report, calibration, source hashes and patches:
tool/audit/codex-dual-kawase-followup.md,
perf/2026-10-07-dual-kawase.

Unchanged-source translation cache (same device/base, two GPU and two
energy launches, three repeats): Gaussian -> cached Dual sigma 2 GPU
1.982 -> 0.952 ms/frame, power 573 -> 500 mW; sigma 10 GPU
2.079 -> 0.972, power 611 -> 518. UI p95 stays 1.495/1.523 ms.
Power improves in both launches but baseline variation is substantial
(small 8.7/16.4 percent, large 5.2/22.6 percent); no app-wide guarantee.
The immutable owned source has 100 percent cache hits; source setup/misses
and production optics are excluded. Native phase max error 8/7 with a
motion+kernel guard, not production fidelity acceptance. Three/seven
prewarm passes remain constant across repeats, with one retained output
and owned target capacities 1.306/2.232 MiB, plus a shared 9.89 MiB source;
these are not RSS measurements. The current transform is applied in the
current frame. Real source invalidation and native batched submission
remain next work, not implemented production features.

## Combined current-frame source (2026-10-07)

COMBINED CURRENT-FRAME SOURCE (2026-10-07, Pixel 6a Vulkan): unmerged
exp/same-frame-backdrop a34b9d0 combines versioned owned-picture ROI,
current translation, native deferred blur and unchanged full Morph optics.
Two GPU/two energy launches, three repeats, final small Gaussian sigma 2:
GPU native/candidate static 4.073/1.900, periodic 4.064/2.234, dynamic
4.084/3.531 ms/frame; selected whole-phone power 738/609, 748/777,
754/735 mW. Max native phase error 3/255 over 42 comparisons. Periodic
power +3.8 percent rejects unconditional admission despite GPU savings;
app CPU scheduled time did not grow, CPU-rail/DVFS cause unresolved.
Large-sigma hybrid Gaussian static/periodic wins, dynamic costs more;
Dual dynamic costs more at both widths. Current-frame misses are included,
0/30/144 per typical static/periodic/dynamic 144-frame window. Small
logical-sigma single-picture Gaussian aligns ROI to two device pixels.
One retained output 3.063/4.717 MiB, not total GPU memory or RSS. Fixed
opaque picture fixture only: no generic backdrop service, iOS acceptance,
nested glass or arbitrary textures. Production optics stay unchanged.
Report and reproducible evidence: tool/audit/codex-combined-source-report.md,
perf/2026-10-07-combined-source.

## Provenance

whynotmake-it/flutter_liquid_glass `liquid_glass_renderer`
(release/01-renderer-core @ cbbac845, sdf.glsl; ours derives from
ab1c2d29 with library fixes through 3cec75ed - see VENDORED). Upstream's LiquidGlassLoupe and LoupeTabBar are
EXAMPLE code, not package API. Its smin uses the normal-modulation idea
with the WRONG exponent (sin(theta/2) chord vs Apple's sin^2 - necks too
fat by +0.5..+8 pt as spacing grows); its fusion is not used.

## Open

- A container drawn under a transform the package does not gate (an app's
  own scale or rotation above it) shades its members on its own grid
  unshifted; only the sheet closes its containers while scaled (see
  "Raster ties, scaled containers").
- The backdrop filter itself costs ~0.75 ms of raster a frame on the
  Pixel 6a (Q1 above), and a composed blur reads its whole pass (F1 of
  "The lifted lens's frost", "Small blurs"): engine-side levers. The
  bars' frost could be exact and as cheap if the frost seed's pass
  origin were right for bar geometry ("Small blurs").

- Dark lifted slider thumb look (slider.md).
- Popover arrow drawn flat; LIGHT reference set pending (glass-optics.md).
- Backdrop groups: two resting body glass surfaces with content painted
  between them - the later one reads the root copy without that content
  unless the app gives the later section its own BackdropGroup (option
  C, decided 2026-10-05; device evidence and costs under "Second resting
  body glass").

## Real gallery Navigation (2026-10-07)

REAL GALLERY NAVIGATION (2026-10-07, Pixel 6a Vulkan): new standalone
navigation_stage_bench exercises actual GalleryApp/Inbox/detail callbacks,
first enter, nested push/pop, toolbar morph, scrolling and a repeated
five-action workflow. Short clean stock liquid: nested push UI p95
23.71-26.32, raster 29.00-32.08, GPU 5.818-5.887 ms/frame; pop
19.01-24.36/27.61-35.16/5.250-5.291. These are profile windows with
framework phase collection, not presentation latency. First-enter raster
p99 reached 64.712 ms after shader precache. Capsules have sigma zero;
edge blur/seed and real optics remain. Own-isolate CPU samples attribute
about 20 percent to native GPU submit, 12-16 percent inclusive to fused
outlines, about 12 percent to geometry preparation. Short content-channel
and exact two-box sampler experiments do not establish stable power wins;
no production optimization is admitted from those windows. Native host
168 phase pairs are byte-identical across the two experiments, and 20,000
pair-field probes equal the original. Pixel raw candidate and stock/stock
repeat both reach 64 on isolated body pixels; raw errors are retained.
Long workflow power stock/content/pair: 706/705/706, then 704/699/712
mW; UI p95 17.649/16.555/16.599, then 17.211/17.086/17.570 ms.
Neither candidate delivers a repeatable material win; both stay unmerged.
The native control and final verdict are documented in
tool/audit/codex-navigation-report.md; source/evidence in
perf/2026-10-07-navigation. Runner restores the release gallery and its
owned tracing state. Main library behavior is unchanged.

## Navigation without glass (2026-10-07)

FLAT NAVIGATION ATTRIBUTION (2026-10-07, Pixel 6a): four clean native
GPU launches isolate nonglass cost, three repeats per action. All case
censuses have zero backdrop filters. Hiding button glyphs cuts nested
raster p95 from roughly 24-33 to 7-8 ms; omitting their blur alone cuts
roughly 24-29 to 15-17 ms. Plain contour substitution cuts nested UI
p95 roughly 13-15 to 7-11 ms, while the raster tail remains. Removing
page painting does not remove the nested raster tail. These are visible
diagnostic ablations, not production wins. Prioritize preserving the
animated glyph/filter path and skipping unused optical-field preparation
on flat/fake; energy and native fidelity still gate any implementation.
See tool/audit/codex-navigation-flat-report.md and the frozen evidence in
perf/2026-10-07-navigation-flat. Main library behavior is unchanged.

## Stable Navigation optimization (2026-10-08)

The owner's current priority is smoothness on weak Android devices;
modest measured power increases may buy a meaningful reduction in frame
cost. Historical energy-only rejections above remain historical.

Flat layer parts now generate a silhouette without unused optical
distance/half-minor/turn fields. Block-corner minima still use the same
near-block bound; the original normal-aware sampler, contour trace and
spline determine the exact outline. Separate bounded caches prevent
fieldless outlines serving fake/liquid. Those tiers and custom renderer
subclasses keep full optical parts. All 63 host scene/tier collections
match the original source; seeded path/cache tests cover two-to-four-box
fusions and translations. This is work reduction, not a quality tier.

Android bar content retains a device-resolution image under the existing
>=0.5 pt screen-space blur. Scale, blur, opacity, spring timing and
semantics remain. Existing cached button content is retained, while
immutable activation values give image ownership to the render object.
Content repaint and DPR changes invalidate it; disabling, detach and
dispose release it. Fractional logical bounds sample the corresponding
pixel extent. iOS/web bar content remains live and menu sampling remains
unchanged. This is a small additional source render, not framebuffer
reuse or a previous-frame backdrop.

Pixel 6a, stable 3.47.2, two clean same-binary flat GPU launches,
five repeats: full-field/live -> sparse/raster nested push raster p95
24.545/28.192 -> 19.916/21.350 ms, GPU active time per frame
2.527/2.483 -> 2.574/2.625 ms. Entry improves with silhouettes alone;
other actions are mixed, and nested frames still exceed 16.667 ms.
Separate three-repeat 16-second workflows give selected ODPM power
556/534 -> 542/547 mW, not a repeatable saving. An anomalous sparse
727.6 mW window is retained and accompanied by other-process accounting.

Final immutable-activation port, five repeats in one native launch:
liquid live -> retained push UI p95 26.690 -> 21.612 ms, raster p95
33.843 -> 25.341 ms, GPU 5.807 -> 5.950 ms; pop raster 32.829 -> 26.671 ms,
GPU 5.147 -> 5.303 ms. A preceding three-repeat port also improves pop
33.833 -> 26.729 ms but regresses push 22.782 -> 28.551 ms. Liquid push is
variable, UI remains over budget and final over-budget medians 10/10
push and 9/9 pop are unchanged. These are work reductions, not proof of
a presentation-FPS gain. That preceding notifier-owning port's gallery
reparenting error is fixed by immutable activation in the final source.

Final native phase controls use 28 pairs per flat/liquid path. Chrome
maximum difference is 8/255; whole-frame 64/56 errors occur on isolated
body pixels, with 64 also observed in liquid same-variant repeats.
This is stated NEAR resampling under blur, not native byte identity.
Performance readbacks are separate from pixel captures. Final port
matrices and verification: tool/audit/codex-navigation-stable-report.md,
perf/2026-10-08-navigation-stable. No beta feature or added frame delay.

## Separate beta SDK and sampler compatibility (2026-10-08)

Flutter 3.49.0-0.2.pre is installed alongside stable 3.47.2 as flutter-beta
and dart-beta. The stage runner can select an SDK and records full
framework/engine/Dart provenance. Builds use independent checkouts,
package configurations and shader bundles; SDK-pinned lock differences
are retained with native results.

Stable Impeller preserves the first bound sampler's low quality when
substituting the filter input. Beta chooses quality from ImageFilter.shader
instead, defaulting to nearest and ignoring that legacy sampler setting.
Unmodified beta therefore reaches 27/255 native chrome error. The typed
morphGlassShaderFilter factory supplies low quality when the named argument
exists and keeps the old call on stable. Final filter and pipeline warm-up
share this policy. No source capture or frame delay is added.
Corrected beta versus stable: flat chrome identical, liquid chrome maximum
1/255 over 28 phase pairs each. Isolated whole-frame maxima 63/64 and
same-variant repeat errors are retained rather than hidden by a chrome crop.

Two native five-repeat launches per SDK, actual Gallery Navigation:
liquid push UI p95 stable 25.191/27.266 -> beta 21.641/19.984 ms;
raster p95 25.611/27.517 -> 29.419/26.456, GPU active work per frame
5.938/5.925 -> 6.228/6.202 ms. Pop UI also improves in these launches;
nested work remains over the 16.667 ms budget. This is a complete SDK
comparison, not attribution to one filter API or proof of uniform
presentation-FPS/energy improvement. Energy was not measured here.

Native paired-Gaussian research uses two composed runtime filters with
a three-sigma discrete reference and the same half-resolution sigma
policy. Pairing matches that reference within 1/255 and reduces GPU work:
small 11.378/10.963 -> 8.230/8.230 ms; large 11.687/11.522 ->
10.441/9.994 ms. Stock is 2.348/2.334 and 3.171/3.184 ms respectively.
Custom versus stock maximum error is 20/255; neither mode is admitted.
Impeller already pairs bilinear Gaussian samples, corrects sigma and
downsamples. A cheaper arithmetic kernel alone does not fix the complete
runtime graph's cost. Both SDKs pass 1404 package and 21 gallery tests.
The native byte-encoding input probe returns 1082x2402 for the second
runtime pass for both region sizes, at all three phases, on a 1080x2400
screen. This prototype carries a viewport-sized intermediate even for the
small ROI; reducing that allocation/graph is the next source experiment.
Android exec-out screencap independently confirms 1082x2402 in the
displayed small-region frame, without invoking Flutter toImage.
Details, provenance and reproduction: tool/audit/codex-beta-sdk-report.md,
perf/2026-10-08-beta-sdk. Production blur remains the stock path.


2026-10-09 handoff: experimental paths and evidence are published separately.
See docs/optimization-handoff.md for branches, dependencies and admission state.

## Navigation glyph blur in one pass, decided fusion blocks (2026-10-09)

Devices: Redmi 6A (MT6762, PowerVR GE8320, Android 9, 32-bit, Skia GLES -
Impeller is unavailable there, so liquid falls back and only flat is
native), Moto g86 power (Dimensity 7300, Mali, Android 16, Impeller
Vulkan, 120 Hz panel but the app is held at 60 fps without a touch; the
system ignores window and surface frame-rate votes). Flutter beta
3.49.0-0.2.pre, profile, actual gallery Navigation callbacks
(navigation_stage_bench, 1500 ms windows, three shuffled repeats).

Finding (Redmi, Skia trace with `--trace-skia`): each push / pop began
with three or four frames of 80 - 140 ms raster. They held 55 - 64 render
passes each: every bar item's blur (`ImageFiltered`, a save layer and
two blur passes), its opacity layer (the engine raster-caches the
children of an opacity layer that cannot inherit opacity), the Android
glyph raster (`toImageSync`, a texture copy and a mipmap regeneration
per new image) - about 2 ms of GL driver time per pass on this GPU.
Attribution by removal: no blur 21 -> 8 missed slots per push window,
no partial opacity as well 8 -> 6; the glyph raster alone 21 -> 19.

Change (Android only, iOS / web unchanged): `MorphGlyphBlur`
(glyph_scale.dart) draws a bar item's content, and the inline title,
blurred and faded as ONE draw in the pass it belongs to, through
`glyph_blur.frag`. It samples a mip pyramid of one raster of the child
at the device pixel ratio: each frame picks the finest level the blur
spans at most 2 texels of (and no finer than about the screen), and the
shader evaluates the continuous Gaussian over the texel centers around
each point (per-fragment weights, 7 x 7 bilinear taps at most, 3 x 3 or
5 x 5 for small sigmas; the kernel leaves out the texels' own box
filter and never goes under 0.4 screen pixels). Pyramids are built once
per child content - every pyramid one frame needs together, in two
passes (one raster atlas, one atlas of all levels drawn by
`glyph_reduce.frag`, exact 2 x 2 box means, no Skia mipmaps: those
copied the source once per downscaled draw, 211 ms in one frame) - and
then last while blur and scale animate. A blur under 0.5 device pixels
paints the child sharp under the box's own opacity layer (a repaint
boundary whose opacity changes update the layer, like `RenderOpacity`).
Rasterized text is drawn at the device ratio, then reduced: text
rasterized directly on a coarse grid moves by up to half a texel
(baselines snap), which a 10 pt blur showed as a 4 pt shift. The
previous bar glyph raster (`MorphGlyphRaster` under `ImageFiltered`
under `Opacity`) remains only on the menu.

Fidelity (test/glyph_blur_test.dart, against a true separable Gaussian
of the sharp render, along the bar's own (presence, scale, blur) curve,
max / mean channel error): p 0.1 2/0.48 (blur layers 2/0.70, previous
Android path 3/0.90); p 0.5 4/0.91 (4/1.32, 5/1.47); p 0.75 14/1.36
(8/1.59, 16/2.07); p 0.9 31/2.52 (1/0.29, 31/2.24); p 0.97 153/3.65
(139/3.05, 139/3.05); p >= 0.99 identical to the sharp live path. Every
step is within one channel step of mean error of the layers it replaces
or of the previous path. Skia's own large-sigma blur is the less exact
one (it downsamples): a blurred square's peak is 107 under the layers,
117 here, 119 in theory.

Container fusion (glass_outline.dart): an 8 pt block where one box is
nearer than every other by `k (1 + (n - 2) / 4)` plus the block's
diameter reads that box alone (`_decidingBox`); the merge law is then
that box's distance bit for bit (the other masses fold to at least the
nearest plus k, and the nearest wins outright). Seeded equivalence over
200 random rows and steps per path (test/glass_fusion_sampling_test.dart)
traces identical outlines, silhouette and optical. Redmi flat fusion of
a 2 - 4 capsule bar row: median 3.3 -> 2.3 ms per frame. Tried and
dropped: per-node sign classification from the box minimum (as costly
as the sampler it skips), re-deciding block quarters (slower), the
sampler torn off as a closure (kept: direct calls, ~5 percent).

Redmi flat, missed display slots summed over three windows, two
launches (A B B A), baseline -> now: push 21/19 -> 4/2, pop 22/22 ->
3/3, enter 11/10 -> 2/4, toolbar 11/11 -> 1/0; raster p95 push
10.6/20.5 -> 12.7/10.6 ms, toolbar 48.7/40.5 -> 9.7/9.6 ms; pop UI p95
14.2/14.3 -> 9.3/12.4 ms. One frame per transition still builds the
pyramids (~30 - 40 ms raster), and fusion stays the largest UI cost of
the remaining slow frames.

Moto, two launch pairs (baseline A, current B, B, A; 60 Hz), raster p95
/ missed slots: liquid push 22.1/21.9 -> 9.4/9.7 ms, 5/5 -> 0/1; liquid
pop 23.7/21.0 -> 10.6/10.2 ms, 6/6 -> 1/1; liquid enter 13.1/13.0 ->
10.3/10.6 ms; flat push 19.8/23.8 -> 4.5/4.5 ms, flat pop 15.7/16.4 ->
4.9/5.1 ms. Without a touch the system holds the app at 60 fps and
ignores window and surface frame-rate votes; with min_refresh_rate 120
(8.33 ms budget, A B B A), missed slots: flat push 21/17 -> 6/6, flat pop
15/14 -> 3/5, flat toolbar 5/3 -> 0/1; liquid pop 26/20 -> 23/13, liquid
push 43/68 -> 55/23 (noisy: liquid raster p95 stays ~8 - 9 ms, at the
budget). Liquid push / pop raster p95 16.7/20.8 -> 9.3/8.8 and 16.6/13.2
-> 8.9/7.9 ms. Liquid at 120 Hz is the next target.

Perf counts: nav-scroll's inline title re-records one small picture per
animated frame instead of updating a filter and an opacity layer
(pictures 0.5 -> 1.1, offscreen layers 7.8 -> 6.8 on fake / liquid;
flat paints 72.9 -> 75.1, offscreen 2.0 -> 1.0); ceilings updated for
that scene only.

Evidence: perf/2026-10-09-nav-glyph-blur (reports, fusion logs; the
Skia / Dart traces were not kept), tools in perf/nav_quick. The bench
now runs flat-only on a device without liquid, records `glyph_rasters`
per window and the owners of every opacity / filter layer in frozen
shots; MainActivity accepts `--ez morph-max-refresh true` for benchmark
launches.

Liquid at 120 Hz (Moto, min_refresh_rate 120, fixed performance mode):
the same liquid push runs at 0 - 3 missed slots alone (UI / raster p50
1.75 / 1.3 ms) but at 3.4 / 2.8 ms per frame from the second push on,
whether the gallery is remounted or the push repeats in one app; render
trees are identical (660 render objects, two liquid layers). Synthetic
actions get no touch boost, and the clocks a run lands on dominate its
120 Hz result: liquid push misses 24 - 68 slots per window in full runs
on both sides. Frames continue for 1.25 - 1.5 s after an action - the bar
motion's springs settling, not a stuck ticker - and in liquid each of
those frames re-encodes the two glass layers' geometry (two Flutter GPU
command buffers per layer: matte and material, plus the field upload):
~22 percent of the UI thread, fusion ~15 percent, scene building ~17.
Liquid fusion's optical field pass now uses the same decided blocks (the
blends weigh the other boxes by 0 or 1 there; samples equal to float
rounding, seeded test): Moto median 0.62 -> 0.53 ms, p90 1.27 -> 0.98 ms.
Liquid push at 120 Hz remains budget-bound: next is the per-frame
geometry encode (re-encode only when the matte changes by a visible
amount, or fewer command buffers) and the settle tail.


## Analytic liquid geometry (2026-10-09, behind MORPH_ANALYTIC_GEOMETRY)

Owner-approved direction (invisible differences do not matter; tiers of
cheaper glass allowed). Reference: Apple's QuartzCore glass evaluates up to
four shapes in the shader per draw (reconstruction in
medfa12/liquid-glass-react-native). An eligible liquid layer skips the
Flutter GPU geometry matte, the material map and the field upload; the
final shader evaluates the shapes (sdf.glsl `sceneSample`, separate shapes)
or the container merge law (<= 4 boxes, `GlassBoxField`) itself, and the
CPU no longer fuses those bodies. Eligibility: <= 8 shapes, uniform or
tint-only appearance, analytic programs loaded; otherwise the matte path in
the same frame. Gallery Navigation: every bar layer analytic at rest, mid
push and pushed (host census).

Host oracles (Impeller + Flutter GPU in flutter_tester):
- separate shapes vs the matte: mean 0.02 - 0.32 per channel over covered
  pixels, max up to 46 on single rim pixels (the matte's 12-bit codes);
- fused bodies vs the sampled 4 pt field: the field's own error dominates
  (far-apart pair vs exact shapes: field mean 3.5 / max 255, analytic
  0.002); vs a fine CPU field (0.25 pt trace) the difference converges to
  0.07 - 0.12 mean on smooth backdrops, 0.32 - 0.51 on stripes (corner
  diagonals); bound mean 0.75.
- Toggle off: byte-identical (parity 0; programs not loaded).

Open before the default flips: Moto/Pixel timing at 120 Hz incl.
static-geometry scroll scenes (per-pixel shape cost now every frame),
Mali register pressure (malioc not available here), native pixels, the
switch pop when a body crosses 4 -> 5 boxes. Commits 1c4c0d3, ecccb2a,
a785a80, 4273ecf; spec in the owner-local specs folder.
