# Candidate A: deferred content with a route-owned first-mount gate

Read-only design against d121d186. Same inherited model as the other local candidates; this is independent design exploration, not different-family consensus. No implementation, tests, devices, or repository edits were performed.

## Problem

A real root PopupRoute is installed on source-down to preserve Flutter's genuine held pointer stream. Its content and focus are intentionally deferred until the measured model opens. There are consequently three boundaries: installation, measured opening/reveal, and first content-subtree mount. SDK policy inside menuBuilder exists only after the third. The current code treats the first as sufficient for super.willPop and the second as sufficient for popDisposition; the new tests demonstrate an SDK modal-scope assertion and an early-close bypass of an unbuilt PopScope. This design preserves the real early route, zero content builds for a canceled pre-hold press, the complete model/lease/time ownership, existing synchronous mounted deadlines, and the previous one-attempt/one-success async protocol. Only the example route host and its tests change.

## Usage (caller's view)

Consumer usage remains unchanged. The consumer supplies its normal Flutter policy inside menuBuilder; there is no prepare callback, separate policy declaration, mount Future, or readiness parameter.

```dart
ProbeMenuSource(
  pointerInput: true,
  menuBuilder: (_) => PopScope<void>(
    canPop: hasSaved,
    child: MenuContents(),
  ),
)
```

Immediate command-mode opening and SDK dismissal wait for the actual content subtree to mount, then use its registered policy:

```dart
final route = source.currentState!.open();
final handled = navigator.currentState!.maybePop();
// Before the next frame: no menuBuilder invocation, no super.willPop call.
// After the first revealed subtree finishes mounting: ordinary SDK policy runs.
```

A hidden held press can instead be abandoned without constructing content that the user never opened:

```dart
final gesture = await tester.startGesture(button.center);
// Real root route already exists; the measured model is still arming.
await navigator.currentState!.maybePop();
// Cancel preparation; do not consult hypothetical, unbuilt menu policy.
// Continuing/up from this abandoned press must not reopen the presentation.
```

For a coarse frame that runs opening and a close deadline together, close admission returns false while content is unmounted. The model remains opening, syncInputPhase reveals it, the first content subtree mounts, and the retained dismissal evaluates policy. An allowed close then starts at the current model sample; a veto leaves it open. This is an explicitly delayed operation rather than a claim that the coarse frame retains the original synchronous close deadline.

## Shape

### One module and one transaction owner

All new lifecycle knowledge belongs in `example/lib/proto/menu_route_probe.dart`. `_MenuSession` keeps model ownership and pointer delivery; `ProbeMenuRoute` owns presentation readiness and dismissal permission. `menu_transfer_probe.dart` only needs a change if the separately investigated covered-pointer work requires an explicit interaction-cancel command; the mount gate itself does not require it. No production `lib/` code, timeline, clock, public exports, dependency, fixture, or measured tuning changes.

Keep `_DismissAttempt` as the single operation identity. Add a request-local mount wait, not a session queue and not an independently reusable route readiness Future:

```dart
enum _DismissKind { cancelPreparation, policy }

class _DismissAttempt {
  _DismissAttempt(
    this.requestedAt, {
    required this.fromModel,
    required this.kind,
  });

  final double requestedAt;
  final _DismissKind kind;
  bool fromModel;
  Completer<RoutePopDisposition>? permission;
  Completer<bool>? firstMount;
  bool approved = false;
  bool claimed = false;
}

class _PolicyMount {
  bool ready = false;
}

class ProbeMenuRoute extends PopupRoute<void> {
  _PolicyMount? _policyMount;
  bool get _policyReady => _policyMount?.ready ?? false;

  void _attachPolicyMount(_PolicyMount mount) => throw UnimplementedError();
  void _finishPolicyMount(_PolicyMount mount) => throw UnimplementedError();
  void _detachPolicyMount(_PolicyMount mount) => throw UnimplementedError();
  Future<bool> _waitForPolicy(_DismissAttempt request) =>
      throw UnimplementedError();
}
```

`_DismissKind` identifies a real behavioral distinction, not request execution stage. A model close is always `policy`, even when `_revealed` is false: the model calls its admission hook only from opening. An SDK request is `cancelPreparation` only when neither revealed nor model-open at entry; command-mode open is revealed immediately and therefore policy-bound. This prevents a delayed dismissal that already belongs to an opening menu from being mistaken for an uncommitted press cancellation. It also makes the allowed exception to content policy visible at the one boundary selecting the kind.

A route-scoped `_PolicyMount` identity is issued by the private mount widget. The route alone mutates its `ready` property. `firstMount` is an optional request-local wakeup; it is created only if policy is not ready and completed on mount or invalidation. It is not a second permission decision. Reuse the existing `_isLive`, shared permission completer, and per-caller successful claim.

### Concrete post-build signal

Wrap only the revealed content in a private StatefulWidget. The child builder must run under that wrapper so installation of its identity precedes mounting descendants. At initState, attach a fresh identity and schedule one post-frame callback. That callback runs after the subtree's first build/mount and descendant didChangeDependencies, so normal PopScope and WillPopScope registration has occurred. It checks State.mounted and the route's exact identity before signaling. No callback during build, no microtask claiming descendants mounted, no route-modal-scope-only proxy, and no endless post-frame polling.

```dart
class _MountedMenuPolicy extends StatefulWidget {
  const _MountedMenuPolicy({required this.route, required this.builder});
  final ProbeMenuRoute route;
  final WidgetBuilder builder;

  @override
  State<_MountedMenuPolicy> createState() =>
      throw UnimplementedError();
}

class _MountedMenuPolicyState extends State<_MountedMenuPolicy> {
  final _mount = _PolicyMount();

  @override
  void initState() {
    // Attach _mount. Schedule one addPostFrameCallback.
    // In callback, if mounted, ask route to finish this exact identity.
    throw UnimplementedError();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);

  @override
  void dispose() {
    // Detach exact identity; route invalidates any still-pending request.
    // A previously scheduled callback is harmless because mounted is false.
    throw UnimplementedError();
  }
}
```

The revealed branch becomes `Flow(children: [_MountedMenuPolicy(route: this, builder: _builder)])`. Its hidden branch remains SizedBox.shrink. The wrapper persists across ordinary notifier rebuilds; it does not repeatedly force menuBuilder recreation, insert new Navigator ownership, or capture a foreign BuildContext. When first mounted, the SDK ModalRoute's scope necessarily exists as the wrapper is inside its page. Arbitrary widget build errors retain normal Flutter error behavior; this is not a mechanism for certifying successful application builds or indefinitely waiting for asynchronously loaded future descendants. The contract covers the policy present in the first actual content subtree.

An implementation may simplify `_PolicyMount` to State identity plus a route boolean only if attach/detach semantics remain equally explicit. Do not use `pageBuilds > 0`, `_revealed.value`, `navigator != null`, or a bare `endOfFrame` as readiness: all are weaker facts.

### Admission and SDK calls

`_deferDismissal(time)` stays the internal production-model seam and is synchronous:

1. Existing pending request: mark fromModel and return true, as today.
2. Not policy-ready: create a policy request with its original canonical deadline and return true.
3. Ready with scoped async guard: use the existing async transaction.
4. Ready with no async guard: preserve the current synchronous popDisposition and local-history path unchanged.

No Navigator or widget mutation occurs inside model admission. In particular, do not reveal from inside an in-progress advance just to mount policy. Rejected admission leaves model opening; after advance, the existing syncInputPhase reveals it. `_drainDismissal` can start the request before or after `_reveal`: the request's mount wait is the synchronization boundary.

For `willPop`, preserve publication of `request.permission` before starting any callback. `_resolvePermission` has this shape:

```dart
Future<void> _resolvePermission(request, permission) async {
  // For cancelPreparation: do not call super.willPop; no subtree policy exists.
  // Validate _isLive and produce one claimed pop success, via the existing wrapper.
  // For policy: if unready, await request-local firstMount.
  // After the wait, revalidate exact attempt/currentness/lease/not closing.
  // Only then call super.willPop and use existing policy/async/error handling.
  // Complete shared permission once. Existing willPop wrapper grants one success.
}
```

A post-mount signal completes only the currently live policy attempt's firstMount waiter; it never resurrects an invalidated request, executes pop itself, or starts a second guard. Ordinary later requests use the already-ready mount identity and skip the wait. All calls waiting on an attempt share one policy evaluation, while only one caller can consume a successful SDK pop permission. If an SDK request and model request coalesce, existing fromModel behavior remains; cancellation of a hidden preparation must not later turn into authorization for a newly opened or replacement menu.

### Cancellation, timing, and reentrancy

Extend `_invalidateDismissal` to complete a pending firstMount with false as well as completing permission with doNotPop, then clear identity. Cover, cover/uncover, remove, replace, whole-Navigator unmount, relinquish, forced pop, failed local-history pop, and disposal use that same invalidation path. The resumed resolver checks identity before touching any route or guard. A late post-frame callback may mark an existing mounted subtree ready, but cannot authorize an old attempt or pop whatever route is now top.

Programmatic Navigator.pop keeps its current unconditional semantics and bypasses policy/mount waits. It invalidates the pending operation first. Source-only loss does not invalidate a still-current root route; the actual subtree can mount and resolve policy without the source State.

When a policy request waited for mount, approval uses the established causal-time path: resume the existing clock from the current engine anchor and close from the current canonical sample. Never close at requestedAt after time has advanced. Normal ready/synchronous replays continue to use their measured deadline. No continuously-running idle clock and no new timer is required.

`cancelPreparation` is a separate route-lifetime operation. It must not invoke unbuilt policy or artificially mount content. While its hidden route is closing, ignore further model commands from the abandoned held pointer, while still clearing the session's tracked pointer on its genuine terminal event. This can be derived from `route.closing && !route._revealed.value`; it does not require globally disabling reversal of an already revealed menu. At disposal, existing routeDisposed creates fresh source motion when needed. Test release/move before disposal and after disposal so an old hold cannot schedule a fresh open. Do not synthesize or replay binding PointerEvents. If an explicit model interaction cancellation is necessary, expose that as a prototype transfer command over existing pointerCancel, not as fabricated framework input.

Reentrant guard navigation and reentrant maybePop retain the prior exact-attempt check and single claimed permission. A content builder can also navigate while mounting: the post-frame signal must check actual currentness before releasing a pending request, rather than assume that its continued State.mounted proves eligibility. A covered but still-mounted subtree can become ready for future requests, but the old pending attempt remains canceled.

The already documented post-issued SDK-success window remains open. Once willPop has returned pop to Navigator, the prototype cannot revoke that answer atomically; Navigator performs its own final checks. This design does not silently expand cancellation guarantees beyond pending requests.

### Honest route and nested behavior

Keep Navigator.of(context, rootNavigator: true), real observer push/pop ordering, and real isCurrent. A canceled reservation therefore still causes an observable root push/pop pair, root home becomes non-current while hidden, and a nested page remains current in its own stack. No observer filter or synthetic currentness is introduced.

The nested proof should exercise actual down/move/up with the full nested hit-test path, not only state.open. Keep root coordinates explicit. Underlying focus may remain primary while its root route is non-current; requestFocus false is not a promise that keyboard traversal behaves as though no popup exists. Once revealed, mount and focus follow normal root popup behavior. An inner Navigator.of(sourceContext).maybePop still targets the inner Navigator; a root popup is not permission to redirect that call. Router/BackButtonDispatcher integration remains a separate gap.

The discovered covered-global-input mutation is not solved by the mount gate. At minimum reject new downs while an active route is non-current and add focused tests. Do not casually reject every non-current event: a genuine cancel/up from an already-tracked pointer still needs coherent cleanup. A cover-time model interaction cancel may be appropriate, but it should be explicit and independently tested; no claim that a simple currentness guard proves all covered interaction safe. Root push can itself cancel tracked pointers, and tests must characterize that real SDK delivery order. This concern must not motivate rewriting model ownership or synthesizing pointer streams in the mount change.

### Interface depth and red-flag screen

The public surface adds zero parameters or methods. One private widget and one route-local identity hide descendant-registration ordering, wait completion, and cancellation. Call chains remain within one file. Session admission asks the route the same question as before; it does not learn widget readiness internals. The transaction has one owner, and policy readiness is derived from one current mount identity rather than synchronized across session/model/route. No public transport type, hand-synced policy list, duplicate async guard API, or application-level coordination is introduced. Methods named attach/finish/detach are justified by identity validation and ownership policy, not pure forwarding. The request-local wait is an intentional internal temporal boundary because the external SDK policy cannot exist before Flutter completes this stage; it does not fragment model integration into a new pipeline.

## Synthesis decision

Pending parent arena synthesis. This candidate recommends the deferred-first-mount shape as the base because it preserves both ordinary consumer policy placement and the established zero-build canceled-press behavior. Do not describe same-model agreement as independent model-family consensus.

## Tradeoffs accepted

- We accept one post-frame wait for the first policy-bound request in exchange for consulting actual descendant policy without an application API burden.
- We accept that a coarse initial frame's close starts later from current state in exchange for refusing an unbuilt policy bypass; mounted normal-frame deadline semantics remain unchanged.
- We accept unbuilt policy cannot veto cancellation of a genuinely hidden, uncommitted preparation in exchange for never eagerly constructing a menu merely to cancel a held press.
- We accept observable early root navigation in exchange for the existing demonstrated genuine pointer continuity. This remains prototype evidence, not final production adoption.
- We accept a request-local optional mount completer in the already-owned dismissal identity in exchange for prompt cancellation without a global route readiness Future that can strand callers.

## Alternatives considered

1. **Eager hidden content mount.** Build menuBuilder immediately under Offstage/TickerMode/focus suppression, then inspect policy once initial modal mount completes. This hides fewer lifecycle phases internally, but changes the established zero-build canceled-press behavior and can eagerly run arbitrary application effects. It also cannot solve same-turn pre-first-build calls without its own readiness wait. Its public surface is similarly small, yet its implicit consumer side effects are larger.
2. **Delay root PopupRoute push until model opens; reserve/paint outside it.** This can align observers/currentness with visual opening, but the existing late-push negative control proves a naive implementation loses held pointer move/up. A replacement input reservation/presentation mechanism would require new cross-layer coordination and measured evidence. It exposes significantly more ownership/input complexity than this bounded private gate and is not justified for fixing the mount-policy bug.
3. **Declare policy separately on ProbeMenuSource.** This makes pre-mount policy immediate but creates a second API and duplicates Flutter's policy source. Consumers must synchronize PopScope and the new callback; copying the nearest example will diverge them. Rejected for split ownership and larger shallow interface.

## Open questions and risks

- Can product code accept an observable root push/pop for a canceled hidden preparation? Evidence can characterize this honestly; final production driver selection still needs that decision.
- Does Escape from retained nested focus target the intended Navigator while hidden, and should it cancel preparation? Characterize SDK behavior before adding action overrides.
- Does the proposed hidden-abandonment input guard suffice through immediate move/up and disposal, or is a prototype-level explicit interaction cancel necessary? Test genuine binding events rather than assume cleanup.
- Do covered existing-pointer cancellation and root/nested focus traversal need a separate bounded follow-up once the mount gate is proved? Do not conflate new-down rejection with complete interaction cancellation.
- Are asynchronously inserted policy descendants intentionally out of the first-mount guarantee? The proposed contract follows ordinary currently mounted SDK policy and does not await unknown future widgets.

## Next implementation step

Implement the private first-subtree post-frame identity and request-local cancellation gate in the route file, make the three new failing lifecycle cases pass, then add hidden-cancel, concurrent-request, cover/remove/unmount, reentrant-builder, and genuine nested-pointer checks before rerunning unchanged strict replays.
