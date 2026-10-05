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
  MorphGlassPainter with `tier` (`MorphGlassTier` flat / frosted / liquid)
  and the liquid settings (`MorphGlassMaterial`, blur, refraction, light,
  tint, frostControls); `liftedOptics` per control; `precache()`.
- WEB: the liquid tier sits behind a conditional import (glass_liquid.dart
  -> _native / _web; the web stub never imports the renderer,
  `liquidAvailable` false, liquid draws frosted); the three final-render
  .frag files compile to an empty stub under SKIA_GRAPHICS_BACKEND ("Only
  simple shader sampling is supported"), so the web builds with nothing
  removed.
- Package tests set the renderer's `isLocalTest` (root-package asset keys).

## Tiers

- Tier 0 (flat) fills the outline.
- Tier 1 (frosted) blurs + tints inside it; resting platters stay flat
  fills.
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
- FAKE GLASS (no Flutter GPU: tests, the first frames, devices without
  it) draws the fused outline too: `GlassField.outline` reaches
  ConsolidatedFakeGlassLayer, which clips its backdrop and surfaces to it
  and tints the neck (outline minus shapes, even-odd - Skia's path ops
  refused an outline running along its capsules).

## Adaptive policy (`MorphAdaptiveGlass`, glass_tier.dart)

Installs the renderer at ONE tier for the session (owner decision
2026-10-05: the glass never switches tier while the app runs). An
explicit `tier` wins; else `MorphAdaptiveGlass.tierFor(deviceClass,
best)`, a pure function, decides once the liquid capability resolves
(`MorphGlassRenderer.precache` before `runApp` makes that the first
frame; without it the first frames draw the frosted fallback):

- `best` below liquid (no Flutter GPU, the web, a renderer pinned lower)
  -> `best`.
- `MorphGlassDeviceClass.capable` (Vulkan / Metal, Apple A13+) and
  `unknown` -> liquid.
- `gles` (Flutter GPU `doesSupportFramebufferRenderMipmap` false - only
  the GLES backend lacks it) and `appleBeforeA13` (iOS and
  `supportsTextureCompression(astcHdr)` false - Metal reports HDR ASTC
  from GPU family Apple 6 = A13 on) -> `MorphAdaptiveGlass.cheapTier`,
  ONE constant, flat today (fake glass may replace it).

Why flat and not frosted as the cheap tier: Pixel 6a forced to GLES
(pixel6a-gles, 60 Hz, medians of 5 runs, frames over the 16.7 ms budget
per scene home / segmented / tab bar / controls / menu / sheet): liquid
11 / 11 / 82 / 64 / 69 / 47, frosted 23 / 17 / 96 / 132 / 59 / 56, flat
6 / 0 / 2 / 0 / 20 / 0; on Vulkan liquid is 1 / 0 / 13 / 13 / 22 / 5.
Frosted blurs every glass surface and costs MORE than liquid on GLES and
on four of six scenes on the iPhone 16 Pro (controls 3.65 vs 2.88,
sheet 3.92 vs 3.21, segmented 2.29 vs 2.00, home scroll 2.51 vs 2.14
raster p95 ms). The pre-A13 branch is unmeasured (no such device).

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

## Liquid tier layering (the former gallery painter, optics unchanged)

- Body surfaces in one layer reading the nearest BackdropGroup's shared
  copy (root group in GalleryApp, own groups for the glass page's scene
  and card); bar and menu kinds take their own copy on the liquid AND
  frosted tiers, through buildLayer, buildBody and buildSurface alike.
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

## First use: pipeline warm-up (2026-10-05, glass_warm_up.dart)

`MorphGlassRenderer.precache()` (morphPrecacheLiquidGlass) draws every
pipeline the glass will need before the first glass frame, offscreen:

- Liquid, inside the capability load (liquid reports available only after
  it): two 8 x 8 geometry renders through the real
  `FlutterGpuGeometryRenderer.render` - shapes + full material map, then
  field + tint-only map - which fetch all four Flutter GPU pipelines
  (geometry, field, material gradient, tint gradient; RGBA8, one sample,
  the real descriptors). Flutter GPU creates a pipeline at its first draw
  and waits for it on the UI thread (engine lib/gpu/render_pass.cc).
  Then one `OffsetLayer.toImage` scene at the view's pixel ratio: a
  backdrop picture (even-odd cutout clip, mask-blurred rounded rect and
  superellipse in a bounded saveLayer: the glass shadows), and per final
  shader (plain, material, tint, samplers bound to the warm-up mattes) a
  ClipRectLayer > BackdropFilterLayer with the shader alone and composed
  over a mirror blur at sigma 1 / 2 / 8 / 14 (each downsample class), plus
  the bare blurs; one row without and one sharing a BackdropKey. A
  snapshot renders through the same canvas into an MSAA + stencil target
  like the screen, so the filter subpasses get the variants the screen
  uses; every clip is non-empty (a clipped-away filter is skipped).
- Frosted (Impeller only, `isShaderFilterSupported`; a no-op under Skia,
  the web and flutter_tester): the same two-row scene with blurs at each
  frost inside an antialiased ClipRRect and an outline ClipPath, with the
  tint fill, highlight gradient and rim stroke over them.
- Failures are swallowed (debug print): the real frame then pays what it
  paid before; the capability and its reason are unchanged. A scene that
  takes over 2 s stops being awaited.

Pixel 6a (Vulkan, 60 Hz, profile, 3e81b9e, one launch each,
pixel6a-warmup-cold = pm clear, -warm = second launch; first_use
home-scroll = runApp to the first timed run, worst UI / raster ms):

| build | precache ms | cold UI / raster | warm UI / raster | am start TotalTime ms |
|-------|------------:|-----------------:|-----------------:|----------------------:|
| liquid before | 3.8 / 4.3 | 3.9 / 16.0 | 121.8 / 126.2 | 595 / 468 |
| liquid after | 374 / 387 | 5.5 / 12.9 | 4.8 / 11.8 | 624 / 576 |
| frosted before | 2.9 / 3.0 | 2.3 / 61.6 | 5.3 / 40.6 | 362 / 413 |
| frosted after | 506 / 382 | 7.1 / 11.3 | 4.0 / 14.8 | 748 / 585 |

The first-use worst of one launch scatters (liquid before cold read 3.9
here, 110.7 at 905517f); the traces are the proof (pixel6a-warmup-trace,
cold, TraceSystrace builds): before, the first app frame's PAINT took
267 ms of the UI thread and its raster created pipelines in a saveLayer;
after, precache holds the UI thread 303 ms (the Flutter GPU pipeline
waits) and the raster thread 110 + 52 ms (the two snapshots), and from
the first app frame on no UI slice reaches 8 ms and raster frames run
6-7 ms in the startup window. Later pipeline creations (17 s, 37 s:
menu and sheet chrome, 1-3 ms each) are unchanged. The trade: about
0.4 s more behind the splash, the first glass frame pays nothing. The
Vulkan pipeline disk cache does not remove the cost (warm before: 122 ms
UI). iOS is not measured in this pass; Metal compiles runtime
stages at load, the Flutter GPU and MSAA variants the same way as here.

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
