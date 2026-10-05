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

- whynotmake-it's `liquid_glass_renderer` (Apache-2.0, upstream ab1c2d29)
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
  ColorFiltered, a viewport, a follower layer - so a MorphTag source,
  whose Opacity hides it during a flight, never joins); and the layer
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
  standalone layer's matte is rendered in its own fractionally offset
  space and resampled, the container's in exact positions: resting shots
  differ by up to 45 - 53 on rim pixels (0.01 - 0.36 percent of the
  screen over 15, the more buttons the more), invisible side by side; the
  audit's controls-resting and sheet-medium shots 76 / 70 at 0.11 / 0.23
  percent, only inside the buttons. flutter_test: hidden, half faded and
  clipped buttons in a container render exactly as without it
  (test/glass_container_test.dart).
- Kill criteria (task gates): raster >= 15 percent and >= 0.3 ms on two
  intended workloads - resting button clusters over moving content, n4
  and n8 - met; no regression > 0.2 ms on N = 1 - 8 beyond run noise; the
  gallery scenes gain less than 15 percent. Fable K2 (>= 30 percent GPU
  time at N = 16) is not met by raster (-23 / -26 percent); GPU time was
  not recorded.

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
perf/shotdiff.py compares two runs' shots (mean, max, percent over 15);
perf/contact.py lays several tiers' shots side by side.
Gallery: the root installs `MorphAdaptiveGlass` with the session's
`MorphGlassRenderer` (GalleryGlassSettings / GalleryGlassScope,
glass_settings.dart, tier null = auto, in GalleryApp's State); the Glass
renderer page edits them and shows the tier being drawn.

## Provenance

whynotmake-it/flutter_liquid_glass `liquid_glass_renderer`
(release/01-renderer-core @ cbbac845, sdf.glsl; ours derives from
ab1c2d29 - see VENDORED). Upstream's LiquidGlassLoupe and LoupeTabBar are
EXAMPLE code, not package API. Its smin uses the normal-modulation idea
with the WRONG exponent (sin(theta/2) chord vs Apple's sin^2 - necks too
fat by +0.5..+8 pt as spacing grows); its fusion is not used.

## Open

- Dark lifted slider thumb look (slider.md).
- Popover arrow drawn flat; LIGHT reference set pending (glass-optics.md).
- Backdrop groups: two resting body glass surfaces with content painted
  between them - the later one reads the root copy without that content
  unless the app gives the later section its own BackdropGroup (option
  C, decided 2026-10-05; device evidence and costs under "Second resting
  body glass").
