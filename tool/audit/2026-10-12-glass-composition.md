# Glass composition: what one surface costs, and one model for all of them (2026-10-12)

Branch `audit/glass-composition` off `audit/2026-10-12` (ec4abb7). Flutter
3.47.2 stable, engine a804b261645ef8c13eb3d5c44a5c2fb0340c5539 (sparse clone
in /tmp/flutter-engine-a804; paths below are under engine/src/flutter).
Device: Pixel 6a (Mali-G78, Impeller Vulkan, 60 Hz, 1080 x 2400 at 2.625).
Evidence: tool/ios_reference/perf/2026-10-12-bench-gc-* (probes),
-bench-gr-* (prototype); traces in /tmp/morph-perf/bench/<label>.

## TL;DR

- The "second saveLayer per glass layer" is not a second pass. Flow traces
  every layer-tree saveLayer as `Canvas::saveLayer` while LayerTree::Paint
  records the frame, and Impeller traces the same saveLayer again under the
  same name while SurfaceFrame::Encode executes it. The flow event costs
  10 - 15 us, the Impeller one 360 - 560 us (inclusive). The bench now
  counts only the Impeller one (9dacedc).
- What glass costs is Impeller's backdrop machinery, not the glass shader.
  The same shader drawn as a plain paint costs 11 - 36 percent of what the
  liquid tier adds over no glass. The rest: a fixed price for any frame
  with a live backdrop read (the whole frame rendered offscreen and copied
  out, one full-screen read; 0.4 - 1.1 ms GPU), the frost blur and shader
  running inside the filter (0.4 - 2.0 ms, the big frosted surfaces), and
  two MSAA offscreen passes plus a composite per surface (~0.2 ms in the
  audit scenes, whose resting glass is already merged; more per separate
  surface).
- Reading the backdrop is cheap: one shared read per frame saves 0.2 - 0.5
  ms, and the backdrop-region prototype (one read per bar band instead of
  per reader) saves nothing measurable. REJECTED.
- Model: a frame pays one live read; a surface whose backdrop is known
  paints over it; all other glass of one plane is ONE filter that its
  members place without passes of their own (Impeller's equal-filter
  path); large surfaces run frost and interior at the resolution the eye
  needs. It replaces containers, stages, the container gate and backdrop
  groups with one plane mechanism. Expected: -1.5 to -2.9 ms GPU and up to
  -450 mW on the Pixel's glass scenes at most (section 2).

- UPDATE (same day, owner: near-invisible pixel changes are fine, a
  backdrop one frame late is not): the frost blur is the largest bucket of
  the big surfaces (`nofrost` probe: sheet -1.4, tab bar -1.3 ms GPU,
  sheet -358 mW), and a SAME-FRAME BACKDROP CACHE wins where the backdrop
  does not change: the floating sheet's glass paints over a frosted copy of
  the page under it, copied again before the frame composites whenever
  what the glass samples changed. Pixel, sheet: GPU 515 -> 393 ms/s (-2.3
  ms a frame), power 1119 -> 833 mW, raster p50 / p95 10.2 / 15.6 -> 8.0 /
  11.5 ms, frames over budget 9.6 -> 2.8 percent; NEAR (host max 26 - 45
  channel steps on < 80 pixels, the frost kernel and the rim corners).
  Section 6.

## 1. One glass surface, end to end

A liquid surface (`RenderLiquidGlassLayer._paintMaterialFilter`,
lib/src/glass/renderer/rendering/liquid_glass_layer.dart) pushes
`ClipRectLayer(filter bounds) > BackdropFilterLayer(filter, key)` with no
children; the filter is `ImageFilter.shader(final glass shader)`, composed
after `ImageFilter.blur` when the glass frosts.

### Flow (raster thread, LayerTree::Paint)

- `BackdropFilterLayer::Paint` -> `mutator.applyBackdropFilter`
  (flow/layers/backdrop_filter_layer.cc:57-64) -> `BackdropFilterEntry::apply`
  -> `delegate_->saveLayer(bounds, ..., filter, backdrop_id)`
  (flow/layers/layer_state_stack.cc:341-357).
- The DisplayList delegate records it into the frame's DisplayList and
  emits the FIRST trace event: `TRACE_EVENT0("flutter", "Canvas::saveLayer")`
  (flow/layers/layer_state_stack.cc:96-105). Device: 10 - 15 us mean.
- `DisplayListBuilder::saveLayer` marks a backdrop layer unbounded: it floods
  to the clip (display_list/dl_builder.cc:531-568), and a backdrop at the
  root sets `root_has_backdrop_filter`.

### Impeller (raster thread, SurfaceFrame::Encode)

- A first pass over the frame's DisplayList counts backdrop filters and,
  per backdrop key, how many filters use it and whether they are all equal
  (`FirstPassDispatcher::saveLayer`, impeller/display_list/dl_dispatcher.cc:996-1020).
- FRAME TAX: if any backdrop filter sits at the root, the whole frame renders
  into an offscreen full-screen MSAA target, copied to the onscreen target at
  the end (impeller/display_list/canvas.cc:1626-1636 and 2614-2618,
  `requires_readback_`): one more full-screen pass and the second queue
  submit every frame that has glass (glass-renderer.md F3).
- `DlDispatcherBase::saveLayer` -> `Canvas::SaveLayer` (dl_dispatcher.cc:309-334)
  emits the SECOND trace event (canvas.cc:1717). Device: 360 - 560 us mean,
  inclusive of what follows. That is the pair the trace showed: every
  saveLayer is counted twice, n equal in every scene (liquid audit, e.g.
  sheet 2805 flow / 2805 Impeller events).
- For a backdrop filter `Canvas::SaveLayer` (canvas.cc:1710-1938):
  1. Coverage: the input floods, so the layer's pass is the clip's bounds
     (canvas.cc:1740-1749).
  2. READ (`FlipBackdrop`, canvas.cc:2415-2522), unless a shared key's
     texture is cached (1800-1846): end the current render pass (an MSAA
     resolve of the whole pass), switch to the other resolve texture
     (Vulkan cannot read from resolve: impeller/renderer/backend/vulkan/
     capabilities_vk.cc:755; impeller/entity/entity_pass_target.cc Flip),
     start a new pass and redraw the whole previous pass into it ("MSAA
     backdrop", canvas.cc:2489-2508), then replay the clips. Cost scales with
     the size of the pass being read - the whole screen at the root - not
     with the glass.
  3. FILTER: wrap the read texture in the filter (1848-1856). Rendering it
     makes the filter's own texture: the frost blur's downsample and
     directional passes (gaussian_blur_filter_contents.cc, non-MSAA) and
     the runtime effect's snapshot, rendered into an MSAA target with depth
     and stencil (impeller/entity/contents/filters/filter_contents.cc:255-272,
     `msaa_enabled = true`).
  4. LAYER PASS: a new render target of the clip's size, 4x MSAA transient +
     resolve + stencil (`CreateRenderTarget`, canvas.cc:147-172 and
     1898-1904); the filtered backdrop is drawn into it (1931-1937).
  5. COMPOSITE: `Canvas::Restore` ends that pass and draws its resolve
     texture into the parent pass (canvas.cc:1977-2050).
- The onscreen surface is 4x MSAA on Android Vulkan
  (impeller/renderer/backend/vulkan/swapchain/swapchain_transients_vk.cc:40-46,
  `SwapchainVK::Create(..., enable_msaa = true)`), so every pass above is
  MSAA except the blur's.
- Shared key, all filters equal (canvas.cc:1858-1890): the filter runs ONCE
  over the whole read (no coverage hint), and every member draws its rect of
  that snapshot straight into the current pass (`Save(0)`, no layer pass,
  no composite). Shared key, filters different (every glass layer today:
  each carries its own uniforms): one read, but steps 3 - 5 per member.

So one resting liquid surface on the Pixel costs: a share of the frame tax
(once a frame), one full-screen read (unless it shares a key), its filter
texture (MSAA), its layer pass (MSAA) and a composite - four extra passes,
two of them MSAA at the clip's size - plus the glass shader itself.

### Measured on the device

Timing proxies behind a debug flag (`debugGlassCostProbe`, read from the
launch settings `MORPH_GLASS_PROBE`; liquid_glass_layer.dart): each replaces
one part of EVERY liquid layer of the frame (the scroll edge effect keeps its
own two filters in all of them):

- `off`: the glass as it is;
- `copy`: the filter is an identity color matrix - read, filter texture,
  layer pass and composite stay; the frost blur and the glass shader go;
- `shared`: one backdrop key for every liquid layer - one read per frame;
- `solid`: the glass shader drawn as a paint over opaque black - no read, no
  offscreen pass, the shader over the same area;
- `skip`: no backdrop filter at all (the floor);
- `pooled`: one key and one identity filter for every layer - the
  equal-filter path above.

`tool/bench/bench.py --suite audit --tiers liquid --arg MORPH_GLASS_PROBE=<p>`,
one APK (9dacedc), two launches per probe in A B C D E E D C B A order,
3 runs per scene, real clocks. GPU = the kernel's GPU work periods of the
app over the scene windows; power = whole phone (ODPM). Per frame = GPU ms/s
over the scene's frame rate (54 - 60). Mean of the two launches (the two
agree within 1 percent on GPU; power spreads up to 10 percent, home-scroll
`solid` 887 / 584 mW):

| scene (liquid layers) | GPU ms/frame off / copy / shared / solid / skip | power mW off / copy / solid / skip | raster p50 off / solid / skip |
|---|---|---|---|
| segmented (nav bar, lifted lens) | 3.08 / 2.65 / 2.63 / 1.57 / 1.39 | 552 / 523 / 474 / 456 | 8.2 / 7.3 / 7.5 |
| controls (nav bar, knob, thumb, containers) | 3.76 / 3.33 / 3.35 / 2.11 / 1.70 | 593 / 575 / 515 / 470 | 8.7 / 7.8 / 6.7 |
| tab-bar (nav bar, tab bar, lens) | 9.19 / 7.16 / 8.92 / 6.30 / 5.61 | 955 / 776 / 710 / 700 | 10.4 / 9.4 / 8.7 |
| menu (nav bar, menu face, buttons) | 6.50 / 5.41 / 6.04 / 4.15 / 3.44 | 757 / 738 / 649 / 587 | 8.7 / 8.2 / 7.4 |
| sheet (nav bar, floating sheet, buttons) | 9.58 / 7.87 / 9.35 / 6.68 / 5.04 | 1137 / 694 / 680 / 540 | 10.3 / 7.6 / 6.8 |
| home-scroll (nav bar; edge effect stays) | 4.41 / 4.27 / 4.38 / 4.02 / 3.99 | 598 / 640 / 736 / 650 | 8.7 / 8.4 / 9.0 |
| list (nav bar, section stages solid) | 5.78 / 5.54 / 5.76 / 5.40 / 5.21 | 631 / 625 / 630 / 598 | 9.1 / 9.3 / 8.8 |

Reading (GPU, ms a frame, scenes where the liquid layers are the glass):

- The liquid tier adds 1.7 (segmented) - 4.5 (sheet) ms of GPU over no glass.
- The glass shader as a paint (`solid - skip`) is 0.18 - 1.64 of that: 11 -
  36 percent (the most on the sheet, the largest surface). The backdrop machinery (`off - solid`) is the other 1.5 -
  2.9 ms: the read, the filter texture, the layer pass, the composite, the
  frame tax, and the frost blur (which only exists inside the filter).
- Machinery without blur and shader (`copy - skip`) is 1.3 - 2.8 ms: the
  structure costs more than the effect.
- One read per frame (`off - shared`) saves 0.2 - 0.5 ms: a full-screen
  read is ~0.6 ms where it is at the root (segmented: 0.75 reads less,
  -0.45 ms), much less where readers sit in smaller passes (sheet: 1.9
  reads less, -0.23 ms). Sharing reads is not where the cost is.
- Power follows the GPU clock, not linearly: the floating sheet loses 443
  mW when its frost blur and shader leave the filter (`copy`) although its
  GPU time drops only 1.7 ms - the frequency steps down a level. The large
  frosted sheet is the one surface where the frost blur dominates.
- Raster thread: `solid` saves 0.5 - 2.7 ms p50 (sheet 10.3 -> 7.6).

## 2. The composition model: one live read per frame, glass placed as paint

Where the money goes (GPU ms a frame over no glass, Pixel 6a, liquid,
probe differences, section 1 and `pooled` in section 4):

| scene | liquid adds | shader as a paint (`solid - skip`) | frame with a live read (`pooled - solid`) | passes per surface (`copy - pooled`) | frost + shader inside the filter (`off - copy`) |
|---|---|---|---|---|---|
| segmented | 1.69 | 0.18 | 0.87 | 0.20 | 0.44 |
| controls | 2.06 | 0.41 | 1.02 | 0.20 | 0.43 |
| tab-bar | 3.59 | 0.69 | 0.64 | 0.22 | 2.03 |
| menu | 3.05 | 0.70 | 1.07 | 0.20 | 1.08 |
| sheet | 4.54 | 1.64 | 0.39 | 0.79 | 1.71 |

(`pooled - solid` also holds the one full-pass identity filter the probe
evaluates; it is the price of the frame's readback mode, its one read and
one filter evaluation.)

The model, per surface, decided by the package (the app optimizes nothing):

1. DECLARED, no read: a surface that knows what lies under it - an opaque
   fill it sits on (a list card, a container on a page color, a sheet's
   content over its opaque detent) - draws its glass shader as a paint over
   that color. Cost: the `solid` column only. `solidBackdrop` today; g1455
   0.2.0's `GlassBackdrop` generalizes the same idea to declared colors,
   images and gradients sampled from a texture rendered once per size.
   IDENTICAL where the declaration is true (host max 1, the shipped list
   stages), visibly wrong where it is not - so the package declares only
   what it paints itself and the app declares its own.
2. ONE FILTER PER PLANE: every live-reading surface of one plane (a bar
   band's capsules, a sheet's buttons, a button row, a menu's satellites)
   shares one backdrop key AND one filter object whose uniforms carry every
   member's geometry (what a container's field / analytic boxes already
   hold). Impeller then evaluates the filter once and each member draws its
   rect of the result straight into the pass at its own place in paint
   order (canvas.cc 1858-1890): no filter texture, layer pass or composite
   per member. Members never change layer, so a pressed, moving, faded or
   scaled member stays a member - the reasons for `still`, the reach check,
   the raster-phase shifts and the scaled-container gate disappear.
   Fidelity: every member reads the plane's read (taken at its first
   member), the BackdropGroup rule of today and UIKit's own rule (glass
   does not sample glass of its container): IDENTICAL for members that do
   not overlap content painted between them; package planes only, where
   the package owns the paint order.
3. AREA AT THE RESOLUTION IT NEEDS: the frost blur and the shader run over
   the surface's area at full resolution inside the filter; on the big
   frosted surfaces this is the largest bucket (tab bar 2.0, sheet 1.7 ms;
   the sheet's shader alone 1.6). A frost below Impeller's half-resolution
   threshold blurs at full resolution (glass-renderer.md "Small blurs"),
   and the interior of a large surface needs no refraction: a rim / interior
   split (refraction only within the bevel, interior = blurred backdrop +
   tint) and frost at the reduced resolution the blur hides are the levers.
   NEAR at best; visible changes need the owner (the open decision "large
   glass surfaces at reduced interior resolution", performance.md).
4. The frame's live read (~0.4 - 1.1 ms) is the fixed price of live glass
   on Impeller Vulkan: any root-level backdrop filter renders the frame
   offscreen and copies it out. Only a frame without one avoids it (the
   flat tier; a screen whose glass is all declared).

What the plane mechanism replaces:

| today | becomes |
|---|---|
| `MorphGlassContainer` join rules (`still`, reach check, MAX_SHAPES layer, one tint), raster-phase shifts and ties, `MorphGlassContainerGate`, `MorphGlassStage` / `sharpOnly` / `MorphGlassStageFade`, `MorphGlassContainerBarrier` | one plane: members stay in place, geometry is a uniform |
| `BackdropGroup` keys, `MorphChromeBackdrop(Scope)`, option C sections | the plane key |
| `solidBackdrop`, list stages | a declared backdrop |

The seeds stay: they bound a blur's pass (the edge effect, the frost seed),
which is what they are for.

Expected savings (Pixel, liquid, GPU a frame): plane pooling removes the
`copy - pooled` column for every surface it merges (0.2 - 0.8 ms in these
scenes, more on screens with many separate surfaces); declared backdrops
remove a surface's whole machinery share; the area levers address the
largest bucket of the tab bar and the sheet. Upper bound with the frame's
read kept: `off - pooled - (solid - skip)`, i.e. 1.0 - 2.5 ms; with all
glass declared, `off - solid`: 1.5 - 2.9 ms and -80 to -460 mW.

## 3. What was not done and why

- Same-frame "glass as paint over a captured image" (g1455's model, the
  combined-source experiment): Flutter gives a paint no access to the
  current frame's backdrop; g1455 is one frame late by construction, and
  the round-5 same-frame replay only covered fixtures (performance.md
  section 5). The pooled path is the in-engine equivalent within a frame.
- Engine changes (a childless backdrop filter drawing its filter result
  straight into the parent pass, non-MSAA filter snapshots, read from
  resolve on Vulkan): each would cut the machinery for every surface but
  needs a Flutter patch.

## 4. Prototype and probes

### Backdrop region (prototype, REJECTED)

`GlassBackdropRegion` (lib/src/glass/renderer/internal/backdrop_region.dart
in e6ce856, `MORPH_BACKDROP_REGIONS`): the navigation bar's edge-effect band
copied once (identity color filter, the edge seed's clip) while the edge
effect shows; the edge blur and the bar's glass read that pass (glass drops
its key and maps its filter coordinates from the region's pass origin). One
full-screen read per frame fewer wherever the edge effect shows. Host
Impeller A/B over the scrolled gallery home
(example/test/backdrop_region_host_test.dart): max channel difference 1,
the bar's filter nested in the region's pass.

Device, one APK (e6ce856), off on on off, 3 runs per scene, means of two
launches (GPU ms/s / power mW / raster p50 ms / frames over budget):

| scene | off | on |
|---|---|---|
| home-scroll (edge shows) | 259 / 646 / 8.5 / 0.4 % | 264 / 616 / 9.0 / 1.8 % |
| list (edge shows) | 325 / 642 / 9.4 / 1.2 % | 331 / 621 / 9.4 / 0.4 % |
| tab-bar (edge shows) | 555 / 920 / 10.9 / 2.8 % | 557 / 930 / 11.0 / 3.3 % |
| segmented | 184 / 573 / 8.3 | 185 / 526 / 8.6 |
| controls | 226 / 569 / 8.9 | 226 / 574 / 9.1 |
| menu | 367 / 720 / 9.0 | 367 / 748 / 8.9 |
| sheet | 516 / 1130 / 9.5 | 510 / 1115 / 9.9 |

GPU within +-2 percent everywhere (the launches of one variant agree within
1 percent); power and raster inside their launch spread. The read the
region saves is about what the region's own pass and composite cost: the
`shared` probe already put a full-screen read at <= 0.6 ms. Not adopted;
the code is removed again after this report (the probe stays).

### Pooled filter (probe)

`MORPH_GLASS_PROBE=pooled`: one key and one identity filter for every
liquid layer, so Impeller filters the read once and places every layer's
rect without a pass of its own. Two launches (9dacedc for `pooled-11`,
e6ce856 for `-12`, identical probe code), against `copy` (the same identity
filter per layer, each in its own passes):

| scene | GPU ms/frame copy -> pooled | power mW copy -> pooled | raster p50 copy -> pooled |
|---|---|---|---|
| segmented | 2.65 -> 2.45 | 523 -> 528 | 8.3 -> 7.8 |
| controls | 3.33 -> 3.13 | 575 -> 572 | 9.2 -> 8.1 |
| tab-bar | 7.16 -> 6.94 | 776 -> 772 | 9.8 -> 10.3 |
| menu | 5.41 -> 5.21 | 738 -> 671 | 8.5 -> 8.0 |
| sheet | 7.87 -> 7.08 | 694 -> 646 | 9.4 -> 8.1 |

The per-surface passes are worth 0.2 ms a frame in scenes with two or three
separate liquid layers and 0.8 ms on the sheet (three own-layer buttons in
the floating sheet, the sheet, the page container, the bar), with raster
p50 -0.5 to -1.3 ms. Building the plane mechanism of section 2 is the next
step: a container whose members each draw their rect of one shared filter
at their own paint position (same shader, same uniforms, a per-member
clip), measured against the container it replaces on a screen with many
separate glass surfaces (the density stand, glass_density_test.dart).

## 6. Same-frame backdrop cache (prototype, the sheet)

Probe first (`MORPH_GLASS_PROBE=nofrost`, 7eaea98, two launches): the frost
blur alone is GPU ms/s sheet 518 -> 440, tab-bar 551 -> 475, menu 367 ->
344, others unchanged; power sheet 1137 -> 779 mW. The bars' and menus' 2 pt
frost already blurs at half resolution (Impeller's `CalculateScale` picks
the scale from sigma alone), so a cheaper frost needs a different source,
not a different sigma.

Mechanism (`GlassBackdropCache`, lib/src/glass/renderer/internal/
backdrop_cache.dart; `MORPH_BACKDROP_CACHE`, default off; 5bff563, f849a74,
4e2962d):

- The sheet route remembers the route below it; its repaint boundary is the
  source. The sheet's glass (not its content) reads the cache through
  `GlassBackdropCacheScope`.
- While the frame composites (the glass layer's compositing hook, after
  every paint of the frame, before the scene is built) the cache signs the
  source's layers that reach what the glass samples (its bounds grown by
  the frost kernel and the refraction): each leaf picture or filter with
  the transform, clip, opacity and filters it is drawn under. Equal
  signature: the copy is still exact. Different: `OffsetLayer.toImageSync`
  copies the source in this frame and blurs it once with the layer's frost
  sigma. No frame is ever shown over an older copy.
- The glass records its final shader as a paint over that copy: the rect
  is drawn in screen device pixels (the canvas undoes the layer's
  transform, because a paint's `FlutterFragCoord` is local), so the
  shader's filter mapping, refraction mirroring and texel fetches stay as
  they are. The dimming between page and sheet is composited in the shader
  (uSolidBackdrop alpha in (0, 0.5]; no uniform layout change).
- No backdrop filter, layer pass, composite or frost pass for the sheet.

Host Impeller (example/test/backdrop_cache_host_test.dart, gallery Sheets,
cache off vs on): mid-open max 55 on the top corners (131 pixels over 8),
rest max 26 (74 pixels over 8, the frost kernel over the page's buttons),
page scrolled 120 px under the open sheet for one frame max 45 (78 over 8,
top corners) - the copy is taken in that frame. 7 copies over the whole
sequence.

Pixel 6a (4e2962d, full liquid audit, off on on off, 3 runs per scene):

| sheet | off | on |
|---|---|---|
| GPU ms/s | 515 (512 / 518) | 393 (394 / 393) |
| power mW | 1119 (1114 / 1124) | 833 (805 / 861) |
| raster p50 / p95 ms | 10.2 / 15.6 | 8.0 / 11.5 |
| frames over budget | 9.6 % | 2.8 % |
| page copies a launch | - | 77 |

Every other scene within its launch spread (the cache only serves the
sheet). The first version signed the whole page and copied 338 times a
launch (a pressed button above the sheet): GPU 514 -> 422 ms/s but power
unchanged; signing only what the glass samples took power down.

Fidelity: NEAR. The copy is blurred by `ImageFilter.blur` on the image
instead of inside the backdrop filter, and the paint has no filter clip at
the rim corners. Owner check on the iPhone pending.

Next: the same cache for every overlay over a page - menu faces, alerts,
action sheets, popovers, the date picker overlay - and for a lifted lens
over its own control; bars over a scrolling list keep the live filter (their
backdrop changes every frame), and pay nothing extra there.

## 7. The cache for every presentation, and frost in the final pass (evening)

Cache, final form (3bc02d4, 61a05d3; `MORPH_BACKDROP_CACHE`, default off):

- Sources: `GlassBackdropCacheRoute` gives a presentation route the opaque
  route below it (sheet, alert and action sheet, date picker). Only an
  unkeyed read is cached; glass in a backdrop group (a sheet's buttons,
  submenu cards, a context menu's hero) reads its own copy as before.
- The copy is taken AFTER a frame (`OffsetLayer.toImageSync` while the
  frame composited reused the page's engine layers, which debug builds
  assert on), only after a frame in which neither the page nor the frost
  sigma changed, and serves a later frame only while the page's layers in
  a band around the glass (its sample region + 15 percent of the page
  height) are the same ones. Any other frame reads through the filter,
  synced to that frame: never an older frame on screen.
- Menus: OFF. The menu face fuses the source button's blob and animates
  its frost; a cached mid-open frame showed the hidden source button
  through the face on the host (max 128 on ~7000 pixels). Open.
- Host (example/test/backdrop_cache_host_test.dart, cache off vs on): sheet,
  alert, popover, date picker within max 45 (sheet's top corners when the
  page scrolls); the frame the page moves under the sheet reads the
  filter (0). An alert opened by a button under it rarely hits the cache:
  that button is still releasing under the alert, a real change.

Frost in the final pass (8d8030a; `MORPH_SHADER_FROST`, default off): a
frost up to 8 device px on a layer without dispersion skips Impeller's
blur pass; the shader takes 24 bilinear taps importance-sampled from the
Gaussian on a golden-angle spiral, and the filter clip grows by three
sigma so the taps read real backdrop past the rim. Host: tab bar max 29
along the rim. NEAR.

Pixel 6a, A/B per lever (2 + 2 launches, off on on off, full liquid
audit, GPU ms/s / power mW / raster p50 / p95 ms / frames over budget):

| lever | scene | off | on |
|---|---|---|---|
| shader frost (8d8030a) | tab-bar | 560 / 904 / 10.5 / 13.9 / 2.1 % | 514 / 798 / 10.0 / 12.6 / 0.3 % |
| | sheet | 523 / 1128 / 9.6 / 14.4 / 7.6 % | 465 / 921 / 9.1 / 13.3 / 5.2 % |
| cache + shader frost (61a05d3) | sheet | 526 / 1122 / 9.9 / 14.6 / 8.7 % | 432 / 902 / 8.6 / 12.9 / 6.3 % |
| | tab-bar | 560 / 981 / 10.3 / 13.0 / 1.5 % | 513 / 811 / 10.3 / 14.4 / 0.9 % |

Every other scene within its launch spread, except one `on` launch of the
combined run whose segmented and list scenes (untouched by either lever)
fell to raster p95 18.5 / 15.6 ms while the other `on` launch read 10.3 /
13.1 - an interfered launch, not the levers. The cache took 14 copies a
launch.

Next (owner, 2026-10-12): move the widget layer's controls onto their own
RenderObjects (no per-frame rebuilds), shared base first, then agents per
control on host gates only (pixel goldens IDENTICAL, perf_counts ratchet,
replay, semantics), one batched device run at the end.

## 5. Files

- Probes: `debugGlassCostProbe` / `GlassCostProbe`
  (liquid_glass_layer.dart), audit `MORPH_GLASS_PROBE`, `bench.py --arg`.
- Bench fix: analyze.py counts the Impeller `Canvas::saveLayer` only (inside
  SurfaceFrame::Encode); bench.py prints the census's backdrop reads.
- Runs: tool/ios_reference/perf/2026-10-12-bench-gc-{off,copy,shared,solid,
  skip}-{1..10}, -gc-pooled-{11,12}, -gr-{off,on}-{1..4}.
