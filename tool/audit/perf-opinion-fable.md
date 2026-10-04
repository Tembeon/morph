# morph - independent per-frame cost opinion (Fable, 2026-10-05)

Static read of branch wip/measured-liquid-glass (c4d14a7 plus the
uncommitted tree). No code was run; device numbers quoted are the ones the
passports record (tool/ios_reference/spec/glass-renderer.md, "Device
numbers", iPhone 16 Pro, profile). Every claim cites file:line as read on
2026-10-05. Ranking is expected gain x confidence; every item says what it
does to pixels. Nothing here touches a measured spring, delay, gain or
threshold.

## 0. The cost model this stack actually has

Three budgets matter, in this order on an iPhone at 120 Hz (8.3 ms):

1. Raster / GPU on Impeller. The unit of cost is not "a blur" but a RENDER
   PASS BREAK: every independent BackdropFilter ends the current pass,
   stores the tile memory, snapshots the coverage and starts a new pass.
   The renderer's own doc puts one capture at ~115 mW on a Pixel 10
   (rendering/liquid_glass_layer.dart:84-88). A BackdropGroup collapses N
   filters into one break. On top of a break, chrome frost (sigma 14,
   MorphGlassDefaults.chromeFrost, internal/glass_defaults.dart:14) goes
   through a separate Gaussian pass, "about four command buffers per
   frame on Metal regardless of its radius"
   (rendering/liquid_glass_layer.dart:602-604), while anything under
   1.25 device px folds into the final shader (same file :605-615).
   Then the final shader pass itself over the clipped filter bounds, and
   any saveLayer (Opacity < 1, ImageFiltered, MaskFilter shadows).
2. UI thread, Dart. Two kinds: (a) widget rebuild + layout + paint per
   tick, (b) pure CPU geometry: the fused outline traces (0.12-0.71 ms per
   call on the device, glass-renderer.md "FUSED OUTLINE COST") and the
   Flutter GPU command encoding per changed matte.
3. The engine flight and skin. Already paint-only per tick (skin.dart:564,
   628, 1240-1300); the flight shuttle rebuilds only wrappers around a
   content built once (flight.dart:1621-1628, 1665-1700). These are not
   where the time goes; see section 4.

Important asymmetry: "glass at rest" with nothing else moving costs ZERO
(every control's ticker stops on settle, widgets/clock.dart:72-76; no frame
is scheduled). The expensive rest case is glass that is still while OTHER
content repaints - a list scrolling under a navigation bar and toolbar.
Then every frame pays: the retained glass layers re-add to the scene
(internal/transform_tracking_repaint_boundary_mixin.dart:137
`alwaysNeedsAddToScene => true` forces every ancestor layer to re-add),
the compositing polls (rendering/liquid_glass_render_object.dart:641-651,
503-551; internal/render_liquid_glass_geometry.dart:179-202, a
`getTransformTo` per shape per layer per frame), and on the GPU the full
capture + blur chain + shader pass per chrome surface, because Impeller has
no raster cache: retained Flutter layers save UI-thread recording, never
GPU work.

Device numbers already on file (p95 build / raster ms, liquid tier):
segmented 1.75 / 1.80, tab bar 2.91 / 2.52, controls 3.87 / 2.67, menu
3.03 / 2.90; flat tier 0.54 / 0.76, 0.69 / 0.92, 3.00 / 0.79, 3.23 / 2.35.
Read: ~1.2 ms of UI thread per frame is the liquid widget stack for ONE
animating segmented control (1.75 vs 0.54), ~2.2 ms for the tab bar.
Raster for controls is cheap; raster for chrome (menu 2.90, bars) is
where the GPU goes.

## 1. Where the per-frame costs are, scene by scene

### 1a. A control animating (segmented lens lift, switch knob, slider)

Per tick, MorphClock fires `frames` (widgets/clock.dart:64-77) and
MorphGlassLayer rebuilds the painter's whole layer widget tree
(widgets/glass.dart:466-482: `ListenableBuilder` -> `painter.buildLayer(
context, surfaces(), ...)`). On the liquid tier that is:

- `MorphGlassLayerParts.of` (widgets/glass_renderer.dart:431-477): three
  list comprehensions, `morphGlassContainerGroups` (glass_outline.dart:588)
  even at spacing 0 (early return, cheap).
- `morphLiquidLayer` (widgets/glass_liquid_native.dart:333-441): a new
  `GlassContentSnapshot()` every build (:354), a Stack of keyed Positioned,
  a `_Platter` with `Opacity` (saveLayer) during the first quarter of lift
  (:393-401, 476), a `ClipPath` with an even-odd hole over the live content
  (:402-410, 652-690), the content copy (:413-427) and a second
  `LiquidGlassLayer` for the lifted lens with `shared: false` (:428-437) -
  its own pass break.
- `_layer` (:209-239): `morphLiquidSettings` builds a fresh preset
  `LiquidGlassSettings` per surface per frame (:58-73, 79-111: two
  `copyWith`), a `ClipRect(const _Reach())`, a `LiquidGlassLayer`
  StatefulWidget whose `_buildLayer` allocates
  `LiquidGlassAppearance.ios27Toolbar(...)` and depends on
  `MediaQuery.platformBrightnessOf` every build
  (rendering/liquid_glass_layer.dart:235-239; morph never passes
  `defaultAppearance`), then `MultiShaderBuilder` -> `_RawShapes` ->
  `updateRenderObject`.
- `_glass` (:188-205): `LiquidGlass` -> `_LiquidGlassState.build`
  (liquid_glass.dart:46-98: scope lookup, `copyWith`, KeyedSubtree,
  OptimizedClip, `Opacity(appearance.visibility)` around an empty child,
  `GlassShadow` when shadows are non-empty).
- Render side: the lens shape changes every frame so
  `RenderLiquidGlass.shape` forces a geometry rebuild
  (liquid_glass.dart:175-180); lift changes refraction amount, so
  `settings` triggers `onSettingsChanged` -> `_updateShaderSettings`
  (writes ~65 floats into THREE shaders although one is bound,
  rendering/liquid_glass_layer.dart:496-514, 583-600) and
  `needsGeometryUpdate` (:691-699). `_buildGpuGeometryImage`
  (:1397-1603) packs uniforms, calls `roundedSuperellipseParameters`, and
  `FlutterGpuGeometryRenderer.render` encodes 1-2 command buffers
  (internal/flutter_gpu_geometry_renderer_native.dart:401-448). Then a new
  `ImageFilter.shader` (+ `compose` when frosted) because the engine
  snapshots uniforms at filter creation (:1160-1177).

Raster per lifted frame: root group capture (shared by resting bodies),
one extra break for the lifted lens (`shared: false`), the platter
saveLayer during the first quarter, the final shader pass over the lens
reach, and the content copy drawing the WHOLE content picture once per
strip per overlapping slot (up to 3 x 2 `drawPicture`s,
widgets/glass_liquid_native.dart:613-629; `shouldRepaint => true`, :634).

UI-thread cost here is dominated by widget churn (item A3), not by physics
(the pure motions are cheap by design: MorphLensMotion.advance is a few
closed-form springs plus the sub-clock, widgets/lens_motion.dart:527).

### 1b. The menu (MorphMenuButton, bar back menu)

Per frame while opening/closing:

- `MorphMenuLayer` rebuilds the whole layer under
  `Listenable.merge([host.menuRepaint, flight.frameTicks])`
  (widgets/menu.dart:931-1010), including `_cards` and `_glow`.
- `motion.silhouette` (widgets/menu_motion.dart:1547-1555): while
  `fusionRadius >= 1` a blurred-SDF trace per frame (0.36-0.71 ms device,
  memo in `MorphMenuFusion.outline` misses every frame because both rrects
  move, widgets/menu_fusion.dart:50-59); while `fusionRadius < 1` (the
  kick tail, press growth, content grow/shrink) it falls through to
  `morphGlassContainerOutline([rootBlob, buttonBlob], 0)`, i.e. a FULL
  field trace of two boxes per frame (glass_outline.dart:634-767) for a
  silhouette the geometry shader draws analytically as a plain-min group
  (shaders/gpu/sdf.glsl:398-403 `k <= 0` -> min). The global memo of four
  (glass_outline.dart:624, 643) is thrashed by the cards below.
- Every submenu card: `BackdropGroup(child: Builder(... glass.buildBody(
  context, morphGlassContainerOutline([surface.shape], 0), [surface])))`
  (widgets/menu.dart:1215-1222). That is (1) a CPU field trace of ONE
  rounded rect per card per frame while the card rect animates, (2) an
  RGBA32F `GlassField` upload per card per frame (`_FieldTextures.upload`,
  flutter_gpu_geometry_renderer_native.dart:1024-1049), (3) a
  `MorphGlassBodyShadow` with an UNBOUNDED `saveLayer(null, ...)` plus a
  MaskFilter-blurred `drawPath` of the outline and a dstOut cutout
  (widgets/glass_body_shadow.dart:22-36), (4) `shared: false` because the
  kind is menu (glass_liquid_native.dart:292, 313-314): one pass break per
  card, with the `BackdropGroup` wrapper being a group of one (pointless
  but harmless). A root menu with two open cards is 3 captures + 3 blur
  chains (cardBlur) + 3 shader passes + 3 shadow saveLayers per frame.
- `_Faded` (menu.dart:722-765): `Opacity` + `ImageFiltered(blur ∘
  ColorFilter)` over the whole content during the content blur - one
  saveLayer + Gaussian of the full menu content per frame. Measured UIKit
  behaviour; keep, see A7 for bounding.
- Flat tier only: `_CardBackdropClipper.shouldReclip => true` with
  `Path.combine` per under-list (menu.dart:2080-2095),
  `_CardPlatterPainter.shouldRepaint => true` allocating a
  `ui.Gradient.linear` per paint (:2124-2167).

### 1c. Chrome at rest while content moves (the real steady state)

MorphNavigationStack lays the bar and the toolbar as siblings over the page
(widgets/navigation_stack.dart:346-380, 1006-1035). Each is a `MorphBarItems`
whose `buildLayer` makes one body layer with `shared: !chrome` = false
(glass_liquid_native.dart:371-377, 313-314) -> two independent captures,
two chromeFrost blur chains, two shader passes per frame, for ever, while
anything under them repaints. `MorphScrollEdgeEffect` adds a
`BackdropFilter` with no group key per edge (widgets/scroll_edge_effect.dart:
233-237): up to two more breaks. So a plain scrolling page with a nav bar,
a toolbar and both edge effects is 4 pass breaks + 2-4 blur chains + 2
shader passes per frame before the app draws anything of its own. On the
UI thread the same page pays the per-frame compositing polls of every glass
layer (section 0) and, in `MorphBarItems`, nothing (the ticker sleeps) -
until a scroll edge effect or title motion wakes `frames`, at which point
PF1 (bar_items.dart:1086-1200 rebuilds every item each tick) applies.

### 1d. Engine flights and the skin

Already shaped right: the shuttle builds content once and per tick only
rebuilds wrappers (flight.dart:1621-1628, 1665-1830); `Opacity` at 1 paints
through; the skin is a repaint boundary that re-traces only on a changed
signature (skin.dart:1240-1247) and otherwise draws one path + one
`drawShadow` (:1268-1272). Inherent per-tick raster: the `Material`
elevation shadow on a changing shape (flight.dart:1775-1784) and the
fade-through `Opacity(frame.targetOpacity)` saveLayer (:1812). Neither can
be removed without changing pixels; both are bounded to the container. The
skin's hot path is covered by its own benchmarks; nothing new to add.

## 2. Ranked optimizations (gain x confidence; pixels identical unless said)

### A1. Draw single-shape and non-fusing bodies analytically, not from a traced field
Gain: high (removes 0.3-0.7 ms UI per card/frame plus one field upload per
card per frame, and the two-box trace every frame of the menu's kick tail).
Confidence: high. Fidelity: the analytic shapes ARE the reference the field
imitates - the field's `halfMinor` and optical `turn` exist to make a fused
corner light "where the same shape alone does" (glass_outline.dart:47-53;
glass_renderer.md "The field's gradient is the field's own normal TURNED to
the optical corners"), so a lone rounded rect through the field path is an
approximation (bilinear from a 4 pt grid) of what the shape pass draws
exactly. Expect identical-or-better; verify with glass_audit shots of the
open menu with cards (max channel diff should sit inside the existing <= 19
run-to-run noise).
Where: widgets/menu.dart:1215-1222 (cards: call `buildSurface`, or pass
`outline: null` so `MorphGlassLayerParts` yields `separate`);
widgets/menu_motion.dart:1551-1553 (return a path-only union or null when
`radius < minimumRadius` and let the renderer's plain-min group draw it;
`morphLiquidLayer` must then keep the SAME wrapper chain so the 'body' key
does not swap types - the fused path wraps `_layer` in a `CustomPaint`
(glass_liquid_native.dart:283-296) while the separate path does not
(:371-377); audit K1 is the same hazard. Always mount the `CustomPaint`
and give `MorphGlassBodyShadow` empty shadows when there is no fused
outline.)
Also: the 4-entry global memo `_recentOutlines` (glass_outline.dart:624,
643) should become per-owner (a `MorphMenuFusion`-style memo on the card
state) once cards stop tracing; today the cards and the bars evict each
other.

### A2. One backdrop capture for sibling chrome; count captures in the audit
Gain: high at steady state (halves the pass breaks of a bar+toolbar page;
removes two more if the edge effects join). Confidence: high for the two
bars, medium for the edge effects. Fidelity: pixel-identical for the nav bar
and toolbar - they never overlap and nothing of the page paints between
them in z (navigation_stack.dart:346-380). NOT identical if the edge effect
joins the same key: the bar's frost today samples the edge effect's already
blurred band under it; with a shared snapshot it samples the raw content.
Under sigma 14 the difference is tiny but non-zero (audit PF9 flagged the
same); measure before deciding.
Where: glass_liquid_native.dart:313-314 (`_chrome` -> `shared: false`) and
:371-377; the bar layers need a way to say "chrome, but share THIS key":
e.g. `MorphGlassPainter.buildLayer` gains a `backdropKey:` (or
MorphNavigationStack wraps both bars in a `BackdropGroup` and the chrome
path uses `BackdropGroup.of(context)` when one is an ancestor that is NOT
the root group). scroll_edge_effect.dart:235 for the edge effects.
Instrument first: `debugRegisterBackdropCapture` already exists
(rendering/liquid_glass_layer.dart:1219-1224); have glass_audit_test record
captures per scene next to the frame timings. Use Instruments > Metal
System Trace to confirm pass counts on the phone.

### A3. Stop rebuilding the renderer widget stack per tick; write render objects
Gain: medium-high (the 1.2 ms / 2.2 ms UI deltas liquid-vs-flat on
segmented / tab bar are almost entirely this). Confidence: high on
direction, medium on magnitude (expect to recover most of the delta, not
all: the matte re-render encoding stays). Fidelity: none - same render
objects, same values.
Where: widgets/glass.dart:466-482 is the one entry; the per-frame data is
already a pure `List<MorphGlassSurface>` from `surfaces()`. Shape of the
fix, in increasing ambition:
  1. Cheap wins inside the current tree: cache the default
     `LiquidGlassAppearance.ios27Toolbar` per brightness and pass
     `defaultAppearance` explicitly (rendering/liquid_glass_layer.dart:
     235-239; today also a `MediaQuery` dependency per layer); hoist
     `_preset` per (renderer, brightness) (glass_liquid_native.dart:58-73);
     write only the ACTIVE shader's uniforms with a per-shader dirty flag
     (liquid_glass_layer.dart:496-514, 583-586; `renderShader` :441-446);
     keep one `GlassContentSnapshot` per control instead of one per build
     (glass_liquid_native.dart:354; `updateRenderObject` disposes the old
     one every frame, internal/content_snapshot.dart:105-108).
  2. The real fix: a `MorphGlassSurfaces` channel (ValueListenable of the
     surface list) consumed by a liquid-tier RenderBox that owns its
     `RenderLiquidGlass` children and updates `shape` / `appearance` /
     `settings` / child offsets in a listener - the skin's
     `MorphPieceChannel` pattern ("a write is markNeedsPaint ONLY",
     CLAUDE.md). The widget tree then builds once per layout; ticks never
     enter `build`. Flat and frosted tiers can stay widget-based (they are
     cheap) or ride the same channel.
This also retires PF5's glass button case (glass_button.dart:498-510
`ListenableBuilder` over `LayoutBuilder` over `MorphGlassLayer`).

### A4. Bound the fused-body shadow saveLayer
Gain: medium on raster during menu/bar fusion (an unbounded saveLayer sizes
to the culling bounds, i.e. the whole overlay, then a MaskFilter blur of an
arbitrary path, then dstOut, every animating frame and per card).
Confidence: high. Fidelity: identical when the bounds include the blur
support (`glassShadowBlurSupport`, renderer/glass_shadow.dart:14-15) and
the offset; the cutout stays inside.
Where: widgets/glass_body_shadow.dart:22 `canvas.saveLayer(null, Paint())`
-> `outline.getBounds().inflate(support).shift(offset) union bounds`.
Compare with the renderer's own `drawGlassShadows`, which is already
bounded (rendering/liquid_glass_render_object.dart:742). At rest the
painter is skipped by identity (`shouldRepaint`, :40-43, because
`MorphMenuFusion` returns the same outline object), so this is
animation-only.

### A5. Lens content copy and lens clips: rrect difference clips, no even-odd paths
Gain: medium while a lens is lifted (Impeller rect/rrect clips are cheap;
even-odd path clips are not, and there are three per frame: the live
content hole glass_liquid_native.dart:402-410 + 652-690, and the tab bar's
two `_LensClipper`s tab_bar.dart:449-451, 486-488, 727-755). The copy
painter draws the whole content picture per strip per overlapping slot
(:613-629) with `shouldRepaint => true` (:634). Confidence: medium (clip
cost on A18 is small in absolute terms; the gain is in avoiding stencil
path clips and 3-6 full picture replays). Fidelity: identical - a
`clipRRect(lens, clipOp: difference)` is the same set of pixels as the
even-odd hole; clipping each `drawPicture` to `slot ∩ lens` before the
transform is already done.
Also flag a trap, not a cost today: `GlassContentSnapshot._capture` falls
back to `layer.toImageSync` (internal/content_snapshot.dart:56-63) - a
synchronous raster + readback on the UI thread EVERY lifted frame - as soon
as the content's layer tree holds any layer other than PictureLayer or a
plain OffsetLayer (a child that needs compositing: a nested BackdropFilter,
a Texture, a ClipRectLayer from a composited descendant). Consumer tab
items with such content will silently hit it. Add a debug counter and an
assert in tests.

### A6. Skip compositing polls for layers whose frame did not touch them
Gain: low-medium at steady state (N glass layers x ancestor-walk x 3 per
frame: `syncCompositionOpacity` walks to the enclosing layer
(internal/glass_composition_probe.dart:45-67), `syncAncestorClips`,
`pollCompositorTranslation` -> `getTransformTo` per shape
(rendering/liquid_glass_render_object.dart:641-651, 503-551;
internal/render_liquid_glass_geometry.dart:179-202)). With ten glass
buttons on a page that is ~0.1-0.2 ms UI per frame while a list scrolls.
Confidence: medium. Fidelity: none, but correctness risk: these polls are
what keep a scrolling glass button's retained filter mapped to the backdrop
(`onCompositorTranslated`, :1260-1268); any skip must be keyed off "no
ancestor transform changed", which `GeometryTransformTrackingLayer`
already computes (transform_tracking_repaint_boundary_mixin.dart:145-153)
- run the opacity and clip syncs only when `onTransformChanged` fired or
paint ran. `alwaysNeedsAddToScene => true` (:137) can stay; its cost is
UI-side scene re-adding only, since Impeller has no retained raster.

### A7. Bound the ImageFiltered content fades and the glow/platter saveLayers
Gain: low-medium (one saveLayer + Gaussian per frame during the menu's
content blur and the title/search blurs; the platter crossfade saveLayer
for the first quarter of every lift). Confidence: medium. Fidelity: none.
Where: widgets/menu.dart:743-764 (`ImageFiltered` has no bounds hint;
wrap in a `ClipRect` sized to the content so the filter pass covers the
menu, not the overlay), navigation_bar.dart:491-497, search_field.dart:875,
bar_items.dart:1272; `_Platter` glass_liquid_native.dart:476 (an `Opacity`
around a DecoratedBox: paint the platter with an alpha-scaled color and a
`BoxShadow` whose color is scaled too - identical for a single-color fill
with one shadow only if shadow and fill do not overlap in alpha, so test
the crossfade frames; otherwise keep).

### A8. Shader and pipeline warm-up
Gain: one-off (the first-glass hitch; CLAUDE.md records the worst raster
frame as "first-use shader work"). Confidence: medium. Fidelity: none.
`precache()` (glass_liquid_native.dart:20-35) loads the three
FragmentPrograms and the GPU bundle (and builds the Flutter GPU pipelines
synchronously in `_SharedGeometryResources`, flutter_gpu_geometry_renderer_
native.dart:1062-1090) but Impeller creates the runtime-effect PIPELINE
VARIANTS (per blend / sample count / target format) and the Gaussian blur
pipelines on first draw on the raster thread. Options: an opt-in one-frame
warm-up widget that mounts a clipped-away frame of each variant (body
glass, frosted chrome with a blur pass, a lifted lens with dispersion and
backdrop shrink), or an offscreen `Scene.toImage` of the same from
`precache` (medium confidence that offscreen variants match onscreen MSAA /
format). The fake-glass surface shader is not precached at all
(`_fakeSurfaceShaderAssets`, rendering/liquid_glass_layer.dart:119-121,
339-343) - irrelevant on the device, visible on simulators.

### A9. Governor fallback policy: frosted is not a cheaper tier for controls
Gain: high on weak devices only. Confidence: medium. Fidelity: frosted's
blur radii are "engineering defaults, not measured" (glass_defaults.dart:
13-24), so there is no measured look to lose. The passport's own numbers
(controls scene raster p95: liquid 2.67, frosted 3.70, flat 0.79) show the
step down liquid -> frosted RAISES raster cost when controls dominate,
because frosted blurs every glass surface (`_FrostedSurface`,
glass_renderer.dart:517-573) while liquid frosts only chrome and lifted
lenses. Either let the governor skip frosted for scenes whose glass is
mostly controls, or give frosted buttons/tracks no blur pass (sigma 0 ->
the shader-free path still tints and rims). Where: glass_tier.dart:135-150
(`addFrame` steps one tier at a time), glass_renderer.dart:499-510
(`_frostSigma`).

### A10. Allocation hygiene in the per-frame path (GC pressure at 120 Hz)
Gain: low each, adds up. Confidence: high. Fidelity: none.
`MorphGlassLayerParts.of` lists (glass_renderer.dart:436-476);
`_shadows()` per surface (glass_liquid_native.dart:167-186); `_local()`
copy (:241-257); `MorphGlassSurface` lists in every host's `_surfaces()`;
`_prepareGeometryAppearance` builds an appearances list and `listEquals`
per paint (rendering/liquid_glass_layer.dart:931-950);
`_appearanceLookupData` 128 doubles per mixed render (:619-639);
`morphGlassOutlineFromFields` allocates `Float32List` + a fresh `Path` per
trace (glass_outline.dart:199, 222); `_fuseContainer` allocates five
typed arrays per call (:672-677) where `menu_fusion.dart` already keeps
them in `_Scratch` (:520-565) - reuse the same pattern. Also the plain
`shouldRepaint => true` painters (segmented_control.dart:458,
slider.dart:466, switch.dart:309, tab_bar.dart:701/724, progress.dart:319)
are harmless only because they are the flat path and their CustomPaint is
not rebuilt per tick (the `repaint:` Listenable does the work).

### A11. 120 Hz hygiene for consumers (fidelity, not speed)
The example opts into ProMotion (example/ios/Runner/Info.plist:5
`CADisableMinimumFrameDurationOnPhone`) and Flutter GPU (:27). A consumer
that forgets the first key runs frames at 60 Hz while
`MorphClock.motionFrameRate` reads 120 from `display.refreshRate`
(widgets/clock.dart:85-89), so the flex sub-clock steps twice per rendered
frame - a deformation mismatch against the recordings, not a perf cost.
Worth a README line and a debug check (`SchedulerBinding` frame spacing vs
`motionFrameRate` over the first second).

## 3. What is already right (do not "optimize")

- Tickers sleep on settle (clock.dart:72-76): a static page with glass
  costs nothing until something else repaints.
- The matte is retained and only translated under uniform motion
  (rendering/liquid_glass_layer.dart:830-837, 885-911); textures ride a
  bucketed ring (flutter_gpu_geometry_renderer_native.dart:880-1000); one
  HostBuffer per frame (:137-191); command buffers are flushed before the
  scene reaches the raster thread (:558-568, transform_tracking_repaint_
  boundary_mixin.dart:159-164).
- The lens's shrink/magnification are done in the shader and a pre-grown
  copy, not by re-rendering content at higher resolution (the renderer
  never enlarges its backdrop; upstream's Loupe was rejected).
- Sub-pixel frost folds into the final pass instead of a blur pass
  (:602-615).
- `_Reach` clips every liquid layer to the control + 24 px
  (glass_liquid_native.dart:640-650), so filter coverage is the control,
  not the screen.
- Fused outlines are sampled sparsely near the edge and memoized by
  inputs (menu_fusion.dart:165-196, glass_outline.dart:725-751, 638-644);
  the tracer buffers persist (glass_outline.dart:516-574,
  menu_fusion.dart:520-565).
- The skin re-traces only on a changed signature and paints one path.
- The engine's shuttle builds content once per flight.

## 4. Things I looked for and did not find (so they are not on the list)

- No `toImage`/readback in the production per-frame path except the
  snapshot fallback in A5.
- No per-tick `setState` in control hosts' tick path (the 56 `setState`
  calls in widgets are event-driven; the two in `lens_driver.dart:70` and
  `tab_bar.dart:314` are post-frame reconciliations).
- No Opacity between resting glass and its layer (the rule in CLAUDE.md
  holds; `_Platter` and the shuttle's `Opacity` sit outside glass).
- `MultiShaderBuilder` creates each `FragmentShader` once per State, not
  per build (internal/multi_shader_builder.dart:109-121); the three
  `final` shader fields on `RenderLiquidGlassLayer` are consistent with it.
- The menu kick Euler loop (audit PF7) has its idle skip-ahead per
  PLAN.md (793dc9f); not re-audited here.

## 5. How to verify without arguing

1. Add to example/integration_test/glass_audit_test.dart, per scene: the
   independent backdrop capture count (hook
   `debugRegisterBackdropCapture`, backdrop_capture_debug.dart), the
   `FlutterGpuGeometryRenderer.debugTotalRenderCount` delta, and
   `RenderLiquidGlassLayer.debugPaintCount` deltas - these turn A1, A2,
   A3 and A6 into numbers, not opinions. Keep `AUDIT_OUTLINES_ONLY` for
   A1's CPU side.
2. Pixel identity: the audit already diffs reference states with a <= 19
   max-channel noise floor; run liquid before/after A1, A2 (bars only),
   A4, A5, A7 and require the same floor. A2 with the edge effects joined
   is the one change that may fail that bar; decide on the diff.
3. GPU truth: Instruments > Metal System Trace on the iPhone 16 Pro for
   the "scroll under nav bar + toolbar" case, counting render passes per
   frame before and after A2. Expect 4 -> 2 (bars only) or 4 -> 1 (edge
   effects joined).
4. UI thread: the existing per-scene build p95 in the audit; A3 should
   move segmented from ~1.75 toward the flat tier's 0.54 and the tab bar
   from 2.91 toward 0.69 (the remainder is matte encoding + PF1).

## 6. Order I would do them in

A1 (one afternoon, biggest CPU win, closes an architectural wart) ->
A2 bars-only with the capture counter (half a day, biggest GPU win at
steady state) -> A4 and A5 (small, mechanical) -> A3 step 1 (hygiene)
then A3 step 2 together with PF1 (the bar rebuild) as one "render-object
glass channel" change -> A9 policy -> A6/A7/A8/A10 as time allows.
