# Candidate A: origin-bound acquisition, one revocable sequence

Same inherited model as the orchestrator. Read-only repository design at `cfade8834496cc0cf580230b0e097e172ec27514`; no tests, devices, repo edits or agents. Architect phases Ground and Sketch only. Grounding: `ground.md`, `how/findings.md`, `why/findings.md`, the seven new ownership checks and their 3-failure/4-pass log; current route, transfer, clock, motion and timeline sources. This is a candidate, not independently verified behavior.

## Problem

The complete motion already has the right sampling owner, but a binding-global callback treats coordinates as authority to begin a new source interaction. Root currentness must gate new menu input; actual source hit testing plus source route ancestry must gate source input. A cover must revoke a held interaction without freezing the complete motion, destroying committed release deadlines, or requiring an application API. The early root push remains necessary for the existing recorded held stream and remains an acknowledged currentness/observer cost.

## Usage: caller's view first

The consumer's `ProbeMenuSource(pointerInput: true, menuBuilder: ...)` remains unchanged. Only the prototype adapter's private call sites change:

```dart
// Source Listener, the one authority for a fresh source hit.
onPointerDown: (event) {
  session.handleSourceDown(event);
  // Preserve the existing pre-ancestor-Navigator down ordering.
  if (session.needsPresentationFor(event)) open();
}

// Binding-global transport: continue an acquired sequence, or acquire a new
// sequence only for this session's current, non-closing root presentation.
pointerRouter.addGlobalRoute(session.handlePointer);

// Root route lifecycle, local cleanup only: no Navigator mutation here.
void didChangeNext(Route<Object?>? next) {
  invalidateDismissalIfNextChanged(next);
  if (next != null) session.revokePointerFor(this);
  super.didChangeNext(next);
}
```

A second source whose root page is beneath another session's preparation cannot arm merely because that preparation still passes through hit tests. Its source entry checks its complete Navigator/ModalRoute ancestry, not only its nearest nested route. A revealed, logically popped menu can still reverse/reopen from a genuine eligible source hit. A closed source can never acquire through the global transport.

## Shape

One module continues to own input policy: `_MenuSession` in `menu_route_probe.dart`. `ProbeMenuTransfer` gains exactly one domain operation. No new public application API, route registry, global keyboard hook, model replacement, timeline category or production edit.

```dart
final class _PointerSequence {
  _PointerSequence(this.pointer, this.viewId);
  final int pointer;
  final int viewId;
}

class _MenuSession {
  _PointerSequence? _pointer;
  ProbeMenuTransfer? _cancelAfterCommand;
  int _modelDepth = 0;
  int? _viewId; // Actual source View; retained after source teardown.

  void updateSourceView(int viewId); // From State.didChangeDependencies.
  void handleSourceDown(PointerDownEvent event);
  void handlePointer(PointerEvent event);
  void revokePointerFor(ProbeMenuRoute route);

  bool _sourceCanAcquire(); // State callback, false after detach.
  bool _routeCanAcquire(); // Same active route, isCurrent, !closing, !disposed.
  bool _sequenceCanContinue(_PointerSequence sequence);
  void _deliver(_PointerSequence sequence, PointerEvent event);
  T _modelCommand<T>(T Function() action); // Drain local cancel only at outer exit.
  void _revokePointer();
  void _drainPointerCancel();
}

class ProbeMenuTransfer {
  /// Cancels only the current physical interaction at the model's latest
  /// canonical sample; committed release work and passive motion remain.
  bool cancelPointer(ProbeMenuLease lease) {
    if (!identical(lease, _owner)) return false;
    _motion.pointerCancel(_motion.time);
    return true;
  }
}
```

These signatures are a sketch; bodies are not implemented. `needsPresentationFor(event)` need not become an additional method if the existing small source-listener guard expresses the same invariant: acquired sequence is still identical, source still eligible, and no non-closing route already owns it. Keep the smaller local spelling in implementation.

`_viewId` is not inferred from the last global event. Obtain it from `View.of(sourceContext).viewId`; reject other-view events at both entry points and when continuing. A source view migration while an interaction is live revokes the old sequence before updating the view. Retain the captured view after source removal because a live route intentionally outlives its source. Tests of real multiple Views are required before claiming multiwindow support; this field prevents the obvious binding-global cross-view capture but does not establish all focus/window behavior.

### Acquisition and data ownership

`handleSourceDown` accepts only primary down, no existing sequence, matching source View, and one of:

1. No presentation: actual source hit and all source ancestor modal routes current.
2. Revealed closing presentation: actual source hit, source ancestry current, current transfer remains the old menu's model or source handback model. A non-current source beneath a newer root cover fails.
3. Current non-closing own presentation: ordinary menu ownership permits acquisition, including a pass-through pending source hit; no second sequence is created when the later global delivery observes that same down.

The global callback accepts a new down only under condition 3. It no longer tests `button.contains(position)` to acquire a closed source. An existing sequence is continued by identity and matching view only while its presentation remains eligible. The original down's later global delivery is a duplicate acquisition attempt and returns, not a second model down. Other pointers and other sessions cannot steal the sequence.

For source ancestry, a source State helper can use only public APIs: check `ModalRoute.of(sourceContext)`, then repeatedly inspect `ModalRoute.of(nearestNavigator.context)` and ascend with `Navigator.maybeOf(nearestNavigator.context)`. The Navigator's own context excludes its own State when finding an ancestor Navigator. Reject any non-current ancestor modal route. Do not retain a context after detach, and avoid caching these booleans: route eligibility changes without rebuilding the source. Actual hit origin remains the primary authority; ancestry closes the pass-through/multiple-source gap.

One sequence object is the sole stream identity; clearing it makes all later physical events stale. No parallel pointer ID plus generation counter is needed. The model remains the sole owner of its private pointer details. The session translates a revocation into its domain cancellation; the lease remains the sole sampling authority. This follows boundary-discipline and single-source-of-truth rather than synchronizing a second model state.

### Cover and cancellation ordering

On cover, clear the session sequence synchronously, remember the exact transfer identity requiring cancellation, then issue `cancelPointer(currentOwnerLease)` at the next safe outer model-command boundary. If no model command is running, cancel immediately at `transfer.frame.time`. If a user action pushes a cover from inside `advance`/pointer delivery, defer the model call until that outer operation has returned. Never call a reentrant `advance` from `didChangeNext`, and never call Navigator.pop from that history callback. Before draining, check the session still references that same transfer; a forced removal/new model must not receive an obsolete cancel. A lease captured before a legitimate source/route handoff is not reused: resolve the current lease for the same complete transfer when draining.

Wrap the adapter's model entry points with the small `_modelCommand` envelope so a cover inside a frame callback and a cover inside pointer handling share this rule. No asynchronous cancellation queue is necessary. The only deferred local operation is idempotent cancellation for one transfer; two cover notifications merely leave the sequence absent. Keep sampling, kicks, fusion, close and handback active while non-current. Wake the current live owner clock for any cancellation-generated relaxation tail; do not retime it, reset the model or clear the timeline.

A new safety requirement discovered from actual model control flow: `_motion.pointerUp(t)` runs due callbacks before it consumes the held pointer. A due committed action can synchronously push a cover; simply setting a pending cancel at that moment lets the rest of pointerUp schedule a *new* selected action after revocation. Therefore `_deliver` first stamps the genuine event once, advances the same transfer to that stamp inside the command envelope, then revalidates sequence identity, route/source eligibility, transfer identity and owner clock. If any changed, drain cancellation and reject the pointer command. Only then dispatch `transfer.pointer` at exactly the same local time. The pointer method's own same-time advance then has no old due callbacks left to run. At this base, pointerUp's selection path schedules effects; it does not synchronously invoke an application action after that advance. Verify this with a due-action-pushes-cover-during-a-second-up test. This extra sample must leave all replay frames/timings unchanged; if it does not, stop and redesign rather than tuning fixtures.

Do not backdate cancellation to a callback's deadline, fabricate a PointerCancelEvent, use GestureBinding.cancelPointer, or stamp a fake event. The domain cancel uses the current canonical sampled state after the outer command, so physics continuity stays meaningful. The genuine eventual SDK cancel is ignored because it no longer owns the session sequence.

### Released action versus held interaction

A valid release commits its already scheduled action. Covering immediately afterward does not erase or reschedule it. It may run once while covered; close admission continues to refuse a pop of the covering page. `pointerCancel` intentionally leaves that timeline work intact. A held interaction revoked before its up cannot commit a release; late move/up after uncover remain stale. This is a precise ordering contract, not a promise that all actions stop whenever a menu is invisible.

The pre-advance/revalidation rule preserves the previous release's already committed action but prevents the interrupted new pointer command from creating another release after that action covers the route. User effects already executing when cover occurs cannot be undone.

### Keyboard and Back

No handler change. Preserve four passing binding/focus characterizations: hidden Escape retains source focus/preparation in the ordinary plain/nested WidgetsApp harness, while actual platform Back cancels the hidden root preparation without building menu policy. Add revealed plain/nested Escape characterization through SDK focus/actions. Document that Router child-priority, editor-local Escape, custom Actions, IME and multiwindow focus remain open. Do not claim root-first keyboard or Router semantics from direct root maybePop.

## Interface depth and red-flag screen

- Deep private boundary: callers supply real source events or route lifecycle notifications; they do not coordinate pointer ID cleanup with model mutation themselves.
- No split stream owner: sequence identity lives only in session; private pointer geometry stays in motion; transfer controls writes by lease.
- No two source acquisition paths: only the source Listener grants a new source sequence. Global transport's acquisition capability is confined to a current presentation.
- No temporal module chain: policy remains in the existing route/session file; transfer's added method owns canonical cancellation and does not expose the model reference.
- No state registry, per-source global keyboard action, transport-shaped app API, hand-maintained route list or new dependency.
- The model-command depth/cancel field is justified only by concrete reentrant callback control flow. If implementation needs several independent deferred operation queues or boolean exception ladders, scrap this candidate and investigate a unified input/command boundary; do not grow a generic transaction framework here.

## Tradeoffs accepted

- Accept one binding-global continuation subscription per live session in exchange for preserving the recorded original hold across early root transfer. Acquisition authority is now narrow and view-bound.
- Accept a same-time pre-sample for delivered input in exchange for rejecting commands invalidated by due action reentrancy before their model mutation. Replay evidence must prove equivalence.
- Accept committed selected actions running under cover in exchange for preserving the existing measured release semantics and production model unchanged.
- Accept the early root push's observer/currentness side effects; this work does not approve them as the final library architecture.
- Accept a bounded prototype cancellation operation and command-depth envelope, pending typed-effect/interaction boundaries in unit 2.4, instead of hiding these concerns in fabricated binding input.

## Alternatives considered

1. Merely guard global handler with route.isCurrent: hides little and leaves the closed covered source/multiple-source ghost acquisition; blocks legitimate revealed-closing reopen if applied indiscriminately. Rejected.
2. Hit-test-only local Listener/GestureRecognizer transport throughout: gives source origin naturally and can hide binding-global policy, but a later overlay/route changes hit paths while the original held stream needs to continue. It requires proving a transport lease that captures the sequence across that topology and reproduces all early-outside recordings. Viable future structural candidate, greater scope here.
3. Close or replace the model on cover: shallow apparent cleanup destroys passive timeline/physics and committed releases; bypasses navigation veto. Rejected.
4. Global input coordinator across all sessions: can arbitrate competing preparations, but exposes global lifetime/window policy to solve a gap public ancestry plus actual hit origin already handles. Rejected until a failing multi-source case proves necessity.

## Open questions and risks

- Does the public source ancestry traversal cover every intended Navigator arrangement, including externally hosted overlay sources? Verify plain/nested multiple sources and root covers; do not claim arbitrary custom host support.
- Can a client callback replace/remove the route during the pre-advance? Identity/lease checks must reject the event and avoid stamping or waking a disposed old clock. Add a real reentrant removal test if implementation touches this path.
- Does same-time pre-sampling leave every recorded geometry/clock sample unchanged? Require all existing strict replays and scenes; no tolerance changes.
- Do genuine multi-View tests establish pointer isolation as well as source migration, or is this only an explicit remaining gap?
- Should future product semantics revoke a valid release's delayed action when covered? That would need a deliberate selective model interaction contract/unit 2.4, not a silent adaptation of pointerCancel.
- Router Back priority, editing/IME Escape and native device behavior remain unestablished.

## Synthesis decision

For arena to fill after independent comparison. Candidate A recommends origin-bound source acquisition plus root-current menu acquisition and direct leased cancellation; retain passive motion and committed release deadlines.

## Next implementation step

Make the three existing failure checks green with the new acquisition boundary, then add cover/reentrant-callback/multiple-source/view/closing-handback checks before broadening to keyboard characterizations and rerunning the unchanged replay suite.
