# Glass: the seam and the renderer

Every measured control works with either renderer: the liquid glass
renderer or the flat renderer. The app (or its user) chooses which one -
some users want iOS physics without glass, others want everything iOS -
and both renderers stay supported. A change to glass or render code must
keep both paths correct.

This document is the contract. Numbers, costs and device measurements
live in `tool/ios_reference/spec/glass-renderer.md` and
`tool/ios_reference/spec/glass-optics.md`.

## The seam

- `MorphGlassScope(painter:)` (glass.dart) installs a `MorphGlassPainter`.
  Controls build their glass surfaces (`MorphGlassKind`) every frame
  behind their content via `buildLayer(surfaces, content:, spacing:,
  contentSlots:, outline:)`, `buildSurface`, `buildFill` and `buildBody`.
- Touch glow: `MorphGlassSurface.glow` (`MorphGlassGlow`: wash, center,
  Gaussian sigma, gain) is data. A painter renders it as part of the lit
  surface's glass, over everything the glass shows and under the content,
  or not at all; there is no glow paint layer of its own. The renderer
  lights it on the liquid tier only (below); flat and the no-painter look
  draw no glow.
- `MorphGlassSurface.glass` is false for plain fills (tracks, stepper);
  those are drawn flat through `buildFill`.
- Only native glass is glass: bars, glass buttons and bar capsules,
  menus, popovers, the date picker overlay, alerts, floating sheets, the
  search capsule. A lens / knob / thumb is an opaque platter at rest and
  clear glass only while lifted.
- Without a painter, controls draw flat fills.
- App glass: `MorphGlassEffect` (glass_effect.dart, SwiftUI
  `glassEffect(_:in:)`) is a glass button's capsule host
  (`MorphControlCapsule`) with an app shape (stadium, circle, uniform
  rounded rect), a `MorphGlassStyle` and a tint; `interactive` runs the
  glass button's flex motion from a raw `Listener`, so the child keeps its
  touches.
- Material per surface: `MorphGlassSurface.style` (`MorphGlassStyle.regular`
  / `.clear`, `UIGlassEffect.Style`) picks the liquid preset for that
  surface; null keeps the renderer's `material` (regular, toolbar, clear).
  An owned plane merges only members whose settings match its pass's and
  whose appearance matches beyond tint, so clear glass keeps its own layer
  in a regular container.

## The surfaces channel

- Controls never call the painter themselves. They mount a
  `MorphGlassHost` per painter entry (layer / surface / fill / body;
  `MorphGlassLayer` is the layer host plus its MetaData) with a frame
  closure (`MorphGlassFrame`: surfaces, outline, contentSlots, spacing).
  Code: glass_channel.dart.
- With `MorphGlassRenderer` the host builds its tree once per structure
  (`MorphGlassRenderer.structureOf`: tier, roles and counts, brightness,
  glows, lifted lenses, platters, outline kind) over a `MorphGlassChannel`.
  Every later frame is pushed: render objects bound by
  `MorphLiveBinding` (lib/src/live.dart) write new values
  through their own setters - `MorphLiveStack` / `MorphLivePositioned`
  boxes, live clips, backdrop filters, decorations, painters that
  repaint on a key of what they read, `LiquidGlass.live` /
  `LiquidGlassLayer.live`.
- A host rebuilt by its parent pushes from `update` without building (a
  custom element); one its frames already marked builds once instead. A
  host whose frames notify from a ticker pushes once after every ticker
  ran (a microtask); frames notified in the mid-frame microtasks (a
  `MorphFrameSync`) push at once; anywhere else, or under a dirty
  ancestor, the host builds.
  Until the liquid capability resolves, a host listens to it and builds
  once when it does: a renderer asking for liquid draws flat before that
  and compares equal across the change. `keep` hands back the same glass
  widgets when only the content changed.
- A `slotted` frame (`morphGlassLayerSlots`: glass body surfaces of a
  container that neither float, glow nor frost) builds a slot for every
  surface as a separate shape and as a member of every fused body the
  surfaces can form; each frame fills the slots, an empty one absent from
  its layer (`LiquidGlassShapeFrame.present`) and taking no hits. Its
  structure is only the surface count, so a bar's capsules fuse and part
  through an item change without a build; the owner pads the surfaces
  with invisible ones to hold the count.
- Other painters are asked every frame.
- MorphGlassRenderer's buildLayer / buildSurface / buildBody build the
  same trees from a fixed source: one implementation.

Rules:

- Whatever a tree branches on belongs in `structureOf`. A missing branch
  input shows stale pixels. test/glass_frames_test.dart compares every
  perf-counts scene on every tier against
  `debugMorphGlassRebuildEveryFrame`.
- A live widget that replaces a stock one subclasses it (tests find them
  with `find.bySubtype`).

## Painters across presentations

- A surface presented above its source draws with the painter installed
  above the source. A MorphGlassScope inside a page is invisible from the
  navigator's overlay.
- `MorphGlassScope` is an InheritedTheme, and every presenter carries the
  source's InheritedThemes (themes.dart, `MorphThemeCarrier`, the
  popup-route precedent):
  - engine flights: `MorphFlight.sourceThemes` wraps the whole shuttle
    and the settled route page (ghost, surface, content);
  - alerts, action sheets, sheets, the date picker: captured from the
    presenting context up to the navigator, recaptured on each page
    build;
  - the zoom replica: from its tag.
- Menus also carry `MorphMenuHost.menuGlass` explicitly.

## Fading glass

- Fade glass through `MorphGlassSurface.opacity`, never through an
  Opacity above it: an Opacity makes the glass read an empty backdrop.
- Never put an OpacityLayer between resting glass: it breaks
  BackdropGroup sharing.
- The same holds for every BackdropFilter. The scroll edge effect fades
  through `MorphScrollEdgeEffect.opacity` (an alpha matrix composed onto
  its blur); under an Opacity the page shows sharp under the bar for the
  whole fade (edge_effect_fade_test).

## Flat edge effects

`MorphScrollEdgeEffect` reads the installed renderer's effective tier.
Flat draws its fade / hairline only: no blur, no color-matrix backdrop
filter, no seed copy. Liquid and custom painters keep the full edge
effect. The flat audit census is zero backdrop filters in all seven
scenes (home-scroll, segmented, tab-bar, controls, menu, sheet, list).

## Backdrop groups

- A shared group member does not read the backdrop at its own place in
  paint order. On iOS (Metal reads from the resolve texture) every member
  after the first reads the pass texture as it stood at the last backdrop
  flip before it (any filter's); elsewhere it reads the copy of the first
  member.
- So only glass whose backdrop is complete before the group's first glass
  may share. The page's resting body glass shares the root group.
- Anything floating over the page reads a copy of its own or its own
  group: bar / menu kinds (both tiers, also through buildSurface), the
  navigation bar + toolbar (one shared read per screen,
  `GlassPlaneScope.shareRead`), the search tab bar, a sheet's content, a menu's
  card, a context menu's hero and satellites, lifted glass, and a lifted
  lens / knob / thumb.
- Two resting body glass surfaces with content painted between them: the
  later one misses that content. This cannot be detected per frame
  (pictures carry no drawn bounds).
- Groups are declared with `GlassPlaneScope` (plane/glass_plane.dart):
  `plane` (a key of its own), `chrome` (joins the read a `shareRead`
  above hands down, else its own key), `shareRead`, and `backdrop` for
  what glass with a read of its own reads (live, or a presentation's
  cached copy of the route below). A layer says where it reads with
  `GlassRead`: its plane, its own read, or its own read around a lifted
  lens.
- There is no automatic grouping. The app wraps a section painted over
  earlier glass in its own `BackdropGroup(child: section)`
  (GlassAdaptiveScope dartdoc, backdrop_section_test; options and device
  costs in glass-renderer.md).
- The scroll edge effect keeps its own copy: in the bars' group the
  capsules would miss its fade.

## Glass planes and containers

`MorphGlassContainer` (glass_container.dart, opt-in) and the package's
stages (`MorphGlassStage`, internal) declare an owned plane
(`GlassPlaneScope.owned`, plane/glass_plane.dart): a pass at the plane
(`LiquidGlassLayer(planePass: true)`, with the settings and material of a
resting glass button) draws the resting glass below it that would look the
same there, in one geometry pass and one filter. Everything inside is
content above that glass.

Membership lives on the render side (plane/render_glass_plane.dart):

- Every `LiquidGlassLayer`'s repaint boundary is a `RenderGlassMember`. It
  clips the layer to its reach, registers with the nearest
  `RenderGlassPlane` when it attaches, reads its layer's facts (settings,
  glow, fused field, `joins`, read and read key) from the layer's live
  sources, and follows its rest when its own layer composites: its
  transform to the plane and its shapes' transforms, sizes, outlines and
  materials. A member rests from the moment it appears, after two quiet
  frames, or after a frame no frame follows.
- The plane decides in its layout, from these facts. The reasons a member
  keeps its own layer (`GlassSplit`, in check order): closed (a stage its
  owner closed), read (its own or a lifted read, or another plane's read
  key in between: a bar), control (its control paints a fill under this
  glass, `joins` false), glow, fused, empty (no shapes, or mixed
  materials), frost (an `outsideGlass` plane), blocked
  (`glassPlaneBlocker`: a fade below 1, an offstage, any clip, a shader
  mask, a backdrop filter, a follower, a viewport, other glass, an active
  `GlassPlaneScope.planeBreak`, anything else that always composites a
  layer), scaled (the plane or the member under more than a translation:
  a floating sheet), settings, look (beyond tint, against the first merged
  member), capacity (32 shapes), moving.
- A merged member lends its shapes to the pass
  (`GeometryRenderLink.lendTo`): its own layer paints none and the pass
  paints them. The member is their raster anchor
  (`RenderGlassRasterAnchor`): the pass shifts them onto the grid of the
  member's own layer, so off the pixel grid they read the pixels of their
  own layers (1 - 3 channel steps).
- A fact a member reports before layout (a glow, a plane break, a
  `MorphTag` hiding it: a host in a tag below an owned plane depends on
  `MorphTagVisibility` and breaks its glass out while hidden) resolves in
  the same frame. What only the composited frame shows (a member that
  moved, faded, was not drawn or is drawn scaled; a plane drawn scaled)
  the plane checks after paint and resolves in the next frame: a merged
  member that starts moving leaves its pass one frame later (NEAR).
- Scale is known only after a frame composites, so a new plane, and a new
  member, merge from their second frame: glass merged under a scale it
  did not know draws differently in its own layer for frames after it
  leaves. A member that mounts while its plane lays out under another
  layout boundary (inside a LayoutBuilder) is resolved after the frame in
  debug builds, where layout may not dirty the plane.
- `RenderGlassMember.census` (`GlassMemberCensus`) says how a member is
  drawn (merged, split, painted) and why.

Stages:

- MorphSearchToolbar is one; its items fade through a plain `Opacity`
  (exactly opaque is no break), and the toolbar closes the stage while
  items appear or the field moves.
- Every MorphListSection card is one, with `GlassPaintOrder.outsideGlass`:
  the rows paint between the stage and its glass, never inside a member's
  outline, so resting unfrosted glass (which samples only inside its own
  outline) never reads them, and frosted members keep their own layers. A
  row whose highlight shows keeps its accessories out through
  `GlassPlaneScope.planeBreak`.
- Solid backdrop: a card's stage declares `solidBackdrop: cellColor` (its
  glass can read nothing but the opaque card), and the pass draws the
  final shader as a plain paint with `uSolidBackdrop` replacing every
  backdrop read: no backdrop filter. A member the plane reaches but does
  not merge (pressed, glowing, moving, unlike the others; not blocked, not
  scaled, not frosted over an `outsideGlass` plane, on the plane's read)
  is shaded over the same color in its own layer
  (`RenderGlassMember.planeSolid`, which its layer reads); one kept out (a
  held row's highlight between, a fade, a clip) reads its backdrop. Read
  from the plane's copy, a member leaving a solid plane would become the
  read's first reader above everything painted between it and the read's
  other glass, and that glass would show the page instead of what it sits
  on (a picture further down) until the member settled back.
  `MorphGlassContainer.solidBackdrop` is the app's opt-in for its own
  containers; declare it only where that color really is all the glass
  would read (the gallery's sheet, controls and menu pages pass their page
  background).
- The navigation stack's chrome is not a stage: one screen-high layer
  costs the GPU more than the raster saves.
- The scaffold body gets no flag: a container above its scroll view joins
  nothing, because the viewport blocks.
- App sections stay explicit.

Numbers and gates: glass-renderer.md "Glass container".

## Glass inspector

`MorphGlassInspector` (glass_inspector.dart, public) overlays the frame's
backdrop filters, captures, owners (GlassLayerOwners when set, else the
nearest composited render object's Morph widget chain) and hints from the
plane census over the render tree: resting members outside any owned
plane whose look would merge, grouped by their nearest blocker
(`glassPlaneBlocker` up to the root), read key and look; and members of an
owned plane kept out by a blocker.

- Debug and profile only: in kReleaseMode it builds the child alone and
  the code is tree-shaken.
- One persistent frame hook serves all inspectors; a layer walk per
  frame, the element and render walks only when the filter set changes.
  While it watches, members outside any plane follow their rest too
  (`RenderGlassMember.followsRestEverywhere`).
- `MorphGlassInspector.census()` returns the same data for tests.
- The gallery's Glass renderer page toggles it.

## The renderer and its tiers

- The package carries one renderer: lib/src/glass/renderer, vendored
  from whynotmake-it (Apache-2.0); VENDORED lists the local patches.
- The widget layer reaches the renderer only through
  lib/src/glass/renderer/renderer.dart: test/architecture_test.dart
  rejects imports of its composition/, geometry/, internal/, pass/ and
  rendering/ directories from lib/src/widgets (a ratchet lists the few
  exceptions left, each with the step that removes it).
- Public entry: `MorphGlassRenderer` with `MorphGlassTier`: flat and
  liquid. Liquid draws where the GPU holds it; flat draws everywhere
  else: the cheap device classes, the web, and every frame before the
  liquid capability resolves. A backdrop-reading look without Flutter GPU
  was measured and dropped: it cost about what liquid costs on the GLES
  Pixel 6a, and on Skia its multi-pass blur ran 30 - 125 ms raster p95 a
  page (Redmi 6A).
- `GlassAdaptiveScope` picks the tier once per session, never at runtime.
  There is no tier switching from frame timings. An explicit tier wins;
  otherwise `GlassAdaptiveScope.tierFor(deviceClass, best)`: liquid on
  Vulkan / Metal, the single `GlassAdaptiveScope.cheapTier` (flat) on the
  GLES fallback, on Apple GPUs before the A13 and on Skia (a native
  runtime without Impeller, known at once from
  `ImageFilter.isShaderFilterSupported`). The device class is probed from
  Flutter GPU (glass_device_native.dart) once the liquid capability
  resolves.
- The startup flip: until the capability resolves, liquid is drawn flat.
  `GlassAdaptiveScope` installs flat for liquid (chosen or explicit) and
  installs liquid when the capability flips, so the painter changes and
  every dependent rebuilds; a `MorphGlassScope` holding a renderer that
  asks for liquid listens to the capability itself and notifies its
  dependents on the flip; a glass host listens and builds once. Await
  `MorphTheme.precacheGlass` before `runApp` and the first frame is
  already liquid.
- A `LiquidGlassLayer` paints its child with no glass while shader
  filters are unsupported or its Flutter GPU geometry renderer is still
  loading. The widget layer builds liquid layers only once liquid is
  available, which caches the renderer, so only direct renderer users
  see that transient.

## Outline is truth

- The package computes every shape once and fuses it (skin merge law,
  the menu's blurred SDF) into a `MorphGlassOutline`. The renderer only
  shades the outline it is given and never fuses on its own.
- A plain union (spacing 0: the menu's tail under 1 pt, submenu cards)
  carries its boxes instead of a field: path union for the edge, each box
  shaded as its own circular rounded rectangle. Exact, with no per-frame
  trace or upload.
- An outline built from a path alone (`MorphGlassOutline(path)`, a
  custom control's) has neither a field nor boxes: the renderer draws it
  as the flat body (`morphGlassLiveBody`) on the liquid tier too.

### Analytic geometry

On by default. `MORPH_ANALYTIC_GEOMETRY=false` restores the matte; mode
`changes` runs analytic only while geometry changes and the matte at
rest. Qualification: tool/audit/claude-navigation-options-report.md.

- An eligible liquid layer (<= 8 shapes, uniform or tint-only
  appearance; a container body of <= 4 uniform-radius boxes as a
  `GlassBoxField`) is evaluated in the final shader itself
  (analytic_geometry.glsl): no matte, no material pass, no field upload,
  no CPU fusion.
- The shader carries the same merge law as liquid_field.dart (angular
  width k*sin^2(theta/2), the `_share` optics fold, the optical turn).
  The law has two implementations; the host oracles pin them together
  (analytic A/B against the matte; a fine-grid CPU field at 1/8 step,
  mean < 0.75 per channel). Change both or neither.
- The matte such a body rests on in `changes` (or draws with analytic
  geometry off) is encoded by the same law per pixel
  (gpu/geometry_fused_fragment.glsl; fused_optics.glsl holds the optics
  both passes share), never from the 4 pt sampled field, so a rest frame
  matches the moving ones up to the matte's quantization.
- A matte under a scale of its pass along its axes (each 0.5 to 2, no
  material map; a held tab bar's flex stretches one axis and squashes the
  other) is encoded at the pass's pixels, its texels centered on them
  (`glassMatteDensity`), so its nearest samples repeat no texel; the
  geometry passes map a texel to the layer's device pixels, in which every
  encoded position and distance stays.
- The body shadow is the plain union of the boxes clipped outside a
  neck-covering path (fidelity NEAR).
- Menus (blurred SDF), bodies of 5+ boxes and mixed appearances keep the
  matte path.

### Flat shader bodies

On by default. `MORPH_FLAT_SHADER_BODIES=false` restores the traced path.

- A flat fused body of <= 4 boxes is filled by the same merge law in a
  fragment shader (lib/src/widgets/shaders/flat_fused_body.frag, shared
  fused_law.glsl) instead of a CPU-traced silhouette.
- Its path is traced only if something reads it.
- Qualified on Skia (Redmi 6A).

### Final pass budget

The final pass compiles into the variants of
lib/src/glass/renderer/liquid_shader_variants.dart (one table; the hook,
the asset keys, the warm-up and offline.py read it). Mali-G78 figures from
tool/audit/shader/offline.py; before and after the 2026-10-19 diet in
tool/audit/2026-10-19-shader-diet/.

- The shader frost (24 unrolled taps) holds a variant at 64 work
  registers, half occupancy, whatever else it does: the taps fill 32 alone
  and anything live across them tips the allocation. A rolled loop fits
  32 but costs about 24 more arithmetic cycles a frosted pixel. So the
  one-appearance and tint-only matte variants come twice, frosted (64) and
  unfrosted (32, full occupancy, for no frost, the softening kernel or a
  blur pass); the pass picks by `GlassFrost.shaderSigma`. The
  mixed-appearance and analytic variants always carry the frost (64
  either way).
- Where every tap lies inside the backdrop texture (all but the pixels
  near its edge), the frost reads its taps unmirrored: about a third of
  the frosted path's arithmetic. The edge pixels run a rolled, mirrored
  loop. NEAR: host Impeller within one channel step on the frosted harness
  cases. The mixed-appearance variant keeps one mirrored loop (split, it
  spills).
- No variant spills on Vulkan. The rim values the layer always writes the
  same (light along +y, white highlight, contour offset and transmittance
  0, glint wrap 0.5 at full strength on both walls, bevel directionality
  0.5 without size response) are shader constants; held as uniforms they
  pushed the analytic variants into spills. The coverage and contour
  direction are derived again after the refraction; the one-model variants
  compute only the tint tone of their model. All IDENTICAL on the host
  harness.
- `mediump` buys nothing: impellerc does write RelaxedPrecision for
  mediump arithmetic into the Vulkan stage (Flutter 3.47.7 and 3.50 beta,
  with or without the file's `precision highp float`), but the color, tint,
  light and glow math in mediump moves no variant's registers (fp16 1 - 2
  percent of the arithmetic).

### Touch glow

On the liquid tier the final pass of a layer applies the glow of its lit
surface (shaders/glass_glow.glsl, included by every final-render variant):
`c = mix(c, min((c + wash) * (1 + gain exp(-r^2 / 2 sigma^2)), 1), cover)`
on the glass color before it is composited, `cover` the lit surface's
circular rounded box antialiased over one device pixel. That is the plus
wash then the color dodge of white level `1 - 1 / factor`, clamped at
white, exactly as the dodge painter drew it, with no blend pass, clip or
paint layer.

- Uniforms: `uSolidBackdropGlow[4]` (the core's last declaration, float
  index 65): `[0]` the solid backdrop, `[1]` spot (center, falloff
  `log2(e) / 2 sigma^2` in device px, gain), `[2]` the lit box (center,
  half extents), `[3]` corner radius and wash; all zero skips the branch.
  One array because Metal has 31 buffer slots and the fused tint variants
  use them all. Matte space is the layer's local coordinates times the
  device pixel ratio. Packing: `LiquidGlassGlow.uniformsOf`, with its CPU
  reference `LiquidGlassGlow.shade` (test/glass_glow_shader_test.dart).
- One glow per layer pass: the first lit surface of the layer's shapes
  (a control lights at most one). A fused body keeps the glow inside its
  lit member's box, so the menu's neck and button stay unlit.
- Every variant lights it, the one for mixed appearances (shapes of one
  layer that differ by more than tint) included.
- The glow is not structure: it enters `LiquidGlassLayer.live` through
  `glowOf` every frame and rebuilds nothing. A glowing layer leaves its
  plane's pass in the same frame (`GlassSplit.glow`): the pass carries no
  glow.
- A frame in which only the glow moves (it rises, follows the finger or
  fades while the control stands still) travels on its own channel:
  `MorphClock.glows` (`motionGlowOnly`) or the menu host's `menuGlows`
  -> `MorphGlassHost(glows:)` -> `MorphGlassChannel.pushGlows` ->
  `LiquidGlassLayer.live(glows:)`. Only the layer's glow binding hears it;
  `RenderLiquidGlassLayer.glow` rewrites the uniforms and hands the
  retained backdrop filter a new filter over them, no paint, no picture,
  no capture (glass recorded into a picture over a solid or cached
  backdrop repaints). The control's other render objects keep the frame
  they last showed.
- `morphGlassLightsGlow(painter)`: whether glass shows a glow at all (the
  renderer's liquid tier, any custom painter). The open menu lights none
  without it (`MorphMenuMotion.lightsGlow`), so its 0.5 s fall keeps no
  flat menu awake. The tab bar and glass buttons still run theirs.
- Fidelity NEAR against the old 16-stop gradient: under 0.65 of an 8-bit
  level inside three sigma for the tab bar and the menu, and the old cut
  at a six-sigma square (a step of `gain e^-4.5`: 0.9 level on the tab bar,
  1.6 on the menu, up to 3.2 on a small dark button) is gone. A glass that
  fades out while lit fades its glow with it.
- Cost (tool/audit/shader/offline.py, malioc Mali-G78): the lit path
  costs about +1 arithmetic and +3 load/store cycles a fragment, total
  arithmetic +0.75 - 1.1.

## Shadows

Glass shadows clip to outside the glass (an even-odd path), never a
saveLayer + dstOut per surface: no offscreen pass, no shadow under the
translucent body (GlassShadowCaster, MorphGlassBodyShadow).

A liquid shape paints its own shadows (RenderLiquidGlass mixes in
GlassShadowCaster): a proxy render object above the shape would lay out
again on every frame the shape resizes.

## Packaging and web

- The build hook writes `build/shaderbundles/`; its pubspec asset entry
  must stay. Flutter 3.47.2 does not request data assets from hooks, so a
  data-asset-only bundle silently loses liquid glass on the device.
  Verify packaging on a native device.
- The final pass is no pubspec shader: the hook compiles it with
  impellerc --iplr once per variant of the one table
  (lib/src/glass/renderer/liquid_shader_variants.dart) into
  `build/shaderbundles/<name>.iplr`, for the target's runtime stages; an
  edit to any file under shaders/ reruns it. Its Skia stage is an empty
  stub only the host tests load.
- The web build compiles: the liquid tier sits behind a conditional
  import, and the hook compiles no final pass for the web.
