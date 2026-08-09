# morph - identity-based widget-to-overlay morphs

Spring-driven, interruptible morph animations from an inline widget to an
overlay (dialog, sheet), plus a "liquid" skin that fuses nearby surfaces
into one organic shape. No Navigator coupling. Physics comes from the
`motor` package.

Not on pub.dev by design (`publish_to: none`); releases are git tags
following semver, and the API follows the owner's app. Owner-local
context (roadmap, priorities) lives in `CLAUDE.local.md`, untracked.

## Layers

Flutter-style split, two entrypoints:
- `lib/foundation.dart` - the ENGINE export (former morph.dart;
  `lib/morph.dart` remains as a one-line alias so the conventional
  import keeps working).
- `lib/widgets.dart` - the opinionated widget layer
  (`lib/src/widgets/`): showMorphMenu/MorphMenuItem (the worked-through
  chapter-04 pattern as one call: a control becomes its own menu,
  popover anchored to the control's current box, rows cascading via
  MorphReveal, onSelected fires before the close), SpringButton, Tug
  (the glass tether; paint mode transforms above the child, channel
  mode writes a MorphPieceChannel directly and paints only the content
  correction inside), MorphSurface/MorphTapTarget (the Material
  adapter and its surface-less sibling), ChaseSpring
  (the moving-target integrator: per-event controller retargets
  starve - a high-frequency mouse restarts the sim before it ticks;
  the chase inverts the flow, events move the target and the owner
  integrates per frame; critically damped, rest guard included).
  BOUNDARY: widgets import foundation and motor, the engine NEVER
  imports widgets. Taste knobs in widgets are API but expected to move
  with the owner's app (semver majors are cheap pre-1.0). No glass
  shader lives here and none is planned - the layer is about USING
  morph well, not reproducing a platform's shading. The bar for
  promotion: worked through and pointed at a real use (SpringToggle,
  SpringSwitcher and GooSelector stayed in example as lab chrome -
  shell furniture, not worked through). The example keeps its chrome
  in example/lib/ui/ and consumes the layer like any app.

## Architecture (lib/src/)

- `motion.dart` - `MorphMotion`: a pair of `Motion`s from **motor**
  (openMotion/closeMotion) plus `closeVelocityHint`. Presets
  glacial/slow/normal/fast/instant built on `CupertinoMotion`. Custom
  profiles via the public constructor from ANY Motion (Material tokens,
  curves, custom springs).
- `controller.dart` - `MorphController`: one scalar ticker,
  `motion.createSimulation` as the single physics seam; handoff latch on
  the first zero crossing; scrub API (`beginScrub`/`updateScrub`) for
  custom gesture driving; `animation` adapts it to `Animation<double>`.
- `frame.dart` - `computeMorphFrame`: ALL visual properties of a flight
  frame derived from one spring value. Corner radius is derived from live
  geometry (concentric-corners model), not lerped as a shape. Also the
  shared landing-bump math: `morphLandingBump` (scaleX/scaleY/kick, used
  by the MorphTag transform) and `morphBumpedRect` (same applied to a
  rect, used by the liquid skin).
- `scope.dart` - `MorphScope` (tag/flight registry + TickerProvider) and
  `MorphTag` (identity: rect/shape/surfaceColor/elevation/replica;
  landing bump is a full-wave squash+recoil along the impact axis).
- `flight.dart` - `MorphFlight` + the shuttle (OverlayEntry): retarget
  instead of new flights, live per-frame tracking of source and target,
  snapshot ghost (opt-in `snapshotGhost`; the capture waits for the
  frame's paint and the tag hides only AFTER the shot - a launch from
  the button's own tap happens mid-ripple with a dirty boundary, where
  toImage asserts, and a hidden tag never repaints so the dirt would be
  permanent; the shuttle's replica covers the extra visible frames),
  `MorphFlightScope` for
  content. Semantic getters `isAirborne`/`isLanding`/`impactAxis`.
- `show.dart` / `anchor.dart` - imperative `showMorph*` (escape hatch)
  and declarative `MorphAnchor(isOpen, onDismiss)` - the morph as a
  function of state; identity is the State itself unless an explicit
  `tagId` is given.
- `route.dart` - `showMorphRoute`/`MorphPageRoute`: the destination as
  a REAL Navigator route with the flight as its transition. The route
  is pushed immediately (back button, predictive machinery and further
  pushes behave like on any page; the flight overlay is passed
  `navigator.overlay` explicitly - the navigator's context sits ABOVE
  its overlay); the page stays empty while the shuttle plays. At settle
  the SECOND latch fires: `MorphFlight.routeOwnsContent` flips, both
  sides rebuild in the same frame, and the content subtree - carrying
  the shared `routeContentKey` GlobalKey - REPARENTS into the route
  page with its live state (the one sanctioned GlobalKey move; the
  wrapper chain under the key must stay IDENTICAL on both sides:
  KeyedSubtree > MorphFlightScope > MorphSurfaceSpecScope >
  SharedSideScope > Builder). A pop hands the content back the same way
  and plays the ordinary close; a close launched from the flight side
  (flight.close in content) retires the route automatically via the
  route's controller listener. Scrim swaps between owners at full
  opacity on both latches (the route's modal barrier stays transparent
  and only contributes dismiss taps and semantics); pre-latch scrim
  taps route through the Navigator (onDismissRequested -> pop) so the
  route lifecycle stays the single source of truth. PREDICTIVE BACK:
  the route reimplements the PredictiveBackRoute hooks on the flight
  (the default TransitionRoute impl drives the route's zero-duration
  shell controller) - the gesture hands the content back to the shuttle
  and scrubs the value shallowly (depth 0.18: the card visibly shrinks
  toward home, the crossfade midstates stay unreadable); cancel springs
  back and the second latch re-hands the content, commit pops and the
  close plays from the scrubbed value. A private binding observer
  bridges the system events to the route hooks, because the material
  page-transitions detector never wraps a PopupRoute.
- `reveal.dart` - `MorphReveal`: staggered unfolding of content blocks on
  sub-ranges of the same spring. Render transforms ONLY - overflow is
  impossible by construction. The subtree structure is STABLE for every
  value: an early "return child" above t=1 used to change the tree
  shape at the boundary, rebuilding the child - stateful content lost
  its state and a MorphTag inside tripped the duplicate-id assert
  (pinned by morph_reveal_test).
- `gesture.dart` - primitives for building your own drag-to-dismiss
  (rubber band c=0.55, velocity projection, `morphCloseHintScale`,
  `morphDragRecede`, commit thresholds). A prebuilt drag widget is
  intentionally NOT provided - but the MECHANICS live on the flight as
  the DISPLACEMENT CHANNEL: `MorphFlight.beginDrag`/`dragBy`/`endDrag`.
  While the finger is down the WHOLE container (surface, shadow,
  content, shared elements) follows it 1:1 as one rigid body - the
  morph value does not move, so no fade-through midstates can show; the
  scrim thins and the card recedes slightly, both pure functions of the
  displacement (`morphDragRecede`). Releasing always springs the offset
  home on its own always-to-zero simulations (per-axis closeMotion with
  carried velocity); past the commit heuristic (projected distance >
  `morphDragCommitDistance` or speed > `morphDragCommitVelocity`,
  overridable via `endDrag(commit:)`) the ordinary close flight plays
  SIMULTANEOUSLY - the superposition reads as "the card flies home out
  of the hand" (the Apple model: gesture phase = direct manipulation of
  a rigid card, morph phase starts visibly at release). The offset is a
  genuine second degree of freedom (it cannot be a function of the
  spring value: at value 1 it must equal both the release offset and
  zero at settle); the shuttle applies `appliedDragOffset` = (raw
  offset + arm lean) x progress, so it vanishes exactly at the handoff
  latch, and the liquid mirror blob rides the same offset. COMMIT
  FEEDBACK: past the commit distance the card "arms" (`morphDragArm`, a
  smoothstep over 60 px after the threshold - pure and reversible):
  extra scale recede, extra scrim thinning, and a 12 px drift toward
  the source so the destination of a release is legible before the
  release; `MorphFlight.isDragArmed` exposes the same threshold for
  app-side haptics. The drag is opt-in by construction: the core never
  attaches a gesture - no detector wired, no swipe exists. The app
  supplies only the gesture policy (which gesture, on what). Value-scrubbing the morph
  itself remains the controller-level expert path (beginScrub/
  updateScrub) - it exposes midstates when frozen under a finger, so it
  suits only short fast scrubs such as future predictive back.
- `liquid_field.dart` / `skin.dart` - liquid fusion: CPU SDF (rounded
  box / capsule) + smooth-min + marching squares + Chaikin smoothing
  producing a single vector `Path` skin behind live content
  (`MorphSkin`/`MorphPiece`/`MorphLink`). One knob `blend` (the smin k) spans crisp
  concave joints (low) to gooey necks (high); `blend` and `cell` are
  DISTANCES in px and scale with the scene. Blend depth at the middle of
  a gap is ~k/4. Field bounds are padded by k (otherwise the neck would
  clip); contour recomputation is cached by an input signature. No
  shaders, no blur+threshold - no halos; "one mass - one shadow" holds
  by construction.
- **Tracing hot path is optimized and guarded**: sampling runs through
  an allocation-free flat evaluator (`_FieldSampler`: typed arrays, no
  Offset objects or virtual dispatch per vertex), and shapes are split
  into connectivity clusters (bounds gap <= k, transitive), each traced
  on its own tight grid - EXACT, not approximate: beyond a gap of k the
  mix-form smin equals plain min identically (proof sketch at
  `_clusterShapes`). The per-cluster grid cap logs loudly in debug
  instead of failing silently. Correctness is pinned by
  `test/liquid_regression_test.dart` (field-sign/contour consistency
  probes plus near-range bulge and far-range no-deformation checks) -
  any pipeline change must keep that net green. Microbenchmarks:
  `flutter test benchmark/liquid_benchmark_test.dart` (benchmark_harness;
  JIT numbers, use for relative before/after only).
- **Render-object implementation**: `MorphSkin` is a thin stateless
  facade over `RenderMorphSkin` (public API unchanged). Spring ticks
  call markNeedsPaint ONLY - no widget rebuild and no relayout in an
  animation frame - and app-driven geometry has the same citizenship
  through the piece geometry channel (next bullet); the group is its
  own repaint boundary, so an animating skin never repaints ancestors.
  The landing squash deforms
  content via a child-local paint transform (mirroring the skin's mass)
  with transform-aware hit testing; layout runs solely when piece
  geometry changes from the outside. Flight subscriptions live in
  attach/detach. Skin fill supports an optional Gradient
  (MorphSkin.gradient) shaded across the group bounds. Safety nets
  around the descent: geometry snapshots
  (test/liquid_geometry_golden_test.dart, regenerate via
  test/golden_dump_helper.dart) and seeded fuzz
  (test/liquid_fuzz_test.dart); the frame benchmark
  (benchmark/group_frame_benchmark_test.dart) measures the full
  build+layout+paint cost per pumped frame during a glacial flight,
  plus the orbit scene both ways (rebuild-driven vs channel-driven).
- **Piece geometry channel**: `MorphPieceChannel` (skin.dart, on
  `MorphPiece.channel`) - "frameTicks for pieces". The payload is
  (offset, scaleX, scaleY) over the base rect, applied about its
  center; no rotation by construction (SDF boxes are axis-aligned).
  Scale ZERO is legal and deflates the mass to nothing - births and
  deaths are mass, not opacity (the selection-blob pattern); a
  degenerate content transform paints nothing and hit testing skips
  it (non-invertible matrix).
  A write is markNeedsPaint ONLY: no rebuild, no relayout, no
  _syncFlightSubscriptions, no allocation (channel identity is part of
  piece geometry equality, so a swap resyncs; subscriptions live in
  attach/detach with one shared handler). EFFECTIVE rects (base +
  channel) feed the whole pipeline: resolve, trace signature (a stale
  contour is impossible), launch fellowship (captured at flight
  subscription from that moment's effective rects - a launch out of a
  body fused by a live drag keeps its neck), bridge endpoints, blob
  fallback. Content rides as ONE RIGID BODY on the same child-local
  paint transform as the landing squash (the two compose; scales
  multiply, kick adds); layout stays at the base rect - content
  paint-scales, text does not rewrap: the channel's contract, fine at
  tether scales. applyPaintTransform mirrors the paint transform, so
  localToGlobal / MorphTag measurement / popover anchoring see the
  displaced rect - without that override a flight would launch from
  the base position while the pill visibly stands elsewhere. Transient
  motion commits into the base rect at rest (the sandbox pattern:
  dragBy writes the channel, endDrag commits and resets - one rebuild
  per gesture). Consumers: Tug's channel mode (writes the full pull
  and paints only the desired/applied content correction inside),
  the sandbox drag, the stress orbits, the dock/selector selection
  blobs and the toolbar merge. The companion pattern for CONTENT whose
  values derive from the same spring (label emphasis, icon
  opacity/glyph): the content listens to the spring itself inside a
  stable piece child - tiny text/icon rebuilds, the skin and the piece
  list untouched. Pinned by the channel group in
  morph_skin_test (re-trace isolation via LiquidTracer.lastMissCount,
  no-rebuild/no-relayout counters, displaced launch rect, fellowship
  from displaced geometry, resubscription).
- **Per-cluster cache**: `LiquidTracer` (one per MorphSkin State) -
  only clusters whose geometry changed re-trace; the rest reuse their
  loops. Keys are full per-cluster signatures compared element-wise on
  hash collision; the cache swaps wholesale per trace, so it never
  outgrows the scene. This keeps a mostly-static group cheap while one
  piece animates (a flight blob re-traces its own cluster, not the
  scene). Instrumented via lastMissCount/lastClusterCount.
- **Bounded worst frame**: `evalBudget` (default
  `liquidDefaultEvalBudget` = 200k field evaluations per cluster) -
  when a scene exceeds it (a screen-wide blob of dozens of fused
  pieces), the grid coarsens by exactly the overshoot factor: quality
  degrades before the frame rate does. Deterministic function of
  geometry (no time, no hysteresis); null disables. Exposed on
  MorphSkin and the tracing functions.
- **Fill rule is evenOdd**: interior holes (a ring of linked pieces)
  must stay hollow; the stitcher walks loops in arbitrary directions,
  so the default nonZero rule filled holes by winding accident and
  popped on topology changes.
- **Flight neck is a core feature, and free**: the group finds flights
  in MorphScope by its piece ids (listens to `scope.lastFlight` for
  discovery and to each flight controller for ticks; unsubscribes on
  `closed`, which is guaranteed to run before the controller's deferred
  dispose). Airborne: the home mass turns off and a companion blob
  follows the shuttle (a mirror of the flight frame geometry: center by
  value, size by progress, radius via the concentric lerp with its cap;
  coordinates translated through the group's localToGlobal); explicit
  links of the flying piece detach. LAUNCH FELLOWSHIP: at subscription
  the skin captures the connectivity component of the flying piece
  over solid pieces AND their MorphLink bridges (labeled by
  `liquidConnectivityLabels` - the ONE body predicate the tracer's
  cluster split also delegates to), and the blob necks ONLY to those -
  a flight stays attached to what it was part of, not to whatever it
  passes (a dialog opened from an isolated pill must not goo onto its
  neighbor; a launch out of a fused body keeps its neck, including a
  body fused moments earlier by a drag). Fellowship entries outlive
  subscription blips and are erased only on flight close or skin
  detach. Landing: the mass is home and the rect squashes via
  `morphBumpedRect`. Perf gate: if `liquidRectGap` to every FELLOW
  piece exceeds k, the neck provably cannot exist and the blob is
  skipped. Instrumented via lastFlightBlobCount (pinned by
  morph_skin_test's fellowship pair). STRAY FLIGHTS: a flight can
  outlive its tag (the scope owns flights; a disposing tag only
  unregisters) - engine consumers go through
  `MorphScopeState.liveFlightOf` (null when the tag is not
  tree-active), which guards BOTH doors: the skin's `_flightFor` and
  the retarget lookup in `MorphFlight.launch`; the public `flightOf`
  stays honest for observers/HUDs. Otherwise a rebuilt screen touches
  the defunct tag's context/widget (the toolbar-lesson attach crash;
  pinned by the stray-flight test). Outside a MorphScope the group
  degrades to pure fusion (`MorphScope.maybeOf`).
- **Surface model and ambient defaults** (`MorphSurfaceSpec`,
  `MorphTheme` in theme.dart): the surface model (shape, color,
  elevation) is a first-class value declared ONCE at the tag
  (`MorphTag.spec`) and read back by any rendering stack via
  `MorphTag.specOf(context)` - drift between the visible surface and
  the flight's belief is structurally impossible; the core blesses no
  design system (Material adapters are app-side recipes). App-wide
  archetype vocabularies belong in the APP's own ThemeExtension holding
  spec values. Engine defaults live in the `MorphTheme` ThemeExtension
  (motion, bumpScale/bumpRecoil, maxScrimOpacity, skinStyle) with the
  resolution order explicit parameter > MorphTheme > builtin,
  everywhere (showMorph*, MorphTag bump, MorphSkin knobs). No new
  scopes: MorphScope stays an identity/flight registry only. The SAME
  surface model describes both ends of a flight: MorphTargetSpec
  accepts `surface: MorphSurfaceSpec` (winning over its individual
  fields, mirroring MorphTag.spec), and the shuttle publishes the
  target's resolved model so custom dialog/sheet content reads it via
  MorphTag.specOf - an app's archetype vocabulary serves buttons and
  destinations alike. Custom dialogs/sheets = a custom MorphTargetSpec
  (any rectFor placement + surface) with your content builder;
  showMorphDialog/Sheet are just presets over it.
- **Shared elements inside a flight** (`MorphSharedElement` in
  shared.dart): content marked with the same id on both sides TRAVELS
  between its endpoint rects instead of riding the fade-through. No
  route-hero machinery: both sides already live in the one shuttle, so
  the flying frame is a lerp of endpoint rects by the RAW spring value
  (interruption-continuous by construction), crossfaded on the same
  fade-through curves and clipped by the morphing container shape.
  Registry lives on the flight; sides register via SharedSideScope
  (internal). Degradations: an unpaired id renders in place;
  snapshotGhost has no live source markers so pairs do not form; marker
  children must not carry GlobalKeys. The shuttle republishes the
  SOURCE tag's surface spec around the replica, so specOf-rendered
  buttons replicate correctly.
- **Pop layering**: an OVERLAY flight opened above a ModalRoute
  registers a LocalHistoryEntry on it, so Esc (DismissIntent ->
  maybePop), the Android back and a plain Navigator.pop close the
  TOPMOST surface first - the flight - and only the next pop touches
  the route (without it, Esc under a morph route popped the route and
  left the flight orphaned above it). Route-mode flights skip the
  entry (their route IS the history); MorphPageRoute.didPop and the
  predictive-back hooks yield when willHandlePopInternally - a stacked
  entry owns the pop.
- **Overlay accessibility**: the scrim is a real modal barrier
  (Semantics label + onDismiss when dismissible); the container is a
  semantic route (scopesRoute, and namesRoute when `semanticLabel` is
  passed to showMorph* - screen readers announce the opening); a
  FocusScope + FocusTraversalGroup trap Tab traversal inside the open
  overlay; Esc and focus restore were already there.
- **Layer-1 API (typical cases without ceremony)**:
  `MorphPiece.morphable(...)` - an auto-MorphTag (piece id, shape from
  its radius, skin color/elevation, tag bump zeroed - the skin plays the
  landing); the consumer just calls `showMorph*(from: pieceId)` from ANY
  context. `MorphSkinStyle` - named knob presets (subtle/geometric/goo);
  explicit k/cell/smoothPasses override the style; k is a distance and
  presets are calibrated for button-scale UI. `showMorphDialog`/`Sheet`
  adopt shape and color from `DialogTheme`/`BottomSheetTheme` unless
  overridden. `MorphAnchor.tagId` gives the anchor's flight a public
  name - a MorphPiece with the same id gets the neck for free.

Example: the app is a TOUR - an introduction to the library where the
app itself is the first exhibit (`example/lib/tour/`). The home is a
grid of chapter cards; every card opens AS a morph route (container
transform via showMorphRoute, fullscreen target) - the navigation is
the thesis. Each chapter (Widget-of-the-Week format) = one mechanism +
a live demo + taste notes ("use it when / skip it when" - the design
philosophy as content). Chapters: identity, retargeting (comet +
torture), landing knobs, BUTTON-TO-MENU (iOS 26: the pill expands into
its own popover - a custom MorphTargetSpec closed over the button's
rect), TOOLBAR MERGE (iOS 26: scroll-driven liquid fusion of actions
into one pill on a single retargetable merge spring), player
(shared elements + displacement drag), liquid dock, liquid chips, the
real route, and the Playground. The honesty criterion that shaped
this: a morph must TRANSFORM IDENTITY (the thing you touch becomes the
surface you use); spring-skinning ordinary controls is animation, not
morph - segmented controls as goo were rejected for the chrome and
demoted to chapter content where the pattern is legitimate (tab bars).

The Playground chapter (`example/lib/playground/`) is the old Morph
Lab: the whole canvas is a sandbox builder:
- pieces (box/stadium/circle) are added, selected, dragged, resized from
  the sidebar; all fused by one liquid skin;
- every piece is a morph source: double-tap = a real flight (dialogs or
  a sheet by id % 4); torture and the autodemo fly from piece id 2;
- MorphLink bridges: select a piece -> link -> tap another (repeat to
  unlink); link chips in the sidebar;
- keyframes A/B: scene snapshots (geometry by id + blend); playback is a
  spring morph from the CURRENT state on the profile's openMotion;
  pieces missing from a snapshot stay put;
- sidebar sections: MOTION / LANDING / SANDBOX / KEYFRAMES / LIQUID /
  STRESS;
- THE SHELL ITSELF RUNS ON THE WIDGETS LAYER (lib/widgets.dart, plus
  the lab chrome in example/lib/ui/lab_chrome.dart): every
  segmented control is a GooSelector (liquid track + selection blob on
  a retargetable spring, slightly proud of the track; a null selection
  deflates the blob - mass, not opacity; label emphasis is a pure
  function of the blob position), every switch is a SpringToggle (knob
  on a spring, deformed by its own velocity), every action button is a
  SpringButton (press scale on a spring, bounce release), and every
  panel/canvas swap is a SpringSwitcher - a MorphController-driven
  crossfade-and-rise with TWO STABLE KEYED SLOTS: the outgoing element
  keeps its tree position (state, tickers, MorphTags stay alive) until
  settle, an interruption back returns to the still-living subtree, and
  a mid-flight swap flips value := 1 - value via the scrub API so the
  outgoing layer keeps its exact opacity. Sliders deliberately stay
  plain: a slider is direct manipulation, the finger owns it 1:1 -
  springs do not belong there;
- the chapter demos live in example/lib/tour/lessons/ (Player: shared
  elements + the displacement drag channel; Goo dock; Comet; Chips:
  layout-as-targets with mass births/deaths and the stiffness wave -
  sims evaluated at t*rate, rate falling by slot distance; NOTE the
  ticker-clock trap: Ticker.elapsed restarts from zero on every
  start(), so idle-restart flows must reset their own clock or springs
  evaluate at negative time and thrash) and example/lib/tour/lessons/
  (identity/retarget/landing + the two iOS 26 chapters);
- stress mode (example/lib/playground/stress_lab.dart): N pieces on
  deterministic golden-angle orbits re-trace the skin every frame, with
  an on-screen FPS meter (average + worst frame per window). Measures
  the FULL frame cost, complementing the isolated microbenchmarks;
  judge numbers in --profile/--release, debug is pessimistic.

Flight-to-skin coupling lives entirely in the core: the demo uses
`MorphPiece.morphable` and just calls `showMorph*(from: pieceId)`.
Hard-won rules already enforced in the core:
- Stack children in MorphSkin MUST be keyed by piece id - otherwise
  removing a piece from the middle of the list confuses the identity of
  stateful content (MorphTag used to hit 'duplicate id' asserts);
- content with a MorphTag stays HOME for the whole flight (it must not
  move: the flight tracks the source through the tag); only the mass
  blob travels;
- with a MANUAL MorphTag inside a piece (non-morphable) BOTH bumpScale
  and bumpRecoil must be 0 - the skin plays the landing (squash AND
  kick), otherwise each applies twice. MorphPiece.morphable zeroes both.
  Enforced in debug: the skin asserts MorphTagState.resolvedBump == 0
  when it subscribes to a flight (morph_contract_asserts_test).

## API conventions (decided at the pre-release shake)

- ONE vocabulary: every public type is `Morph*`. The liquid subsystem is
  spoken of as "the skin": `MorphSkin`/`MorphPiece`/`MorphLink`/
  `MorphSkinStyle`, knob `blend:` (the widget name for the smin k;
  the internal math layer keeps `k` - SDF literature language).
  "Liquid" survives as the technique name in liquid_field.dart, which
  is no longer exported.
- The motion profile parameter is `motion:` everywhere (never "speed" -
  a profile carries character, not just tempo). MorphController.motion /
  effectiveMotion follow suit.
- Export diet: morph.dart is the whole public surface; liquid_field
  internals, RenderMorphSkin and the shared-element machinery are not
  exported (package-internal tests import src/ directly). The minimal
  motor vocabulary (Motion, CupertinoMotion, MaterialSpringMotion,
  CurvedMotion) is re-exported so custom MorphMotion profiles need no
  direct motor dependency.
- Engine seams that must stay public for cross-file use are annotated
  `@internal` (scope registries, tag machinery, controller.notifyFrame,
  flight route/shared plumbing): the analyzer warns consumers off.
- RETARGET CONTRACT: a repeated showMorph on a live tag retargets the
  existing flight - it keeps its target, builder, barrier and scrim
  (content lives in the shuttle and cannot be swapped mid-air); only
  motion, dismissal routing and semanticLabel are updated.
- MorphTargetSpec factories cover the honest shapes: dialog, sheet,
  fullscreen (container transform to a page), popover (anchored to the
  summoning control, flips above when out of room).
- `from:` is OPTIONAL in showMorph*/showMorphRoute: inside the source
  tag's own subtree the nearest enclosing MorphTag is the source
  (MorphTag.idOf; the marker is installed by the tag itself and
  deliberately NOT republished by the shuttle - dialog content names
  its source explicitly). Calls from elsewhere (morphable pieces, list
  controllers) keep the explicit id.
- Surface RENDERING is an opinion, not engine contract: MorphSurface
  (lib/src/widgets/morph_surface.dart, widgets layer) is the Material
  adapter (Material+InkWell from specOf, Semantics(button:), onTap
  receives an under-the-tag context so from: is inferred);
  MorphTapTarget is its surface-less sibling for skin pieces ("one
  mass - one shadow": a second Material would split from the mass).
  Both live in widgets.dart - fork them if the design system differs.
  The ENGINE's contract still ends at MorphTag.specOf, and the core
  never depends on the widget layer.
- MorphPageRoute.barrierLabel is the localized dismiss label (passed by
  showMorphRoute), NOT the route name - that is semanticLabel.

## Structural conventions (the pre-release structural pass)

- ONE frame stream: `MorphFlight.frameTicks` merges the value spring
  and the displacement channel; the shuttle and the skin subscribe
  THERE. A new co-driver of the frame joins the merge - never a
  notifyListeners backdoor on the controller.
- ONE geometry: `morphFlightGeometry` + `morphConcentricRadius` in
  frame.dart are the only implementations of the frame's rect/radius
  math; computeMorphFrame and the skin's mirror blob both call them,
  so the blob cannot drift from the visible container.
- ONE content chain: `buildMorphTargetContent` (flight.dart) is the
  only place the target wrapper chain exists; the shuttle and the
  route page both mount it - the route-mode reparent preserves state
  only while the chains match, and now they cannot diverge.
- The displacement channel is `_DragChannel`, a ChangeNotifier owned by
  the flight (data lives where its nature says, not accreted onto the
  flight); the flight's public drag API delegates.
- Example spring recipes ride motor's `SingleMotionController`
  (retarget with velocity carry-over built in) instead of hand-rolled
  ticker+sim copies; hand-rolling remains ONLY where a controller
  cannot go - the chips wave evaluates sims at t*rate (per-chip
  stiffness), and a controller owns its own clock.

## Invariants (never break these)

1. **Every visual property is a pure SYMMETRIC function of a single
   spring value.** No direction-dependent curves, no wall-clock time.
   This yields interruption continuity by construction. Any feature that
   breaks this is rejected. Precisely: ONE SPRING PER DEGREE OF FREEDOM.
   The gesture displacement is a second, ORTHOGONAL DOF with its own
   always-to-zero spring; each DOF stays pure and continuous, and their
   superposition preserves the guarantee. What stays forbidden is two
   clocks driving the SAME property (the buried "position leads, size
   follows").
2. Retarget = a new simulation starting from the current (value,
   velocity). One active flight per tag; re-showing retargets it.
3. Handoff latch: the shuttle-to-widget swap happens exactly on the
   first zero crossing; the residual oscillation plays out on the live
   button (full-wave!).
4. Target content lives in the shuttle for the whole flight (no
   reparenting; a GlobalKey inside the tag child is forbidden - assert).
5. Shadow and elevation belong to the shuttle and lerp source->target
   (a button with its own shadow must declare `MorphTag.elevation`).
6. closeMotion must be able to go below zero (a spring), otherwise the
   landing bump cannot play (graceful degradation); `snapToEnd` must
   stay false - the handoff latch lives on the zero crossing. Enforced
   in debug: MorphMotion.debugContractViolation, asserted whenever a
   profile is installed into a controller.

## Motion design principles

- Springs are the default; curves are an option only. open is FASTER
  than close (normal: 400/550ms) and strictly overshoot-free
  (critically damped); character/bounce lives on close only.
- Landing must read: weight scales with distance
  (`morphCloseHintScale`) plus a full-wave button oscillation (squash
  along the impact axis + recoil).
- Content "unpacks" in a top-down cascade rather than just appearing.
- "One mass - one shadow": nothing may visually split a morph into
  layers.

## Rejected approaches (deliberate - do not reintroduce)

- **Shader/blur-based liquid neck** (SDF shader, blur+threshold
  metaballs): halos and mush on small-into-large morphs. The CPU vector
  path (marching squares) replaced it and is the only supported way.
- **Prebuilt drag widget**: gesture policy for DISMISSING A FLIGHT
  belongs to the app. The primitives in gesture.dart plus the scrub
  API remain. (The widgets layer's Tug is not this: a tactile tether
  recipe, not a dismiss policy.)
- **Snapshot ghost by default**: a frozen ripple looks worse than a live
  widget replica. Kept as opt-in for heavy content.
- **"Position leads, size follows"** and back-out on position: not
  supported by platform references and caused a wind-up on close.
  Geometry is linear in the value; character comes from physics.
- **MotionController from motor**: its settle semantics conflict with
  the handoff latch. Only Motion-as-simulation-factory is used.
- **anchorScale** in the frame: dead remnant of a two-blob model,
  removed.
- Built-in gesture driving, text/layout morphing, glass effects - out
  of scope.

Deliberately kept although the engine does not use it:
`MorphFrame.cornerRadius` (public info for consumer accessories, covered
by a test).

## Documentation conventions

- One strict analysis_options at the package root (strict-casts/
  inference/raw-types plus a hand-picked lint set:
  always_use_package_imports, prefer_final_locals, no_default_cases,
  avoid_catches_without_on_clauses and friends); the example includes it
  via `include: ../analysis_options.yaml`. `flutter analyze` must stay
  at zero. Tried and DROPPED (style-only, tax exceeded value):
  cascade_invocations (an expression-bodied lambda swallows the next
  `..` section - `..onHandoff = () => x++ ..open()` parses the open()
  onto x++; and the rule fights tests that interleave actions with
  asserts), join_return_with_assignment,
  prefer_if_elements_to_conditional_expressions. Existing cascades
  stay where the receiver is configured at construction; actions that
  a test asserts on live as plain statements, not in a declaration's
  cascade.
- `public_member_api_docs` is ON in BOTH analysis_options (package and
  example): every public member carries a dartdoc, including the
  unexported src/ machinery and the example's teaching code - the lint
  is the coverage gate.
- Dot shorthands (`.center`, `motion: .normal`, `rect: .fromLTWH(...)`)
  and pattern matching (switch expressions, relational and object
  patterns, if-case) are the house style where the context type is
  known; there is no built-in lint for shorthands. For a full sweep,
  temporarily add the `prefer_shorthands` analyzer plugin to
  analysis_options (as of 0.4.7 it needs its analyzer/analyzer_plugin
  constraints widened and a small port to the analyzer 14 AST names),
  apply its findings, then remove it. It has one known false positive:
  `Object.hashAll` in an int context.
- Example layout: `tour/` (home, lesson framework, lessons/ - all
  chapter demos and dialog_contents.dart), `playground/` (the sandbox,
  stress rig, HUD and the chapter shell), `ui/` (lab chrome: LabActionButton, SpringToggle/Tile, SpringSwitcher, GooSelector; the promoted recipes live in lib/widgets.dart),
  `perf/` (the release bench), flags.dart, main.dart. The historical
  gallery/ and demo/ directories are gone.
- Dartdoc speaks to the CONSUMER in the present tense: behavior,
  contract, the constraint the code cannot show. Design history, bug
  archaeology and test pointers live HERE (CLAUDE.md) and in commit
  messages, never in doc comments.
- Effective Dart style: single-sentence summary first, noun phrases
  for properties, square brackets only for resolvable identifiers
  (ranges like `[0, 1]` are backticked), no caps-shouting for
  emphasis.
- `dart doc --dry-run` must report zero warnings (broken references).

## Verification workflow

```bash
dart format lib test example/lib example/test && flutter analyze
flutter test && (cd example && flutter test)
cd example && flutter build macos --release
cd example && flutter run -d macos --dart-define=MORPH_AUTODEMO=true
```

Every step must be green after each change (analyze from the package
root also covers example). Animations are judged by eye only by a human
(the glacial profile is the magnifier mode); agent self-verification is
the tests (162 in the package + 29 in example) plus the autodemo with no
EXCEPTION in the log (autodemo: opens the Playground chapter AS a
morph route - exercising the card flight and the second latch - then a
dialog flight from a piece -> interruption torture -> 4 keyframe
morphs A/B). For changes touching
the tracing pipeline additionally run the microbenchmarks
(`flutter test benchmark/liquid_benchmark_test.dart`) and compare
against the previous numbers on the same machine (JIT - relative
only).

## Performance passport (AOT)

The absolute numbers come from the RELEASE bench - the same scenes as
the microbenchmarks (shared via src/benchmark_scenes.dart, so the two
harnesses cannot drift) measured inside an AOT build, plus real engine
FrameTimings during a glacial flight:

```bash
cd example && flutter build macos --release --dart-define=MORPH_BENCH=true
./build/macos/Build/Products/Release/morph_example.app/Contents/MacOS/morph_example | grep BENCH
```

Baseline 2026-07-30, Apple Silicon macBook (tembeon), macOS release:

| scene                   | us/op  |
|-------------------------|--------|
| fusedPair               |     86 |
| sandboxSpread           |    231 |
| flightFar               |    177 |
| manyPieces              |    437 |
| megaCluster64 (budget)  |  1 997 |
| megaCluster64/unbounded |  8 551 |
| oneMoving/pure          |    158 |
| oneMoving/cached        |     57 |

Frame timings (glacial open+close, n=1087): build avg 0.22 / p95 0.35
/ worst 0.60 ms; raster avg 0.79 / p95 1.33 / worst 6.8 ms (the worst
raster frame is first-use shader work). Reading: the cached animated
frame costs 57 us - under 1% of a 120 Hz budget; the 64-piece
worst-case cluster re-traces in 2.0 ms with the eval budget (fits
120 Hz) vs 8.6 ms unbounded (would blow it) - the budget is what keeps
the worst frame inside the envelope. AOT runs ~9x faster than the JIT
test VM across every scene.
