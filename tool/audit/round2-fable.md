# Round 2 bottleneck review (Fable, 2026-10-06, read-only)

Scope: a fresh attribution of the Pixel 6a numbers after the 2026-10-05
batch (menu fusion, field uploads, retained layers, surfaces channel,
glass container, warm-up, shader audit), and the levers left. Inputs:
CLAUDE.md, glass-renderer.md, every tool/audit/*.md, the perf dirs
2026-10-05-* and 2026-10-06-shader-audit/e2e, the atrace of
2026-10-05-pixel6a-attrib, and the code under lib/src/glass/renderer,
lib/src/widgets/glass*.dart, menu*.dart, bar*.dart, chrome_group.dart,
scroll_edge_effect.dart, navigation_stack.dart, sheet.dart.

Not covered here: glyph atlas churn (text under animated scale). Another
agent owns it. Its weight in the Pixel trace is recorded in 1.2 so the two
reviews add up, and 2.x notes where a lever of this review would interact
with it (retaining pictures under a Transform.scale does not stop atlas
churn; Impeller re-rasterizes glyphs per scale step).

Conventions: Pixel 6a = Mali-G78, Impeller Vulkan, 60 Hz, 16.67 ms
budget, profile builds, DPR 2.625. "raster" = FrameTiming.rasterDuration,
which ENDS AT SUBMIT: it is raster-thread CPU plus any wait the thread hits
(swapchain acquire, buffer release), never GPU execution time. "layer" =
one `LiquidGlassLayer` = one BackdropFilterLayer = one Impeller saveLayer
subpass with a runtime-effect filter.

## 1. Where the time goes on the Pixel 6a

### 1.1 The current numbers (perf/2026-10-06-shader-audit/e2e, 9f330b5 and HEAD; flat from 2026-10-05-pixel6a-cpu-menu, 3e81b9e)

Median of 5 runs, active frames, ms. `over` = frames over 16.67 ms per
run (about 100 - 170 active frames per scene).

| scene | liquid build p50 / p95 | liquid raster p50 / p95 | over | flat build p50 / p95 | flat raster p50 / p95 | over |
|---|---|---|---|---|---|---|
| home-scroll | 2.9 / 5.6 | 8.5 / 11.5 | 2 | 2.8 / 5.5 | 7.8 / 10.4 | 2 |
| segmented | 5.0 / 7.4 | 8.7 / 11.4 | 0 | 1.4 / 3.2 | 6.6 / 10.3 | 0 |
| tab-bar | 5.5 / 8.8 | 11.0 / 14.5 | 14 | 2.3 / 4.2 | 8.2 / 10.0 | 0 |
| controls | 4.8 / 12.2 | 8.9 / 15.0 | 13 | 1.4 / 7.6 | 5.5 / 6.7 | 0 |
| menu | 6.0 / 14.8 | 10.8 / 20.5 | 23 | 2.7 / 11.6 | 5.4 / 14.6 | 12 |
| sheet | 2.7 / 6.7 | 10.5 / 15.0 | 6 | 1.5 / 3.8 | 5.5 / 7.7 | 0 |

Two readings that frame everything below:

- THE FLOOR IS HIGH. The flat tier, with no glass at all, already rasters
  at p95 10.0 - 10.4 ms on home-scroll, segmented and tab-bar, and the
  flat menu has 12 frames over budget per run. On this device a scrolling
  or animating gallery page costs ~8 ms raster at p50 and ~10 at p95
  before any glass. Glass has ~6 ms of raster p95 to spend. It spends
  +1.1 (segmented, home), +4.5 (tab bar), +5.9 (menu), +7.2 (sheet), +8.3
  (controls) today. The deltas, not the absolute numbers, are what the
  package owns.
- THE BOTTLENECK IS THE RASTER THREAD'S CPU, NOT THE GPU. The shader
  batch's 2 - 9 percent GPU gain did not move raster (glass-renderer.md
  "Shader harness"), and the atrace below accounts for the whole raster
  frame in CPU-side slices with no acquire or buffer-release wait worth
  naming. GPU time was never recorded for a gallery scene; 1.4 says how.

### 1.2 Raster thread anatomy (atrace 2026-10-05-pixel6a-attrib, whole liquid audit vs whole flat audit)

Slice totals over the capture divided by frames rendered (2761 liquid,
2825 flat); self time unless marked incl. Means over every scene, so they
understate the menu and overstate home-scroll, but the SHAPE is the point.

| raster-thread slice | liquid ms/frame | flat ms/frame | note |
|---|---|---|---|
| GPURasterizer::Draw (incl, the frame) | 9.96 | 7.16 | |
| SurfaceFrame::Encode (self) | 2.80 | 2.18 | Impeller display-list dispatch into render passes, per draw op |
| QueueSubmit (raster, incl) | 2.71 | 1.94 | 2.0 / 1.6 submits per frame at 1.37 / 1.21 ms each |
| Canvas::saveLayer (self) | 1.74 | 0.37 | 10.4 / 1.1 saveLayers per frame at 0.17 / 0.35 ms |
| CreateGlyphAtlas (incl) | 0.88 | 0.73 | of which UpdateAtlasBitmap 2.5 ms in 22 / 17 percent of frames (other agent) |
| queueBuffer + QueuePresentKHR + AcquireNextSurface | ~1.8 | ~2.3 | swapchain; flat waits more because it is faster |
| LayerTree::Paint + Preroll | 0.42 | 0.28 | |
| AllocateCommandBuffers | 0.10 | - | 6.9 per frame |
| PipelineVK::Create | 26 x 5.9 ms over the run | - | first use; warm-up landed after this trace |

Liquid minus flat is ~2.8 ms per frame on average and it is three terms:
saveLayer encoding +1.37, submit +0.77, Encode +0.62. Nothing else moves.
The three scale together with the number of glass layers: on Mali, vkQueueSubmit
builds the tiler and fragment job chains for EVERY render pass in the
command buffer, so a saveLayer costs once at encode (0.17 ms) and again
at submit; the density scene measured the whole per-layer tax at 0.31 ms
raster per resting liquid layer for N <= 16 (glass-renderer.md "Glass
container": n1 5.74 -> n16 10.43 p50). The container's gain (-1.4 .. -2.4
ms at n4 .. n32) is this tax times the layers it removed.

What a glass layer puts on the raster thread, in order of cost:

1. The BackdropFilterLayer saveLayer with the runtime-effect filter
   (rendering/liquid_glass_layer.dart:1304-1306, 1337-1346): one subpass,
   plus a full-screen FlipBackdrop when its key has no earlier member.
2. For frosted layers (bar / menu kind, lifted small lens) the composed
   `ImageFilter.compose(blur, shader)` (:1276-1285) is five passes:
   downsample, blur Y, blur X, full-resolution re-rasterize, shader
   (flutter-tricks F3).
3. THE SHADOW PICTURE'S saveLayer. `RenderLiquidGlassLayer` records its
   shape shadows through `drawGlassShadows`
   (rendering/liquid_glass_render_object.dart:739-796), which opens
   `canvas.saveLayer(effectPaintBounds, Paint())` (:742) and cuts the
   shapes back out with `BlendMode.dstOut` (:787-789). Every layer whose
   shapes carry shadows - every glass button layer, every bar capsule layer
   (`button` kind -> `MorphGlassDefaults.bodyShadow`,
   glass_liquid_draw.dart:134-139), every standalone density button - pays
   a second subpass per frame, forever, because the picture is retained but
   Impeller re-executes it every frame (F4). The b0f79b1 change ("glass
   shadows clipped, no saveLayer") reached GlassShadow (fake tier) and
   MorphGlassBodyShadow (fused bodies), not this path. This is the ~1.6
   saveLayers per frame the layer census (8.8 filters) does not explain in
   the 10.4 the trace counts.
4. Widget-level offscreen passes around glass during transitions: the
   ZOOM present's crossfade - `Opacity(opacity: fade)` around the whole
   sheet (sheet.dart:881) and `Opacity(1 - fade)` around the source replica
   (zoom_source.dart:122), both fractional for the crossfade's frames, so
   the sheet's own glass then paints inside a seeded probe pass as well
   (internal/glass_composition_probe.dart:35-38; the outer Opacity at
   sheet.dart:864 is at alpha 1 except in the source-lost dissolve and
   costs nothing) - `ImageFiltered` blur +
   `Opacity` on the menu's button look and on the whole card content
   (menu.dart:776-796, 1023-1030), `ImageFiltered` + `Opacity` per bar item
   in transition (bar_items.dart:1434-1447), `GlassLiveOpacity` around the
   platter for the first quarter of every lift (glass_liquid_draw.dart:560).
   Each is a subpass, some with a Gaussian.

### 1.3 UI thread anatomy (same trace)

| UI slice | liquid ms/frame | flat ms/frame |
|---|---|---|
| Animator::BeginFrame (incl) | 5.27 | 3.11 |
| BUILD | 1.04 | 1.08 |
| LAYOUT | 0.92 | 1.04 |
| PAINT | 1.78 | 0.71 |
| COMPOSITING (self) | 1.35 | 0.52 |
| QueueSubmit on the UI thread (Flutter GPU geometry passes) | 0.44 (0.8 submits at 0.54 ms) | 0 |
| CollectNewGeneration | 0.16 mean; one scavenge per 14 frames at 2.2 ms | 0.10; one per 21 frames at 2.1 ms |

Liquid costs the UI thread +2.2 ms per frame on average and +4.2 ms at the
menu's p50 (6.0 vs 2.7 ms build), all of it in PAINT and COMPOSITING. Builds
and layout are already at the flat tier's level: the surfaces channel did
its job. Per glass layer per frame the UI thread now does:

- PAINT: `paintFrame` (liquid_glass_layer.dart:941-1028) ->
  `_prepareGeometryAppearance` (a fresh appearances list + listEquals,
  :1030-1049), and, when geometry changed, `_buildGpuGeometryImage`
  (:1512-1718: per shape ~10 Offset / Size / List allocations, a
  `roundedSuperellipseParameters` list, Matrix4 math) ->
  `FlutterGpuGeometryRenderer.render` (flutter_gpu_geometry_renderer_native.dart:283-480:
  ~12 FFI calls, a 2352-byte uniform pack and arena copy, a field upload
  for fused bodies) -> `_recordOriginalShadows` (:1118-1134: a NEW
  PictureRecorder and a shadow redraw on EVERY paint, even when nothing but
  the backdrop changed) -> `_bindGeometryShader` (:1053-1109: ~70 uniform
  floats and 4 samplers written per paint) -> `_updateShaderFilter`
  (:1271-1288: a new `ImageFilter.shader`, and a compose + blur for frosted
  layers, whenever any input changed - every frame while moving).
- COMPOSITING: `GeometryTransformTrackingLayer.updateSubtreeNeedsAddToScene`
  (transform_tracking_repaint_boundary_mixin.dart:137-153) runs
  `trackedTransform()` = `getTransformTo(null)` PLUS `.clone()`
  (liquid_glass_layer.dart:1143-1147), then `runCompositorPoll`
  (liquid_glass_render_object.dart:641-651): `syncCompositionOpacity` walks
  to the enclosing layer (glass_composition_probe.dart:45-69),
  `syncAncestorClips` walks again, `pollCompositorTranslation` does a
  `getTransformTo` per shape, then `syncCoordinateMapping` inverts a Matrix4
  and transforms three points (:1193-1206), possibly rebuilding the filter.
  Then `addToScene` of ClipRect + BackdropFilter + OffsetLayer, and
  `flushPendingSubmissions` (one vkQueueSubmit on the UI thread, 0.54 ms on
  this CPU: that is the Mali driver's submit cost, not Dart).
  With ~9 layers in the menu scene that is ~90 us per layer in COMPOSITING
  self - three tree walks, two Matrix4 allocations and three native layer
  adds on a Cortex-A55-class little core is about that.
- GC: liquid scavenges 50 percent more often than flat on the same scenes.
  A scavenge is 2 ms here; landing inside a frame it is a p95 frame by
  itself. The passport also saw old-generation marking land mid-frame in
  the menu (3.1 ms in one frame).

### 1.4 GPU: not measured for any gallery scene

Everything above is CPU. The one GPU instrument that exists reads the
kernel's gpu_work_period for the shader bench (audit_android.sh
`AUDIT_GPUWORK=1`, tool/audit/shader/gpu_work.py). It was never pointed at
glass_audit. Until it is, "GPU has headroom" rests on inference (raster
would show acquire waits if the GPU were behind; it shows none). The sheet
scene is the one where the GPU could be close to the budget: a 340 x 600 pt
frosted face is 0.9 M device px through the five-pass chain plus a 1.8 Mpx
full-screen flip for its content group; the shader bench puts big-sheet
GPU at the top of every table.

### 1.5 Per-scene attribution and the measurements to get

Layer census per scene (from the code; the device census tool used for
"8.8 filters" should confirm per scene and per phase):

- home-scroll: root group (page body glass, if any) + edge effect (own
  flip, scroll_edge_effect.dart:457, no key) + chrome group (nav bar
  capsules; toolbar shares the key, chrome_group.dart:53) = 3 flips, 3 - 4
  layers, 1 - 2 shadow saveLayers. Liquid costs +0.7 raster p50 over flat
  here - the resting case is already cheap.
- segmented: body layer (1) + lifted lens layer (own copy, shared: false,
  glass_liquid_draw.dart:539) + platter opacity pass for the first quarter
  of the lift + content copy (CustomPaint, no pass) + the page's bars and
  edge effect. +1.1 raster p95 over flat: fine.
- tab-bar: bar layer (frosted: bar kind) + lifted lens layer (own copy,
  geometry re-encoded every frame of the drag: lift changes the codec
  scale) + edge effect + nav chrome. +4.5 raster p95.
- controls: the container's layer for the button row + switch knob /
  slider thumb lifted layers (own copies, re-encoded per frame) + platter
  passes + slider track fills + bars + edge effect. +8.3 raster p95, the
  worst delta: it also has the most moving geometry per frame on the UI
  thread (build p95 12.2 vs flat 7.6).
- menu: menu face (one fused body: field upload + geometry pass every
  frame while fusing, frosted chain) + card(s) (one body each, frosted,
  own BackdropGroup, menu.dart:1252) + the content blur ImageFiltered pass
  (menu.dart:1023) + the look's ImageFiltered + Opacity (menu.dart:776)
  + the page's glass button under it + bars + edge effect. 23 frames over
  budget per run; raster p95 20.5; build p95 14.8 (flat 11.6: the UI
  thread's p95 is mostly NOT the renderer - see lever U4).
- sheet (the audited "Medium and large" present is the PLAIN path,
  sheet.dart:623 / 914, no Opacity): the sheet surface (menu kind,
  frosted, full sheet: the five-pass chain over 0.9 Mpx) + its content
  group flip + the buttons' container inside + bars. +7.2 raster p95 with
  only two or three layers more than flat: this is the one scene where the
  per-layer tax does not explain the delta, so the frosted chain's own
  raster encoding and the GPU are the suspects - M1 and M2 first. The zoom
  present adds the two crossfade Opacity passes of 1.2 item 4.

Measurements that would turn the estimates above into numbers (all are a
few hours each, no code changes in lib/):

- M1 GPU busy ms per frame per scene: run glass_audit with
  `AUDIT_GPUWORK=1` and attribute work periods to scene windows (the
  harness records `(start, end)` frame indices per scene in `_scenes`,
  glass_audit_test.dart:153-163; it needs the frame timestamps written
  into the JSON to join on the CLOCK_MONOTONIC periods).
- M2 Raster slices PER SCENE: emit `Timeline.startSync('scene:<name>')`
  around each `measure()` body (:153) so atrace_slices.py can window by
  scene, and add per-scene saveLayer and QueueSubmit counts to the
  table. One run gives the per-layer raster tax per scene directly.
- M3 Per-frame dumps: write the FrameTiming list per scene (an
  `AUDIT_FRAMES=1` define) so the p95 frames can be read off against the
  phase they fall in (open frame, settle tail, GC). Today the JSON holds
  only percentiles.
- M4 UI phases on the Pixel for menu and sheet: glass_phases_test has
  segmented, tab-bar and density only (:138-170); add a menu and a sheet
  scene (the agent's `PHASES_ONLY` define in the working tree makes this
  cheap to iterate).
- M5 Allocation per frame: `--profile` with the VM service
  `getAllocationProfile` (reset, then read after 60 frames of the menu
  scene) to find what allocates ~0.5 - 1 MB per frame; the 14-frame
  scavenge period says that is the order of magnitude.
- M6 The layer census per scene and phase (the tool behind "8.8 filters /
  8.85 glass layers", run for every scene, counting saveLayers inside
  pictures too).

## 2. Levers, ranked by gain x confidence

Gain is the Pixel 6a raster or UI p95 I expect, from the per-layer tax
(0.31 ms raster per layer, 0.17 per extra saveLayer, 0.54 per UI-thread
submit, 2 ms per avoided scavenge in a frame) and the census above.
Fidelity: IDENTICAL (same bytes), NEAR (stated maximum error, gated by the
shader harness or shot diff), VISIBLE (owner decision).

| # | lever | thread | gain on the Pixel | fidelity | confidence | effort |
|---|---|---|---|---|---|---|
| R1 | shape shadows through the even-odd clip, no saveLayer + dstOut (renderer path) | raster + GPU | -0.17 .. -0.3 ms per shadowed layer per frame: controls / menu / tab-bar about -0.5 .. -0.8 ms p50, density -N x 0.2 | NEAR (AA of the cut-out rim row; GlassShadow's own form, already accepted on fake and bodies) | high | S |
| U1 | pre-layout the menu's content before the open frame; one `PlatformDispatcher.requestDartPerformanceMode(latency)` window around open .. settle | UI | menu build p95 14.8 -> ~9 (the open frame and the mid-frame GC are the p95) | IDENTICAL | medium-high (needs M3 to confirm which frames) | S-M |
| R2 | the zoom present's crossfade without group `Opacity` over glass; fade the surface through `MorphGlassSurface.opacity`, the replica and content through their own alpha | raster + GPU | zoom sheets only: -2 sheet-sized saveLayers and -1 probe pass per crossfade frame: -1 .. -1.5 ms on those frames; nothing on the audited plain sheet | NEAR where children do not overlap, VISIBLE where they do (owner looks at the crossfade frames) | medium | M |
| U2 | per-frame hygiene in the layer: retain the shadow picture, drop `clone()`, reuse the appearances list, skip the three compositing walks when neither paint ran nor the tracked transform changed | UI + GC | -0.3 .. -0.6 ms per frame with ~9 layers; fewer scavenges | IDENTICAL | high for the first three, medium for the walk skip | S-M |
| R3 | one layer for the stack's nav bar + toolbar capsules (automatic chrome container) | raster | -1 layer and -1 shadow saveLayer per frame on every stack page with a toolbar: -0.3 .. -0.5 ms | NEAR (container semantics: exact matte positions, rim pixels up to ~50 steps as measured for the container) but a GPU cost (full-height matte, full-screen clip) | low-medium: measure, kill if GPU-bound | M |
| D | analytic SDF in the final shader for layers of <= 4 plain shapes while they move (no geometry pass) | UI + GPU | -1 geometry pass, -1 matte texture, often -1 UI-thread submit (0.54 ms) per frame per moving control; +ALU in the final pass | NEAR (12-bit matte quantization disappears; expected < 1 channel step on the face; the normal must stay analytic, never dFdx) | medium-low | L |
| F | menu silhouette one frame ahead on an isolate (typed arrays over, Path rebuilt on the main isolate) | UI | -0.5 .. -0.75 ms per fusing frame on the Pixel (menu10-r4 0.76 ms, r20 0.46; bar capsules 0.31) | IDENTICAL when the predicted frame stamp matches; sync fallback otherwise | low-medium | M-L |
| R4 | smaller filter-clip buckets for unfrosted layers (flutter-tricks L5) | GPU + raster | small: a 44 pt capsule's 128 px bucket vs its 116 px; saveLayer subpass bytes | IDENTICAL for unfrosted | medium | S |
| E | glass-aware `requestDartPerformanceMode` is app policy; the package can only recommend it | UI | p95 only | IDENTICAL | - | docs |

Not ranked, deliberately: anything changing blur sigma, field step, sub-clock
rate, or the measured chains; the screen-level unified canvas (rejected
twice, still rejected); tier switching at runtime (owner decision).

### R1. Shape shadows without a saveLayer (renderer path)

Where: rendering/liquid_glass_render_object.dart:739-796 (`drawGlassShadows`:
`canvas.saveLayer(effectPaintBounds, Paint())` at :742, the dstOut cut-out
loop at :775-793), recorded per layer by liquid_glass_layer.dart:1118-1134.
The clip form already exists for the fake tier: glass_shadow.dart:178-199
(`outside.fillType = evenOdd; addRect(bounds.inflate(1)); _addShape(outside,
rect.deflate(.5)); canvas.clipPath(outside)`, then plain blurred shape draws)
and glass_body_shadow.dart for fused bodies.

Sketch: in `drawGlassShadows`, replace the saveLayer with one even-odd
clip path containing `bounds.inflate(1)` and every visible shape's rect
deflated by .5 under its `geometryToLayer` / `shapeToGeometry` transform
(path.addRRect / addRSuperellipse / addOval with `Path.transform` or by
adding in the transformed canvas and using `Path.combine` - prefer
building the path in layer space: transform the four corner points when
the transform is affine, which it is for every control). Draw the shadows
with `BlurStyle.normal` as today; drop the second loop. Shadows with zero
offset can use `BlurStyle.outer` and no clip at all (the GlassShadow rule,
:177). Pixels: the dstOut loop drew the shape deflated by .5 with coverage
AA; the even-odd clip at deflate(.5) is the same geometry rasterized as a
clip - the difference is the AA of one rim row, exactly what the fake tier
and the bodies already carry. Gate: shotdiff of controls-resting,
menu-resting and the density n8 shot against the noise floor; the
expected difference is confined to the shadow's inner rim.

Also drops the UI-side `_recordOriginalShadows` picture re-recording when
combined with U2's retention.

### U1. The menu's UI p95 is the open frame and GC, not the renderer

Evidence: flat menu build p95 is 11.6 ms with p50 2.7; the fusion costs at
most 0.76 ms per frame on the Pixel (`outline_us.menu10-r4`), the menu's
rows are a `RepaintBoundary` memo per layout (menu.dart:866), and the
renderer adds ~3 ms at p50 (6.0 liquid). So ~8 ms of the flat p95 comes
from a few frames: the open frame (build + layout of every row's text,
`MorphTypography.resolve`, the card header, the layout pass of
menu_layout.dart measuring labels), the frame that disposes the menu, and
the frames a scavenge or old-gen mark lands in (passport: 3.1 ms in one
frame). Confirm with M3 before building.

Sketch, two parts, both IDENTICAL:
1. Pre-layout at pointer down. `MorphMenuButton` / the bar's back menu know
   their entries before the open (declarative API); on `pointerDown`
   (menu_host.dart) build the card content and run its layout offstage
   (an `Offstage`-like host, or simply a `TextPainter.layout` pass over the
   labels through the same `MorphTypography.resolve` the rows use, cached
   in the layout memo the rows already key on). A tap opens at pointer
   up, ~100 ms later; a long press later still. The open frame then only
   paints. Keep the cache keyed by (entries, style, width) so a rebuild
   with new entries is not served stale text.
2. GC window: call `PlatformDispatcher.instance.requestDartPerformanceMode(DartPerformanceMode.latency)`
   when a menu, sheet or zoom starts and `balanced` at settle (flutter-tricks
   C3: the SchedulerBinding wrapper does not forward; the direct call
   does). This defers the old-generation work out of the animation; it
   does not remove it. Measure the menu's build p95 and worst with M3
   before and after; if the p95 frames are not GC frames, drop part 2.

### R2. The zoom present crossfades inside two Opacity saveLayers

Where: sheet.dart:862-883 is the ZOOM presentation (`_source =
_route._zoomSource!`, :314). `Opacity(opacity: opacity, child: sheet)`
(:881) receives the crossfade's `fade` (zoom_motion.dart:211) and is
fractional for every crossfade frame; `zoom_source.dart:122` puts the
source replica in `Opacity(1 - fade)` at the same time; the outer
`Opacity(_source.opacity(...))` (:864) is 1 except during a source-lost
dissolve (zoom_source.dart:97-104) and pushes no layer. While `fade` is
fractional the whole sheet - its glass surface (sheet.dart:925, menu kind,
frosted), its buttons' container and its content - renders into an
offscreen pass the size of the sheet, the glass inside then paints inside
the probe's seeded identity backdrop pass (glass_composition_probe.dart:35-38,
a third pass), and the replica is a fourth. The audited plain sheet does
not take this path (its +7.2 raster p95 needs M1 / M2); every zoom sheet
and the push zoom's analogue do.

Sketch: fade the surface through `MorphGlassSurface.opacity` (the seam's
own rule, CLAUDE.md "Fade glass through MorphGlassSurface.opacity"), fade
the content through a `ColorFiltered` alpha matrix or per-child opacity,
and keep the clip. Fidelity: for a surface and content that do not
overlap in alpha the composite is identical; where the content overlaps
the glass (always: content sits on the glass) group opacity and
per-element opacity differ in the overlap - this is VISIBLE in principle
and must be judged on the crossfade frames against the UIKit film (the
sheet passport has the recordings). If the owner rejects, the fallback is
IDENTICAL and smaller: give the Opacity a `RepaintBoundary` child so the
content's pictures are retained across the fade (saves UI PAINT, not the
passes).

### U2. Per-frame hygiene in RenderLiquidGlassLayer (IDENTICAL)

- Retain the shadow picture: `_recordOriginalShadows` (liquid_glass_layer.dart:1118-1134)
  re-records every paint; key it on (shape rects, transforms, shadows,
  visibility) and keep the `PictureLayer` (Codex X4). With R1 the picture
  also loses its saveLayer.
- `trackedTransform()` clones the matrix it just received (:1145);
  `getTransformTo` already returns a fresh Matrix4 - keep the reference,
  clone only in `shaderCoordinateTransform` if a consumer mutates it (it
  does not; `filterPassTransform` reads).
- `_prepareGeometryAppearance` (:1030-1049) builds a list and listEquals
  on every paint; compare in place against `_shapeAppearances` without
  allocating, and skip entirely when `link.isDirty` is false and no shape
  appearance changed (the GeometryCache already knows).
- Skip `syncCompositionOpacity` and `syncAncestorClips` (the two ancestor
  walks in `runCompositorPoll`, liquid_glass_render_object.dart:641-651)
  when this frame neither painted this layer (`FramePollMarker`) nor fired
  `onTransformChanged`; the opacity seeding and clips can only change
  through a paint or a transform change of an ancestor, both of which the
  tracking layer already observes. (perf-opinion A6; still open.)
- `_currentCoordinateMapping` (:1193-1206): `Matrix4.inverted` plus three
  `transformPoint` allocations per layer per frame; compute the 2 x 3
  affine inverse from the matrix entries directly (the screen transform
  is affine for every control).
- `_updateShaderFilter` (:1271-1288): for frosted layers the
  `ImageFilter.blur` is rebuilt whenever ANY input changed; cache the blur
  by sigma and only rebuild the compose.

Expected: -0.3 .. -0.6 ms UI per frame on the menu and controls scenes
(nine layers), and a lower allocation rate (fewer 2 ms scavenges in
frames). Gate: perf_counts unchanged (builds / paints / pictures), the
glass_frames hashes unchanged, device shots within noise.

### R3. One layer for the stack's bars (automatic chrome container)

Today MorphNavigationStack's nav bar and toolbar share one backdrop KEY
(chrome_group.dart:9-28, navigation_stack.dart:297, 355-400) but each bar's
`MorphGlassHost` (bar_items.dart:1321-1335) is its own `LiquidGlassLayer`:
two unfrosted layers, two matte passes when a capsule moves, two shadow
saveLayers. Paint order is page, nav bar (edge effect, capsules, glyphs),
toolbar (capsules, glyphs). A shared layer placed at the FIRST member
(the nav bar) would shade the toolbar's capsules before the toolbar's
glyphs paint and after the page and edge effect - IDENTICAL by
construction for the stack's own chrome, because nothing painted between
the two bars intersects the toolbar's capsules (the nav bar's content is
at the top). This is the glass container's contract applied automatically
where the package controls both members.

Sketch: `MorphNavigationStack._bars` wraps both bars in one
`MorphGlassContainer`-like scope whose layer sits at the nav bar; bar
items register their capsules as container shapes (the `joined` branch in
morphLiquidLayer, glass_liquid_draw.dart:440-446, already does this for
buttons) with the container's `still` rule relaxed for bars (a bar whose
capsule is moving re-encodes the shared matte - one pass for both bars
instead of one for each, still a win). The matte is then screen-high: a
1080 x 2400 RGBA8 render whenever a capsule moves (bar transitions only),
and the filter clip is the union - full screen - so the final pass runs
2.6 Mpx with the one-fetch exit for empty texels (~10 MB of reads), plus
the capsule shader on the capsules. Cost moves from the raster thread
(-1 layer, -1 shadow pass: -0.3 .. -0.5 ms) to the GPU (+0.3 .. +0.8 ms of
bandwidth per frame always). On a raster-thread-bound device it wins; on a
GPU-bound device it loses. Kill criterion: GPU busy per frame (M1) on
home-scroll rises by more than the raster p95 falls, or any shot of the
bars differs from the two-layer build beyond the container's measured rim
difference. A ClipPath of the two bands around the shared filter would
stencil-reject the empty fragments before shading on Mali, but the
subpass texture stays full-screen: try only if M1 says the GPU pays.

Do NOT extend this to the menu face or cards (fused bodies, frosted, own
copies by fidelity) nor to page body glass across arbitrary content (the
2026-10-05 option C decision stands: the package cannot see what paints
between two controls).

### D. No geometry pass for simple moving shapes (unified-canvas design D, re-costed)

What it removes per moving layer per frame on the UI thread: the Flutter
GPU render (flutter_gpu_geometry_renderer_native.dart:283-480) - a command
buffer, a render pass, ~12 FFI calls, a 2.3 KB uniform pack, a matte
texture from the ring - and, when it is the frame's only pass, the
UI-thread vkQueueSubmit at 0.54 ms. On the GPU: one small pass and one
texture fetch per pixel, replaced by evaluating up to 4 shape SDFs per
pixel in the final shader (`sdf.glsl:39-65`, the 6-step superellipse
bisection - the same ALU the geometry pass spends, now over the filter
clip instead of the matte, about the same pixel count). Fidelity: the
12-bit displacement and normal codes (displacement_encoding.glsl:6-16)
disappear; the result moves TOWARD exact by less than one channel step on
the face. The normal must come from the analytic gradient (closed form for
rounded rectangles and ovals; for the superellipse differentiate the
solved parameter, or evaluate the SDF at +-1 texel like the geometry pass
does, 3x ALU), never from dFdx / dFdy (quad-granular normals alias on the
1 - 3 px rim band - visible). Keep the matte for fields (fused bodies)
and for layers above 4 shapes. Gate: the shader harness's regular, lifted
lens and slider cases (parity max channel <= 1), then segmented, tab-bar
and controls raster / build p95 and GPU (M1). Effort L; do after R1, U1,
U2, R2.

### F. Menu silhouette one frame ahead

The fusion is pure (`morphMenuSilhouette(menu, source, radius)`,
menu_fusion.dart:79) and its inputs for the next frame are a function of
the motion clock. The rejection "isolates: the result is needed in the
same frame" (flutter-tricks section 2) does not apply to pipelining:
compute frame k+1's outline while frame k renders, send back the contour
points and field samples as TypedData (a `Path` cannot cross isolates;
rebuilding it from the points is the 0.07 ms trace step), and fall back to
the synchronous call when the frame stamp differs from the predicted one.
On a device whose menu frames are over budget 15 - 20 percent of the time,
that many frames get no gain; the other 80 percent save 0.5 - 0.75 ms of
UI. Worth it only if, after U1 and U2, the menu's UI p95 is still above
~9 ms with the fusion visible in the per-frame dumps (M3).

### R4. Clip buckets (flutter-tricks L5), briefly

`expandToPixelBuckets` (snap_rect_to_pixels.dart, liquid_glass_layer.dart:1260,
1293) snaps every unfrosted filter clip out to 64 device px; a 44 pt
capsule is 116 px tall and becomes 128, a 2 pt wide bucket in each axis
costs subpass bytes and shader invocations. 16 px buckets for unfrosted
layers keep retained-motion stability (the bucket exists so a translated
layer does not resize its render target) at a quarter of the waste.
IDENTICAL; small; S.

### Things to STOP doing

- Stop chasing GPU shader cycles for these scenes until M1 shows a scene
  that is GPU-bound. The e2e runs proved the point; the harness stays for
  fidelity gates.
- Stop re-recording the shadow picture every paint (U2) and stop paying a
  saveLayer for it (R1).
- Stop wrapping glass in fractional `Opacity` (sheet.dart:881 and
  zoom_source.dart:122 during a zoom crossfade, bar_items.dart:1446,
  navigation_bar.dart:501, menu.dart:776): each is a subpass plus, for
  glass inside it, the probe's pass. Where the fade is
  measured, fade through the surface's own opacity and the content's
  alpha; where the owner needs group opacity, say so in the passport.
- Stop `ImageFiltered` with an effectively zero blur: menu.dart:769-796
  passes `_none` (a blur with default sigma 0) with `enabled: blurred`,
  which is fine; bar_items.dart:1434 gates on `frame.blur > 0.05`, fine.
  Keep these gates; add one to any new ImageFiltered.
- Stop measuring p95 without per-frame dumps (M3); a p95 of 150 frames is
  the 8th worst frame, and three different mechanisms (open frame, GC,
  atlas update) each own a couple of them.
- Stop adding `alwaysNeedsAddToScene`-style forced re-adds; the one that
  existed cost 1.3 ms COMPOSITING per frame on 16 resting buttons.
- Do not build the screen-level canvas, automatic grouping across page
  content, or a per-body BackdropGroup by default (decided; the numbers
  in glass-renderer.md "Second resting body glass" still hold).

## 3. What "nothing left to do" looks like on the Pixel 6a

Targets, median of 5 runs, active frames, with the floor measured by the
flat tier in the same launch (the floor is the device's, not the
package's; it moves with thermals, so every target is a delta):

| scene | liquid raster p95 target | liquid build p95 target | over budget | rationale |
|---|---|---|---|---|
| home-scroll | <= flat + 1.0 | <= flat + 0.5 | 0 - 2 (= flat) | resting glass costs one layer per group |
| segmented | <= flat + 1.5 | <= flat + 2.5 | 0 | one body + one lifted lens layer |
| tab-bar | <= flat + 3.0 | <= flat + 3.0 | <= 3 | frosted bar + lifted lens, re-encoded per frame by design |
| controls | <= flat + 4.0 (from +8.3) | <= flat + 3.5 (from +4.6) | <= 3 | two lifted layers + the container |
| menu | <= flat + 4.0 (from +5.9) and raster p95 <= 15 | <= 10 (from 14.8); flat <= 8 (from 11.6) | <= 5 (from 23) | frosted face + card are the look; the open frame and GC are not |
| sheet | <= flat + 4.5 (from +7.2), provisional until M1 says what the frosted face costs the GPU | <= flat + 2.0 | <= 2 | one frosted face and its group flip; the chain is Impeller's |

Per-mechanism invariants that define "done" (checked by perf_counts
ceilings, the layer census and the trace, not by eye):

- One saveLayer per glass layer and none for shadows; saveLayers per frame
  = glass layers + measured ImageFiltered passes, nothing else.
- No `Opacity` layer at fractional alpha with glass inside it anywhere in
  lib/src/widgets.
- Zero UI-thread submits in frames where no geometry changed (true today)
  and at most one otherwise.
- The liquid tier's COMPOSITING self time within 0.1 ms per layer of the
  flat tier's; PAINT within 0.3 ms per MOVING layer.
- Scavenge period on liquid within 20 percent of flat's on the same scene
  (M5).
- Every target above met with shots within the run-to-run noise floor and
  the shader harness at 0 steps for IDENTICAL changes.

Kill criteria (stop a lever, or the whole effort):

- K-R1: if after R1 the controls / menu / density saveLayer count per
  frame does not drop by the shadowed-layer count, the shadow picture was
  not the pass; revert.
- K-U1: if M3 shows the menu's p95 frames are neither the open frame nor
  GC frames, U1 is void; the UI p95 is then rows re-layout or the fusion
  and lever F moves up.
- K-R3: GPU busy (M1) rises by more than raster p95 falls on home-scroll,
  or bar shots exceed the container's rim difference: do not land.
- K-D: parity above 1 channel step on any lens / control case, or no
  measurable change in segmented / tab-bar build p95: abandon.
- K-ALL: when every scene is within its target and the device's own floor
  (flat p95 ~10 ms raster) is more than two thirds of the liquid number,
  the package is done on this device; what remains is Flutter's (Impeller
  Vulkan submit cost, swapchain, glyph atlas) and the app's content.

## 4. Summary

The Pixel 6a is raster-thread CPU bound: every liquid frame pays ~0.3 ms
of encode + submit per glass layer and a second saveLayer per shadowed
layer, on top of a device floor of ~8 ms p50 / ~10 ms p95 that the flat
tier already shows. The UI thread's liquid overhead (+2.2 ms mean, +4 ms
at the menu p50) is renderer PAINT and COMPOSITING per layer plus more
frequent 2 ms scavenges; the menu's UI p95 (14.8) is mostly not the
renderer and not the fusion but a few heavy frames (open, GC). GPU time
has never been measured for a scene; the shader gains were real and
invisible for that reason.

Do first, in this order: R1 (shadow saveLayer -> clip, NEAR, high
confidence, every scene), U2 (per-layer hygiene, IDENTICAL), U1 (menu
pre-layout + GC window, IDENTICAL, needs M3), then the measurements M1 to
M6 (M1 and M2 before touching the sheet, whose delta the layer count does
not explain), then R2 (zoom crossfade without group Opacity, owner looks)
and the decisions on R3 and D with numbers instead of estimates. Expected:
controls raster p95 to about flat + 4, the menu to flat + 4 with build p95
under 10, over-budget frames on the menu from 23 to single digits; the
sheet's target is provisional.
