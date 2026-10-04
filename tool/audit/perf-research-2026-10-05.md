# Performance research - 2026-10-05 (read-only, no code changed)

Goal (owner): best performance with ZERO degradation of widget fidelity.
Every item below is tagged:

- IDENTICAL - provably the same pixels / the same motion (same inputs to
  the same math; only allocation, caching, invalidation or bounding
  changes). Still run the replays + glass_audit shots, but a diff is a bug.
- VERIFY - plausibly invisible, but the output can differ (antialiasing,
  quantization, pass order, backdrop timing); needs the shot diff on the
  iPhone 16 Pro before it lands.

Cost classes: UI = Dart build/layout/paint on the UI thread (FrameTiming
buildDuration); RASTER = Impeller encoding on the raster thread
(rasterDuration); GPU = render passes / bandwidth (not in FrameTiming).

Sources: own read of the renderer and the glass seam, two read-only
sweeps of lib/src/widgets (controls; overlays), the 2026-10-03 audit
(PF1-PF9; PF1, PF2, PF7, PF8 are already fixed in 03b8b15, 68aa6c7,
da7e6db and the renderer slimming), the upstream repo, and Codex.

## 0. The shape of the cost (what the device numbers already say)

glass-renderer.md, iPhone 16 Pro, p95 build / raster ms:
liquid 1.75/1.80 (segmented), 2.91/2.52 (tab bar), 3.87/2.67 (controls),
3.03/2.90 (menu); flat 0.54/0.76, 0.69/0.92, 3.00/0.79, 3.23/2.35.

- The UI thread on Controls and Menu costs ~3 ms even on the FLAT tier:
  most of the build cost there is the widget layer (rebuild-per-tick,
  page-wide repaints), not the renderer. Section 1.2 / 1.3 is where the
  UI-thread wins are.
- Raster/GPU cost is dominated by BACKDROP READBACKS and blurs. On the
  iPhone the surface is BGRA10_XR (8 B/px, per upstream's impeller_model
  report on the same device class): one full-screen readback is
  ~1206 x 2622 x 8 = 25 MB of traffic. Every independent capture
  (a chrome bar, a menu, a lifted lens, a scroll edge effect without a
  group key) pays that. Section 1.1 / 3 is where the raster wins are.
- Frost costs ~1 ms raster per frosted surface (measured), which is why
  the frosted tier is not cheaper than liquid on Controls.

## 1. Duplication / waste map

File:line refer to the working tree of 2026-10-05 (other agents are
editing lib/ concurrently; re-check line numbers before acting).
Cost class per frame: S < 0.05 ms, M 0.05-0.3 ms, L > 0.3 ms (UI), or
RASTER pass / GPU traffic.

### 1.1 Glass seam and renderer (lib/src/widgets/glass*.dart, lib/src/glass/renderer)

G1. Content snapshot churn - glass_liquid_native.dart:354-361 creates a
NEW `GlassContentSnapshot` on every `morphLiquidLayer` build (every
tick), and `GlassContentSource.updateRenderObject`
(internal/content_snapshot.dart, updateRenderObject) disposes the old
one and calls `markNeedsPaint()` UNCONDITIONALLY - also when `capture`
is false (no lens lifted). The content subtree (labels) is re-recorded
every tick. While a lens IS lifted, `_capture` replays the content's
layers into a Picture, and falls back to `layer.toImageSync` (a GPU
snapshot per frame) as soon as the content contains any layer that is
not a plain OffsetLayer/PictureLayer (an Opacity, a clip, a transform
layer - see 1.2 C5: `MorphDisabled` puts an OpacityLayer above content).
Fix: keep one snapshot per State (an Expando on the layer element or a
field in the host), and markNeedsPaint only when `capture` is true or
toggles. Add a debug counter for the toImageSync fallback and make it 0
in the gallery. Cost: M UI (repaint of the label row per tick) and L
RASTER+GPU when the fallback hits. IDENTICAL.

G2. `MorphGlassSurface` has no `==`/`hashCode` (glass.dart:110-205), so
`MorphGlassLayer` (glass.dart:466-479) cannot skip
`MorphGlassLayerParts.of` + the whole surface widget rebuild when a
parent rebuilds without motion (focus ring, theme, page setState). Add
value equality, keep the last surfaces list and parts in the layer, skip
`buildLayer` when `listEquals`. Also lets `LiquidGlass`/`_glass` be
reused as the same widget instance (Flutter's identical-widget fast
path). IDENTICAL.

G3. Field upload on every geometry pass -
flutter_gpu_geometry_renderer_native.dart:410 `_fieldTextures.upload`
overwrites the RGBA32F texture on every render() with a field, even when
the same GlassField is re-rendered because of a settings/appearance
change. Skip when identical to the last uploaded field (and the texture
is still the current one). `_FieldTextures` (native:1013-1051) reuses
only exact-size textures, so a menu whose field grid changes size every
frame of its open allocates a new texture per frame (ring max 4,
dropped ones pinned until GC): use bucketed capacity like `_TextureRing`
and write the real size into uFieldSize. IDENTICAL. RASTER/GPU S-M,
allocation churn.

G4. Field identity churn - menu.dart:548 `motion.silhouette?.shift(origin)`
on every build allocates a new GlassField (and `Path.shift` copies of
the outline, glass_field.dart `shift`); `RenderLiquidGlassLayer.field`
compares by identity (liquid_glass_layer.dart:432) -> needsGeometryUpdate
-> geometry pass + upload on every rebuild of the menu face, even at
rest open. Memoize the shifted outline per (silhouette identity, origin).
IDENTICAL.

G5. Container outline memo misses pure translation -
glass_outline.dart:634-645 keys the 4-entry memo on exact shapes. A bar
whose capsules all move by the same offset (a bar riding a sheet, a push
zoom, a scroll) re-fuses every frame (0.12 ms per two capsules, more per
group). The grid origin is derived from the shapes (area.left/top,
:663-667), so translating every shape by d translates every sample
position by d: return `outline.shift(d)` (the method exists, :36-39)
when the shapes match up to a common offset. IDENTICAL up to the last
float bit of the origin (the samples are distances, translation
invariant); verify with the outline golden if paranoid.

G6. Double field evaluation in `_fuseContainer` (glass_outline.dart:679-724):
per field node it computes all box distances for the weights
(`boxes.distance`, quadratic smin for `share`) AND calls the LiquidField
sampler (`sample(x, y)`), which recomputes the same box distances with
normals. Fold the half-thickness / turn weights into the sampler pass
(or have the sampler return per-mass distances). IDENTICAL. UI S-M only
while fused shapes move.

G7. Side finding (correctness, not perf) - `morphGlassContainerOutline`
with spacing 0 (menu_motion.dart:1551, the menu's plain-union field when
the fusion radius is under the minimum) divides by `2 * spacing` and
`4 * spacing` (glass_outline.dart:695, 714): at a node where both box
distances are equal `share` is 0/0 = NaN, so `w` is NaN and halfMinor /
turn at that node become NaN in the uploaded field. Guard spacing 0
(plain min, w = d < di ? 1 : 0). Check before any perf work on the field.

G8. Unbounded saveLayer in `MorphGlassBodyShadow.paint`
(glass_body_shadow.dart:22): `saveLayer(null, ...)` - the offscreen pass
covers the whole layer clip instead of the outline. Bound it by
`outline.getBounds()` inflated by max(3 x blur + |offset| + spread).
Also `outline.shift` allocates a Path per shadow per paint (:31) - use
canvas.translate. shouldRepaint compares `shadows` by identity (:43); for
lens kinds `_shadows` builds a new list each build
(glass_liquid_native.dart:173-185) -> always repaints. IDENTICAL.
RASTER M (one smaller offscreen pass).

G9. One saveLayer per shadowed glass surface per frame -
glass_shadow.dart `_RenderGlassShadow.paint` (needsCutout when the
shadow has an offset: `MorphGlassDefaults.bodyShadow` is (0, 4)), i.e.
every glass button and menu body pays an offscreen pass per rasterized
frame (Impeller has no raster cache: retained pictures are re-executed
every frame anything on screen animates). Alternatives: (a) draw all
shadows of a layer under ONE saveLayer (the consolidated path in
liquid_glass_render_object.dart:739-797 does exactly that for fake
glass); (b) replace saveLayer + dstOut with an even-odd clip (bounds
rect minus the shape) - no offscreen pass. (a) is IDENTICAL only if
shadows do not overlap other content in between (they are drawn just
before their glass, so merging changes order when two shadowed glasses
overlap) - VERIFY; (b) changes the cut-out antialiasing (dstOut of a
0.5-deflated shape vs a clip edge) - VERIFY.

G10. Shader uniforms written three times - liquid_glass_layer.dart:496-514
`_updateShaderSettings` writes the 47-float common block into all three
FragmentShaders (default, material, tint) on every settings/appearance
change, which happens every frame while a lens lifts (frost, refraction,
highlight follow lift). Only `renderShader` is bound; write the other
two lazily when the variant switches (mark them stale). IDENTICAL. UI S.

G11. Lifted lens settings force a geometry pass per frame -
`onSettingsChanged` (liquid_glass_layer.dart:691-699) rebuilds the matte
when `effectiveRefractionAmount` changes; `morphLiquidSettings`
(glass_liquid_native.dart:97-99) makes the amount a function of lift,
so every lift frame re-encodes the matte (the codec scale is the
refraction amount, native:715-718). Encoding a unit displacement and
scaling it in the final pass would make lift frames uniform-only, but
changes the 12-bit quantization -> VERIFY. Small texture, low priority.

G12. `_ContentCopyPainter` (glass_liquid_native.dart:583-635) replays the
content picture up to 3 strips x N slots per frame with nested
clipRRect + clipRect + transform (shouldRepaint true). Required for the
measured "each item scaled about its own slot" optics; only skip slots
that do not overlap the lens (already done) and strips that do not
intersect the lens shape (not done: every strip is replayed even when
the lens lies entirely inside the middle strip). Strip culling is
IDENTICAL. RASTER S-M while lifted.

G13. `_LensClip` (glass_liquid_native.dart:652-689) builds an even-odd
path with a 3x-size rect each reclip; with no lens lifted it is still a
ClipPath with Clip.none (no layer, fine). Audit PF9 asked to drop the
wrapper when no lens is lifted - changing the widget type remounts the
content subtree, so keep it (Clip.none is free). No action.

G14. Backdrop sharing (the raster lever). Independent captures per frame
today: the root BackdropGroup (MorphAdaptiveGlass, glass_tier.dart:311),
+1 per chrome layer (`shared: !chrome`, glass_liquid_native.dart:376 -
every bar and every menu), +1 per lifted lens (`shared: false`, :433),
+1 per `MorphScrollEdgeEffect` (scroll_edge_effect.dart:235, no group
key, audit PF9), + `_Frost` / frosted-tier surfaces read the nearest
group (shared). A nav page with a nav bar, a tab bar and two edge
effects while scrolling = 5 full-screen readbacks (~125 MB/frame at
BGRA10_XR). Options, all VERIFY because a shared key changes WHEN the
backdrop is captured: (a) one "chrome" BackdropGroup for the top and
bottom bars of a MorphNavigationStack (they never overlap each other and
both paint after the page; exact when nothing paints between them inside
either bar's sampling reach); (b) edge effects share the chrome key of
their bar (they sit under it - but the bar must then not need to see the
edge effect's own output: it does, so (b) changes the bar's look unless
the edge effect is drawn inside the bar's layer); (c) audit PF9's
grouping of the edge effect with the page group. Measure each with
xctrace before deciding; this is the largest single GPU item.

G15. `MorphAdaptiveGlass` governor: fine (pure, per-30-frame window).
No action.

### 1.2 Controls, bars, search (sweep 1, spot-checked)

C1. No RepaintBoundary around any animating control -
`grep RepaintBoundary lib/src/widgets` finds only menu.dart:830. Every
tick's markNeedsPaint climbs to the route's boundary and re-records
every sibling picture on the page (tab_bar.dart:506/523/526,
glass_button.dart:498, bar_items.dart:1086, stepper, page_control.dart:529,
progress.dart:261, activity_indicator.dart:211, search_field.dart:389,
navigation_bar.dart:479). Segmented / switch / slider are isolated only
by accident through C5's Opacity. Fix: one RepaintBoundary in
`MorphControlHost` (or around each animating visual). An OffsetLayer adds
no blend; IDENTICAL for flat paint. For glass: a RepaintBoundary is not
an OpacityLayer and does not break BackdropGroup sharing, but verify the
shot diff once. UI L on busy pages.

C2. Search bars rebuild their glass buttons every frame and wrap them in
Opacity / ImageFiltered - search_field.dart:811-841 (`_GlassItem` inside
the frames builder, `_placed` :869-884), search_tab_bar.dart:403-423
(`_RoundGlassButton`). Each `MorphGlassButton.build` per frame: style +
brightness walks, `MorphTypography.resolve`, IconTheme/DefaultTextStyle
merges, new FocusableActionDetector maps (control_focus.dart:64-99).
Hoist the item widgets out of the builder (IDENTICAL). The
Opacity/ImageFiltered over glass breaks the "fade glass through
`MorphGlassSurface.opacity`" contract: fixing it changes output TOWARD
the contract - VERIFY against the native film.

C3. search_tab_bar `_MorphingTabs` / `_SearchCircle` (303-425, 434-719):
`Opacity(1 - p)` over `glass.buildSurface` (:343), `Opacity(fade)` per
tab (:529), `_TabGlyph` (:589-591) re-resolves typography and
`copyWith(fontSize: 10 * labelVisible)` -> label relayout per frame,
`_SearchCircle` resolves a constant style per frame (:703-708),
`Opacity(settled ? 1 : 0)` over the search field glass stays a layer at
rest (:393). Hoist constant styles (IDENTICAL); the opacity items as C2
(VERIFY).

C4. Tickers that run while nothing visible changes (each scheduled tick
forces a frame, and every on-screen BackdropFilter re-runs):
activity_indicator.dart:175-185 ticks at 120 Hz for a 20 Hz image
sequence (16 images / 0.8 s) - ~100 wasted frames/s while a spinner is
visible; stepper.dart:182-185, 219 ticks through the 500 ms hold only to
fire repeats; page_control.dart:217 through the 193 ms platter delay;
glass_glow.dart:239 through the 42 ms riseLag. Fix: sleep the ticker and
wake it with a Timer at the next timeline due time / image boundary.
IDENTICAL images and events (phase within one vsync - the image index is
a function of time, so pick the wake time at the boundary). RASTER L for
the spinner (it is a full re-raster per tick), S otherwise.

C5. `MorphDisabled` always pushes an OpacityLayer
(control_focus.dart:176, `Opacity(opacity: enabled ? 1 : opacity)`):
RenderOpacity composites whenever alpha > 0 and is a repaint boundary
(SDK proxy_box.dart: `alwaysNeedsCompositing => child != null && _alpha
> 0`, `isRepaintBoundary => alwaysNeedsCompositing`), so segmented,
switch and slider carry an OpacityLayer above their glass at rest, the
pattern the menu passport measured as breaking BackdropGroup sharing
(raster p50 11.8 vs 2.3 ms). Same at rest: bar_items.dart:1281 (per bar
item), navigation_bar.dart:500 (title), :393 (Opacity over the edge
effect BackdropFilter). Fix: paint the child directly at alpha 255 and
push opacity only below 1, keeping one render object type so the
subtree never remounts; pair with C1 (this Opacity is the only boundary
those controls have). Flat output IDENTICAL; glass output may change
toward the contract - VERIFY (and measure: this may be a hidden raster
cost today).

C6. Search field rebuilds/repaints a static capsule every press frame -
search_field.dart:398-407 hands `frames` to `MorphControlCapsule` with
no lift/glow; `MorphGlassLayer` rebuilds it (glass_button.dart:601-618)
and the flat `_CapsulePainter` re-draws its MaskFilter shadow per frame
(633-664); only the outer Transform.scale (:391) changes. Pass a
non-firing Listenable when lift and glow are null. IDENTICAL.

C7. Tab bar computes the lens shape 3-4 times per frame with 2 Path
builds and 2 clip layers - `_LensClipper` (tab_bar.dart:727-754) builds
inside + even-odd outside Paths per frame, plus ClipRect (:449),
`_LensPainter` (:679), `_surfaces` (:374); each `morphLensShape`
(lens_driver.dart:12-25) evaluates ~5 closed-form springs. Compute the
lens RRect once per advance and share it (IDENTICAL); ClipPath ->
ClipRRect for the inside clip (VERIFY AA, likely identical).

C8. Same springs re-evaluated many times per frame - `MorphLensMotion`
getters (lens_motion.dart:358-382), `MorphSmallLens` size/scale/progress
(small_lens.dart:190-205) call `_state(t)` per access; slider `_frame`
runs 3x per frame (slider.dart:290, 299, 418) and builds all three
RRects each time, plus scaleX/Y again (:309-310); switch re-reads
scaleX/Y after `_frame` (switch.dart:227-228). Memoize per advanced t
(pure functions of t). IDENTICAL.

C9. Slider: two glass layers + one CustomPaint per frame
(slider.dart:338-364); the track layer rebuilds a plain fill though the
track height only changes while it stretches. One buildLayer call for
track + thumb, or cache the track surface. IDENTICAL (same back-to-front
order).

C10. Style/brightness resolution walks ancestors ~3x per build -
widgets_theme.dart:107-113, 165-171, 178-205 (`morphResolveStyle` calls
`_themeHost` twice, then every control calls `morphBrightnessOf` again:
segmented:334, switch:238, slider:320, glass_button:447, bar_items:1076,
search_field:264, search_tab_bar:262). DUPLICATED resolvers:
`MorphBarStyle.resolve` (bar_items.dart:452-458) and
`MorphScrollEdgeEffectThemeData.resolve` (scroll_edge_effect.dart:88-97)
re-implement `morphResolveStyle`. One walk returning (theme, brightness),
cached in didChangeDependencies. IDENTICAL.

C11. Label measuring per build, three separate measurers -
tab_bar `_widestLabel` (338-351, N TextPainters per build), segmented
`_naturalWidth` + `_layout` (210-219, 185-192: up to 4 layouts per label
before Text lays it out a 5th time), search_field `_buttonWidth`
(712-721, uncached); bar_items (855-875) and navigation_bar `_titleSize`
(213-230) DO cache. Unify `morphLensLabelWidth` / `morphBarContentWidth`
/ `_titleSize` behind one cache keyed on (text, style, textScaler,
direction). IDENTICAL.

C12. `MorphTypography.resolve` allocates 1-2 copyWith + a new
List<FontVariation> per call (typography.dart:174-189), per build per
label and per frame in C3. Memoize on the input style (the role styles
are const; an identity map plus a small LRU for caller styles).
IDENTICAL (TextStyle == compares variations by value).

C13. Glass button per-frame allocations - glass_button.dart:501-510 two
Matrix4 + multiply per frame; the flat `_CapsulePainter` repaints its
blurred shadow each frame though only the Transform changes; `glow: ()
=> ...` (:523) is a new closure per build so shouldRepaint (:671) is
always true. IDENTICAL fixes.

C14. `MorphBarItems` (bar_items.dart:1086-1199) rebuilds every item per
frame while any capsule press or menu animates (Opacity +
Transform.scale + Semantics + Listener with new closures, 1281-1307;
content already cached 1255-1270); `_relayout` (895-949) computes
prominence in O(capsules x items x groups x buttons) (926-930); the nav
bar rebuilds MorphBarItems every build because `_placed(...)` and
`onLayout` are new closures (navigation_bar.dart:325-333); `_BarMenu.glyph`
re-resolves MorphBarStyle per call (bar_items.dart:1364). IDENTICAL
fixes (skip Opacity at 1 is C5).

C15. Nav title + edge effect - ListenableBuilder + Opacity + Transform
per frame (navigation_bar.dart:388-394, 479-509), ImageFiltered created
per frame while blurring. Drive opacity at render level from `frames`
(FadeTransition-style adapter). IDENTICAL.

C16. Page control paint is O(n^2) per frame (page_control.dart:596-630:
`motion.center(i, t)` loops 0..i, :339-346) plus a Paint per dot; also
`CustomPaint(size: _size)` (:530) is fixed at build, so the painted width
can drift from the layout during the width springs (correctness).
Prefix pass per paint. IDENTICAL.

C17. Activity indicator allocates 16 x 8 = 128 Paints per build
(activity_indicator.dart:224-245). Cache per (color, size). IDENTICAL.

C18. A focus change rebuilds the whole control (control_host.dart:32-34
setState) incl. LayoutBuilder subtrees, label measuring and surface
lists, to toggle the ring. ValueNotifier listened to by MorphFocusRing
only. IDENTICAL.

C19. Dead dependency - tab_bar.dart:662 `DefaultTextStyle.of(context)
.style.merge(style)` merges into an inherit:false style (returns style);
the lookup only registers a dependency. Remove. IDENTICAL.

C20. DUPLICATED geometry (~8 places): capsule / small-lens RRect -
lens_driver.dart:12-25, switch.dart:189-200, slider.dart:263-273 (the
same "size x scale, radius min / 2" knob), glass_button.dart:628 and
search_field.dart:420 (identical `_capsule`), search_tab_bar.dart:466-469
and 629-632, segmented:282 and tab_bar:363. One `morphCapsule(Rect)` and
one `morphSmallLensShape(lens, center, t)`; enables C8's shared memo.

C21. DUPLICATED reconcile pattern - lens_driver.dart:61-73,
switch.dart:124-134, slider.dart:153-163, page_control.dart:416-423
hand-roll "call onChanged, then post-frame snap back to widget.value".
Hoist into MorphControlHost (code health, not speed).

C22. DUPLICATED search focus logic - search_tab_bar.dart:147-231,
265-270 vs MorphSearchToolbar (search_field.dart ~640-708, 727-732);
duplicated private painters (`_MagnifierGlyph`/`_MagnifierPainter`,
`_CrossLines`/`_CrossPainter`) around `morphPaintMagnifier` /
`morphPaintCross`. Extract one helper (code health).

C23. DUPLICATED flat painters - "lens fill lerp + rim stroke at lift"
three times (segmented `_SegmentedPainter` 425-458, tab_bar `_LensPainter`
670-702, small_lens `paintMorphSmallLens` 27-46); capsule/body painters
four times (glass.dart `_BodyPainter`, search_tab_bar `_BodyPainter`
786-813, glass_button `_CapsulePainter`, bar_items `_CapsulePainter`);
flat painters with `shouldRepaint => true` that allocate a fresh
MaskFilter.blur / Paint per frame (segmented:441, switch:297, also
slider:466, progress:319, tab_bar:701/724). Unify; cache Paints. IDENTICAL.

Already fine: lens surface lists really change every animating frame;
MorphBarItems caches widths/content/fused flat bodies; glass_glow caches
its spot shader (98-121); every control's ticker sleeps at rest except
C4's cases.

### 1.3 Menus, sheets, alerts, date picker, zoom (sweep 2)

The blurred-SDF fusion itself (menu_fusion.dart) is already separable
(row pass memoized in `_acrossValues`), sparse (only nodes within
band/depth of the edge are blurred; straight sides keep raw values;
round corners use `morphRiceMean`; only near blocks are traced). Its
single-entry exact memo (menu_fusion.dart:50-59) misses on every
morphing frame by construction. The waste is around it.

M1. = G8 (body shadow unbounded saveLayer). The menu's `_MenuShapes`
surfaces are `Positioned.fill` over the vessel, which covers the whole
overlay (menu.dart:706, 950-958), so today the offscreen pass is
OVERLAY-sized on every menu and submenu-card frame. Biggest pure-raster
win in the menu. IDENTICAL.

M2. Each submenu card fuses ONE rounded rect through the full container
fusion every frame - menu.dart:1220 `morphGlassContainerOutline(
[surface.shape], 0)` -> `_fuseContainer` (step-2 grid, LiquidField
sampler, marching squares, B-spline, new typed arrays, a Path). The card
size is lerped during open/close/back, so the memo never hits. Minimum:
memo per card by size (the shape sits at the origin) - IDENTICAL. Better:
an analytic single-box field (`morphBoxDistance` samples, RRect path) -
VERIFY (exact RRect vs traced B-spline edge).

M3. The plain-union silhouette (fusion radius < 1: the settle tail after
~0.2 s, every resize, every submenu-driven grow) re-fuses root + button
through `_fuseContainer` each frame (menu_motion.dart:1548-1555); the
global 4-entry LRU misses because both blobs move; plus G7's NaN. Route
radius < 1 through `morphMenuSilhouette` with the blur disabled (one law,
one code path, reuses `_Scratch`) - VERIFY (different grid/tracer).

M4. = G3 (field texture reallocated + re-uploaded per frame, menu body
and every card body). IDENTICAL.

M5. Allocation inside the blurred silhouette - menu_fusion.dart:88-98
kernel rebuilt per call, 237-240 four new axis arrays in `_BlurredUnion`,
167 `near`, glass_outline.dart:199 `samples`; in dense mode (step >= 4)
the pre-pass (269-284) stores min(dg, ds) per padded node but the field
loop recomputes `menuDistance` / `sourceDistance` (126-127, 185-187).
Cache the kernel per (radius, step), move arrays into `_Scratch`, read
raw values when dense (dg, ds still needed for `share`). IDENTICAL.
(`samples` must stay a fresh array per outline because the GlassField
retains it - or double-buffer with the 3-frame reuse rule of G3.)

M6. A resting finger keeps the menu clock at 120 Hz - `isSettled`
(menu_motion.dart:1656-1665) is false whenever `_pointer != null` or
`glowOpacity > 0`, so a finger resting on the menu or button rebuilds
the whole `MorphMenuLayer` + the button's three frame builders every
frame while nothing changes. Settle when the timeline is empty, every
spring/kick rests and the glow is at its target; pointer events already
`wake`. IDENTICAL (event stamping while asleep is defined by
`MorphClock.stamp`; confirm the menu replays stay green).

M7. The button rebuilds its HIDDEN resting face every tick of a flight
(menu.dart:573-611, 528-538): three `ListenableBuilder(frames)` wrappers;
while airborne `_face` rebuilds `_MenuShapes` -> `glass.buildLayer` ->
`MorphGlassLayerParts.of` for a hidden tag. Merge into one builder; cache
the resting face unless landing or the press scale changed. IDENTICAL.

M8. Two tickers and a duplicated spring per menu (menu.dart:309-342,
menu_host.dart:184-201, flight.dart:1665-1687, 1573-1602, 1041-1061,
menu.dart:938-941): the motion's progress spring runs on the button's
MorphClock AND `MorphMenuFlightProgress` launches a flight whose
controller integrates the same open/close springs on a second ticker;
the vessel ignores the controller value for geometry, yet per frame the
shuttle runs `refreshSourceRect` (transform walk), `resolveRect` and
`_ShuttleScrim` (Localizations lookup + Semantics) at maxScrimOpacity 0.
Skip the scrim widget at maxScrimOpacity 0 (IDENTICAL); let the motion
drive the flight (scrub / a vessel mode without its own simulation) -
geometry identical, latch/landing timing VERIFY (invariant 1's
exemption explicitly keeps the flight pure; do not feed the menu's
kicks into frameTicks).

M9. The same menu motion geometry is recomputed many times per frame
(menu_motion.dart:1224-1247, 1270-1343, 1447-1508, 1586-1650; menu.dart
945-1006, 1028-1046): one layer build evaluates `_frameAt` ~15 times,
`progress` / lean springs / `_radius` ~8 each; `menuBlob` rebuilt by
contentScale, contentRect, rootBlob and silhouette; `cards` (allocating,
O(n^2)) 3-5 times. A per-`_now` snapshot (frame, blobs, cards)
invalidated on advance and on any mutation. IDENTICAL.

M10. Date picker rebuilds the calendar month grids every overlay tick
(date_picker.dart:1470-1499, `_month` 1550-1604, `_Day` 1631-1678): up to
84 `_Day` widgets with DateTime work, strings, closures and one
`MorphTypography.resolve` per day, on every frame of open/close/year
toggle/part swap/page turn. Build both grids as the builder's `child`,
move only offsets. IDENTICAL.

M11. Context menu: up to four extra tickers (`_LiveExtent` above, below,
heroWidth, heroHeight, each a SingleMotionController,
morph_context_menu.dart:1313-1345) beside the flight controller and the
hold ticker; each notifies `_MenuGeometry` = the target's `repaint` =
part of frameTicks, so frameTicks listeners (`land()`, the shuttle,
`_Retract`) run up to 4 extra times per frame. Width and height always
move together. Duplicates the flight's `_ContentSizeChannel`
(flight.dart:1276-1327). One channel, one ticker, one notify. IDENTICAL
(same springs, same frame time).

M12. Opacity above glass in the zooms (sheet.dart:838-856, push_zoom.dart
265-312): the sheet zoom crossfade wraps `_SheetBody` incl.
`painter.buildSurface`; push zoom wraps the whole page (glass bars).
Sheet/page-sized saveLayer per crossfade frame, and it breaks the seam
rule (glass reads an empty backdrop, BackdropGroup sharing breaks). Fade
through `MorphGlassSurface.opacity`, Opacity only around non-glass
content. VERIFY (a correctness fix that changes pixels; audit PF9).

M13. Bar back-button menu lands with a DIFFERENT fusion law and re-fuses
the whole capsule group per frame (bar_items.dart:1110-1139, 1182-1187,
1523 vs menu.dart:539-549): during landing it lets
`buildLayer(spacing: containerSpacing)` fuse button + menu blobs by the
container law (LRU miss per frame), while MorphMenuButton lands on
`motion.silhouette`. Pass the motion's silhouette as the outline like
`_face`. VERIFY (it switches the bar landing to the measured menu law -
a fidelity FIX).

M14. = G6 (double box distance in `_fuseContainer`).

M15. ONE global 4-entry outline cache thrashed by every caller
(glass_outline.dart:623-645): menu union, every card, bars and toolbars
share it; each call scans with `listEquals` + copies with `List.of`; an
animating menu evicts every bar's entry each frame. A memo per owner
(caller passes its slot). IDENTICAL.

M16. = C12 (typography resolve) on per-frame menu paths: card header
(menu.dart:1305, `_text` 1564, x2 at 1765-1773 incl. a merge), `_Day`
(date_picker.dart:1667), wheel row style (1797).

M17. Card header rebuilt every frame with two crossfading Text layers
under two Opacity layers (menu.dart:1297-1327, 1733-1806), outside the
`_rowsOf` cache; `_headerAt` allocates a `MorphMenuPlaced` per frame.
Cache the header subtree per layout, drive opacities paint-only.
IDENTICAL.

M18. Fallback (no painter) submenu cards: `_CardBackdropClipper`
`Path.combine(difference)` per card with `shouldReclip => true`,
`_CardPlatterPainter` `shouldRepaint => true` with mask-blurred RRects,
a BackdropFilter per card (menu.dart:2077-2096, 2121-2167, 1236-1274).
Reclip by listEquals (IDENTICAL); even-odd clip instead of Path.combine
(identical only for non-overlapping cut RRects). Flat/frosted tiers only.

M19. Alert: one TextPainter per action per build in `_fitsInRow`
(alert.dart:697-721) and a full `_AlertCard` rebuild on every pointer
highlight change (setState 563, 572, 581, 589). Cache the row decision on
(width, scaler, direction, style); highlight via a ValueNotifier read by
`_AlertButton`. IDENTICAL.

M20. Date picker wheels: ~4 rebuilds per wheel item crossing
(date_picker.dart:1970-1994, 1950-1958, 782-804, 1837) and a new
`ListWheelChildBuilderDelegate` per build (every visible wheel child
rebuilds). Keep the delegate, no-op `_sync` / `_reconcile` on an
unchanged value. IDENTICAL.

M21. Every MorphMenuButton build schedules `flight.markNeedsBuild()`
post-frame (menu.dart:557-561) -> new `MorphMenuLayer`, new
`Listenable.merge`, resubscribe; `_rowsOf` resets whenever the style is
not identical (`MorphMenuStyle` has no `==`). markNeedsBuild only when
items/style/glyph changed; hoist the merge; value equality on
MorphMenuStyle. IDENTICAL.

M22. Layout built on presses that do not open (menu.dart:475-501,
menu_motion.dart:1105-1122, 2055-2059, menu_content.dart:110-121):
every pointer-down runs `_prepare` -> relayout -> full
`MorphMenuLayout.build` (a TextPainter per multi-line row); an upward
menu is built twice (reversed). Once per press, not per frame - still a
first-frame cost on open. Build lazily / build the reversed layout
directly. IDENTICAL.

M23. DUPLICATED geometry motion vs widget: root shown rect
(menu_motion.dart:1617-1628 vs menu.dart:1049-1066 `_shown(0)`), header
column interpolation (menu_motion.dart:1306-1316 vs menu.dart:1341-1374
`_headerAt`), content-local transform (menu_motion.dart:1465-1508 vs
menu.dart:1454-1457 `_contentLocal`). Expose `shownRect` and header
columns per `MorphMenuCard`; the widget reads them (with M9). IDENTICAL.

M24. Kick integration at 1 ms sub-steps (~8 per 120 Hz frame per kick)
with closed-form `open.velocity(s)` per sub-step and two closures per
advance (menu_motion.dart:2006-2034, 732-757); push zoom evaluates
`rect(t)` (four springs) ~4x per frame (push_zoom.dart:230-270,
push_zoom_motion.dart:393-424). Hoist closures; cache per t. IDENTICAL
(do NOT change the sub-step: the kick integration is a measured,
exempt behaviour).

Checked and fine: no toImage per flight or frame in zoom_source / push
zoom (live replica); wheel and calendar content are not relaid out per
frame (constant OverflowBox constraints, date_picker.dart:1089-1098);
`_rowsOf` keeps rows built once per layout; the blurred-fusion memo hits
at rest.

## 2. Renderer vs upstream

Upstream: https://github.com/whynotmake-it/flutter_liquid_glass, cloned to
/tmp/perf-upstream (worktree of the vendored base at /tmp/perf-upstream-base,
normalized diff at /tmp/perf-vendor.diff, 2780 lines, `diff -ruw` after
rewriting `package:morph/src/glass/renderer/` imports back).

### 2.1 Versions

- Vendored base: `release/01-renderer-core` @ ab1c2d2 (2026-10-02). It is
  STILL the head of that branch: upstream has no newer renderer code.
- Newest upstream activity: branch `impeller-model-gpu-report-pr197`
  (3 commits, 2026-10-04, on top of ab1c2d2). Library code unchanged; it
  adds `example/test/gpu/*` - an impeller_model GPU ESTIMATE of the
  playground (render passes per frame, bytes read/stored, "screen
  equivalents" of extra traffic, which widget causes each pass, and frames
  requested while the screen looks still). Its reports are useful as
  reference numbers: playground Controls with real glass on an iPhone 16
  model = 11 render passes/frame, BackdropFilter alone 6 passes and
  199 MB extra traffic, 8.33 extra screen equivalents, surface format
  BGRA10_XR (8 bytes/px). impeller_model itself is NOT public (path
  dependency into a private checkout of whynotmake-it/talks; the public
  talks repo has no such package) - ask the authors, or use our own
  layer-tree counters (section 4).
- `main` (0.2.0-dev line, April 2026) and the June branches
  (`feat/update` 9937713 "performance optimizations", `feat/layered`,
  `tl-branch-1`) are the OLD architecture, superseded by the release
  rewrite (a41c399). Ideas there that the release line dropped:
  - DIRECT RENDER while geometry animates (`liquid_glass_direct_render
    .frag`): SDF + refraction evaluated inline in the final filter from
    shape uniforms, no matte texture per frame; bake a texture again once
    the shapes rest. The release line instead made the per-frame matte
    cheap (texture rings, sub-rect reuse, deferred submit), so the win is
    now one small Flutter GPU pass per animating layer. VERIFY (different
    shader path); low priority.
  - SPARSE BLEND GROUP components: one small backdrop pass per disjoint
    shape cluster instead of one pass over the union bounds. Relevant
    only to a layer whose shapes are far apart (a toolbar's capsules at
    both ends): the filter clip covers the empty middle. VERIFY.
  - `feat/bounding-box-early-exit` (2025): per-shape bounds culling in the
    SDF - already in the release line (`_boundsData` / uShapeBounds).

### 2.2 Upstream optimizations already present in our copy

Texture rings with frame-counted reuse (reuseAfterFrames 1, idle trim 120
frames, app-wide released pool of 4), 64-px bucketed sub-rect mattes that
only grow, deferred command-buffer submit flushed at scene build,
translated-geometry reuse (`_reuseUniformlyTranslatedGeometry`),
retained compositor translation polling (ancestor motion stays
compositor-only), cached ImageFilter while shader inputs are unchanged
(`takeShaderInputsChanged`), shader softening instead of a blur pass for
frost <= 1.25 device px, 8x-downsampled material map only for mixed
appearances, shared pipelines across renderers, BackdropKey sharing,
geometry culling by per-shape bounds. Nothing in upstream's release line
is missing from ours.

### 2.3 Upstream code we dropped (cost-neutral or a win)

liquid_glass_blend_group, liquid_glass_capture + capture_pass (drops
whole controls on iOS, measured earlier), stretch + glass_drag_builder,
upstream glass_glow (3 motion controllers per surface), logging,
precache. liquid_glass.dart is 452 lines shorter. This was audit PF8 and
is done.

### 2.4 Our local patches and their cost

| patch | cost | note |
|---|---|---|
| backdropShrinkRim (shader) | ~0 GPU | one dynamically uniform branch, only while shrink != 1 |
| field geometry (GlassField + geometry_field_fragment) | CPU field build on the UI thread every frame the outline changes (0.12-0.71 ms measured) + a host-visible RGBA32F upload per geometry pass | `_FieldTextures.upload` overwrites the texture on EVERY geometry pass, even when the same GlassField is re-rendered for an unrelated reason (settings / appearance change): skip the upload when `identical(field, lastField)` - IDENTICAL |
| field identity churn | a NEW GlassField per `MorphGlassOutline.shift` call (menu.dart:548 every build) and the layer's `field` setter compares by identity (liquid_glass_layer.dart:432) -> geometry pass + texture upload on every rebuild even when the silhouette did not change | memoize the shifted outline per (silhouette, origin) - IDENTICAL |
| fake glass draws the fused outline | fake path only (tests, first frames, no Flutter GPU) | none on device |
| WP-I capability (resolve once) | one-time | a win |
| removed blend groups / capture / glow | - | a win (PF8) |
| `_FieldTextures` ring: exact-size textures, max 4 | a field whose size changes every frame (a menu opening) allocates a NEW RGBA32F texture per frame - the ring only reuses exact (cols, rows) matches | allocate with bucketed capacity (like `_TextureRing`) and upload a sub-rect, or keep the newest of each size; IDENTICAL if sampling uses the field size uniform, not the texture size (it does: `1 / texture.width` is written into uFieldSize.zw - change it to the bucket's real size, which is still exact) |
| tryCreateCached / fromAsset no longer evict a failed load | correctness, not perf | a failed bundle load stays cached for the isolate (by design per VENDORED) |

## 3. Ranked plan

Gain: H = visible in p95 build or raster on the device (> ~0.5 ms or a
removed full-screen pass), M = 0.1-0.5 ms or one bounded pass, L = small /
allocation churn. Effort S / M / L. "Agree" column: C = Codex lists it
too, F = Fable (pending), - = only this research.

### 3.1 Provably identical output (do these first, in this order)

| # | item | thread | gain | effort | agree |
|---|---|---|---|---|---|
| 1 | Bound `MorphGlassBodyShadow`'s saveLayer to the outline + shadow reach; no Path.shift per shadow; listEquals on shadows (G8 / M1) | RASTER | H in menus (overlay-sized offscreen pass per frame today) | S | C (A7: bounding is "verify blur tails" for Codex; identical if the bound covers the full Gaussian support, keep dstOut) |
| 2 | RepaintBoundary per animating control in MorphControlHost / around animating visuals (C1) | UI (+RASTER re-record) | H on busy pages (Controls 3 ms build on FLAT tier) | S | - (Codex B1 goes further: repaint-driven host) |
| 3 | Content snapshot: one per State, markNeedsPaint only when capturing; counter + kill the toImageSync fallback (G1) | UI / RASTER+GPU | M, H when the fallback fires | S | C (A1, Codex rank 1) |
| 4 | Sleep tickers between timeline events: activity indicator at its 20 Hz image rate, stepper hold, page control delay, glow riseLag (C4) | RASTER (every tick re-rasters every backdrop) | H while a spinner is visible | S-M | - (Codex: clock already sleeps; did not see the inter-event ticking) |
| 5 | Menu settles under a resting finger (M6) | UI + RASTER | M-H while touching | S | - |
| 6 | Field texture: skip identical uploads, bucketed capacity instead of a new texture per size (G3 / M4); memoize the shifted silhouette (G4) | GPU + UI | M during menu morphs | S | C (A5) |
| 7 | MorphGlassSurface value equality + layer-level skip of buildLayer when unchanged (G2, M7 hidden face, C6 static capsule) | UI | M | S-M | C (B1 partial) |
| 8 | Per-t memo of motion outputs: lens/small lens/slider/switch (C8), menu frame snapshot (M9, M23), push zoom rect (M24), tab bar lens shape once per frame (C7) | UI | M | M | C (B2, Codex top 5) |
| 9 | Hoist per-frame widget construction out of frame builders: search glass items (C2/C3 hoist part), calendar grids (M10), card header (M17), nav title opacity at render level (C15) | UI | M-H for search/date picker | M | C (B5 partial) |
| 10 | Outline caches: per-owner memo (M15), translation reuse via shift (G5), card memo by size (M2 min), kernel/scratch reuse in the blurred silhouette (M5), single evaluator in `_fuseContainer` (G6 - verify float order) | UI | M during morphs (0.1-0.7 ms today) | M | C (A3 top 5, A9) |
| 11 | Context menu: one extents channel on one ticker, one notify (M11); skip the scrim widget at maxScrimOpacity 0 (M8 part) | UI | M | M | - |
| 12 | Caches: typography resolve (C12/M16), style+brightness single walk (C10), unified label width cache (C11), alert row decision + highlight notifier (M19), wheel delegate + no-op syncs (M20), MorphMenuStyle == and conditional markNeedsBuild (M21), lazy menu layout (M22) | UI | L-M each, broad | M | C (B3, B4) |
| 13 | Paint-level hygiene: Paint/MaskFilter caching, page control prefix pass (C16, and its size drift), activity indicator Paints (C17), glass button Matrix4/closure (C13), focus ring notifier (C18), dead DefaultTextStyle dep (C19), uniforms written only to the bound shader (G10), strip culling in the content copy (G12) | UI/RASTER | L each | S | C (A10 lazy uniforms, B7 glow terms) |
| 14 | Code-health unifications with no speed claim: capsule / small-lens geometry (C20), reconcile in the host (C21), search focus helper (C22), flat painters (C23) | - | enables 8 | M | - |

### 3.2 Needs visual verification (one at a time, shot diff on the phone)

| # | item | thread | gain | fidelity risk | effort | agree |
|---|---|---|---|---|---|---|
| V1 | Backdrop sharing: one chrome group for top + bottom bars; edge effects (PF9) (G14) | GPU | H (each removed capture = ~25 MB/frame at BGRA10_XR) | capture timing: content painted between members is not seen | M | C (A11, same caveat: only where composition proves independence) |
| V2 | Remove Opacity layers over glass: MorphDisabled at alpha 1 (C5), search bars (C2/C3), zooms (M12), bar items at presence 1 | RASTER/GPU | M-H (may be a hidden BackdropGroup break today) | changes toward the seam contract; compare to native films | M | - |
| V3 | Glass shadows without a saveLayer per surface: one saveLayer per layer, or even-odd clip instead of dstOut (G9) | RASTER | M per shadowed glass (toolbars: N passes) | cut-out AA, overlap order | M | C (A7/A8 shadow retention, different angle) |
| V4 | Single-box analytic field for submenu cards (M2) and the radius < 1 union through the silhouette path (M3, also fixes G7's NaN) | UI + GPU | M | traced vs exact edge | M | DISAGREE: Codex lists "replacing sampled outlines with analytic shapes" as not automatically allowed; keep it in VERIFY, do the size memo (identical) first |
| V5 | Bar back-menu landing on the measured silhouette (M13) | UI | M | it is a fidelity FIX (same law as MorphMenuButton) | S | - |
| V6 | Menu: let the motion drive its flight instead of a second integrating ticker (M8) | UI | M | latch / landing timing; invariant 1 | M | - |
| V7 | Lift without per-frame matte re-encode (unit displacement, scale in the final pass) (G11) | GPU | L | 12-bit quantization | M | - |
| V8 | Upstream's old DIRECT render while animating / sparse component passes (2.1) | GPU | L-M | different shader path | L | - |
| V9 | App-level: wide gamut off (BGRA10_XR -> 8-bit) halves backdrop traffic | GPU | H | colour depth / P3 - an app decision, not package; measure only | S | - |

Not recommended: lowering blur sigma, sampling density, field/trace
step, sub-clock rate, kick sub-step, or skipping frames of the fusion -
each changes measured output.

Before any of it: fix G7 (NaN in the spacing-0 field) - correctness.

### 3.3 Added from Codex (not found by this research's sweeps)

| # | item | thread | gain | fidelity | effort |
|---|---|---|---|---|---|
| X1 | Separate geometry-matte and material-map invalidation: a mixed-appearance change (tint, saturation, gamma) sets needsGeometryUpdate (liquid_glass_layer.dart:940-946) and reruns the full-resolution matte pass although only the 8x-downsampled material map changed | GPU + UI | H while mixed materials animate (e.g. a tinted capsule beside a plain one) | IDENTICAL with complete revision tracking | M-L |
| X2 | Shader early reject: move the existing coverage rejection (final_render_core.glsl:661-677) up to right after the matte fetch (:532), before the tint / mixed contributor reads (:544-658) | GPU | M for sparse shapes in padded bounds | IDENTICAL if `contourExtent()` and `gContourAlpha` do not depend on the material section (check: gContourAlpha must be set before :544); confirm on device | S |
| X3 | Field-only geometry prep: for `field != null && !writeMaterials`, skip analytic shape bases, superellipse params and the 192-float shape block (liquid_glass_layer.dart:1434-1544) | UI | L-M per field update | IDENTICAL | M |
| X4 | Retain the layer's shadow picture (`_recordOriginalShadows`, liquid_glass_layer.dart:1019-1035) keyed by geometry/shadow/visibility, not tint/highlight | UI | L-M | IDENTICAL | M |
| X5 | Fake glass: return before `drawGlassShadows`' saveLayer when no shadow is visible; cache neck/ring paths and filters (consolidated_fake_glass_layer.dart:274, 343-371; fake_glass.dart:415, 487-505) | UI/RASTER | L on device (fake path = first frames, no Flutter GPU) | IDENTICAL | S-M |
| X6 | Skin: cache each cluster's finished Path, not only its point loops (liquid_field.dart:808-852) | UI | M in one-moving-many-static skins | IDENTICAL | S-M |
| X7 | Repaint-driven glass host for the built-in renderer: a render object fed by `frames` instead of `ListenableBuilder` -> `buildLayer` -> widget diff per tick (glass.dart:470); keep the widget path for custom painters | UI | H (largest structural UI win) | VERIFY (hit testing, semantics, ordering) | L |
| X8 | Transform/opacity channels as listenable render objects instead of builder-wrapped Transform/Opacity per tick (glass_button.dart:498, tab_bar.dart:506, bar_items.dart:1160, menu.dart:978, sheet.dart:652) | UI | M | VERIFY | L |

### 3.4 Merged final plan (own + sweeps + Codex; Fable pending)

Where the three inputs (own read, two sweeps, Codex) agree, the item is
a safe first move; Fable's opinion is pending and may reorder.

Phase 0 - baseline (section 4): glass_audit 3 tiers x 5 runs with the
harness fixes, one xctrace Metal System Trace per tier, the pass-count
test, the idle-frame check. Fix G7 (NaN) as a separate correctness
commit.

Phase 1 - IDENTICAL, broad agreement (own + Codex):
1. Lens content snapshot retained per State (G1 = Codex A1) - both rank it first-tier.
2. Body shadow saveLayer bounded to the full blur support (G8/M1 = A7).
3. Per-owner outline memo + translation reuse + card size memo + scratch reuse (G5, M2-min, M5, M15 = A3, A9).
4. Field texture: no identical uploads, bucketed capacity, memoized shift (G3, G4 = A5).
5. One motion snapshot per advanced t / revision (C7, C8, M9, M23, M24 = B2).
6. Geometry vs material invalidation split (X1 = A2) and the shader early reject (X2 = A4) - Codex-only but well-founded; X2 is S effort, check the data dependency first.

Phase 2 - IDENTICAL, own-research only (Codex did not look there):
7. RepaintBoundary per animating control (C1) - expected to be the biggest UI win on the Controls page (3 ms build on the FLAT tier says the cost is not the renderer).
8. Tickers that sleep between events (C4; spinner first), menu settle under a resting finger (M6), hidden face cache (M7), context menu single extents channel (M11), scrim widget skipped at opacity 0 (M8 part).
9. Hoists and caches: search items, calendar grids, card header, typography, theme walk, label widths, alert, wheels, MorphMenuStyle == (C2/C3 hoist, M10, M17, C10-C12, M19-M22).
10. Paint hygiene batch (C13, C16-C19, C23, G10, G12, X3-X6).

Phase 3 - VERIFY, one at a time with shot diffs:
11. Opacity off glass at alpha 1 and in zooms/search (C5, C2/C3, M12) - measure first: if C5 really breaks BackdropGroup sharing on segmented/switch/slider today, this is also a raster win.
12. Backdrop sharing for chrome / edge effects (G14 = A11) - largest GPU lever, needs composition proof per scene.
13. Shadow passes per surface (G9), analytic single-box fields and the radius < 1 union (M2/M3 - Codex disagrees on analytic replacement; keep behind a golden), bar back-menu landing law (M13, a fidelity fix).
14. Structural: repaint-driven glass host (X7) and render-level transform channels (X8) once phases 1-2 have made invalidation explicit; menu flight driven by its motion (M8).

Not to do: anything that lowers blur sigma, sampling density, grid
steps, sub-clock rate, kick sub-steps, or skips fusion frames.

## 4. Measurement plan (baseline BEFORE any change)

Device: iPhone 16 Pro, iOS 27.0.1, 120 Hz, profile builds, phone lock
`/tmp/morph-native/device.lock` (spec/README.md). One heavy job at a time
(a Mac reboot happened during a profile build on 2026-10-04).

### 4.1 Existing harnesses and what they miss

- `example/integration_test/glass_audit_test.dart`
  (`--dart-define=GALLERY_GLASS=liquid|frosted|flat`): per-scene
  build/raster p50/p95/worst from FrameTiming + outline micro-timings.
  Gaps: (a) the `menu` scene's measure window contains a
  `shot('menu-open')` (takeScreenshot) - that frame pollutes raster_worst
  and p95; move shots out of measure windows; (b) settle() pumps idle
  frames inside the window, which dilute p50 - report only frames whose
  build or raster > 0.3 ms, or count frames-while-animating separately;
  (c) no GPU time; (d) n is small (one gesture per scene) - run each
  scene 5x and report the median of p95; (e) no `vsyncOverhead` /
  `totalSpan`, which show a missed frame even when build and raster are
  each under budget.
- `example/integration_test/menu_trace_test.dart`: two launches with a
  timeline trace + FrameTiming. Keep it as the menu open/close baseline;
  add the `TRACE_SCENE` variants for a submenu and a 10-row menu.
- Release bench (`--dart-define=MORPH_BENCH=true`, lib/perf/
  release_bench.dart): AOT skin microbenchmarks + glacial flight timings.
  Stale (2026-07-30 table, spot run 2026-10-03). It does not touch glass.
- `benchmark/glass_outline_benchmark_test.dart`: JIT outline fusion,
  tracks the device within ~20 percent - fine for relative before/after.

### 4.2 What to add

1. PER-TIER x PER-SCENE matrix: run glass_audit 3 tiers x 5 repeats;
   store report.json per run under tool/audit/perf/2026-10-05/ (small
   JSON, commit it) and a tiny script that prints median p50/p95 build,
   raster, and over-budget counts. This is the baseline table that
   replaces CLAUDE.md's 2026-07-30 passport.
2. UI vs RASTER split is already in FrameTiming (buildDuration =
   UI-thread build+layout+paint, rasterDuration = raster thread). Add
   `FrameTiming.totalSpan` and `vsyncOverhead`, and a per-frame UI
   breakdown with `Timeline.startSync` marks around (a) the glass layer
   build (`MorphGlassLayer`), (b) outline fusion (`_fuseContainer`,
   `morphMenuSilhouette`), (c) `_buildGpuGeometryImage` (CPU encode +
   field upload), behind a `MORPH_TRACE` dart-define so release builds
   pay nothing. Capture with `binding.traceTimeline` as menu_trace does.
3. GPU TIME: FrameTiming does not include GPU execution. Two sources:
   - Instruments: `xcrun xctrace record --template 'Metal System Trace'
     --device <udid> --attach <pid> --time-limit 20s` during the audit
     run (profile build); read GPU frame durations, per-encoder
     durations (Impeller labels render passes: "EntityPass Render Pass",
     "Gaussian Blur Filter", "Snapshot"; Flutter GPU passes are
     unlabeled command buffers) and memory bandwidth.
   - Impeller's own GPU tracer (Metal) emits GPU frame time into the
     timeline when enabled; the switch name has changed across engine
     versions - check `FlutterShellArgs` / the Info.plist keys of the
     3.47.2 engine before relying on it (do not guess the key).
4. PASS COUNT REGRESSION TEST (deterministic, runs in `flutter test`, no
   device): walk the layer tree after pumping each gallery scene and
   count BackdropFilterLayers, distinct backdrop keys (independent
   readbacks), saveLayers from GlassShadow / MorphGlassBodyShadow, and
   Flutter GPU geometry passes (`debugRenderCount`,
   `debugDeferredPassCount`, `debugAllocatedTextureCount` already exist
   in flutter_gpu_geometry_renderer_native.dart; a backdrop capture
   counter exists: `debugRegisterBackdropCapture`). Pin the counts per
   scene; every optimization must lower or keep them. This is the cheap,
   provable proxy for GPU cost that impeller_model gives upstream.
5. REBUILD / REPAINT COUNTERS: `debugProfileBuildsEnabled` /
   `debugProfilePaintsEnabled` (timeline events per widget / render
   object) in one profile run of the Controls scene, to confirm which
   subtrees rebuild/repaint per tick (section 1 claims). In flutter_test:
   count `RenderObject.paint` calls with a `debugOnProfilePaint` hook.
6. IDLE CHECK: with the screen still (no finger, everything settled),
   count frames over 5 s - must be 0. A ticker that does not sleep, or a
   post-frame `markNeedsBuild` loop (menu.dart:557-560) shows up here.
7. FIDELITY GATE for every change: the replay tests (they are the
   motion spec), glass_audit shots diffed against the pre-change shots
   (max channel diff, percent of pixels over 15 - the protocol used for
   the renderer move in glass-renderer.md), and for IDENTICAL items a
   pixel-exact diff.

### 4.3 Order

Baseline (4.2.1 + 4.2.3 once) -> land the IDENTICAL items in small
commits, re-running 4.2.1 after each batch -> VERIFY items one at a time
with the shot diff -> update the performance passport in CLAUDE.md and
glass-renderer.md.

## 5. Second opinions

### 5.1 Codex (gpt-6-astra, reasoning high, read-only sandbox)

Run 2026-10-05 01:47 (the first attempt at 00:50 hit the usage limit). Prompt: same goal, same file pointers, read-only, ranked list with file:line, gain, fidelity, effort. Verbatim answer below (unicode punctuation folded to ASCII, links made repo-relative).

> The strongest opportunities are **retaining lens snapshots, separating geometry from appearance invalidation, and moving animated glass updates out of widget build/layout**.
>
> This is an independent static review of the current code and the requested architecture/spec documents. I did not edit files or run builds/tests. Gains below are estimates of avoided work, not measured speedups.
>
> "Identical" means the proposal reuses unchanged results or removes computations that cannot affect output. "Verify" means pixel equivalence still needs demonstration. Effort: **S/M/L**.
>
> **A. Renderer and glass seam  -  ranked**
>
> 1. **Retain the lens content snapshot across builds.**  
>    Evidence: [glass_liquid_native.dart:354](../../lib/src/widgets/glass_liquid_native.dart:354), [content_snapshot.dart:105](../../lib/src/glass/renderer/internal/content_snapshot.dart:105), capture at lines 28-64 and 130-138.
>
>    **Now:** Every `morphLiquidLayer` call creates `GlassContentSnapshot()`. Updating the source disposes the previous snapshot and unconditionally calls `markNeedsPaint()`. While lifted, paint records another picture; unsupported composited content invokes `toImageSync`. Unchanged content therefore cannot retain its capture across surface-only builds.
>
>    **Proposal:** Give the mounted layer stable snapshot ownership. Recapture on actual source paint/composition, size, or DPR changes; lens position and compensation transforms should only repaint the copy. Start with the supported picture/offset-layer case; conservatively recapture other composition until its invalidation is reliable.
>
>    **Gain:** High potential: UI picture recording and subtree painting; raster/GPU image rendering and allocation on the image fallback. **Fidelity:** Identical for correctly versioned unchanged pictures; **verify** arbitrary composited content. **Effort: M.**
>
> 2. **Separate geometry-matte and material-map invalidation.**  
>    Evidence: [liquid_glass_layer.dart:931](../../lib/src/glass/renderer/rendering/liquid_glass_layer.dart:931), especially `"needsGeometryUpdate = true"` at 945; [flutter_gpu_geometry_renderer_native.dart:401](../../lib/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart:401).
>
>    **Now:** Changed mixed appearances invalidate geometry. `render()` then replaces/renders the full-resolution matte and, when required, the separate material map. Tint/saturation/gamma changes can consequently rerun geometry that has not changed.
>
>    **Proposal:** Track geometry and material revisions independently. Appearance-only updates should redraw the existing material-map format while retaining the matte. Preserve geometry invalidation for visibility crossing zero, contributor geometry, bounds, field, DPR, and optical parameters encoded in the matte.
>
>    **Gain:** High on mixed-material animation: removes a full-resolution GPU pass, matte rotation, and CPU geometry packing. No gain when geometry genuinely changes every frame. **Fidelity:** Identical with complete dependency tracking and unchanged map encoding. **Effort: M-L.**
>
> 3. **Replace the shared four-entry outline memo with owner-local retention.**  
>    Evidence: [glass_outline.dart:623](../../lib/src/widgets/glass_outline.dart:623), [glass_renderer.dart:449](../../lib/src/widgets/glass_renderer.dart:449), [menu.dart:1224](../../lib/src/widgets/menu.dart:1224).
>
>    **Now:** `_recentOutlines` holds four outlines for the entire isolate. Five distinct unchanged bodies requested repeatedly in the same order can continually evict one another. Submenu cards also request sampled outlines for single shapes.
>
>    **Proposal:** Retain each mounted body's last exact shape/spacing signature and outline; retain group membership separately from appearance. Keep any global cache bounded and secondary. Preserve the existing sampled representation, including single-shape bodies.
>
>    **Gain:** Potentially high UI savings when the global cache thrashes: avoids complete field sampling, tracing, and Float32 output allocation. Also stabilizes field identity downstream. **Fidelity: Identical. Effort: M.**
>
> 4. **Reject uncovered fragments before fetching material contributors.**  
>    Evidence: [liquid_glass_final_render_core.glsl:532](../../lib/src/glass/renderer/shaders/liquid_glass_final_render_core.glsl:532), material reads at 544-658; existing rejection at 661-677.
>
>    **Now:** The shader samples the matte, then resolves tint or mixed appearance, and only afterward checks whether material and contour coverage are negligible. The mixed path performs two contributor-map reads and four lookup reads first.
>
>    **Proposal:** Move the existing signed-distance decode and **unchanged** coverage rejection immediately after the matte sample. Its current predicate does not depend on the intervening appearance calculations.
>
>    **Gain:** Raster/GPU: up to six avoided material texture reads plus blending arithmetic per rejected fragment; strongest for sparse shapes and padded bounds. **Fidelity:** Identical by data dependency; confirm generated shaders/device pixels. **Effort: S.**
>
> 5. **Keep unchanged field samples resident on the GPU.**  
>    Evidence: [flutter_gpu_geometry_renderer_native.dart:410](../../lib/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart:410), [flutter_gpu_geometry_renderer_native.dart:1024](../../lib/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart:1024), [glass_field.dart:58](../../lib/src/glass/renderer/glass_field.dart:58).
>
>    **Now:** Every field-backed geometry render calls `_fieldTextures.upload`, ending in unconditional `texture.overwrite(...)`. `GlassField.shift` shares the same sample array, but creates another field wrapper.
>
>    **Proposal:** Associate a resident texture with a sample-buffer revision and dimensions. Update origin/scale uniforms independently. Use the existing safe overwrite ring when samples really change. Make immutability/versioning explicit: `final Float32List` alone does not prevent mutation.
>
>    **Gain:** UI/native upload overhead and CPU->GPU bandwidth of **16 x rows x cols bytes** per avoided upload. Especially useful for optical/material updates over fixed fields. **Fidelity: Identical. Effort: M.**
>
> 6. **Add a field-only geometry preparation path.**  
>    Evidence: [liquid_glass_layer.dart:1434](../../lib/src/glass/renderer/rendering/liquid_glass_layer.dart:1434), superellipse preparation at 1492-1501; [flutter_gpu_geometry_renderer_native.dart:376](../../lib/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart:376).
>
>    **Now:** Field-backed bodies still compute analytic shape transforms, inverse bases, singular-value distance scales, superellipse parameters, bounds arrays, and the large shape uniform block. When appearances are uniform, the field shader consumes none of those analytic shape arrays.
>
>    **Proposal:** For `field != null && !writeMaterials`, prepare only field uniforms and the shape metadata actually needed for bounds, visibility, material short side, and shadows. Keep analytic preparation for material passes that use it. Independently cache superellipse parameters by size/radius/DPR for the remaining paths.
>
>    **Gain:** Medium UI/native savings per field update; removes shape-count-dependent math, allocations, and uniform-buffer traffic. **Fidelity: Identical if the retained metadata is unchanged. Effort: M.**
>
> 7. **Retain shadow recordings independently of material updates.**  
>    Evidence: [liquid_glass_layer.dart:916](../../lib/src/glass/renderer/rendering/liquid_glass_layer.dart:916), [liquid_glass_layer.dart:1019](../../lib/src/glass/renderer/rendering/liquid_glass_layer.dart:1019), [glass_body_shadow.dart:20](../../lib/src/widgets/glass_body_shadow.dart:20).
>
>    **Now:** `_recordOriginalShadows` clears its retained container and records a fresh picture on each active paint. Fused shadows allocate shifted paths and paints; their `saveLayer(null, Paint())` has no explicit bounds.
>
>    **Proposal:** Retain the shadow picture by geometry/transforms, shadow values, visibility, and relevant bounds - not tint/highlight. Cache shifted fused paths and compare shadow lists by value. Separately investigate bounding the fused shadow layer using the backend's full blur support.
>
>    **Gain:** Medium UI recording/path savings. Tighter offscreen bounds could reduce raster/GPU memory and fill cost where the current clip is large. **Fidelity:** Recording/path reuse is identical; **verify** bounded-layer blur tails and AA. Keep the `dstOut` cutout. **Effort: M.**
>
> 8. **Skip empty shadow work and cache remaining fake-glass paths/filters.**  
>    Evidence: [consolidated_fake_glass_layer.dart:274](../../lib/src/glass/renderer/rendering/consolidated_fake_glass_layer.dart:274), neck construction at 343-371; [liquid_glass_render_object.dart:739](../../lib/src/glass/renderer/rendering/liquid_glass_render_object.dart:739); [fake_glass.dart:415](../../lib/src/glass/renderer/fake_glass.dart:415), ring construction at 487-505.
>
>    **Now:** Consolidated fake glass calls `drawGlassShadows` unconditionally; that method enters a `saveLayer` even when there are no visible shadows. The neck path is rebuilt every paint. Standalone fake glass recreates its backdrop filter and exterior ring.
>
>    **Proposal:** Return before shadow-layer creation when no visible shadow contributes. Cache neck/ring paths by shape geometry and transforms, and standalone filters by their actual settings/appearance/size inputs. The consolidated union clip already has caching; extend rather than replace it.
>
>    **Gain:** Small-medium UI savings; potentially one avoided offscreen pass on shadowless fallback paints, subject to engine empty-layer elimination. **Fidelity: Identical. Effort: S-M.**
>
> 9. **Avoid duplicate trace-node evaluation and reuse temporary field buffers.**  
>    Evidence: [glass_outline.dart:672](../../lib/src/widgets/glass_outline.dart:672), overlapping block loops at 742-747; [menu_fusion.dart:182](../../lib/src/widgets/menu_fusion.dart:182).
>
>    **Now:** Container fusion allocates several full-grid temporary arrays on every cache miss. Neighboring near-edge blocks both evaluate shared boundary nodes. Menu fusion already retains substantial scratch storage, but its boundary loops can still recompute final node values.
>
>    **Proposal:** Give trace nodes generation stamps or explicit single-block ownership. Reuse container scratch buffers as menu fusion does, resetting every read-relevant element. Keep each returned outline's sample buffer separately owned.
>
>    **Gain:** Medium UI savings during genuinely changing fusion: fewer SDF/blur evaluations and less allocation/GC. **Fidelity: Identical; preserve sample coordinates, arithmetic, grid spacing, and blur kernel. Effort: M.**
>
> 10. **Specialize common final-shader configurations further - but treat this as a profiling candidate.**  
>     Evidence: [liquid_glass_layer.dart:496](../../lib/src/glass/renderer/rendering/liquid_glass_layer.dart:496); [liquid_glass_final_render_core.glsl:685](../../lib/src/glass/renderer/shaders/liquid_glass_final_render_core.glsl:685), branches at 716, 796, and 813.
>
>     **Now:** Uniform/tint/mixed programs already exist. Each still handles several uniform-controlled optical/material cases, and settings updates write common uniforms to all three program instances.
>
>     **Proposal:** First update inactive shader instances lazily. Then benchmark a small number of exact specializations, such as direct clear lenses versus regular material, using identical formulas and current dispersion thresholds.
>
>     **Gain:** Small UI uniform-write savings; uncertain raster/GPU benefit from lower instruction/register pressure. Uniform branches may already compile efficiently. **Fidelity:** Lazy synchronization is identical; shader specialization **needs visual verification**. **Effort: M.**
>
> 11. **Share additional backdrop captures only where composition proves independence.**  
>     Evidence: [glass_liquid_native.dart:280](../../lib/src/widgets/glass_liquid_native.dart:280), independent lifted layer at 430-435; [scroll_edge_effect.dart:235](../../lib/src/widgets/scroll_edge_effect.dart:235).
>
>     **Now:** Chrome and lifted lenses intentionally take independent copies. Scroll-edge effects do not supply a group key. Frostered surfaces already use an inherited key, and `MorphAdaptiveGlass` already installs a group at [glass_tier.dart:311](../../lib/src/widgets/glass_tier.dart:311).
>
>     **Proposal:** Permit explicit shared keys for peer effects proven to sample the same backdrop without intervening relevant painting or overlapping filter composition. Disjoint peer chrome is a candidate; a lens over body glass/content generally is not.
>
>     **Gain:** Potentially high raster/GPU capture/blur savings in qualifying scenes; none elsewhere. **Fidelity: Needs composition and visual verification. Effort: M-L.** This is conditional, not a blanket grouping recommendation.
>
> **B. Widget layer, skin, and field  -  ranked**
>
> 1. **Introduce a repaint-driven path for the built-in glass renderer.**  
>    Evidence: [glass.dart:470](../../lib/src/widgets/glass.dart:470), [glass_renderer.dart:431](../../lib/src/widgets/glass_renderer.dart:431), [glass_liquid_native.dart:227](../../lib/src/widgets/glass_liquid_native.dart:227).
>
>    **Now:** Every `frames` notification invokes `surfaces()` and `painter.buildLayer`. This rebuilds classification lists and surface widget stacks. Changed `Positioned` bounds also involve layout of the renderer's shape widgets, although consumer content often stays unchanged.
>
>    **Proposal:** Add a renderer-specific mounted host that subscribes to frames, updates explicit surface geometry/material state, and marks paint. Retain the existing widget-building fallback for arbitrary `MorphGlassPainter` implementations. Cache static fills, grouping, and content separately.
>
>    **Gain:** High potential UI savings across active controls: removes surface-tree build/diff work and avoidable dummy-shape layout. Raster quality/work need not change. **Fidelity: Verify**, especially transforms, clipping, hit testing, semantics, and frame ordering. **Effort: L.**
>
> 2. **Compute one presentation snapshot per motion revision.**  
>    Evidence: [menu_motion.dart:1276](../../lib/src/widgets/menu_motion.dart:1276), [menu.dart:951](../../lib/src/widgets/menu.dart:951), `_cards` at 1039; [slider.dart:246](../../lib/src/widgets/slider.dart:246), consumers at 290, 299, and 418.
>
>    **Now:** `motion.cards` allocates and evaluates nested spring loops on every getter call. One menu build reads it repeatedly, including through `rootBlob` and `silhouette`. The slider computes the entire track/fill/thumb frame separately for track surface, thumb surface, and painter; some lens values are then fetched again.
>
>    **Proposal:** Produce one frame record and share it across geometry, content, clipping, painting, and hit testing. Invalidate on motion mutations as well as time changes - pointer events and scroll offset can change state at the same timestamp. Preserve arithmetic evaluation order.
>
>    **Gain:** Medium UI savings; menu card derivation is currently quadratic in stack depth per invocation. **Fidelity: Identical with complete revision tracking. Effort: M.**
>
> 3. **Cache label measurements and resolved typography.**  
>    Evidence: [lens_driver.dart:29](../../lib/src/widgets/lens_driver.dart:29), [segmented_control.dart:180](../../lib/src/widgets/segmented_control.dart:180), `_naturalWidth` at 210; [tab_bar.dart:338](../../lib/src/widgets/tab_bar.dart:338); [typography.dart:196](../../lib/src/widgets/typography.dart:196).
>
>    **Now:** Each label-width request creates, lays out, and disposes a `TextPainter`. An unbounded content-sized segmented control measures the same labels in both `_naturalWidth` and `_layout`. Typography resolution repeatedly copies styles and constructs font-variation lists.
>
>    **Proposal:** Retain natural metrics by labels, resolved styles, scaler, and relevant font/platform inputs; reuse widths between both layout calculations. Resolve common role styles once per relevant change. Invalidate metrics when fonts change.
>
>    **Gain:** Medium UI/text-layout savings on parent rebuilds and changing constraints. These are **not all per-motion-tick costs** in the current controls. **Fidelity: Identical. Effort: S-M.**
>
> 4. **Resolve theme host, extension, and brightness together.**  
>    Evidence: [widgets_theme.dart:113](../../lib/src/widgets/widgets_theme.dart:113), brightness at 173, ancestor walk at 186, style fallback at 202; [segmented_control.dart:333](../../lib/src/widgets/segmented_control.dart:333).
>
>    **Now:** `_themeHost` walks ancestor elements each time. Style fallback can perform one walk for the extension and another for brightness; a control then commonly asks for brightness again.
>
>    **Proposal:** Resolve a context-local record once per build/dependency resolution and use it for both style and brightness. Preserve nearest-theme precedence between SDK Material and `material_ui`, including reparenting and overlay theme changes.
>
>    **Gain:** Small-medium UI savings proportional to control count x ancestor depth; more noticeable in rebuilt chrome/search subtrees. **Fidelity: Identical. Effort: M.**
>
> 5. **Move transform-only chrome animation out of builders and positional layout.**  
>    Evidence: [glass_button.dart:498](../../lib/src/widgets/glass_button.dart:498), [tab_bar.dart:506](../../lib/src/widgets/tab_bar.dart:506), [bar_items.dart:1160](../../lib/src/widgets/bar_items.dart:1160), [menu.dart:978](../../lib/src/widgets/menu.dart:978), [sheet.dart:652](../../lib/src/widgets/sheet.dart:652).
>
>    **Now:** Stable children are correctly hoisted in several places, but their transformation wrappers rebuild every tick. Bars and menus additionally reconstruct positioned wrappers for moving content.
>
>    **Proposal:** Use listenable render-object transforms/opacity/clippers for movement-only channels. Keep content at its existing natural constraints. Separate actual size changes from translation, scale, dimming, and glow updates.
>
>    **Gain:** Medium UI build/layout savings in compound controls and transitions. **Fidelity: Verify** transform-aware hits, semantics, clipping, and backdrop ordering. Sheet height/keyboard changes that affect child layout must still relayout. **Effort: L.**
>
> 6. **Cache cluster paths, not only traced point loops.**  
>    Evidence: [liquid_field.dart:808](../../lib/src/liquid_field.dart:808), cached-loop lookup at 833 and path reconstruction at 847-852; [skin.dart:1253](../../lib/src/skin.dart:1253).
>
>    **Now:** `RenderMorphSkin` already skips tracing when its whole signature matches. When one cluster changes, `LiquidTracer` reuses unchanged clusters' loops but reissues every `moveTo/lineTo/close` for all clusters.
>
>    **Proposal:** Store the completed path alongside each cluster's exact signature and append retained paths in the same order with the same even-odd fill rule.
>
>    **Gain:** Medium UI savings in "one moving cluster, many static clusters" scenes. Removes repeated Dart-to-native path commands; final native path concatenation still has a cost. **Fidelity: Identical. Effort: S-M.**
>
> 7. **Precompute invariant glow-gradient terms.**  
>    Evidence: [glass_glow.dart:98](../../lib/src/widgets/glass_glow.dart:98), particularly the 17-stop loop at 107-112.
>
>    **Now:** The four-entry shader cache keys exact `(radius, gain)`. Animated gain/radius usually miss it, rebuilding lists and evaluating the same `exp(-0.5 * 9 * p * p)` terms for every stop.
>
>    **Proposal:** Precompute the exact stop positions and exponential factors once; only evaluate the gain-dependent conversion on misses. Retain per-surface recent shaders where useful. Do not quantize radius/gain or replace the gradient with a differently interpolated approximation.
>
>    **Gain:** Small UI math/allocation savings per active glow. Shader creation itself remains when parameters change. **Fidelity: Identical. Effort: S.**
>
> Several tempting changes do **not** qualify automatically: reducing blur sigma or resolution, coarsening SDF grids, replacing sampled outlines with analytic shapes, collapsing group opacity into individual paints, or lowering tiers. Likewise, [clock.dart:64](../../lib/src/widgets/clock.dart:64) already stops settled tickers, and [control_host.dart:12](../../lib/src/widgets/control_host.dart:12) already centralizes a control's clock. Multiple springs are not evidence of redundant tickers; their measured timing must remain intact.
>
> **The top five I would do first, in order:**
>
> 1. **A1:** Retain unchanged lens content snapshots.
> 2. **A2:** Separate material updates from geometry rendering.
> 3. **A4:** Move the existing shader coverage rejection before material reads.
> 4. **A3:** Retain outlines per mounted body.
> 5. **B2:** Share one computed motion frame across consumers.
>
> Then I would undertake **B1**, the larger repaint-driven glass-host change, using those smaller changes to make its invalidation and retained state easier to verify.

### 5.2 Fable opinion: see tool/audit/perf-opinion-fable.md (A1-A11; agrees on outline memo/cards, backdrop sharing for bars, unbounded shadow layer, lens snapshot fallback; adds: governor liquid->frosted raises raster on control scenes, CADisableMinimumFrameDurationOnPhone missing in consumer Info.plist)

(Left for the coordinator.)
