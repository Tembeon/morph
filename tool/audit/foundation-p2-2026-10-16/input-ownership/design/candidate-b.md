# Candidate B: hit-acquired physical sequences, with a bounded acquisition bridge

Read-only design at `cfade8834496cc0cf580230b0e097e172ec27514`. Architect skill, runner, rationale, red flags, Phase A how/why/ground, the seven initial ownership tests and their failing log, route/transfer sources, and public installed Flutter binding/pointer-router sources inspected. No tests run, repository edits, device, keyboard override, or subagents. Same inherited model as the other candidate; this is structural comparison, not independent model agreement.

## Problem

The current session has a lifetime global subscription that both discovers unrelated downs and transports already accepted streams. Those are different authorities. A model lease authorizes sampling; it does not authorize the library to receive a down that hit a different page. Separate discovery from transport: a real source or presentation hit acquires one physical sequence, and that sequence alone gets a public SDK pointer route until termination or revocation. Cover revokes interaction while the complete model and its clock continue. The awkward constraint is that the hidden root route exists before it has a rendered acquisition surface: a second outside down in that gap currently belongs to the pending menu and recorded input must retain this behavior.

## Usage first

The app's `ProbeMenuSource` constructor and observations stay unchanged. All changes are private to `menu_route_probe.dart`; production classes, timeline, clock, fixtures, tuning and exports are untouched.

```dart
// Actual source Listener; coordinates alone never discover a closed source.
onPointerDown: (down) {
  if (_session.beginSource(down, sourceContext: context)) {
    _session.prepareRootRouteBeforeAncestorNavigatorSeesDown();
  }
}

// Full presentation viewport acquisition surface, behind actual menu content.
// This handles downs only. Accepted continuation uses PointerRouter.addRoute.
onPointerDown: route.beginPointerFromPresentationHit,

// Route history callback; local cancellation only, no Navigator mutation here.
void didChangeNext(Route<Object?>? next) {
  if (next != null) _session.revokeInputFor(this);
  super.didChangeNext(next);
}
```

The source call both acquires and delivers the original down exactly once. Preparing the root route remains within that source callback before the ancestor Navigator records the down. Route acquisition is available over the actual modal viewport, including outside the menu's visual rectangle; a menu-row-only Listener is insufficient. A `PointerDownEvent` that only hit the covering route is never acquisition evidence for the source or underlying menu.

## Shape

Private, in the existing single prototype file:

```dart
class _PhysicalSequence {
  _PhysicalSequence({
    required this.pointer,
    required this.viewId,
    required this.origin,
    required this.route,
  });
  final int pointer;
  final int viewId;
  final _InputOrigin origin;
  final PointerRoute route;
  // Identity is the generation; there is no numeric epoch.
}

sealed class _InputOrigin {}
class _SourceHit extends _InputOrigin {
  _SourceHit(this.sourceIdentity, this.viewId);
  final Object sourceIdentity;
  final int viewId;
}
class _PresentationHit extends _InputOrigin {
  _PresentationHit(this.presentation);
  final ProbeMenuRoute presentation;
}

class _MenuSession {
  _PhysicalSequence? _sequence;
  _AcquisitionBridge? _bridge;
  bool beginSource(PointerDownEvent down, {required BuildContext sourceContext});
  bool beginPresentation(ProbeMenuRoute route, PointerDownEvent down);
  void _continue(_PhysicalSequence sequence, PointerEvent event);
  void revokeInputFor(ProbeMenuRoute route);
  void _retire(_PhysicalSequence sequence);
}

class _AcquisitionBridge {
  // Only genuine downs, only while a desired pending-menu hit surface has
  // not yet been published by the rendered tree. Never continuation transport.
  final ProbeMenuRoute route;
  final int viewId;
  final Object requestedSurface;
  void onGlobalEvent(PointerEvent event);
  void renderedSurfacePublished(Object surface);
  void dispose();
}
```

These signatures are a sketch, not a proposal to export hierarchy types. An enum plus payload can replace the sealed origin types if fewer states are needed. Source provenance has no presentation reference; presentation provenance does. The source's view comes from its actual `View.of(context)` at acquisition, never from a process-global implicit view.

`beginSource` rejects an existing sequence and non-primary button, binds `down.viewId`, and admits solely because the source was actually hit, subject to the rule that a live non-closing menu already owns acquisition. It should also reject hidden closing preparation and obsolete source identity. It delivers the down through the active clock/whole-model transfer, installs one `PointerRouter.addRoute(down.pointer, callback)`, then performs the existing preparation ordering. It does not install a long-lived down observer.

`beginPresentation` requires the identical session's current, mounted, non-closing presentation and matching source view. It admits outside/menu downs through the viewport hit surface. The source and presentation both enter one private acquisition routine so delivery/coalescing has one owner. A competing source under the current menu is not in the hit path. If a source is actually hit through a transparent hidden preparation before that preparation arms, it still rejects ownership while another non-closing root menu exists. Nested source route currentness must not be approximated by a nearest-modal-only check.

Continuation is accepted only by `_continue` for the identical sequence and matching view/pointer. Public SDK pointer routing transports the real event regardless of current source/route model lease. It deliberately resolves the current transfer owner and clock at delivery; tying the physical sequence to the old motion lease would break source-to-route continuity. Continuation ignores down: the acquisition callback already delivered it, and `PointerRouter.route` can observe a route added by the source Listener before the binding's final hit-test entry dispatches that same down. Up/cancel retire before calling arbitrary model callbacks, with identity-aware cleanup so reentrant acquisition cannot be cleared by the older operation.

Cover removes the per-pointer route and clears `_sequence` first, then issues the existing model cancellation command at the canonical current owner time. This is a library command, not a fabricated binding event and not `GestureBinding.cancelPointer`. A late physical move/up, including SDK cancellation queued by cover navigation, has no route to this session and cannot reanimate it after uncover. Cover does not pause clocks, replace the model, call close, clear the whole timeline or attempt a Navigator mutation inside its history flush. Explicit forced removal/disposal also retires local input. Source teardown alone need not cancel a valid route-owned interaction if presentation lifetime remains valid.

Already committed releases remain committed: once a valid up has scheduled activation, coverage does not clear that deadline. If cancel at time t advances an already due activation, that is the chosen action policy rather than an accidental promise of blanket suppression. New down/move/up under cover is excluded; passive physics and delayed actions already committed are distinct channels. A direct existing `pointerCancel` command is enough for the live interaction contract provided the existing model generation guards clear held/dwell work; retaining committed release deadlines is intentional.

### The mount/publication gap is real

A pure local-hit-only version cannot preserve the existing pending-menu outside input contract. `Navigator.push` changes logical ownership synchronously but Flutter does not insert a hit-testable rendered route until a frame. No ordinary Listener can receive a second outside down that arrives before that frame, and manufacturing/replaying binding events is excluded. This is a hard feasibility boundary, not an implementation omission.

To remain viable, B keeps a **bounded down-only global bridge** while the desired pending-menu acquisition surface has not been published. Its handler requires the identical active/current root route, matching view, no existing sequence, and the menu's pending/open state; source-coordinate fallback is forbidden. It hands the actual down directly to the same sequence acquisition and adds the per-pointer route. Because global pointer routing has already copied its route list, the new per-pointer route will start with the next event; the acquisition routine delivers this down once.

The bridge cannot simply stop at first `buildPage`: a mounted hidden route can later change from unarmed to open-pending between frames. Stop only after the **matching surface generation has completed render publication**, and reinstall it for another publication gap if pending eligibility changes before a later frame. A small stateful surface acknowledgement after the frame is needed; callbacks compare identity and actual mounted/current state. Cover/pop/disposal removes the bridge immediately. Leaving it active until first reveal is simpler but lengthens the global exception and must be declared.

This hybrid is structurally different from a lifetime global router: global down discovery exists only as a temporary substitute for an unrendered surface; continuations are exclusively per-physical-sequence routes; settled closed sources have no global subscription. However, it has three acquisition transports and an explicit render-publication protocol. That is substantial cost for this reduced prototype.

### Closing and reopening

Logical pop normally makes `route.isCurrent` false while its closing visuals still paint; the presentation cannot use non-currentness as a reason to stop passive samples or handback. Reopen acquisition must come from a genuine hit on the source, never merely from a global coordinate match to the old button. The route's acquisition surface and modal barrier therefore become non-hit-testable for a closing presentation so the underlying source can acquire. Old sequence retirement must precede replacement route acquisition without revoking the newly acquired source sequence.

There is a second publication hazard here: changing ordinary widget `IgnorePointer` flags only rebuilds on the next frame. A down delivered before that frame might still be hit by the old barrier and cannot be reclassified as a source hit. B either accepts that strict actual-hit rule (potentially losing a historical immediate reopen replay) or needs a small custom hit-test gate whose eligibility reads the current route state synchronously at hit-test time. Do not claim a source Listener alone preserves every pre-frame closing reopen. This must be tested against all recorded reopen cases before choosing B. A render gate adds a new custom rendering seam solely to avoid a global acquisition seam; that cost may outweigh the benefit at P2.

## Interface depth and red-flag screen

The app surface does not grow. One private owner controls acquisition, the current sequence, router registration and revocation. The per-sequence token makes stale callbacks structurally harmless and reduces unrelated input exposure. This is deeper than asking each source/route caller to remember origin flags.

No model state copy, hand-synced input/model state mirror, app-level broker, parallel controller, public escape hatch or keyboard policy is introduced. The bridge's surface generation is a real render-publication invariant, not another motion generation. Nevertheless three input discovery paths and a render-ack protocol are a **two-ways-to-one-task / temporal decomposition red flag**. All must feed one acquisition function, and the mounted local surface replaces the temporary bridge rather than running as an enduring alternative. The custom closing gate, if required, is an additional ownership boundary and must stay inside the same private file. If prototype growth exceeds the simpler global admission design, reject B rather than layering exceptions.

## Synthesis decision

For the parent/judge. My candidate prefers B only if the team wants to establish hit-test locality as a future production invariant now and is willing to test render-publication gaps explicitly. For the current small P2 prototype, retaining a global transport with actual source-hit provenance plus currentness admission is likely the smaller verified implementation; B's bridge shows that the global mechanism cannot simply be deleted while retaining all existing timing semantics.

## Tradeoffs accepted

- We accept one per-pointer registration and exact retirement protocol in exchange for no lifetime global observation of continuation streams.
- We accept the bounded global down exception in exchange for preserving outside input before a presentation surface renders.
- We accept a mount/publication acknowledgement and possibly custom closing hit gate in exchange for truthful hit-based acquisition semantics.
- We accept that moving transport does not fix currentness/publication races automatically; identity and route eligibility checks still apply at boundaries.
- We preserve measured callbacks committed by valid release in exchange for not promising that every action stops merely because another route covers the menu.

## Alternatives considered

Pure source/menu Listener transport is smaller but loses original-stream continuity if source leaves the mounted tree and cannot receive pending outside downs before a frame; it hides too little lifetime complexity for its apparent simplicity. A fresh app-wide arbiter could centralize multiple sources/windows, but introduces a production integration service and keyboard/window policy outside this prototype's scope. A lifetime global handler with true source provenance and route admission has fewer publication states and preserves existing transport; it loses B's limited subscription lifetime but is a credible preferred base at this stage.

## Keyboard and Back

This candidate changes no keyboard routing. Characterize actual SDK Escape with retained source focus versus revealed popup focus, plain/nested WidgetsApp, binding Back and a separately explicit Router dispatcher harness. Hidden Escape retaining focus/preparation and ordinary binding Back dismissing the hidden root route are different existing outcomes, not a bug to hide with FocusManager interception. No universal root-first promise follows for prioritized nested Router delegates.

## Open questions and risks

Can a bridge acknowledgement be reduced to a single render-surface identity without introducing a second synchronization owner? Do the immediate pre-frame reopen recordings require the custom render hit gate? Does a real route viewport Listener preserve interactive embedded content and all barrier semantics, especially source hit-through during closing? Do multiple views require a host-level arbiter beyond the current fixed-geometry prototype? These are implementation evidence questions; no human permission checkpoint is requested.

## Next implementation step

Implement the per-pointer sequence/acquisition core against the seven failing/passing ownership checks, then run all recorded input replays before adding the bridge or claiming transport equivalence; if it requires both bridge and closing render gate, compare the measured code/state cost against the smaller global-admission candidate before proceeding.
