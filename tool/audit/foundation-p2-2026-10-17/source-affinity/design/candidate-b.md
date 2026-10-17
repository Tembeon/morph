# Candidate B: keyed source host with an attachment handle

## Problem

A public GlobalKey preserves ProbeMenuSourceState while its physical source changes root Navigator or FlutterView. The currently retained session therefore cannot also be the definition of the current source. This candidate gives each physical source attachment a separate private handle and keys the rendered source subtree by that handle. The public State remains a stable command facade; an old PopupRoute retains its old handle/session independently. Geometry stays the existing fixed-input experiment.

## Usage (caller's view)

```dart
final source = GlobalKey<ProbeMenuSourceState>();

ProbeMenuSource(
  key: source,
  button: button,
  bounds: bounds,
  menuBuilder: buildMenu,
);

final first = source.currentState!.open();
// Move the same widget/GlobalKey to root B through one parent rebuild.
final second = source.currentState!.open();
assert(!identical(first, second));
// first still belongs to root A; second belongs to root B.
```

A same-root nested Navigator move keeps the same handle, transfer, current route and canonical motion. Moving A → B → A creates three source attachment lifetimes: it never reconnects the first route to the third source. Caller code neither waits for the old popup to close nor supplies disposal or migration flags. Existing `open(): ProbeMenuRoute`, frame, ownership, settled, frame-count and activeRoute observations all refer to the current attachment only.

Three internal call sites define the required behavior:

```dart
// Stable facade, including a command received before the next scheduled frame.
ProbeMenuRoute open() {
  final mount = _currentForLiveContext();
  return mount.open();
}

// Rendering/hit testing uses a captured attachment, not an indirect current session.
Widget build(BuildContext context) => _MenuSourceHost(
  key: ObjectKey(_current),
  mount: _current,
  source: widget,
);

// A route knows the physical presentation it was installed into.
bool land(ProbeMenuRoute route, double time) =>
    route.mount.tryLand(route, time);
```

## Shape

Keep all private types in menu_route_probe.dart. No exported new controller, generic geometry service or production motion edit.

```dart
final class _MenuAffinity {
  const _MenuAffinity(this.root, this.sourceView, this.presentationView);
  final NavigatorState root;
  final FlutterView sourceView;
  final FlutterView presentationView;
  bool sameAs(_MenuAffinity other); // identical on all three, no viewId-only match
  bool get canPresent; // sourceView and presentationView are identical
}

class ProbeMenuSourceState extends State<ProbeMenuSource>
    with TickerProviderStateMixin {
  _MenuSourceMount? _current;
  bool _elementActive = true;
  _MenuAffinity _readAffinity();
  _MenuSourceMount _currentForLiveContext();
  ProbeMenuRoute open(); // existing public signature
  Widget build(BuildContext context);
  void didChangeDependencies();
  void deactivate();
  void activate();
  void dispose();
}

final class _MenuSourceMount {
  _MenuSourceMount({
    required this.affinity,
    required TickerProvider vsync,
    required ProbeMenuSource source,
    required bool Function(_MenuSourceMount) isCurrentAndCompatible,
  });
  final _MenuAffinity affinity;
  final _MenuSession session;
  bool get attached;
  ProbeMenuRoute open();
  bool acceptsSourceAction();
  bool tryLand(ProbeMenuRoute route, double localTime);
  void sealSource();
  void drainRetirement();
}

class _MenuSourceHost extends StatefulWidget {
  const _MenuSourceHost({super.key, required this.mount, required this.source});
  final _MenuSourceMount mount;
  final ProbeMenuSource source;
}

class _MenuSourceHostState extends State<_MenuSourceHost> {
  Widget build(BuildContext context);
  void dispose(); // seals only widget.mount, idempotently
}
```

The private host owns the captured handle's painter, pointer Listener, semantic callbacks and source theme subscription. The facade owns attachment selection and vsync only. Handles own sessions and all source-side teardown. Route-created policy/content remains outside this host and survives its replacement. The keyed boundary means a new host cannot accidentally retain an old painter, semantic closure or widget-local source environment. This follows separate-before-serializing-shared-state: current source B and retained route A do not share writable transfer state.

`_currentForLiveContext` computes View.of(source context), root Navigator and View.of(root.overlay!.context) from the active element. Compare object identities. Root pages/currentness are acquisition policy, not affinity. Theme, MediaQuery and inherited widget replacement within an unchanged affinity update the existing handle; they do not rotate it. A source View nested beneath a root Navigator in a different View is unsupported by the fixed-space probe: fail source acquisition before creating/pushing a popup; explicit open throws StateError with the incompatible presentation description. Do not quietly accept an old popup or map coordinates across render trees.

The nullable current handle exists only before the initial dependency setup or after disposal. No public operation receives a nullable handle. The key is the handle object itself, not `(root, view)`: returning to an old pair must still produce a new lifetime. Inside that lifetime the affinity is immutable.

### Rotation and callbacks

The new handle must exist synchronously, independently of its keyed host mounting. Otherwise public open immediately after a reparent would need an incompatible return-type change or frame queue. Its source clock is created with the public facade's TickerProviderStateMixin. This deliberately gives up the attractive idea that the inner host alone supplies vsync: creation before its State exists would be impossible. SingleTickerProviderStateMixin cannot be retained on the facade, even when the old ticker is disposed first.

The retirement transition has two phases hidden behind facade selection:

1. Seal the old handle immediately. Clear all source context callbacks (`present`, eligibility and live-binding reader), mark its landing site lost permanently, invalidate held sequence/source action entitlement, stop/dispose its source clock and clear the session's sourceClock. This phase performs no Navigator calls, ValueNotifier publication or observer callback. If a model command is in progress, record its existing deferred cancellation rather than entering the motion again.
2. Publish the new handle on the facade, then schedule the old handle's idempotent retirement drain outside the framework build/tree lock. The drain cancels domain input, retires reservations by route identity, starts finite hidden-preparation closing and disposes the session once unused. Old `onSample` callbacks may reenter public open only after the new attachment is the facade's current one. Revalidate session/model/route identity after every callback.

The new handle must not start its ticker until old sealSource has stopped the previous source ticker. There can be multiple registered, already disposed ticker objects over the public State lifetime, but at most one active source clock. Route clocks use their original Navigators independently.

`deactivate` marks ancestor reads unavailable without declaring permanent affinity loss; GlobalKey reparent itself passes through deactivation even for same-root moves. `activate` makes live reads legal; didChangeDependencies then compares the actual pair. Every source action and hand-back also checks live binding, so a stale source semantic callback or pointer callback retained before that refresh is rejected. Calling ancestor lookups while inactive must fail closed without touching context. Do not revoke a held sequence merely because same-frame framework deactivation began. On dispose, seal the current handle synchronously and drain cleanup safely; late private-host dispose seals only its own captured handle, never the facade's newer handle.

The normal synchronous Navigator.push restriction during a framework build remains a framework restriction; this design must not invoke observer callbacks from dependency retirement that create such an artificial reentrancy. A caller command outside the locked build can use the new handle before host rendering catches up.

### Input and landing

A session's view identity becomes immutable presentation input provenance. Global raw-pointer handling checks that immutable viewId and the route's ordinary current/input entitlement. The old route remains able to accept old-View events after its source is sealed. New-View down/move/up cannot mutate it; stale old sequences are canceled once. Captured source hit callbacks additionally require that handle's live source binding, so the old private host cannot acquire an old source lease after a move. Do not globally disable the old session's pointer router while its shown popup is still live.

`tryLand` requires attached handle, the same current handle object, current live affinity equal to its immutable origin, and the route actually installed on affinity.root in affinity.presentationView. Validate before clock resume and after commands/observation that can reenter. A failed landing does not change owner or time; the route keeps its existing clock and completes the whole model. Source departure is sticky: returning to A cannot make an old A handle current again.

Shown old popup remains shown and independently dismissible by its original SDK route policy. It is neither removed nor popped solely because its source moved. A hidden preparation has no independently committed content: cancel its sequence, close it and sample to whole-model rest on its original route clock, then remove that exact route. A hidden held-reopen reservation is retired exactly once; committed opening on its old active owner is closed under existing source-loss behavior. Neither path may pop the new root or promote a reserved popup into the new source handle.

### Source-owned tail

If the departing source already owns the transfer, its old painter has disappeared. This candidate abandons that complete source-owned lifetime: stop its source clock, cancel held input safely and release that session when no routes retain it. It does not reset/copy that old model, paint it into B, invent a final settled sample or create a second invisible source ticker. A still-retained old closing route must finish its own SDK projection without regaining the source-owned model. The report must distinguish abandoned source-owned tails from completed old route-owned tails. If the requirement is that an invisible source-owned tail also reaches numerical rest, this shape needs a different explicit retirement driver and no longer meets the stated one-active-source-clock constraint unaided.

This is an accepted semantic choice only for physical attachment loss, not normal closing or a same-root nested relocation. Add a test that moves after hand-back and observes no old samples/new-source mutation and zero old source scheduling, while the fresh source can open normally.

## Synthesis decision

Pending the parent comparison. This candidate intentionally adds a keyed source render lifetime instead of leaving all mutable pointer, semantic and painter callbacks directly in the stable public State.

## Tradeoffs accepted

- Accept one private keyed host and handle in exchange for source widget callbacks/painters structurally tied to one attachment lifetime.
- Accept TickerProviderStateMixin on the facade in exchange for preserving immediate public command semantics before private host mount.
- Accept loss of a physically removed source-owned tail in exchange for no invisible extra ticker, model copy or migration across coordinate spaces.
- Accept explicit failure for source/overlay View mismatch while fixed geometry is the experiment contract.
- Accept deferred route/policy publications in exchange for safe dependency-change and disposal behavior under tree lock; source action and landing revocation remain immediate.

## Alternatives considered

Direct mutable-session rotation in the public State has a smaller type count and hides the same public lifecycle complexity. It loses the keyed widget boundary: every closure must capture and validate the intended session, and late old callbacks naturally see a mutable `_session` field. It may nevertheless win on total maintenance cost for this probe if all source rendering stays trivial.

A fully self-contained keyed inner State with SingleTickerProviderStateMixin hides more clock ownership but loses synchronous `open(): ProbeMenuRoute` before its mount. Returning a future or adding readiness coordination exposes framework scheduling to callers. Prebuilding an unmounted State is not a valid workaround.

Pinning the existing single session until its route finishes hides retirement but prevents a source moved to B from presenting an independent menu immediately; it exposes old-route lifecycle to callers and does not meet the requested boundary.

## Red-flag screen

No public transport types or migration knob. No motion model copy or hand-synchronized current/old model. One source selection writer (facade), one session writer per model, one source callback owner (captured handle). Private host is a meaningful ownership boundary, not a pass-through public API. The main cost is the handle/host split and the two-phase teardown; if implementation duplicates routing policy between facade and host, scrap that duplication rather than add adapters. Neither View identity nor root identity is inferred from route currentness.

## Open questions and risks

Does invisible source-owned tail retirement meet the required source-loss semantics, or must its model reach rest despite no compatible renderer? Parent should resolve this explicitly before choosing this candidate.

Can all source-vsync cleanup occur synchronously without invoking ProbeMotionClock frame observers, and can reservation retirement reuse its existing deferred route removal without duplicate projection completion? Check against actual disposal/reentrant tests; do not assume.

## Next implementation step

Build the two-root retained GlobalKey harness and old-route/new-source simultaneous ownership assertions, then implement the private attachment handle and keyed host without changing production models or measured replay baselines.
