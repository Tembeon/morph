# Glass renderer passport (MorphGlassRenderer, tiers, adaptive policy, outline as truth)

Status: implemented in the package (owner decision 2026-10-03: the old
"no shader in the package" rule is CANCELLED); optics measured on the
device (see [glass-optics.md](glass-optics.md)); tier costs measured on the
iPhone 16 Pro. The tier POLICY numbers are engineering defaults, not
measurements.

## Contract (the seam)

- `MorphGlass(painter:)` installs a `MorphGlassPainter`; every control
  builds its glass surfaces (`MorphGlassKind`: track, lens, knob, thumb,
  button, bar, menu) every frame behind its content. Multi-surface
  controls call `buildLayer(surfaces, content:)` (`MorphGlassLayer`,
  rebuilt on the clock's `frames`; segmented labels and the tab row ride in
  as `content`, the menu hands button + platter in one call; options
  `spacing:`, `contentSlots:`, `outline:`); single surfaces call
  `buildSurface` (glass button) or `buildFill` (stepper), placed at
  `MorphGlassSurface.bounds`; `buildGlow` draws touch glows (tab-bar.md).
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
- FAKE GLASS (no Flutter GPU: tests, the first frames, devices without
  it) draws the fused outline too: `GlassField.outline` reaches
  ConsolidatedFakeGlassLayer, which clips its backdrop and surfaces to it
  and tints the neck (outline minus shapes, even-odd - Skia's path ops
  refused an outline running along its capsules).

## Adaptive policy (`MorphAdaptiveGlass`, glass_tier.dart)

Installs the renderer and picks the tier: an explicit `tier` wins, else the
pure `MorphGlassTierGovernor` over FrameTimings (`MorphGlassTierPolicy`):
windows of 30 frames vs 1 / refresh rate; >= 25 percent of a window over
budget steps down at once; a window whose p90 is under 0.6 budget steps up
after 5 s quiet, doubling per repeated failure of that tier up to 80 s,
NEVER while a pointer is down. Engineering defaults, not measurements.

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
- Backdrop groups: a lifted lens on the FROSTED tier still reads the root
  copy (it does not see the track under it; kept shared so the fallback
  tier stays cheap), and glass inside an alert or a context menu's hero
  replica shares the root group - unverified on the device.
