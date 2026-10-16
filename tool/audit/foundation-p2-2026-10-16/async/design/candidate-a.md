# Candidate A: route-owned dismissal transaction

## Problem

The model can request dismissal at a measured subframe deadline, but the route decides whether dismissal is permitted. A real asynchronous guard cannot approve a physical close in the past after opening/kicks have continued. Preserve exact synchronous acceptance inside the existing timeline; represent a delayed approval as a fresh command from the current state. Keep the entire asynchronous transaction in the prototype route rather than expanding the production bool seam into a callback family.

Grounding: `/tmp/morph-p2-async-design/{ground.md,how/findings.md,why/findings.md}`; checked current route, transfer, clock, model/timeline and local Flutter 3.47.2 SDK. No implementation, heavy jobs, devices or repository edits were performed for this candidate.

## Usage (caller's view)

The application continues using Flutter navigation policy. There is no new public `onCanDismiss`, gate, clock, request object or integration widget to configure.

```dart
ProbeMenuSource(
  pointerInput: true,
  menuBuilder: (_) => PopScope<void>(
    canPop: canDismiss,
    onPopInvokedWithResult: (didPop, _) => recordAttempt(didPop),
    child: menu,
  ),
)
```

That synchronous policy keeps the existing measured close deadline. Rejection leaves the model open. Selection actions are independent and are not undone.

```dart
ProbeMenuSource(
  pointerInput: true,
  menuBuilder: (_) => WillPopScope(
    onWillPop: () => askPermission(),
    child: menu,
  ),
)
```

`WillPopScope` is deprecated SDK compatibility evidence, not a recommended new product API. Outside dismissal waits for this callback while the same opening model and interaction remain live. A true result starts closing from the current state; false or error does not close. Repeated outside requests share the pending attempt.

```dart
Navigator.of(menuContext).pop();
```

Explicit programmatic pop keeps SDK semantics, including bypassing permission and consuming local history before closing. It invalidates an outstanding asynchronous attempt. Back/Escape calling `maybePop` share the route's SDK permission future; `didPop` remains the only logical-pop commit point.

## Shape

The route owns its pending dismissal transaction, permission future and navigation epoch. The session continues owning the single model/lease/clock; it installs the existing bool adapter and drains queued route work immediately after each model input/advance. No application callback runs during model integration. Only the route can pop itself; it never asks a future continuation to pop an unspecified current route.

### Types and signatures

These are private prototype declarations in `example/lib/proto/menu_route_probe.dart`, not proposed package public API. All timestamps below are canonical model seconds unless explicitly called local.

```dart
enum _DismissKind { synchronous, pendingPermission, pendingFirstBuild }

final class _DismissAttempt {
  _DismissAttempt({
    required this.requestedAt,
    required this.epoch,
    required this.lease,
    required this.kind,
  });

  final double requestedAt;
  final int epoch;
  final ProbeMenuLease lease;
  final _DismissKind kind;
}

final class _ApprovedPop {
  _ApprovedPop({required this.attempt, required this.closeLocalTime});
  final _DismissAttempt attempt;
  final double closeLocalTime;
}

class ProbeMenuRoute extends PopupRoute<void> {
  int _navigationEpoch = 0;
  bool _policyReady = false;
  _DismissAttempt? _pendingDismissal;
  Future<RoutePopDisposition>? _permission;
  _ApprovedPop? _approvedPop;

  // Pure SDK/model observations and allocation only. Called by the bool seam.
  // Queues a single attempt; false means no closing channels may change.
  bool _admitMotionClose(double requestedAt) => throw UnimplementedError();

  // Called outside model advance/input and before publishing that frame.
  // Synchronous accepted motion is already closing; deferred attempts ask SDK.
  void _drainDismissal() => throw UnimplementedError();

  // Checks this exact pending attempt, lease, epoch, navigator attachment,
  // route currentness and nonclosing/non-disposed state before any continuation.
  bool _isLive(_DismissAttempt attempt) => throw UnimplementedError();

  Future<void> _finishDeferred(_DismissAttempt attempt) =>
      throw UnimplementedError();

  // One permission future for model requests and SDK maybePop on this epoch.
  // Calls super.willPop outside integration, captures the epoch and revalidates.
  // Deprecated override exists solely to cover the real deprecated SDK boundary.
  @override
  Future<RoutePopDisposition> willPop() => throw UnimplementedError();

  // Actual SDK local-history result is authoritative. Only true starts motion.
  @override
  bool didPop(void result) => throw UnimplementedError();

  // Invalidate before relinquish/dispose and actual successful pop. didChangeNext
  // invalidates when the next-route identity changes; cover then uncover is stale.
  void _invalidateDismissal() => throw UnimplementedError();
}

class ProbeMotionClock {
  // Fresh non-pointer local command stamp, monotonic, including ordinary idle.
  // Uses an engine timestamp/time anchor and timeDilation, wakes the ticker,
  // advances the clock floor, and does not invoke onFrame or sample the model.
  double stampCommand() => throw UnimplementedError();
}
```

The exact fields may use records instead of tiny classes, provided synchronous versus deferred is explicit and there is one pending identity, not separate unsynchronized lists. `_ApprovedPop` is only the dynamic extent of one validated SDK pop; it is cleared with `finally`. It provides `didPop` a current command timestamp without having the gate mutate the model first. `didPop` closes only after `super.didPop` returns true. An attempt whose SDK pop consumed local history therefore never starts closing.

### Access patterns

1. **Measured synchronous dismissal:** model `_requestClose(deadline)` calls the existing non-mutating bool seam. Route ready, current, no scoped async callback, no outstanding request: inspect `popDisposition` and `willHandlePopInternally`; queue an immediate attempt. Return true only for disposition pop and no local history. Model closes inside its existing timeline at exactly `deadline`. After integration, route drain validates the same identity and issues the SDK pop. Rejected `PopScope` gets the existing SDK refusal notification outside integration. Local history receives an SDK pop, but admission returned false, so its consumption leaves the model open.
2. **Deferred dismissal:** async callback present or initial content policy not ready: queue one attempt and return false. Drain starts `willPop()` once (or waits for readiness). Keep the model and clocks operating normally; additional model close requests return false and coalesce into that attempt. When permission resolves, validate identity/epoch/lease/currentness again, reread `popDisposition` and `willHandlePopInternally`, then use a fresh `stampCommand()` and issue the validated pop. The model closes from that fresh time only if SDK `didPop` succeeds. A denial, bubble, exception or stale attempt clears the pending identity without closing. A later user request may retry.
3. **SDK Back/Escape/maybePop:** the route override caches a permission future for its current epoch and validates the epoch after await. If model dismissal is already asking SDK, SDK callers share the same future instead of invoking the guard again. Both continuations can wake; the first successful SDK pop synchronously makes the route closing and invalidates the attempt, so the other continuation cannot pop a second route. SDK `maybePop` performs its own top-entry recheck as well.
4. **Explicit SDK pop:** `didPop` executes local history first. Actual route pop invalidates pending approval, chooses the current `stampCommand()` when no immediate measured close already occurred, then closes the model as an unconditional command. Direct programmatic pop intentionally bypasses `PopScope`/WillPopScope. Local-history consumption leaves an outstanding permission attempt valid only if still on the same epoch; its eventual completion rereads local-history presence. Alternatively invalidating on any `didPop` attempt is a defensible stricter policy, but choose one and test it; I recommend invalidate even when local history consumes a programmatic pop, to prevent an old user request closing immediately after a separate command consumed history.

This has a short trace: model adapter -> route transaction -> SDK/model command. Route-specific permission knowledge remains in the route; physics does not import Flutter navigation. Per boundary-discipline, raw SDK lifetime checks happen at continuation boundaries. Per make-operations-idempotent, pending identity plus successful-pop invalidation makes duplicate completion inert. Per single-source-of-truth, route fields own transaction lifetime while the transfer lease remains the sole model-writer authority.

### Time semantics

`requestedAt` is immutable provenance: the model's measured reaction deadline. For immediate acceptance, `acceptedAt == closeStartedAt == requestedAt` in the logical timeline; integration has not yet published the later frame, and this is the existing replay semantics. Real wall-clock decision delivery can be later than that logical deadline; do not claim zero event-delivery latency.

For an actual asynchronous boundary or first-build deferral, `acceptedAt` is the fresh canonical command time sampled after approval and all lifetime/policy checks. `closeStartedAt == acceptedAt >= lastPublishedModelTime`; `requestedAt` is never passed to `close` after awaiting. A false result has no close start. Approval does not add the original dismissal delay again, since that delay already preceded the request. One timestamp field cannot faithfully represent both meanings.

`stampCommand()` needs a genuine engine/local anchor even after ordinary settled idle, not `clock.time` plus `resumeAt(now)` alone. Update the clock's anchor at its actual sampled frame and transfer/resume boundaries, then map elapsed raw engine time using unchanged `timeDilation`, with a monotonic floor. Calling it wakes the ticker and raises its floor so the next tick cannot be older than the just-issued close. It must not fake a PointerEvent or use the input fallback's +one-frame lead. Cover running, settled and dozing clocks at 1x/5x; active dilation changes remain a separately named gap unless implemented and proved.

### First-build registration

The hidden early route has no content policy yet. A small private wrapper around the actual revealed menu subtree signals ready in a post-frame callback after descendants have mounted and registered `PopScope`/WillPopScope. Before then, model dismissal returns false and queues `pendingFirstBuild`; navigation must not assume absent policy means permission. On readiness, process that same attempt as deferred using current time, even when the eventual policy is synchronous. This is not permission to instantiate content early or take focus early.

This adds one deliberate causal distinction for a request before first policy registration. Existing measured replay tests must still pass unchanged. If a fixture relies on closing before the first content build, the architecture has exposed a real incompatible requirement: it cannot both inspect an unbuilt descendant's policy and promise an earlier close. Do not adjust fixtures/tolerances or falsely label this exact sync fidelity. Escalate that specific result into a plan refinement with evidence.

### Lifecycle and SDK policy table

| Event while pending | Decision |
| --- | --- |
| Additional outside request / second selected action | Share permission attempt; actions remain independent. |
| Permission false | Keep opening/live model; clear attempt; later request retries. |
| Guard throws | Fail closed; clear attempt; report through FlutterError, no unhandled future. |
| Modern PopScope changes while awaiting | Reread current disposition after await. |
| Scoped async callbacks register/unregister during await | Match SDK callback-list snapshot semantics; no new custom recursive reconsult cycle. |
| Cover then uncover | Navigation epoch invalidates old attempt even if isCurrent is true again. New user request may retry. |
| Replacement, route removal, relinquishment, disposal, whole Navigator disposal | Invalidate; late completion cannot touch clock/model/navigation or notify disposed descendants. |
| Source widget disappears but route remains current | Attempt stays valid; source existence is not route permission. Close route normally, finish without hand-back. |
| Programmatic pop | SDK decides local history; invalidate old attempt; successful pop closes unconditionally. |
| Local history added while waiting | SDK pop consumes history; keep motion open. |
| Async permission doNotPop | Mirror deprecated SDK behavior; do not invent an additional modern PopScope false notification. |
| Async true then modern popDisposition doNotPop | Notify onPopInvokedWithResult(false, null), outside model integration. |
| Async bubble | Do not pop menu; return/record unhandled for SDK caller, preserve model. Popup route normally cannot bubble as nonfirst route. |

The SDK itself rechecks only final history identity; epoch invalidation across temporary cover/uncover is an intentionally stricter prototype policy. Override `didChangeNext` with identity tracking and invalidate on actual next identity change, not blindly on every redundant notification. Cover that hook behavior with a real Navigator test. Invalidate before `_relinquish` and dispose, and on successful `didPop` before running a model command.

## Module map and P2 graft

- `example/lib/proto/menu_route_probe.dart`: one private transaction and its SDK compatibility code, post-first-build readiness wrapper, replacing the session's current `(route, admitted, time)` queue. The session may retain a minimal set of routes requiring drain, but there is one pending attempt owner; no duplicate per-session permission state.
- `example/lib/proto/motion_clock_probe.dart`: one fresh command stamp operation with anchored idle semantics. No animation sampling or Navigator knowledge.
- `example/lib/proto/menu_transfer_probe.dart`: retain unique lease checks and canonical offset. Add only an internal canonical-time observation helper if required by audit; do not expose writable model.
- `lib/src/widgets/menu_motion.dart`: existing `morphMenuSetCloseAdmission` bool seam remains unchanged. No Future or route lifetime object enters production. Update its explanatory contract only if needed to state false can mean host-deferred request, not permanent refusal.
- Prototype tests and audit report: add transaction observations in the existing sample stream or a dedicated test-only observer, so requested/accepted/started times can be asserted directly.

Unit 2.4 replaces the bool adapter with typed `DismissRequested(requestedAt)`/host resolution without changing this host transaction's caller contract. A future typed model must yield at request boundaries before final frame publication if it wants synchronous host resolution outside integration while retaining a measured subframe deadline. Merely draining an event after the model has sampled the whole frame and then backdating close is not an equivalent migration. That future stepping contract is outside this P2 graft; keep the provisional seam narrow and clearly scheduled for removal.

## Alternatives considered

1. **Full model suspension at every dismiss request, host resolves an explicit request event, model resumes the remaining frame.** This is the cleanest eventual typed-E model boundary: one `advance` can return a request checkpoint, allowing host policy outside integration before model time passes that deadline. It hides all timing inside the model driver but requires timeline pausing/resumption, pointer command continuation, scheduled action order and event draining to be redesigned now. Every current model caller would need driving rules or an adapter. Rejected for this P2 step because it turns a route-permission proof into premature unit 2.4 and expands the provisional production seam. Do not adopt half of it (event notification after final sample) and claim synchronous equality.
2. **Always use Navigator.maybePop for outside dismissal, and close only in didPop.** Excellent small caller surface and SDK hides permission/local-history decisions. It inserts an await even for no WillPopScope and starts synchronous measured closing at a later frame/command time. It also cannot guarantee the stronger cover/uncover invalidation without route epoch wrapping. Rejected because the measured sync replay requirement is load-bearing, not a performance preference.
3. **Freeze model/clock at request time until approval.** It avoids a past close and could resume from the deadline, but stops visible interaction and opening for an arbitrary application wait. Clock/owner semantics become dependent on permission latency and it does not preserve frames the user should have seen. Rejected against the live-model requirement.

Candidate A chooses the route transaction with the already-authorized bool shim because its callers need no additional API and the asynchronous complexity is fully removable with the prototype. This is a whole shape choice, not a request to add async branches to production motion.

## Tradeoffs accepted

- Accept a provisional synchronous model callback in exchange for unchanged measured replay and avoiding a model-driver rewrite in P2.
- Accept current-time closing for genuinely delayed approval in exchange for causal, continuous driven state without cloning, rollback or replay.
- Accept a small deprecated route override in prototype code in exchange for testing the real SDK async boundary without adding a product permissions API.
- Accept cancellation across cover/uncover in exchange for never letting an old interaction dismiss a newly resumed route automatically.
- Accept that a policy not yet mounted requires a delayed decision in exchange for actually respecting its eventual registration.

## Red-flag screen

No public shallow gate API: callers still use Flutter policy. No two mutable transaction owners: pending state moves from the session tuple list to the route. No callback family or navigation data added to model. No map/cache/index deferred until later: single pending identity and one cached SDK future cover dominant access patterns. There are intentionally two operations—unconditional programmatic pop and permission-seeking user dismissal—because SDK semantics require that distinction, not two interchangeable ways of solving one task. Private prototype declarations stay local to their library. The existing internal seam remains importable as an explicitly temporary unit-0 compromise, not claimed inaccessible; unit 2.4 must delete it.

## Rubric self-assessment

| Axis | Score / 3 | Reason |
| --- | --- | --- |
| Causal time / unchanged sync fidelity | 3 | Existing immediate timeline untouched; delayed close explicitly current-time. |
| Refusal / one writer | 3 | No close before permission; existing transfer lease owns model mutation. |
| SDK lifecycle / async races | 3 | Route epoch, identity, coalesced future, actual didPop and post-await policy checks. |
| Small API / removable seam | 2 | No public API, but bool seam and deprecated override remain until unit 2.4. |
| Falsifiable tests / feasibility | 3 | Local graft with explicit first-build compatibility gate and clock tests. |

## Required falsification tests

1. Existing failing real-binding WillPopScope reproduction becomes passing for false and true; opening/kick samples keep advancing during a 700 ms permission wait. True closes at fresh acceptance, not requestedAt, and no added dismissDelay.
2. Existing negative backdated-kick test stays passing as a negative control. Add current-time reference comparison through delayed approval at 60/120 Hz, during opening and settled idle, at 1x/5x.
3. Run all existing strict pointer replays without changed fixtures/tolerances. Compare synchronous accepted deadline, every frame, actions and hand-back—not just final progress.
4. False, throw, retry, repeated outside taps and simultaneous SDK maybePop: exactly one guard per pending epoch and no duplicate pop/refusal notifications.
5. Permission true after replacement, removal, dispose, relinquish, cover/uncover, whole Navigator teardown and explicit pop: no mutation of replacement/covering/source model and no stale callbacks. Source-only unmount while route stays alive remains valid and closes cleanly.
6. Local history existing initially and added during await; no motion close if SDK consumes it. Programmatic pop preserves bypass behavior and invalidates pending attempt even when history consumes it.
7. PopScope changes to false during async wait; refusal before close. Async guard registering/unregistering while waiting follows SDK snapshot behavior, documented rather than custom guessed policy.
8. First reveal builds PopScope(false) or WillPopScope before a queued early dismiss is decided. Pending hidden route retains prior content-build/focus behavior. Strict replay passing is an implementation gate; a failure is architectural evidence, not a tolerance adjustment.
9. Idle command timestamp reflects actual engine time; next frame never goes backward. Exercise doze and ordinary settled idle separately.

## Plan refinements and deferred gaps

Refine the plan's “approval preserves original reaction time”: preserve original measured deadline for synchronous acceptance; retain original requestedAt as provenance for async, while physical close begins causally at acceptedAt. These are distinct demonstrated guarantees. Also name readiness-delayed permission as asynchronous for this timing contract. This is a needed resolution of conflicting requirements, not silently satisfied prior wording.

Full-bar scene integration, nonflat glass/optics/device verification, first hidden-route observer/isCurrent effects, active timeDilation changes and the eventual typed-E stepping redesign remain deferred. The P2 async gate does not by itself complete P2 or choose the P1 driver. No native performance/parity claim follows from these host tests.

## Synthesis decision

To be filled by the parent arena judge. This candidate is independent and has not inspected another candidate.

## Next implementation step

Write the route-owned attempt state plus fresh clock command-stamp tests, then turn the existing WillPopScope reproduction positive before running unchanged strict replays.
