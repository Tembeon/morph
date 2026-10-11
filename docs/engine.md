# Engine (lib/src/)

What is where:
- Physics and value: `spring.dart`, `motion.dart`, `controller.dart`, `frame.dart`.
- Identity and flights: `scope.dart`, `flight.dart`, `scrim.dart`, `shared.dart`, `measure.dart`.
- Entry points and destinations: `show.dart`, `anchor.dart`, `presentation.dart`, `target.dart`, `route.dart`.
- Gestures: `gesture.dart` (primitives) plus the displacement channel on `MorphFlight`.
- Liquid skin: `liquid_field.dart`, `skin.dart`; ambient defaults in `theme.dart`.

## Springs and motion

### spring.dart
`MorphSpring(response, dampingRatio)` - UIKit vocabulary (engine-flight.md).
`widgets.dart` re-exports it.

### motion.dart - MorphMotion
- A pair of `Motion`s from motor (`openMotion` / `closeMotion` getters).
  `MorphMotion.springs(open:, close:)` builds one from MorphSprings and
  exposes `openSpring` / `closeSpring`; the public constructor takes any
  Motions (Material tokens, curves, custom springs).
- Built-in profiles:
  - `liquid` - the default everywhere a motion resolves (controller,
    showMorph*, MorphTheme unset): UIKit's liquid morph progress spring.
    Open 0.35/0.75 overshoots ~3 percent (p peaks 1.028); close
    0.49/0.80 undershoots ~1.5 percent - that zero crossing is the
    handoff latch.
  - `glacial` - liquid with every response x5; a magnifier for the eye,
    not a design choice.
  - `instant` - 281 ms critically damped both ways (reduced motion and
    tests); not a cut.
- Value equality: MorphTheme equality and the controller's setter compare
  by `==`.

### controller.dart - MorphController
- One scalar ticker; `motion.createSimulation` is the single physics seam.
- Handoff latch on the first zero crossing of the close.
- Scrub API (`beginScrub` / `updateScrub`) for custom gesture driving;
  `animation` adapts it to `Animation<double>`.
- A close from rest starts still (no velocity hint).

### frame.dart
- `computeMorphFrame` derives all visual properties of a flight frame
  from one spring value.
- Corner radius comes from live geometry (concentric-corners model), not
  lerped as a shape.
- `morphFlightGeometry` + `morphConcentricRadius` are the one geometry;
  the frame and the skin's mirror blob both call them.
- Elevation lerps on p^1.5 (`p * sqrt(p)`), not p: a linear shadow makes
  a nearly-home container float on a borrowed dialog shadow (visible at
  glacial). Pinned by morph_frame_test's continuity check.

## Identity: scope.dart

- `MorphScope` - tag/flight registry + TickerProvider. It stays an
  identity/flight registry only; no new scopes.
- `MorphTag` - identity: rect / shape / surfaceColor / elevation /
  replica / spec. No landing transform on the tag: the landing is the
  close spring's own undershoot (UIKit adds nothing on top).
- Required lookups throw descriptive FlutterErrors in release as well as
  debug. `MorphScopeState.tryTagOf` is the optional lookup for callers
  that can degrade when a source is missing; duplicate ids are reported.
- Stray flights: a flight can outlive its tag (the scope owns flights; a
  disposing tag only unregisters). Engine consumers go through
  `MorphScopeState.liveFlightOf` (null when the tag is not tree-active),
  which guards both doors: the skin's `_flightFor` and the retarget
  lookup in `MorphFlight.launch`. The public `flightOf` stays honest for
  observers/HUDs.

## Flights: flight.dart

### The shuttle
- `MorphFlight` + the shuttle (an OverlayEntry). A repeated launch
  retargets instead of starting a new flight; source and target are
  tracked live per frame. `MorphFlightScope` wraps the content.
- Replica: rides the container geometry (uniform scale by the width
  ratio; exactly 1 at the home end, so the latch swap stays
  pixel-identical) and renders from the source spec with elevation
  zeroed. A natural-size copy inside a grown container, or one casting
  its own shadow, reads as a second surface - "one mass, one shadow"
  holds inside the shuttle too. Pinned by morph_shuttle_render_test.
- Snapshot ghost (opt-in `snapshotGhost`): the capture waits for the
  frame's paint and the tag hides only after the shot. A launch from the
  button's own tap happens mid-ripple with a dirty boundary, where
  toImage asserts, and a hidden tag never repaints so the dirt would be
  permanent; the shuttle's replica covers the extra visible frames.
- Semantic getters `isAirborne` / `isLanding` (landing = the span
  between the latch and the final rest).
- Vessel flights (see target.dart) skip surface, shadow, ghost and
  crossfade and mount the content over the whole overlay.
- `buildMorphTargetContent` is the only place the target wrapper chain
  exists; the shuttle and the route page both mount it.

### Events
- `MorphFlight.events` streams `MorphFlightEvent` (launched, settled,
  closing, latched, landed, aborted) - the haptics seam.
- Moments are recorded synchronously into a queue and handed to the
  broadcast stream in a microtask. A broadcast stream drops what nobody
  hears yet, and showMorph announces the launch before it returns, so
  the deferral lets a listener attached in the same synchronous run
  (before any await) hear it. The queue keeps the order, and a handler
  may close the flight from inside itself without re-entering a firing
  controller.
- `launched` is queued before `controller.open()`, so an instant
  profile's synchronous settle can never precede it; a re-open of an
  already open flight is not a launch.
- The stream closes after landed/aborted. Pinned by
  morph_flight_events_test.

### Source lost
- `refreshSourceRect` checks `!tag.mounted` (mounted, not isTreeActive:
  a deactivate/activate reparent is transient and must not flip it), so
  the loss is seen one frame after the dropping build. The rect freezes
  where it last stood; open content stays usable.
- A close dissolves instead of landing on whatever took the row's place:
  the container fades over the first half of its remaining travel,
  opacity = clamp((progress / dissolveStart - 0.5) * 2), a pure function
  of the spring value from the moment the dissolve begins (continuous
  at 1). A re-open lifts it. Pinned by morph_source_lost_test.

### Source themes
- The shuttle and the settled route page build everything under
  `MorphFlight.sourceThemes` - the InheritedThemes between the source
  tag and the flight's overlay (Theme, DefaultTextStyle, IconTheme,
  MorphGlass, ...). This is Flutter's popup-route precedent with the
  tag's context as the launching context, so target content gets the
  source's themes.
- Captured once at launch (one ancestor walk). The flight makes the tag
  depend on those theme elements; the tag's didChangeDependencies asks a
  live flight to recapture after the frame (so a change reaches an open
  dialog one frame late).
- The kinds captured are fixed at launch: a recapture that finds other
  kinds is ignored, so the subtree never changes shape. A lost source
  keeps the last capture.
- The wrap sits above the route content key on both sides, so the
  content chain under the key is unchanged. Pinned by
  flight_theme_carry_test.

### Scrim channel (scrim.dart)
- `scrimMotion: MorphScrimMotion(motion:, openDelay:, closeDelay:)` on
  launch / showMorph gives the scrim its own spring - a third orthogonal
  DOF (internal `MorphScrimChannel` on the scope's ticker, joined to
  frameTicks).
- It follows the controller's target (open / close / re-open), never its
  value. Each retarget happens after its direction's delay from the
  current (value, velocity); a newer request replaces a pending one.
- Scrim opacity = maxScrimOpacity x clamp(value). `MorphFlight.scrimOpacity`
  / `scrimValue` are the one read for the shuttle, the vessel and the
  settled route page; the drag thinning still multiplies it. Without
  scrimMotion the scrim stays morphScrimOpacity of the progress.
- It outlives the latch: the shuttle then draws only the scrim
  (IgnorePointer, no semantics - the page is live); finalize waits for
  both the value and the scrim to rest (landed comes after the dim); a
  re-open during that tail re-hides the tag and rebuilds the content.
- Reduced motion: instant, no delays.
- The latch does not markNeedsBuild the entry: a rebuild of the
  shuttle's outer build after a consumer disposed a `repaint` Listenable
  would re-subscribe it (the merged Listenable is new each build). The
  frame builder sees the latch on the same tick. Pinned by
  morph_scrim_test.

### Shared elements (shared.dart)
- Content marked with the same id on both sides (`MorphSharedElement`)
  travels between its endpoint rects instead of riding the fade-through.
  Both sides live in the one shuttle, so the flying frame is a lerp of
  endpoint rects by the raw spring value (interruption-continuous by
  construction), crossfaded on the same fade-through curves and clipped
  by the morphing container shape.
- `MorphSharedFade.none` (declared by either side) renders the target
  copy alone at full opacity: fade-through dims both faders mid-flight,
  which reads as a blink on identical content.
- The registry lives on the flight; sides register via SharedSideScope
  (internal).
- Markers hide by the registry's `canFly` - the set of ids the fly-layer
  builder actually measured this shuttle build - not by `hasPair`. The
  pair registers during the shuttle's first build but nothing is
  measurable until its layout runs, so hiding on hasPair leaves the
  element visible nowhere for one frame. Pinned by
  morph_shared_element_test's launch-continuity test.
- Markers never touch render objects themselves: during the route-mode
  reparent their subtree is briefly inactive and findRenderObject
  asserts.
- Degradations: an unpaired id renders in place; snapshotGhost has no
  live source markers so pairs do not form; marker children must not
  carry GlobalKeys.
- The shuttle republishes the source tag's surface spec around the
  replica. The target anchor sits below the shuttle's reveal scale:
  target rects are layout-space endpoints, not the 0.95 - 1 revealed
  pixels.

### Pop layering
- An overlay flight opened above a ModalRoute registers a
  LocalHistoryEntry on it, so Esc (DismissIntent -> maybePop), Android
  back and a plain Navigator.pop close the topmost surface (the flight)
  first; only the next pop touches the route.
- Route-mode flights skip the entry (their route is the history);
  `MorphPageRoute.didPop` and the predictive-back hooks yield when
  willHandlePopInternally - a stacked entry owns the pop.

### Overlay accessibility
- The scrim is a real modal barrier: BlockSemantics + Semantics label +
  onDismiss when dismissible. The label is looked up with
  `Localizations.of`, so MaterialLocalizations is not required.
- The container is a semantic route (scopesRoute; namesRoute when
  `semanticLabel` is passed).
- A FocusScope + FocusTraversalGroup trap Tab traversal inside the open
  overlay; Esc and focus restore.
- The source ghost is ExcludeFocus'd: the live replica stays mounted
  inside the trap for the whole flight (shared markers must keep
  measuring), and without the exclusion Tab reaches the invisible copy
  and Enter fires its onTap. Pinned by morph_focus_test.
- An explicit FocusNode in the tag child still attaches to the replica
  mid-flight (undetectable, GlobalKey's benign cousin; a GlobalKey
  crashes, so it is asserted), but focus cannot enter and requestFocus
  is a no-op while airborne.

## Entry points: show.dart / anchor.dart / presentation.dart

- Imperative `showMorph*` (escape hatch) and declarative
  `MorphAnchor(isOpen, onDismiss)` - the morph as a function of state.
  Identity is the State itself unless an explicit `tagId` is given;
  `MorphAnchor.tagId` gives the flight a public name, so a MorphPiece
  with the same id gets the neck for free.
- `from:` is optional: inside the source tag's own subtree the nearest
  MorphTag is the source (`MorphTag.idOf`; the shuttle does not
  republish the marker, so dialog content names its source explicitly).
- Retarget contract: a repeated showMorph on a live tag retargets the
  existing flight. It keeps its target, builder, barrier and scrim
  (content lives in the shuttle and cannot be swapped mid-air); only
  motion, dismissal routing and semanticLabel update.
- Overlay choice:
  - Overlay flights render in the nearest enclosing Overlay: the flight
    belongs to the world its scope lives in, so a nested navigator (a
    tab, an embedded device mockup) keeps its flights inside itself.
  - Except across a `MorphPresentationBoundary` (MorphNavigationStack
    installs one): presenters default to `morphPresentationOverlayOf` /
    `morphPresentationNavigatorOf`, the overlay / navigator around the
    outermost boundary, so menus, context menus, dialogs and sheets from
    a stack page cover the stack's bars as on iOS. morphAnchorRect
    measures in the same overlay by default. Pinned by
    presentation_boundary_test.
  - `overlay:` (showMorph* / MorphAnchor / MorphMenuButton /
    MorphContextMenuRegion) chooses the shuttle's home for chrome
    layered over nested navigators (e.g. tabs as nested navigators under
    a floating bar, sheets on a shell navigator that is neither the
    nearest nor the root - hence an explicit OverlayState, not a
    useRootOverlay flag).
- Coordinates stay honest by construction: the tag rect is captured
  against the flight's overlay box, the target's rectFor gets that
  overlay's size, and `morphAnchorRect(context, overlay:)` measures in
  the same space (the overlay must be an ancestor of the context, or
  getTransformTo asserts). Pinned by morph_overlay_choice_test.
- A tag below a paint transform captures its whole local bounds through
  `getTransformTo` + `MatrixUtils.transformRect`; transforming only the
  local origin makes a centered scale jump smaller and off-center on the
  first flight frame.

## Destinations: target.dart

### MorphTargetSpec
- Fields: rectFor, surface, contentAlignment, clipBehavior; plus the
  anchor helpers. Factories: dialog, sheet, fullscreen, popover
  (anchored, flips above when out of room), `measured`, `vessel`.
- `surface:` wins over the individual fields; the shuttle publishes the
  target's resolved model so custom content reads it via
  `MorphTag.specOf`. Custom dialogs/sheets = a custom MorphTargetSpec
  with your content builder; showMorphDialog/Sheet are presets over it
  and adopt shape and color from DialogTheme/BottomSheetTheme unless
  overridden.
- `clipBehavior` defaults to antiAlias. `Clip.none` is for a transparent
  surface whose content draws its own surfaces (with the clip on,
  satellites wipe in along the growing edge); the route page's Material
  honors it too.
- `contentAlignment` is a getter over a private field, overridable;
  `repaint` is a Listenable merged into frameTicks (the CustomPainter
  idiom).

### Vessel
- `MorphTargetSpec.vessel(rectFor:, repaint:)`: the content draws the
  whole morph itself - laid out over the entire overlay in overlay
  coordinates, full opacity from the first frame, no surface, shadow,
  source ghost or crossfade.
- It takes pointers while the flight is open or opening, and so does its
  scrim; a closing vessel lets touches through so its source can re-open
  it.
- Its frame chain rebuilds only when the pointer gate, the dissolve,
  the scrim opacity or content ownership changes; every other tick
  only advances the source and target rects.
- Everything else still applies: overlay choice, modal barrier, pop
  layering, focus trap, events, source-lost dissolve. MorphMenuButton is
  its consumer.

### Measured targets (measure.dart)
- `MorphTargetSpec.measured(constraintsFor:, placeFor:)` and
  `fitContent:` on sheet/dialog/popover (and showMorphDialog/Sheet).
- The content lays out under constraintsFor inside `MorphContentMeasure`
  (@internal): an aligning shifted box that reports the child's size in
  a post-frame callback. A report retargets springs and rebuilds owners,
  neither legal mid-layout, so one frame of lag is by construction. The
  shuttle uses it for fixed targets too (tight constraints, no
  reporting), so the chain is one.
- The flight's `_ContentSizeChannel` seeds on the first report and
  springs per axis on the flight's openMotion afterwards - an endpoint
  filter joining frameTicks, not a second clock on any property.
- `resolveRect(overlay, padding, contentSize)` is the one rect
  resolution; the shuttle and the settled route page both call it.
- Staged first frame: a measured target's shuttle is laid out but
  invisible (Opacity 0 + IgnorePointer + ExcludeSemantics, wrappers
  present on every frame so the tree never remounts) and the tag stays
  visible until the first measurement lands (`_hideTagWhenStaged`, one
  door shared with the snapshot-ghost path). The hide runs after
  `controller.open()` because hasHandedOff reads true while the
  controller is idle.

### Keyboard
- The padding every rectFor receives is `morphTargetPaddingOf`: the safe
  area unioned edge by edge with viewInsets. Every factory avoids the
  keyboard by construction (a sheet docks above it, a dialog centers in
  the room left, the context menu column shifts, a menu places itself
  clear of it); fullscreen ignores padding and keeps its insets.
- The content's MediaQuery carries `morphContentViewInsets`: only the
  part of each inset the container still overlaps (a Scaffold inside
  must not avoid twice).
- iOS animates viewInsets per frame and the target follows per frame;
  Android jumps, like every Flutter widget.
- Pinned by morph_measured_target_test and morph_keyboard_test.

## Routes: route.dart

- `showMorphRoute` / `MorphPageRoute`: the destination as a real
  Navigator route with the flight as its transition. It pushes into the
  nearest enclosing navigator (`useRootNavigator:` opts into the root).
- The route is pushed immediately (back button, predictive machinery and
  further pushes behave like on any page). The flight overlay is passed
  `navigator.overlay` explicitly - the navigator's context sits above
  its overlay. The page stays empty while the shuttle plays.
- Second latch: at settle `MorphFlight.routeOwnsContent` flips, both
  sides rebuild in the same frame, and the content subtree - carrying
  the shared `routeContentKey` GlobalKey - reparents into the route page
  with its live state. This is the one sanctioned GlobalKey move; the
  wrapper chain under the key must stay identical on both sides:
  KeyedSubtree > MorphFlightScope > MorphSurfaceSpecScope >
  SharedSideScope > ListenableBuilder (the flight's content revision:
  MorphAnchor's rebuilds refresh only the builder, not the frame chain
  or the layout around it).
- A pop hands the content back the same way and plays the ordinary
  close; a close launched from the flight side retires the route via
  the route's controller listener.
- Scrim: swaps between owners at full opacity on both latches. The
  route's modal barrier stays transparent and only contributes dismiss
  taps and semantics; pre-latch scrim taps route through the Navigator
  (onDismissRequested -> pop) so the route lifecycle stays the single
  source of truth.
- The settled page applies the displacement channel with the same
  rigid-body shift, recede and scrim math as the shuttle, driven by the
  same frameTicks stream, and resolves its rect through the same
  `resolveRect` / `morphTargetPaddingOf` / `morphContentViewInsets`,
  measuring a measured target inside its Material.
- `MorphPageRoute.barrierLabel` is the localized dismiss label, not the
  route name (that is semanticLabel).
- Predictive back: the route reimplements the PredictiveBackRoute hooks
  on the flight (the default TransitionRoute impl would drive the
  route's zero-duration shell controller). The gesture hands the content
  back to the shuttle and scrubs the value shallowly (depth 0.18);
  cancel springs back and the second latch re-hands the content; commit
  pops and the close plays from the scrubbed value. A private binding
  observer bridges the system events to the route hooks, because the
  material page-transitions detector never wraps a PopupRoute.

## Gestures: gesture.dart and the displacement channel

- Primitives for an app's own drag-to-dismiss: rubber band c=0.55,
  velocity projection `morphProjectValue`, `morphDragRecede`,
  `morphDragArm`, `morphDragScrimFactor`, `morphDragScale`, commit
  thresholds `morphDragCommitDistance` / `morphDragCommitVelocity`.
  `morphDragScrimFactor` + `morphDragScale` are the only implementations
  of how a drag dims the scrim and recedes the card. No prebuilt drag
  widget: gesture policy belongs to the app; the core never attaches a
  gesture.
- Displacement channel: `MorphFlight.beginDrag` / `dragBy` / `endDrag`
  (internally `_DragChannel`, a ChangeNotifier owned by the flight).
  - While the finger is down the whole container (surface, shadow,
    content, shared elements) follows it 1:1 as one rigid body. The
    morph value does not move, so no fade-through midstates show; scrim
    thinning and recede are pure functions of the displacement.
  - Release always springs the offset home on its own always-to-zero
    simulations (per-axis closeMotion with carried velocity). Past the
    commit heuristic (projected distance or speed, overridable via
    `endDrag(commit:)`) the ordinary close plays simultaneously - the
    card flies home out of the hand.
  - The offset is a genuine second DOF (at value 1 it must equal both
    the release offset and zero at settle). The shuttle applies
    `appliedDragOffset` = (raw offset + arm lean) x progress, so it
    vanishes exactly at the handoff latch; the liquid mirror blob rides
    the same offset.
  - Commit feedback: past the commit distance the card arms
    (`morphDragArm`, a smoothstep over 60 px, pure and reversible):
    extra recede, extra scrim thinning, a 12 px drift toward the source.
    `MorphFlight.isDragArmed` exposes the threshold for haptics.
- Value-scrubbing the morph itself is the controller-level expert path
  (beginScrub / updateScrub); it exposes midstates when frozen under a
  finger.

## Liquid skin: liquid_field.dart / skin.dart

### Pipeline and merge law
- CPU SDF (rounded box / capsule) + smooth-min + marching squares +
  Chaikin smoothing produce a single vector `Path` behind live content
  (`MorphSkin` / `MorphPiece` / `MorphLink` / `MorphStroke`). No
  shaders, no blur+threshold - no halos; "one mass - one shadow" holds
  by construction.
- Merge law (Apple's, measured on an iPhone 16 Pro; UIKit
  `UIGlassContainerEffect` and SwiftUI `GlassEffectContainer` agree):
  the mix-form polynomial smin with a per-sample width
  k' = k (1 - dot(na, nb)) / 2 = k sin^2(theta/2) (`liquidMergeWidth`),
  na/nb the operands' unit normals. Facing surfaces blend over the full
  k, edges running side by side not at all, so aligned tops/bottoms of
  fused pieces stay straight.
- The fold carries the accumulated unit gradient and mixes normals by
  the smin's own weight (exact for two masses; for 3+ the natural fold,
  unmeasured).
- `blend` (k) == the glass container spacing, 1:1 in logical px: facing
  surfaces lean toward each other below a gap of blend and touch at
  blend / 2; blend depth at the middle of a facing gap is ~k/4, zero
  along aligned edges. `cell` is a distance too.
- Field bounds are padded by k (otherwise the neck clips); contour
  recomputation is cached by an input signature.
- Replay: liquid_apple_merge_test (fixtures ios27-device/merge: capsule
  and circle pairs, spacing 10..80, gaps 40..-5) holds 0.17..0.32 pt
  rms, the screenshots' noise floor; compare at the field's 0.40 level
  (Apple's tint fill sits ~0.4 pt outside the SDF zero).

### Tracing hot path
- Sampling runs through an allocation-free flat evaluator
  (`_FieldSampler`: typed arrays, no Offset objects or virtual dispatch
  per vertex; accumulated distance and normal live in fields; a mass
  whose distance differs by >= k merges by plain min and skips the dot
  product). The field sampler is the only kind-switch outside
  `liquidMassSignature`.
- Shapes split into connectivity clusters (bounds gap <= k, transitive),
  each traced on its own tight grid. This is exact: k' <= k, so beyond a
  gap of k the smin equals plain min identically, distance and carried
  normal (proof sketch at `_clusterShapes`). The per-cluster grid cap
  logs loudly in debug.
- `LiquidTracer` (one per MorphSkin State): only clusters whose geometry
  changed re-trace. Keys are full per-cluster signatures compared
  element-wise on hash collision; the cache swaps wholesale per trace,
  so it never outgrows the scene. Instrumented via `lastMissCount` /
  `lastClusterCount`.
- `evalBudget` (default `MorphSkin.defaultEvalBudget` = 200k field
  evaluations per cluster; internally `liquidDefaultEvalBudget`): over
  budget the grid coarsens by exactly the overshoot factor, so quality
  degrades before the frame rate. Deterministic in geometry (no time, no
  hysteresis); null disables.
- Fill rule is evenOdd: interior holes (a ring of linked pieces) must
  stay hollow, and the stitcher walks loops in arbitrary directions, so
  nonZero fills holes by winding accident and pops on topology changes.
- Masses: `MorphSkin.extraMasses` takes `MorphMass` (sealed, const
  factories `.box(rect, radius:)` / `.bridge(a, b, radius:)`). The flat
  "kind + 5 params" record (stride `liquidMassSignatureStride`) is the
  canonical flattening; @internal `liquidMassSignature` is its one
  implementation, written into both the tracer's cluster keys and the
  skin's input signature (full parameters: two diagonal bridges can
  share an outerRect yet trace differently).
- Gates: `test/liquid_regression_test.dart` (field-sign/contour
  consistency, near-range bulge, far-range no-deformation) and the Apple
  merge replay must stay green for any pipeline change. Microbenchmarks:
  `flutter test benchmark/liquid_benchmark_test.dart` (JIT, relative
  before/after only).

### Render object
- `MorphSkin` is a thin stateless facade over `RenderMorphSkin`. Spring
  ticks call markNeedsPaint only - no rebuild, no relayout in an
  animation frame; the group is its own repaint boundary.
- A piece's content transform is its `MorphPieceChannel` alone, with
  transform-aware hit testing; layout runs only when piece geometry
  changes from the outside. Flight subscriptions live in attach/detach.
- Optional `MorphSkin.gradient` shaded across the group bounds;
  `MorphStroke` draws the inner contour of the same path (paint-only,
  after tints).
- Stack children in MorphSkin must be keyed by piece id, otherwise
  removing a piece from the middle confuses stateful content identity
  (MorphTag duplicate-id asserts).
- Safety nets: geometry snapshots (test/liquid_geometry_golden_test.dart,
  regenerate via test/golden_dump_helper.dart), seeded fuzz
  (test/liquid_fuzz_test.dart), and the frame benchmark
  (benchmark/group_frame_benchmark_test.dart: build+layout+paint per
  pumped frame during a glacial flight, plus the orbit scene
  rebuild-driven vs channel-driven).

### Piece geometry channel
- `MorphPieceChannel` (on `MorphPiece.channel`) - "frameTicks for
  pieces". Payload (offset, scaleX, scaleY) over the base rect, applied
  about its center; no rotation by construction (SDF boxes are
  axis-aligned). Scale zero is legal and deflates the mass to nothing; a
  degenerate content transform paints nothing and hit testing skips it.
- Births: `MorphPieceChannel.birthScale` 0.2 and `birthSpring`
  `MorphSpring(0.492, 0.711)` - a Liquid Glass shape is born at a fifth
  of its size at its final center and leaves by shrinking back, parked
  inside the survivor; fitted to SwiftUI's `glassEffectID` per-frame
  rects (peak ~3 percent over at 0.38 s, settled by 0.7 s).
- A write is markNeedsPaint only: no rebuild, no relayout, no
  `_syncFlightSubscriptions`, no allocation. Channel identity is part of
  piece geometry equality, so a swap resyncs; subscriptions live in
  attach/detach with one shared handler.
- Effective rects (base + channel) feed the whole pipeline: resolve,
  trace signature (a stale contour is impossible), launch fellowship,
  bridge endpoints, blob fallback.
- Content rides as one rigid body on a child-local paint transform;
  layout stays at the base rect, so content paint-scales and text does
  not rewrap. applyPaintTransform mirrors the paint transform so
  localToGlobal / MorphTag / anchor measurement see the displaced rect -
  otherwise a flight launches from the base position while the piece
  stands elsewhere.
- Transient motion commits into the base rect at rest (dragBy writes the
  channel, endDrag commits and resets - one rebuild per gesture).
- Content whose values derive from the same spring (label emphasis, icon
  opacity/glyph) listens to the spring itself inside a stable piece
  child.
- Pinned by the channel group in morph_skin_test (re-trace isolation via
  `LiquidTracer.lastMissCount`, no-rebuild/no-relayout counters,
  displaced launch rect, fellowship from displaced geometry,
  resubscription).

### Flight neck
- The group finds flights in MorphScope by its piece ids: it listens to
  `scope.lastFlight` for discovery and to each flight controller for
  ticks, and unsubscribes on `closed` (guaranteed to run before the
  controller's deferred dispose). Outside a MorphScope
  (`MorphScope.maybeOf` null) it degrades to pure fusion.
- Airborne: the home mass turns off and a companion blob follows the
  shuttle (mirror of the frame geometry via `morphFlightGeometry` /
  `morphConcentricRadius`, translated through the group's
  localToGlobal; it rides the drag offset too). Explicit links of the
  flying piece detach. Landing: the mass is home again, no squash.
- Content with a MorphTag stays home for the whole flight (the flight
  tracks the source through the tag); only the mass blob travels.
- Launch fellowship: at subscription the skin captures the connectivity
  component of the flying piece over solid pieces and their MorphLink
  bridges (labeled by `liquidConnectivityLabels`, the one body predicate
  the tracer's cluster split also uses), from that moment's effective
  rects. The blob necks only to those - a flight stays attached to what
  it was part of, not to whatever it passes. Entries outlive
  subscription blips and are erased only on flight close or skin
  detach.
- Perf gate: if `liquidRectGap` to every fellow exceeds k the neck
  cannot exist and the blob is skipped (exact, k' <= k). Instrumented
  via `lastFlightBlobCount`. The same gate decides whether a geometry
  tick repaints at all: only when the flight took off or latched since
  the last paint, or its blob was in the last paint or would be now. A
  launch elsewhere in the scope repaints the skin only when its own
  flight subscriptions change.

### Layer-1 API
- `MorphPiece.morphable(...)` - an auto-MorphTag (piece id, shape from
  its radius, skin color/elevation); the consumer calls
  `showMorph*(from: pieceId)` from any context.
- `MorphSkinStyle` - named knob presets; `subtle` (blend 8 = SwiftUI's
  default container spacing) is the builtin. Explicit blend / cell /
  smoothPasses override the style.

## Surface model and ambient defaults: theme.dart

- `MorphSurfaceSpec` (shape, color, elevation) is declared once at the
  tag (`MorphTag.spec`) and read back by any rendering stack via
  `MorphTag.specOf(context)`, so the visible surface and the flight's
  belief cannot drift. The engine's contract ends at specOf; the core
  blesses no design system. App-wide archetype vocabularies belong in
  the app's own ThemeExtension holding spec values.
- `MorphTheme` (ThemeExtension) holds engine defaults: motion,
  maxScrimOpacity, scrimColor, shadowColor, skinStyle. Resolution order
  everywhere: explicit parameter > MorphTheme > builtin.
- scrimColor is a hue whose own opacity composes with the animated scrim
  opacity.
- shadowColor is applied verbatim and resolved by both flights and
  MorphSkin against one builtin (60% black): Material elevation and the
  skin draw through the same canvas.drawShadow primitive
  (RenderPhysicalShape.paint). The shared value is the flights' 0x99
  because skins sit at elevation 2-6 while flights reach 24.
- Shadow and elevation belong to the shuttle and lerp source to target;
  a button with its own shadow must declare `MorphTag.elevation`. Vessel
  targets draw neither.
