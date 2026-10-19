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
  lights it on the liquid tier only (below); flat, fake and the
  no-painter look draw no glow.
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
  A glass container admits only members whose settings and appearance
  match its own, so clear glass keeps its own layer in a regular
  container.

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
  once when it does: a renderer asking for liquid draws fake before that
  and compares equal across the change. `keep` hands back the same glass widgets when only the
  content changed.
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
filter, no seed copy. Fake, liquid and custom painters keep the full edge
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
  navigation bar + toolbar (one `MorphChromeBackdrop` key per screen,
  chrome_group.dart), the search tab bar, a sheet's content, a menu's
  card, a context menu's hero and satellites, lifted glass, and a lifted
  lens / knob / thumb.
- Two resting body glass surfaces with content painted between them: the
  later one misses that content. This cannot be detected per frame
  (pictures carry no drawn bounds).
- There is no automatic grouping. The app wraps a section painted over
  earlier glass in its own `BackdropGroup(child: section)`
  (GlassAdaptiveScope dartdoc, backdrop_section_test; options and device
  costs in glass-renderer.md).
- The scroll edge effect keeps its own copy: in the bars' group the
  capsules would miss its fade.

## Glass container

`MorphGlassContainer` (glass_container.dart, opt-in) shades the resting
glass of the controls below it in one layer (one geometry pass, one
filter). Everything inside it is content above its glass.

A host joins only when its glass would look the same:

- still (`MorphGlassLayer.still`; the glass button, the search capsule
  and the bars tell `still`). A moving member would re-encode the
  container's matte every frame;
- separate resting body glass with the container's settings and one
  tint;
- no fade / clip / filter / viewport between it and the container (a
  MorphTag source never joins);
- not under a BackdropGroup of another key;
- at most 32 shapes per container (MAX_SHAPES).

The join decision is part of the host's structure.

Raster phase: a joined host's shapes sit under a `GlassRasterAnchor`, and
the container shifts them by the difference of the two nearest-sampling
phases, so off the pixel grid they read the pixels of their own layers
(1 - 3 channel steps).

Stages (`MorphGlassStage`, internal) are containers the package owns
where it owns the paint order, open only while it neither fades nor moves
its members (`MorphGlassStageFade`):

- MorphSearchToolbar is one.
- Every MorphListSection card is one: the stage sits over the card fill;
  `sharpOnly` closes it while controls frost (resting unfrosted glass
  samples only inside its own outline, so the rows' text and separators
  painted after the stage are never read); a row whose highlight shows
  keeps its accessories out through `MorphGlassContainerBarrier` (an
  InheritedWidget the reach check depends on, like MorphTagVisibility).
- Solid backdrop: a card's stage declares `solidBackdrop: cellColor` (its
  glass can read nothing but the opaque card), and the layer draws the
  final shader as a plain paint with `uSolidBackdrop` replacing every
  backdrop read: no backdrop filter. A member that leaves the stage reads
  its backdrop as before. `MorphGlassContainer.solidBackdrop` is the
  app's opt-in for its own containers; declare it only where that color
  really is all the glass would read (the gallery's sheet, controls and
  menu pages pass their page background).
- The navigation stack's chrome is not a stage: one screen-high layer
  costs the GPU more than the raster saves.
- The scaffold body gets no flag: a container above its scroll view joins
  nothing, because the viewport blocks.
- App sections stay explicit.

Numbers and gates: glass-renderer.md "Glass container".

## Glass inspector

`MorphGlassInspector` (glass_inspector.dart, public) overlays the frame's
backdrop filters, captures, owners (GlassLayerOwners when set, else the
nearest composited render object's Morph widget chain) and hints:
resting joinable hosts outside a container, grouped by their nearest
blocker (`morphGlassContainerBlocker`, the reach check's own predicate)
and settings, and hosts inside a container kept out by a blocker.

- Debug and profile only: in kReleaseMode it builds the child alone and
  the code is tree-shaken.
- One persistent frame hook serves all inspectors; a layer walk per
  frame, the element walk only when the filter set changes.
- `MorphGlassInspector.census()` returns the same data for tests.
- The gallery's Glass renderer page toggles it.

## The renderer and its tiers

- The package carries one renderer: lib/src/glass/renderer, vendored
  from whynotmake-it (Apache-2.0); VENDORED lists the local patches.
- Public entry: `MorphGlassRenderer` with `MorphGlassTier`:
  - flat;
  - fake - the liquid layers through the renderer's consolidated fake
    layer: no refraction, no Flutter GPU. The fallback before the liquid
    capability resolves, and the web's tier;
  - liquid.
- `GlassAdaptiveScope` picks the tier once per session, never at runtime.
  There is no tier switching from frame timings. An explicit tier wins;
  otherwise `GlassAdaptiveScope.tierFor(deviceClass, best)`: liquid on
  Vulkan / Metal, the single `GlassAdaptiveScope.cheapTier` (flat) on the
  GLES fallback, on Apple GPUs before the A13 and on Skia (a native
  runtime without Impeller, known at once from
  `ImageFilter.isShaderFilterSupported`). The device class is probed from
  Flutter GPU (glass_device_native.dart) once the liquid capability
  resolves. Fake glass costs about what liquid costs on the GLES Pixel 6a,
  and on Skia it is a multi-pass blur at 30 - 125 ms raster p95 a page
  (Redmi 6A), which is why the cheap tier is flat. Only the web keeps fake
  glass as its tier.

## Outline is truth

- The package computes every shape once and fuses it (skin merge law,
  the menu's blurred SDF) into a `MorphGlassOutline`. The renderer only
  shades the outline it is given and never fuses on its own.
- A plain union (spacing 0: the menu's tail under 1 pt, submenu cards)
  carries its boxes instead of a field: path union for the edge, each box
  shaded as its own circular rounded rectangle. Exact, with no per-frame
  trace or upload.

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
- The variant for mixed appearances (shapes of one layer that differ by
  more than tint) compiles the glow out: there it spills to stack on the
  Mali-G78 wherever it is placed (4 - 24 bytes). The lit controls never
  mix appearances in a layer; an app layer that mixes clear and regular
  `MorphGlassEffect` shapes shows no glow.
- The glow is not structure: it enters `LiquidGlassLayer.live` through
  `glowOf` every frame and rebuilds nothing. A glowing host joins no glass
  container (`morphGlassJoinLook`): the container's pass carries no glow.
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
  flat or fake menu awake. The tab bar and glass buttons still run theirs.
- Fidelity NEAR against the old 16-stop gradient: under 0.65 of an 8-bit
  level inside three sigma for the tab bar and the menu, and the old cut
  at a six-sigma square (a step of `gain e^-4.5`: 0.9 level on the tab bar,
  1.6 on the menu, up to 3.2 on a small dark button) is gone. A glass that
  fades out while lit fades its glow with it.
- Cost (tool/audit/shader/offline.py, malioc Mali-G78): every final
  variant keeps 64 work registers on Vulkan, 50 % occupancy and main's
  spill (analytic 4, analytic_ios27 4, analytic_fused_tint_ios27 16 bytes,
  the rest 0); the lit path costs about +1 arithmetic and +3 load/store
  cycles a fragment, total arithmetic +0.75 - 1.1. `mediump` buys nothing
  here: impellerc writes no RelaxedPrecision into the Vulkan stage.

## Shadows

Glass shadows clip to outside the glass (an even-odd path), never a
saveLayer + dstOut per surface: no offscreen pass, no shadow under the
translucent body (GlassShadow, MorphGlassBodyShadow).

## Packaging and web

- The build hook writes `build/shaderbundles/`; its pubspec asset entry
  must stay. Flutter 3.47.2 does not request data assets from hooks, so a
  data-asset-only bundle silently loses liquid glass on the device.
  Verify packaging on a native device.
- The web build compiles: the liquid tier sits behind a conditional
  import, and its final-render shaders compile to stubs under Skia.
