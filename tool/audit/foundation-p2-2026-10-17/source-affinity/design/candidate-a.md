# Candidate A: rotate the private session, retain the public source State

Grounded against `d9973893a0cd91c7eff6c68efe6571594033c81c`. Design only; no tests, source edits, GUI or device work. Read the task, ground, how, architect runner/rationale/red-flags, runtime, repository rules, actual source and probe clock. This independent candidate uses the inherited model; it is not a second engine opinion.

## Problem

The model lease answers who can sample a motion, but the current mutable `_viewId` allows the retained source to redefine the input and landing space of an existing popup. The root Navigator and actual FlutterView identities must belong to one session for its entire lifetime. A GlobalKey source State can outlive that session, so rotate the private session when its attachment changes. The old session becomes source-less and retains its own popup, clock, fixed coordinates, policy and old-view pointer filter. The moved source receives a new model. Same-root nested relocation preserves the old session when both View identities also match.

## Usage (caller’s view)

The existing caller does not acquire a controller, reset a model, or coordinate cleanup:

```dart
final source = GlobalKey<ProbeMenuSourceState>();
Widget menuSource() => ProbeMenuSource(
  key: source,
  pointerInput: true,
  menuBuilder: buildMenu,
);

final oldPopup = source.currentState!.open();
moveSourceToOtherRoot(); // Reparent the same GlobalKey in one tree update.
await nextFrame();
final newPopup = source.currentState!.open();
```

`oldPopup.navigator` remains the original Navigator. `newPopup.navigator` is the moved source’s root. Both can be alive simultaneously. Dismissing the old popup never supplies a model to the moved source and never pops the new Navigator. The source State identity is unchanged.

```dart
moveSourceBetweenNestedNavigatorsUnderOneRoot();
await nextFrame();
expect(source.currentState!.activeRoute, same(oldPopup));
```

This preserves the existing model when the root and both FlutterViews remain identical. Existing eligibility still blocks input from a covered nested page; identity is not a replacement for currentness.

```dart
moveSourceToOtherFlutterView();
await nextFrame();
final currentFrame = source.currentState!.frame;
```

The frame getter observes the fresh source session. A retained reference to `oldPopup.frame` observes the old session. Programmatic `open()` still returns `ProbeMenuRoute`. A source nested in a FlutterView different from its selected root overlay is an invalid fixed-space presentation configuration: raw/semantic acquisition declines, and explicit `open()` throws a descriptive `StateError` before any push. It must not silently invent cross-view coordinates or push a route whose pointer space cannot match its source.

## Shape

All code stays in `example/lib/proto/menu_route_probe.dart`. No model, clock, transfer, public configuration or dependency change.

```dart
final class _MenuAffinity {
  const _MenuAffinity(this.navigator, this.sourceView, this.presentationView);

  final NavigatorState navigator;
  final FlutterView sourceView;
  final FlutterView presentationView;

  bool get canPresent => identical(sourceView, presentationView);
  bool sameSpace(_MenuAffinity other); // Identity for all three fields.
  static _MenuAffinity read(BuildContext source); // Actual selected overlay View.
}

class ProbeMenuSourceState extends State<ProbeMenuSource>
    with TickerProviderStateMixin {
  _MenuSession? _current;

  void _refreshAttachment();
  _MenuSession _currentForCommand();
  bool _isAttached(_MenuSession session);
  bool _sourceCanAcquire(_MenuSession session, {
    ModalRoute<Object?>? coveredRoot,
  });
  ProbeMenuRoute _prepare(_MenuSession session, {bool reserve = false});
  void _semanticOpen(_MenuSession session);

  ProbeMenuRoute open(); // Existing return type and caller experience.
}

class _MenuSession {
  _MenuSession(TickerProvider vsync, ProbeMenuSource widget, this.affinity);

  final _MenuAffinity affinity;
  bool Function()? sourceAttached;
  bool Function({ModalRoute<Object?>? coveredRoot})? sourceEligible;
  VoidCallback? present;
  ProbeMotionClock? sourceClock;

  bool get hasSource => sourceClock != null && (sourceAttached?.call() ?? false);
  void detachSource(); // Immediate capability cut, deferred observable retirement.
  bool land(ProbeMenuRoute route, double time);
}
```

Use the SDK `FlutterView` identity, not just `viewId`, and actual root Navigator identity, not its current route/page. Pin pointer filtering to `affinity.presentationView.viewId`; delete `updateSourceView` and its mutable backing field. Capture the presentation View from the root overlay’s context. Reading `View.of(sourceContext)` establishes the source dependency; reading the selected overlay’s View only determines the actual host. If the source and selected overlay are in different Views, this fixed-space prototype cannot present safely.

### One session per attachment

`didChangeDependencies` reads the immutable affinity. If the current session matches, only the existing source-theme refresh runs; theme/MediaQuery changes do not rotate a model. If it differs, detach the old session, create and attach a new one, then let this source build install the new painter and captured input callbacks. Returning to a previous root later creates another fresh session; detachment is sticky. No cache or reattachment registry.

Session construction must no longer happen in `initState`, because the View and root Navigator are inherited dependencies. Construct the first session in `didChangeDependencies`. Use `TickerProviderStateMixin`: `SingleTickerProviderStateMixin` prohibits a second ticker over the entire State lifetime, even if the first was already disposed. Dispose the previous source clock before creating the next. The old route’s clock is provided by its original Navigator and is independent. At most one source clock remains owned by this State.

The nullable `_current` is an internal transition boundary, not a second synchronized flag. During rotation set it to null before external model factory code can run. Reentrant `open()` during that construction must fail clearly rather than returning an old route or half-created session; this is the same unsupported synchronous-constructor reentrancy that must not be made into a hidden queue. After construction publish `_current`, then install callbacks. Public getters require the attached current session and remain callable normally after mount.

### Token captured callbacks, live validation

Session object identity is the attachment token; no integer generation is needed. Install callbacks that capture the exact session:

```dart
session.sourceAttached = () => _isAttached(session);
session.sourceEligible = ({coveredRoot}) =>
    _sourceCanAcquire(session, coveredRoot: coveredRoot);
session.present = () {
  if (_isAttached(session)) _prepare(session);
};
```

`_isAttached` requires State mounted, `identical(_current, session)`, `session.affinity.canPresent`, and a newly read live affinity matching the captured one. This rejects stale source semantic/pointer/land operations even before dependency refresh. Do not reuse a bare `_prepare` method tear-off: after rotation that would resolve the new session from an old session’s callback.

The source build captures `final session = _current!` and uses that in painter and every raw/semantic callback. An old semantic node or hit result therefore cannot accidentally activate the newly installed session. Public `open()` first refreshes the current attachment at a safe command boundary, captures it, prepares a route on `session.affinity.navigator`, then activates that exact session. Recheck attachment after externally observable callback/model command boundaries. Do not return an old active/reserved route before affinity validation as current `_prepare` does.

`sourceEligible` composes attachment with the existing ModalRoute/Navigator currentness checks. `sourceAttached` deliberately does not require page currentness: the menu itself covers its original page, and landing uses attachment identity rather than current-page identity. `land` requires `hasSource` immediately before model transfer and again checks the captured source clock/session after any reentrant model command before publishing hand-back/frame changes. If attachment became invalid, source detachment must already revoke that capability; do not transfer then merely hide the recorded hand-back. The normal transfer model has no external callbacks inside `transfer`, but the boundary should remain explicit.

### Immediate detach without tree-locked publication

Dependency refresh runs while the tree can be locked. Existing `detachSource()` is not safe to call unchanged: reservation retirement can cancel the model, emit observations, mutate route state and later notifications. Split its implementation into two phases behind the one method:

1. Synchronously clear `present`, `sourceEligible`, `sourceAttached`; clear `_pointer` so an in-progress command cannot retain authority; dispose and null `sourceClock`. Invalidate source capability before invoking external code. Do not touch `frames.value`, route stage/projection, Navigator history or user `onSample` here.
2. Defer the observable domain retirement to outside the build/tree lock (a captured old-session microtask after the synchronous framework stack, or the project’s existing safe post-frame seam). The callback captures only the old session; never reads the State’s current session. It cancels the old sequence through existing command-depth serialization, retires stale reservation through existing exact-route removal, then synchronizes old input/route phase. Guard disposal/idempotence and old transfer identity. This closes uncommitted hidden preparation finitely while preserving already committed model work under the current source-loss rules.

Cancellation is required even though the physical sequence is cleared: clearing entitlement alone leaves the model’s hold pending. Store its existing `_cancelAfterCommand` target before clearing the sequence, and drain it only at the safe point. If an in-flight command tries to drain during tree-locked rotation, the drain must retain the pending target until that safe point; otherwise reentrancy bypasses the deferral. An implementation can arrange this with one pending retirement future/token local to the detached lifetime; it should not become an independent model state machine.

A shown old popup continues to accept old-view menu input using its route authority. It has no source callback/clock and cannot land. A stale held tail is revoked once; old-view fresh menu down remains allowed after cancellation retirement. New-view events cannot reach the old model. A hidden preparation cancels pending hold and closes on its original clock; a held reopening reservation is retired exactly once, while its existing owner closes independently. If the old source already owned a landing tail and no route remains, there is no visible old host to maintain: dispose that detached session without copying the tail to the new source.

Old `routeDisposed` already resets only its own session when a source clock exists. After rotation the old source clock is null, so old disposal cannot reset the new model. Retain that structure; do not add a route-to-State callback. Dispose old frame notifiers only once no route remains and after the old painter has detached or publication has finished; do not dispose a notifier from its own notification stack.

### Interface depth and invariants

The public surface stays unchanged and hides attachment rotation, cancellation and independent popup lifetime. `_MenuAffinity` owns the three identities. Session identity owns the source generation. Transfer remains the sole model owner. Route remains Navigator/policy owner. This follows boundary-discipline and separate-before-serializing-shared-state: old and new presentations have different sessions rather than sharing a writable current view id. There is no map, generic attachment manager, public lifecycle controller or per-widget migration flag.

## Synthesis decision

Pending independent arena synthesis. Recommend this candidate when public State retention and confined source-file change are decisive; explicitly graft any better safe-retirement seam from the alternative rather than duplicating generation flags.

## Tradeoffs accepted

- Accept a fresh model when root/View identity changes in exchange for never moving old fixed coordinates across rendering spaces.
- Accept a source-less old popup until its own dismissal/settling in exchange for preserving content State, SDK policy and continuous old motion.
- Accept an explicit unsupported cross-View ancestor/overlay configuration in exchange for honest geometry boundaries.
- Accept one deferred retirement boundary in exchange for avoiding user callbacks and frame notifications under build lock.
- Accept `TickerProviderStateMixin` bookkeeping in exchange for sequential source clocks within one retained public State.

## Alternatives considered

- **Keyed inner source host:** outer public State delegates to a keyed inner host whose entire session lifetime is owned by `(root, View)`. It removes some mutable State bookkeeping but adds an imperative State-to-child forwarding boundary for all getters/open and requires special handling before the inner host mounts. It still needs live stale-action checks and safe detach when the old child disposes under tree lock. Thus it hides no more caller-visible complexity than rotation and creates an extra lifecycle hop. It is a viable independent shape, not rejected for correctness.
- **Keep one session, add a landing/input guard:** smallest patch but insufficient interface depth. New source `open()` still returns the old route and new interactions share the old model. Correctness leaks into each method and eventual same-session route disposal can reset the wrong source.
- **Move existing popup between Navigators or copy the model:** neither is a valid Navigator route/ownership operation; exposes geometry and policy migration that this stage cannot prove.

## Open questions and risks

- Can the actual second-View harness exercise a root overlay different from source View, and does it demonstrate clean rejected acquisition without a foreign push?
- Can deferred cancellation race a route frame or new old-view menu down before retirement, and does the chosen scheduling seam drain cancellation first without notifying during build?
- Does the constructor’s injected `createMotion` observer attempt reentrant `open()`, and if so does it get a clear transition error rather than stale ownership?

These are verification risks, not requests for a human approval checkpoint. Live anchor measurement, transformed roots, scroll/rotation retargeting, source geometry updates and native multiwindow behavior remain unimplemented. Root identity safety must not be marketed as arbitrary geometry correctness.

## Red-flag screen

No public transport/framework affinity types; no second way to open; no synchronized view id; no route-to-new-source reset callback; no generic registry. The only additional callback is source attachment authority, distinct from page input eligibility because those invariants are materially different. Safe detachment is one owner method, not a public temporal protocol. Reject the sketch if implementation starts synchronizing a second “current root” beside `_MenuAffinity` or repeatedly escaping to the State from route code.

## Next implementation step

First build the retained-GlobalKey two-root harness proving old/new route overlap and unchanged State, then implement session rotation with one immutable affinity and verify tree-locked detach, reservation retirement, same-root nested preservation and actual second-View input isolation before running unchanged replay/scene gates.
