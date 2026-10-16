# Candidate B: eagerly mount the route subtree, gate its presentation

## Problem

The early real root route is required by the recorded held-pointer preservation experiment. Its menu builder is currently deferred until measured reveal, so neither synchronous `PopScope` nor legacy asynchronous `WillPopScope` exists during preparation. Calling SDK policy before the SDK modal scope mounts also asserts. This candidate separates *content existence* from *content presentation*: mount arbitrary menu content on the route's first build, but hide its paint, hit testing, semantics, tickers, and focus until measured opening. A single initial-page readiness gate covers immediate SDK calls. This is structurally different from keeping a deferred builder and waiting for its first revealed subtree mount.

**Admissibility: this is a viable whole implementation alternative only if the existing zero-builder-invocations-on-cancelled-pre-hold contract is relaxed. Under the supplied requirement to preserve that evidence, reject this candidate as the base.** No widget mechanism can mount arbitrary application content, discover its descendant policies, and also claim its builder never executed. The earlier cancelled-hold test would intentionally change; it must not be silently deleted or relabelled.

## Usage (caller's view)

No consumer API changes; application policy remains ordinary Flutter widget policy:

```dart
ProbeMenuSource(
  pointerInput: true,
  menuBuilder: (_) => PopScope<void>(
    canPop: canDismiss,
    child: MenuContents(),
  ),
)
```

Command-mode immediate dismissal is safe before any route frame:

```dart
final route = sourceKey.currentState!.open();
final handled = await rootKey.currentState!.maybePop();
// Awaits initial route subtree readiness, then invokes registered policy.
```

Programmatic navigation retains its existing bypass contract:

```dart
rootKey.currentState!.pop();
// Cancels any waiting permission; does not wait for content readiness.
```

The raw-pointer caller remains a normal source Listener. It pushes the root popup before ancestor Navigator listeners record the source down. No pointer fabrication, replay, public preparation option, public readiness future, or application-supplied guard is introduced.

## Shape

One file remains the domain owner: `example/lib/proto/menu_route_probe.dart`. Existing transfer, clock, production model, public exports and tuning are unchanged. The route owns initial content readiness and its existing `_DismissAttempt` owns permission/cancellation. No readiness registry or extra session copy exists.

Sketch signatures, not implementation:

```dart
class ProbeMenuRoute extends PopupRoute<void> {
  final Completer<void> _contentReady = Completer<void>();
  _DismissAttempt? _dismissal;

  Future<RoutePopDisposition> willPop();
  Future<void> _resolvePermission(
    _DismissAttempt request,
    Completer<RoutePopDisposition> answer,
  );
  void _markInitialContentReady();
  bool _deferDismissal(double requestedAt);
  void _invalidateDismissal();
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation);
}
```

`buildPage` always constructs the menu content once in route context. A route-private stateful wrapper schedules `_markInitialContentReady` after its first frame, after descendant `didChangeDependencies` has registered policies. Publishing readiness from a parent `initState` or invoking the builder is insufficient. The callback checks route identity/disposal; a callback from an already removed route cannot revive permission. It does not establish readiness for arbitrarily deferred future descendants; those follow normal Flutter dynamic policy semantics.

The persistent child is wrapped in `Offstage`, `TickerMode`, `ExcludeSemantics`, `IgnorePointer`, and focus eligibility controls keyed by `_revealed`. Offstage alone does not stop focus acquisition, tickers, build side effects, or layout. The wrapper must explicitly prevent hidden autofocus/traversal, then permit the existing visible focus behavior at measured reveal. Neither focus nor semantics is proved by a screenshot. The route's own `requestFocus` remains false until reveal.

A dismissal attempt publishes its completer before any await, waits for initial readiness, rechecks `_isLive`, then calls SDK `super.willPop` and the current `popDisposition`. The existing single successful claim remains necessary for concurrent SDK callers and local history. No model close occurs until approval, and delayed close uses the current sampled model state. Once readiness is complete and there is no legacy async guard, retain the measured synchronous admission path; eager mount must not turn every normal close into an async deadline.

Waiting must be cancellable **without waiting for readiness**. `_invalidateDismissal` completes the attempt's permission immediately; a resolver that remains suspended on the one-shot readiness future is harmless but should be released on disposal to avoid retaining its stack indefinitely. Completing the readiness future on disposal is only a wakeup; the subsequent `_isLive` check prevents treating disposal as mounted policy. Cover, replace, remove, handback, programmatic pop, and Navigator unmount invalidate the attempt. Cover then uncover never reuses an old attempt. A reentrant guard sees the already published attempt. Source-only loss does not invalidate the independently live route.

Model deadline requests before readiness also create a pending attempt and return false to the existing synchronous admission hook. They cannot use an empty `popDisposition` as permission. Coarse first frames therefore cannot close before content policy registers. The existing after-advance drain consumes approved model work from the current state; the model/timeline are not changed. This deliberately adds a deferred path for pre-readiness deadlines, not a claim that their original synchronous close time is preserved.

For hidden *pointer preparation* specifically, choose cancellation of the reservation as the early `maybePop` contract: if measured opening has not occurred, cancel the hidden route without pretending a future builder policy vetoed. Once opening is committed, use mounted policy. This must be a separate documented internal disposition branch, not a forged SDK `PopScope` answer. Eager mounting makes policies exist earlier but does not logically require giving a never-presented menu authority over cancelling its reservation. Command mode is already revealed and therefore always waits for policy. This rule preserves the intended early cancellation semantics but **cannot restore zero builds when a hidden route had a frame**.

Interface depth is strong: consumers specify one ordinary builder and ordinary SDK scopes; the route hides readiness, cancellation, focus gating, and transaction lifetime. Internal implementation is heavier than a revealed-mount latch because it must contain arbitrary already-mounted application side effects. Per single-source-of-truth, `_revealed` still owns presentation and the one readiness completer only owns initial policy existence; no duplicated `mountedPolicy` flags are needed.

## Observable lifecycle and narrow additional proof

Early push remains real: root observers receive push immediately, root home is non-current, popup is current, and a nested local page remains current in its own Navigator. A cancelled reservation produces a real root push/pop pair. `RouteObserver<ModalRoute>` covers/uncover events are expected; `RouteObserver<PageRoute>` filtering follows SDK types. No observer suppression or `isCurrent` override is proposed.

The narrow nested proof should send real down/move/up through a nested source, assert root and nested observer/currentness separately, confirm menu reveal and eventual root pop, and compare the actual pointer sample stream. It must not infer this from command-mode `open`. Existing full-screen geometry proves no transformed coordinate conversion.

Hidden primary focus retention and disabled hidden content autofocus need explicit checks. After reveal, menu focus and Escape should resolve in the root modal subtree. Before reveal, source focus remains in the nested subtree: ordinary nearest-Navigator actions can target that nested Navigator. This candidate does not claim to reroute such actions globally. System Back/Router/BackButtonDispatcher arrangements remain open unless separately exercised.

For covered global input, a bounded settled-open proof can establish that an unrelated down/move/up delivered to a covering route does not mutate the covered menu. Gate new pointer acquisition on `activeRoute.isCurrent`. Do not conflate this with a held pointer interrupted by cover: swallowing the real up can leave model state armed, while forwarding a real up may select underneath the cover. That requires an explicit ownership-loss cancellation seam (using the existing pure model's cancellation operation through a prototype-only adapter), not forged binding events. If that seam is outside this narrow increment, retain the interrupted-held case as OPEN. Gate-at-down alone must not be reported as complete covered-input correctness.

## Tradeoffs accepted

- We accept hidden builder execution, mount/dispose side effects and layout in exchange for policy availability on the initial route frame.
- We accept stronger hidden focus/ticker/semantics containment in exchange for separating policy existence from visible presentation.
- We accept an initial-frame wait for immediate command-mode `maybePop` in exchange for never calling SDK scope policy before mount.
- We accept the existing early root observer/currentness contract in exchange for preserving real held-pointer delivery.
- We retain the known post-issued-SDK-success window: an answer already returned to Navigator cannot be revoked atomically by this route wrapper.

## Alternatives considered

1. **Keep deferred content plus revealed-subtree readiness:** preserves cancelled-pre-hold zero builds and measured content timing; internally needs a readiness signal tied to the actual reveal subtree. It is the stronger choice under the present contract despite a later policy registration boundary.
2. **Source-owned input reservation, late root push:** would give cleaner observer timing, but the naive form is disproved by real down→cancel and lost move/up. A global pointer route cannot reconstruct a removed binding hit-test path for other recognizers. Solving it with synthetic input or custom gesture routing changes semantics and exceeds this increment.
3. **Separate eager policy-only tree:** arbitrary builder policy cannot be extracted without executing its content. Mounting a duplicate tree in source context creates wrong `ModalRoute` registrations, duplicate application state and two policy owners; poor interface depth and split ownership.
4. **Public `canDismiss`/guard or `prepare` API:** exposes framework lifecycle coordination to applications and duplicates normal Flutter widget policy. It violates the no-public-burden scope and is unnecessary for the deferred-mount solution.

## Red-flag screen

No public stages or pass-through modules are added; policy and transaction state stay route-owned; readiness is one-shot rather than a hand-synced set of flags; callers have one builder path. The primary red flag is temporal decomposition through hidden mount/presentation wrappers and application effects that cannot be contained by widgets. This is a substantive cost, not just more implementation lines. Combined with the zero-build regression, it prevents adoption under current constraints.

## Synthesis decision

Candidate B recommends eager mounting only for a consciously changed product contract. For the current brief, select the other whole shape if it preserves deferred content and solves policy readiness without exposing a public staging API. A useful graft from B is to distinguish installed route, actual policy subtree readiness, and presentation focus instead of using one ambiguous mounted flag.

## Open questions and risks

- Would the owner ever accept hidden builder side effects on a cancelled press as a deliberate product contract change? Current evidence says no; no approval is presumed.
- Does a future device/native comparison require a different observer/currentness timing than this early root route can honestly deliver?
- Should an already-held pointer be cancelled on cover, and which prototype adapter should own that cancellation without changing production motion APIs?

## Next implementation step

Do not implement eager mounting under the current acceptance contract; preserve this alternative and implement the deferred revealed-subtree readiness candidate, then run the existing zero-build cancel and strict replay evidence unchanged.

Evidence consulted: supplied ground/how/why artifacts, current route/transfer source, four new lifecycle tests and their recorded before log. No tests, agents, repository writes or implementation were performed by this candidate. Same inherited model as the other candidate; this is independent design exploration, not different-model consensus.
