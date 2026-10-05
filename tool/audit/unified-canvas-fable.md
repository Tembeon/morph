# Unified glass canvas - independent analysis (Fable, 2026-10-05)

Question (owner): would ONE glass layer per screen layer (page body /
chrome / overlays), shading ALL glass shapes of that layer in one pass
from one backdrop capture and one geometry field (a GPU-evaluated
analytic SDF of every shape, or one field texture), make a theoretically
unlimited number of glass elements nearly free, and is it feasible on
Impeller / Flutter GPU here?

Static read of branch wip/measured-liquid-glass as of 2026-10-05 (tree
with the backdrop-group, plain-union and clipped-shadow commits). No
code run; device numbers are the ones the passports record
(tool/ios_reference/spec/glass-renderer.md, iPhone 16 Pro, profile) and
the pinned per-frame counts in test/fixtures/perf/counts.json. Every
claim cites file:line as read today.

Short verdict first: NOT as a screen-level canvas. Flutter paints in
z-order into one picture per layer and has no deferred render queue, so
a glass pass hoisted to one z-position per screen layer is wrong
whenever anything opaque paints between two glass shapes in that layer
(the "second resting body glass" case that is today an OPEN owner
decision would become the architecture, and worse: the glass would also
sit under card backgrounds painted after it). Fixing that needs hidden
content replayed above the glass for EVERY control, which is the lens
copy machinery generalized, with its toImageSync fallback as the failure
mode. The N regime where one pass beats N small passes (dozens of glass
elements on one plane) is also a regime iOS 27 does not have - list
rows, cards and tracks are not glass, and the package's rule is ONLY
NATIVE GLASS IS GLASS (CLAUDE.md, glass seam). YES in the narrow,
UIKit-shaped form the package already half has: unify PER CONTAINER
(one layer for every glass shape that shares one content plane), which
is exactly what UIGlassContainerEffect is, and kill the real O(N) cost
today, which is UI-thread widget churn, not GPU passes.

## 1. What is already unified, and what is per control

Unified today:

- Backdrop CAPTURE: one readback per BackdropGroup key. The root group
  (glass_tier.dart:339-341) serves every resting body glass on a page;
  the navigation bar and toolbar share one chrome key per screen
  (chrome_group.dart:9-28, navigation_stack.dart:297/909); a sheet's
  content, the search tab bar and each menu card take their own.
  Captures per animated frame, liquid tier (counts.json): controls-page
  5.5, nav-scroll 3.9, tab-bar 3.3, menu-card 3.0, segmented 1.3,
  switch 1.4, slider 1.5, sheet 2.0.
- GEOMETRY per CONTROL, not per shape: a `LiquidGlassLayer` encodes up
  to 16 shapes into ONE matte in ONE Flutter GPU pass, the shader
  looping over the shapes per pixel with per-shape box culling and
  group markers (sdf.glsl:431-480, geometry_fragment.glsl:53-66;
  `MAX_SHAPES 16` sdf.glsl:26; the 16 cap liquid_glass_layer.dart:1446).
  A bar's capsules, a segmented control's track and lens, a menu's
  button + platter are already one geometry pass each
  (glass_liquid_native.dart:213-244 `_layer` builds one layer for a list
  of surfaces).
- SHADING per layer: one `ImageFilter.shader` BackdropFilter per
  `LiquidGlassLayer`, clipped to the layer's filter bounds
  (liquid_glass_layer.dart:1162-1238, `_Reach` +24 px
  glass_liquid_native.dart:655-665).

Per control (the O(N) today, for N standalone glass controls on one
page, e.g. N `MorphGlassButton`s):

1. One `LiquidGlassLayer` widget subtree + `RenderLiquidGlassLayer`
   (liquid_glass_layer.dart:271-302) with its own matte texture ring
   (flutter_gpu_geometry_renderer_native.dart:257-258, 880-1001).
2. One Flutter GPU geometry pass whenever its shape/settings change
   (liquid_glass_layer.dart:887-913; a 64-px-bucketed small texture,
   :486). While the control RESTS and the page scrolls, the matte is
   reused by translation (:832-839, :1261-1270) - no geometry pass.
3. One BackdropFilter offscreen pass (filter output sized to the
   control's clip) + one draw per frame anything on screen repaints
   (Impeller has no raster cache). With a shared key the READBACK is
   not repeated (glass-renderer.md "Backdrop groups": the first use
   flips, later uses filter the slot), so the per-control GPU cost is a
   small filter pass whose area is the control's, plus fixed per-pass
   overhead.
4. One shadow draw (now a clip + drawPath, no saveLayer; glass_shadow
   per glass-renderer.md "GLASS SHADOWS WITHOUT A LAYER").
5. UI thread: per tick of ITS motion the control rebuilds the painter's
   layer widget tree (glass.dart:470-485 `ListenableBuilder` ->
   `buildLayer`), i.e. `MorphGlassLayerParts.of` (glass_renderer.dart:
   434-480), `morphLiquidLayer` (glass_liquid_native.dart:343-451),
   fresh `LiquidGlassSettings`/`LiquidGlassAppearance` (:79-136), the
   `LiquidGlass` State build (liquid_glass.dart:43-98), then
   `updateRenderObject`. At rest it costs the compositing polls per
   frame: `syncCompositionOpacity` walks ancestors (glass_composition_
   probe.dart:45-67), `syncAncestorClips`, `getTransformTo` per shape
   (render_liquid_glass_geometry.dart:179-202), driven by
   `alwaysNeedsAddToScene => true` (transform_tracking_repaint_boundary_
   mixin.dart:137-156).
6. CPU-traced fields only for FUSED bodies: the menu's blurred neck and
   bar capsules fusing at spacing 12 (glass_outline.dart:772-884,
   0.12-0.71 ms device per trace); submenu cards and the r < 1 menu tail
   are plain unions now, no field (glass_outline.dart:694-703).

Read of the device numbers (glass-renderer.md "Device numbers",
2026-10-05): liquid vs flat build p95 segmented 1.47 vs 0.53, tab bar
1.58 vs 1.06, controls 3.25 vs 2.52; raster p95 liquid ~3x flat
(controls 2.88 vs 0.80, sheet 3.21 vs 0.95). Raster is "captures and
blurs"; build is item 5 above. Neither is proportional to shape count
in the gallery scenes, which hold 2-6 glass elements.

## 2. Cost model: N glass elements, now vs unified

Let S = screen = 1206 x 2622 device px; one BGRA10_XR full-screen
readback ~25 MB of traffic (perf-research-2026-10-05.md section 0).
Let a_i = pixel area of glass element i (bbox + 24 px reach), A = sum,
B = area of the union bounding box of all elements in a layer. Per
pass fixed overhead p (Metal encoder begin/end, load/store of a small
target; order of tens of microseconds, NOT measured here - see section
7 for how to measure it).

| stage | now (N controls, one group) | screen-level unified (one layer) |
|---|---|---|
| capture | 1 readback (25 MB) + 1 per chrome/lens/edge effect/menu card | SAME count: the plane boundaries (chrome over page, lens over body, edge effect under bar) are fidelity requirements, each measured and kept (glass-renderer.md "SCROLL EDGE EFFECT ... REJECTED", "OVERLAYS AND LENSES") |
| blur (frosted kinds: bars, menus, resting small lens) | 1 Gaussian per frosted layer over ITS clip (~4 command buffers each on Metal, liquid_glass_layer.dart:604-606), area a_i | 1 Gaussian per DISTINCT sigma over B (or S): chromeFrost 14, small-lens 6, button 0 cannot share one kernel. Full-screen sigma-14 blur costs more than two bar strips. A mip/pyramid approximation changes the measured frost - not allowed without a new measurement |
| geometry matte | N small Flutter GPU passes, each area a_i x (shapes in bbox); reused by translation at rest | 1 pass over B (full screen if a bar and a button both belong: 3.2 Mpx RGBA8 = 12.6 MB written + read, x3 ring = 38 MB resident), N shapes per pixel unless tiled; re-encoded whenever ANY shape moves, because the ring writes a fresh texture per render (`_mattes.next`, flutter_gpu_geometry_renderer_native.dart:311-317, loadAction dontCare :858-863) - partial updates need load-preserve plus double buffering against `reuseAfterFrames` (:584) |
| final shader | N clipped filter passes, total area A, overhead N x p | 1 pass over B: B >= A always, B >> A for a bar + a button on the page; the shader early-outs on empty matte (final_render_core.glsl:524-530, 671-677) but the pass still touches B and the backdrop filter's output buffer is B-sized |
| compositing | N filter draws, 1 flip | 1 draw, 1 flip |
| shadows | N clip + drawPath | N clip + drawPath (unchanged; or one picture) |
| UI thread | N widget layer rebuilds per tick of EACH animating control; N poll sets per frame | 1 render object, N channel writes (markNeedsPaint only) - the real win, and it does not need GPU unification (section 5, design A) |

Reading: for N on the order of the gallery (2-6) the unified pass is
roughly neutral or worse on the GPU (B > A, one big matte re-encode per
moving shape instead of one small one). It wins only when N x p (pass
overhead) exceeds the extra area work, i.e. dozens of small glass
elements on ONE plane. That plane does not exist in iOS 27 UI: a list
of glass rows is not native (CLAUDE.md "ONLY NATIVE GLASS IS GLASS").
The expensive native case, bars + menus, is bounded at ~2-6 bodies and
is already per-container unified.

What "nearly free" would actually require: a fixed cost per frame
independent of N. The capture already is (one per plane). Blur is not
(per sigma). Shading is bounded by B, not N - unified makes it depend
on B instead of A, a regression when glass is sparse. Geometry can be
made N-independent per pixel only with tile culling (section 5, D).

## 3. Impeller / Flutter constraints that decide it

1. PAINT ORDER IS THE SHOWSTOPPER FOR A SCREEN-LEVEL PASS. A
   BackdropFilter reads the pass texture as it stands when the flip
   happens (glass-renderer.md "ENGINE": the first use flips; shared
   members read the LAST flip before them, not their own position). A
   single glass pass per screen layer must sit at ONE z: at the bottom
   (before any control content) it misses every opaque thing painted
   between it and a later control (a section card, list row
   backgrounds) - and that content then paints OVER the glass. At the
   top (after everything) its backdrop contains every control's own
   labels, which must sit above glass, so they would be refracted and
   frosted. The device repro of exactly this (red/green stripes between
   two body buttons, 72 / 43 max channel) is the open "SECOND RESTING
   BODY GLASS" item (glass-renderer.md), options A-D; a screen-level
   canvas is option D made permanent plus a z-order bug.
   The only correct screen-level form: paint glass at the top AND hide
   every control's content from the backdrop AND replay it above the
   glass. The seam already separates content from surfaces
   (glass.dart:459-461, 476-483) and the lens copy already records and
   replays content pictures (content_snapshot.dart:33-74), so it is
   buildable - but the replay falls back to `layer.toImageSync` (a GPU
   snapshot on the UI thread, :65-73) for any content layer that is not
   a PictureLayer or plain OffsetLayer: an Opacity, a ClipRect from a
   composited child, a Texture, a nested BackdropFilter (perf-research
   G1, perf-opinion A5). For a lens that content is the control's own
   labels (safe); for "every glass control in the app" it is arbitrary
   consumer content (unsafe). Ancestor `Opacity` and clips would have to
   be re-applied around the replay by hand. This is the kill criterion
   K3 in section 8.
2. CONTENT ABOVE GLASS vs GLASS OVER GLASS. A lifted lens must refract
   the bar glass AND the magnified labels beneath it (glass-renderer.md
   "GLASS ON GLASS"), so it is a second stacking tier with its own
   capture (glass_liquid_native.dart:438-447 `shared: false`). The
   number of simultaneously lifted lenses is the number of fingers, so
   it is never the N problem; a unified design must leave it alone.
3. TRANSFORMS, CLIPS, RepaintBoundary. Today a glass control inside a
   scrolling list rides the compositor: the matte is retained and the
   filter's coordinate mapping re-synced per frame
   (liquid_glass_layer.dart:1041-1046, 1261-1270; retained ancestor
   clips liquid_glass_render_object.dart:681-692). A screen-level layer
   would have to read every shape's `getTransformTo` and the clips
   between shape and layer each frame (the skin does this for its
   blob, skin.dart applyPaintTransform) and re-encode its whole matte
   on every scroll frame, because shapes move relative to the layer
   even when they move uniformly with their list. Per-shape clip rects
   can go into the shader (another vec4 per shape); arbitrary ancestor
   clip PATHS cannot.
4. OPACITY. The seam contract is "fade glass through
   `MorphGlassSurface.opacity`, never an Opacity above it"
   (glass.dart:183-191; the probe seeds a fractional-opacity pass,
   glass_composition_probe.dart:8-13). A single layer honours per-shape
   opacity through visibility (geometry_fragment.glsl / appearance
   visibility). Fine either way.
5. PER-SURFACE MATERIAL. Mixed appearances already go through the 8x
   downsampled contributor map, 16 slots (liquid_glass_layer.dart:
   621-657, material_gradient_fragment.glsl). Beyond 16 shapes the
   uniform arrays become a shape atlas texture (Flutter GPU can bind a
   float texture: the field path does, flutter_gpu_geometry_renderer_
   native.dart:1024-1060); the final `ImageFilter.shader` side takes
   only float uniforms and image samplers, so per-shape data for the
   FINAL pass would also ride a texture. Doable, a mini renderer.
6. HIT TESTING / SEMANTICS. Unaffected: the control keeps its
   `MetaData(opaque)` box (glass.dart:472-473) and semantics; a
   compositor layer is IgnorePointer. Same for the lens today.
7. PLATFORM VIEWS. A backdrop over a platform view needs the view
   composited into the Flutter surface; no change in either design.
8. TEXT OVER GLASS. Content replay of PictureLayers reproduces glyphs
   bit for bit (same picture). Only the fallback path (toImageSync) can
   change text rendering (resampled image).
9. DARK / LIGHT, RTL. Per-shape appearance and geometry; no constraint.
10. ANIMATION PER SURFACE. Today only the animating control's small
    matte re-encodes (:887-913) and its filter is re-created when
    inputs change (:1162-1179). A unified layer re-encodes B per moving
    shape unless the geometry pass is scissored to dirty regions with
    load-preserve, which conflicts with the fresh-texture ring (section
    2, geometry row). Lift also changes the codec scale per layer
    (`refractionAmount` is the codec scale, flutter_gpu_geometry_
    renderer_native.dart:715-718; perf-research G11): a lifted lens and
    resting buttons cannot share ONE matte encoding today without
    moving to a unit-displacement encoding (VERIFY, 12-bit quantization).
11. WARM-UP. More pipeline variants (atlas path, tile path) means more
    first-use hitches (perf-opinion A8).

## 4. How UIGlassContainerEffect relates

UIKit does NOT unify per screen. `UIGlassContainerEffect` /
`GlassEffectContainer` unifies per CONTAINER: every glass subview of
one container shares one backdrop sample and one material pass, and
fuses by the container spacing (the merge law morph measured, CLAUDE.md
"THE MERGE LAW"). A navigation bar and a toolbar are two containers and
two captures in UIKit as well. What UIKit has that Flutter lacks is a
compositor that captures the backdrop at the effect view's own z inside
CA's render tree at tile-memory cost, so a container's pass break is
nearly free and correct by construction. morph's `buildLayer(spacing:)`
+ one `LiquidGlassLayer` per control + `BackdropGroup` per plane IS the
UIKit model; the gap is (a) standalone glass buttons that are siblings
in one plane each get their own layer (no container object for app
code), and (b) the pass break is not free on Impeller. (a) is fixable
cheaply (section 5, design B). (b) is an engine property; sharing the
capture already removes the expensive part (the flip); the remaining
small filter passes per container are the price of correctness.

## 5. Alternative designs, honestly ranked

A. RENDER-OBJECT GLASS HOST (no GPU change). One `RenderBox` per
   control owning its `RenderLiquidGlass` children, fed by a surfaces
   channel (ValueListenable of the surface list); a tick writes shapes /
   appearance / offsets and marks paint - the `MorphPieceChannel`
   pattern. Removes item 5 of section 1: the widget rebuild, settings
   and appearance allocation, State builds per tick. This is
   perf-opinion A3 step 2 / perf-research X7 / Codex B1, agreed by all
   three opinions. Expected: build p95 liquid toward flat on segmented
   (1.47 -> ~0.6) and tab bar; it is the only O(N) term that grows
   with every animating control on the UI thread. Pixels identical.
   DO THIS FIRST; it is a prerequisite for B and C anyway (a channel
   is what a compositor consumes).

B. CONTAINER-LEVEL GLASS COMPOSITOR (UIKit's unit, the honest
   "unified canvas"). A `MorphGlassContainer` (public) / the bars'
   existing `MorphBarItems` generalized: every glass surface registered
   by descendants in ONE content plane is shaded by ONE
   `LiquidGlassLayer` placed at the container's bottom, descendants
   paint only content. Contract, same as UIKit's: the container's
   subtree is content above glass; anything under the glass lives
   outside the container. N buttons in a toolbar: N geometry passes ->
   1, N filter passes -> 1, N polls -> 1; capture already 1. The matte
   covers the container's bbox (a toolbar strip, not the screen), so
   B ~ A. The 16-shape cap stays or grows to 32/64 by widening the
   uniform block (16 x 3 vec4 x 2 + 3 x 16 vec4 today ~ 2.3 KB; 64
   shapes ~ 9 KB, a host-buffer binding, not setBytes - fine on Metal,
   check GLES 3.0's 16 KB uniform block minimum). Paint-order correct
   by contract. Fidelity identical to a bar today (same shader, group
   markers keep standalone shapes plain-min, sdf.glsl:400-402).
   Registration mirrors `GeometryRenderLink` (render_liquid_glass_
   geometry.dart:853-900): a descendant `MorphGlassSurfaceSource` render
   object registers with the nearest container and reports its shape
   and transform; `sortGlassPaintOrder` already orders sources by tree
   position (:10-44). Effort: M-L. Gain: real only where apps place
   several standalone glass buttons on one plane (dream_echo chrome,
   Sonatide floating bar); zero on the gallery's control pages.

C. SINGLE FILTER PER CONTAINER OVER THE UNION BBOX, SHAPES SEPARATE.
   Already what B's layer does: one BackdropFilter clipped to the union
   bounds; the empty middle of a wide toolbar is paid (upstream's old
   "sparse component passes" would split by cluster -
   perf-research 2.1). Measure before splitting: for a 400 x 60 bar the
   waste is ~10 k px, nothing.

D. GPU SDF IN THE SHADING PASS (no matte). Upstream's old DIRECT render
   (perf-research 2.1): evaluate the analytic SDF + displacement inline
   in the final `ImageFilter.shader` from shape uniforms, no Flutter GPU
   pass and no matte texture while animating; bake again at rest.
   Removes one pass + one texture per animating layer; the 12-bit matte
   quantization (displacement_encoding.glsl:6-16) disappears, so pixels
   CHANGE (toward exact) - VERIFY on device. Cost moves into the final
   pass per pixel (RSE solve, 6 bisections sdf.glsl:39-65) over the
   filter clip; for <= 8 shapes per container it is cheaper than a
   pass; for the menu's FIELD body it does not apply (the field is the
   fused truth and must stay a texture). Also blocked for the lens:
   backdropShrink and dispersion need the normal and magnitude the
   matte carries - computable inline. Effort M; wins only during
   animation; low priority behind A and B.

E. TILE-BASED CULLING + SHAPE ATLAS. Per-tile shape lists in a texture,
   the shader loops only over the tile's shapes: the only way to make
   per-pixel cost N-independent. Needed only past ~16-32 shapes in one
   container. No native UI needs it. Skip unless a consumer appears.

F. STENCIL / CLIP-BASED MASKS for one shared filter with N clip regions.
   Not available: a BackdropFilterLayer has one clip; N regions = N
   layers = N passes. Clipping the single filter to the union PATH of
   the shapes (ClipPath instead of bbox) saves fill in the gaps but
   adds a path clip (stencil) per frame; the shader early-out already
   skips those pixels. No.

G. INSTANCING. Irrelevant: every pass is one full-coverage quad.

H. SCREEN-LEVEL CANVAS WITH CONTENT REPLAY (the question as asked).
   Buildable (section 3.1), but: toImageSync fallback for arbitrary
   consumer content; hand-replication of ancestor Opacity/clips/
   transforms; a full-screen matte re-encoded per moving shape; blur
   per sigma over the screen; B >> A on sparse pages; and it still
   needs separate tiers for lenses and chrome. It solves a problem
   (dozens of glass elements on one plane) iOS 27 UI does not pose.
   REJECT.

## 6. Pitfalls specific to this codebase (whichever design)

- OUTLINE IS TRUTH stays: the menu neck and bar fusion are CPU fields
  (`GlassField`, glass_field.dart) uploaded per body
  (flutter_gpu_geometry_renderer_native.dart:1024-1060). A container
  layer holding both analytic shapes and a fused body needs the
  geometry shader to take BOTH a field and shapes in one pass (today a
  layer is either field or shapes, :403-424), or two layers.
- The 'body' layer KEY must not swap types when a body fuses and comes
  apart (glass_liquid_native.dart:381-394, glass-renderer.md "keeps ONE
  layer key"), or the glass restarts. A container compositor must keep
  shape identity stable across re-registration (sources register in
  attach/detach, never per build).
- Backdrop staleness within a group: a container layer at the
  container's bottom is the group's member; nothing may paint INTO the
  group between the flip and the layer (the edge-effect rejection is
  the precedent).
- Lift changes the codec scale (G11): a lens in a container layer
  forces the whole container's matte to re-encode per lift frame. Keep
  lenses in their own layer (they are today).
- Invalidation granularity: one layer per container means any shape's
  motion re-encodes the container's matte (bar-sized, fine) - at screen
  level it is the whole screen (not fine).
- Memory: full-screen RGBA8 matte x ring of 3 ~ 38 MB; bar-sized mattes
  are hundreds of KB. Field textures are RGBA32F (16 B/node).
- The web build: the liquid tier compiles to stubs under Skia
  (glass-renderer.md "WEB"); a new shader path must keep the
  conditional import boundary.
- Fidelity gate: resting audit shots must stay within run-to-run noise
  (the protocol in glass-renderer.md: max channel diff, percent of
  pixels over 15; noise floor <= 56 max channel at <= 0.003 percent on
  resting shots).

## 7. How to measure the win on the iPhone 16 Pro before building B

Baseline the hypothesis "N glass elements cost O(N) today" with a
synthetic scene, because no gallery scene has N > 6:

1. Add `example/integration_test/glass_density_test.dart` (glass_audit
   style, profile, dark, liquid): a scrolling page of coloured rows
   (so every frame re-rasterizes) with N standalone `MorphGlassButton`s
   in a fixed overlay grid on ONE plane, N in {1, 4, 8, 16, 32}; one
   variant with the buttons at REST while the page scrolls (the steady
   state), one with all N pressing in a wave (animation). Record
   FrameTiming build / raster p95 over 5 runs (tool/ios_reference/perf/
   audit.sh conventions: timed windows without screenshots, active
   frames only) and the pinned counters (captures, offscreen, geometry
   `debugTotalRenderCount`).
2. GPU truth: `xcrun xctrace record --template 'Metal System Trace'`
   during the N=16 and N=32 runs; read render-pass count per frame and
   GPU frame time. Per-pass overhead p = slope of GPU time vs N at rest.
3. Prototype B minimally: one `BackdropGroup` + one `LiquidGlassLayer`
   wrapping the N buttons as plain `LiquidGlass` shapes (the renderer
   already supports it; raise MAX_SHAPES to 32 for the prototype in
   geometry_fragment.glsl:13, sdf.glsl:26, material_gradient_fragment.
   glsl:8 and the Dart cap liquid_glass_layer.dart:1446, 754, 772).
   Same scene, same N, same measurements. Compare raster p95 and GPU
   frame time per N; shot-diff the N=4 resting frame against the
   per-control build (must be within noise: same shader, same law).
4. Measure A (render-object host) separately on the existing gallery
   scenes: build p95 segmented / tab bar / controls, liquid vs flat,
   before and after; pixels must be identical (perf_counts' pictures /
   builds columns drop, shots unchanged).

## 8. Kill criteria

- K1 (no problem to solve): if at REST-while-scrolling the status quo
  raster p95 and GPU frame time at N=16 are within 1.0 ms of N=4 on the
  device, per-control passes are not the bottleneck; kill B's GPU side,
  keep A.
- K2 (no win): if prototype B's GPU frame time at N=16 is not at least
  30 percent below the status quo, or its N=4 resting shots differ from
  the status quo beyond the run-to-run noise floor, kill B.
- K3 (correctness): any design that needs content hidden and replayed
  above the glass for arbitrary consumer content (the screen-level
  canvas) is killed on the first `GlassContentSnapshot.
  debugImageFallbackCount` > 0 in the gallery or a consumer app; do not
  start it.
- K4 (fidelity law): any variant that blurs with one kernel for shapes
  of different measured frost, or approximates the Gaussian with a mip
  pyramid, is killed without measuring - it changes measured output
  (perf-research "Not to do").
- K5 (regression on sparse pages): if B's union-bbox filter raises
  raster p95 on the gallery's controls page (sparse glass) beyond
  noise, restrict B to containers whose bbox area is < 2x the sum of
  shape areas, or split by cluster (design C).

## 9. Recommendation

1. Do A now (render-object glass host over a surfaces channel; all three
   opinions agree; identical pixels). It removes the only cost that is
   O(N animating controls) on the UI thread and is the substrate any
   compositor needs.
2. Run the density measurement (section 7, steps 1-2) once, half a day
   on the phone. It settles whether per-control GPU passes matter at
   all on this device.
3. If K1 does not fire, build B as `MorphGlassContainer` (UIKit's own
   unit, paint order correct by contract, one layer per plane), raising
   MAX_SHAPES to 32; land only if K2 and K5 pass.
4. Do not build the screen-level unified canvas (H): paint order makes
   it incorrect without content replay, content replay is unsafe for
   arbitrary content, and the N it is for is not iOS 27.
5. Leave D (inline SDF, no matte) as a measured experiment after B; it
   changes pixels toward exact and needs a device shot diff.
