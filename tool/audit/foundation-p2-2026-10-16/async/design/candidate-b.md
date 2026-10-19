# Candidate B: yield at the dismissal boundary, let the route own permission

## Problem

The current boolean callback conflates a measured model deadline, SDK navigation permission, and permission to mutate closing channels. It works synchronously because `_requestClose(deadline)` runs before the frame's final sample. Replacing its return type with a future cannot preserve that ordering: once the open model has advanced beyond the deadline, a close at that old timestamp mixes past analytic progress with present integrated kicks. The chosen shape makes the synchronous boundary explicit and makes an asynchronous request a route-owned operation rather than a suspended model.

## Usage, written first

The application continues using Flutter navigation policy. There is no new public async-guard API or app setup:

```dart
ProbeMenuSource(
  pointerInput: true,
  menuBuilder: (context) => PopScope(
    canPop: editorIsSaved,
    child: const MenuContent(),
  ),
);
```

The deprecated SDK compatibility case is deliberately tested, not advertised as the preferred application API:

```dart
menuBuilder: (context) => WillPopScope(
  onWillPop: () => saveConfirmation.future,
  child: const MenuContent(),
)
```

Inside the session, one driver owns all model mutations. Its callers submit an input or sample and publish only the finished step; they never coordinate permission futures:

```dart
void handlePointer(PointerEvent event) {
  final owner = currentOwner;
  final localTime = owner.clock.stamp(event);
  driver.input(owner.lease, localTime, event);
  publishFrame();
}

ProbeFrameOutcome onFrame(double localTime) {
  driver.advance(route.lease, localTime);
  publishFrame();
  return schedulingOutcome();
}
```

The route supplies the SDK boundary. Actual successful route pop is the commit point, including when an awaited guard eventually accepts:

```dart
bool didPop(void result) {
  if (!super.didPop(result)) return false; // Local history consumed the pop.
  session.driver.routeDidPop(this);
  return true;
}
```

## Shape

### Data first

```dart
/// One ephemeral boundary. The model consumes it exactly once.
final class MenuDismissRequest {
  MenuDismissRequest._(this.requestedAt, this._generation);
  final double requestedAt;
  final int _generation;
}

enum MenuDismissDisposition { close, retain }

/// Prototype only; this becomes one member of typed E in unit 2.4.
final class MenuDismissEffect {
  MenuDismissEffect._(this.request);
  final MenuDismissRequest request;
}

/// An unresolved SDK operation belongs to one route, never to the model.
final class _PendingDismiss {
  _PendingDismiss(this.requestedAt, this.epoch, this.lease);
  final double requestedAt;
  final int epoch;
  final ProbeMenuLease lease;
}

/// Route-owned state; no session-wide map or second model owner.
int _permissionEpoch = 0;
_PendingDismiss? _pendingDismiss;
bool _policyReady = false;
MenuDismissRequest? _committingRequest;
```

Route identity is encoded by the route owning `_PendingDismiss`; lease identity prevents using permission after ownership transfer. An epoch invalidates cover/uncover, replacement, actual pop and disposal, including a route that becomes current again. Source removal does not invalidate an otherwise living route: that preserves the existing source-independent route policy. Duplicate dismiss inputs while pending coalesce; they do not call the same application guard again. Selection actions remain independent and can still execute while dismissal permission is pending.

### Narrow model boundary

```dart
/// Runs events without sampling beyond the first host-controlled dismissal.
/// True means the target was fully sampled; false means drainEffects has work.
bool morphMenuAdvanceUntilEffect(MorphMenuMotion motion, double target);

/// Moves effect ownership to the caller. No application callbacks run here.
List<MenuDismissEffect> morphMenuDrainEffects(MorphMenuMotion motion);

/// Consumes an effect at its original boundary before further integration.
/// retain means continue opening; it does not store a permission future.
void morphMenuResolveDismiss(
  MorphMenuMotion motion,
  MenuDismissRequest request,
  MenuDismissDisposition disposition,
);
```

All remain internal and unexported. Replace the current boolean admission installer rather than supporting two ways to dismiss. The model stores at most one blocked effect and its generation. The timeline gains an internal `runDueUntil(target, shouldYield)` variant that stops immediately after the effect-producing action, preserving equal-deadline insertion order, and does **not** move its clock to the final target when it stops. The model does not call `_sample(target)` on that return. Resolving `close` invokes the existing private `_close(request.requestedAt)` once. Resolving `retain` invokes no closing code. Resume the same target afterward.

Crucially, do not sample at the effect boundary merely to expose a frame: this would add a driven-kick integration point that existing replays did not contain. The host must not publish or paint a suspended step. This is a synchronous borrow of the writer, not a physically visible freeze.

The driver first drains any scheduled boundaries up to an input timestamp, then calls the existing pointer method. Thus an internal `pointerUp -> advance(t)` sees no earlier queued host boundary. An effect produced immediately by that input has `requestedAt == current timeline time`, so resolving it immediately after the input does not backdate. An implementation must verify these assumptions for `_takeEarlyTouch`, selection and pointer-outside paths; if any path mutates past an unresolved effect within one operation, move that path to the same boundary protocol rather than allowing arbitrary resumable pointer stacks.

The original autonomous `advance` behavior is retained only for models with no host protocol attached, preserving all ordinary package tests. This is an explicit unit-0 exception to the previous narrower admission seam: the prototype now needs a resumable timeline/model boundary. It is not a new public API. Unit 2.4 subsumes it into typed E/drainEvents and removes both prototype installer forms.

### Driver and route signatures

```dart
final class _MenuDriver {
  void advance(ProbeMenuLease owner, double localTime);
  void input(ProbeMenuLease owner, double localTime, PointerEvent event);
  void routeDidPop(ProbeMenuRoute route);
  void permissionCompleted(ProbeMenuRoute route, _PendingDismiss pending);
}

// On ProbeMenuRoute; modern policy stays synchronous.
void _requestDismiss(MenuDismissRequest request);
void _finishPermission(_PendingDismiss pending, RoutePopDisposition result);
void _invalidatePermission();

```

The driver owns the synchronous advance/drain/resolve loop and the reentrancy queue. This is the only writer boundary. Existing transfer lease validation remains authoritative. Reentrant application callbacks enqueue driver operations until the outer model step ends; they do not reenter an integrating or suspended model. SDK navigation itself remains synchronous. `didPop` may resolve the exact currently committing boundary because the model traversal has returned, not while `_requestClose` is integrating.

`_requestDismiss` handles three complete cases:

1. **Modern policy ready, no scoped async guard:** inspect current route eligibility and `popDisposition`, outside model integration. For `doNotPop`, consume `retain` before notifying `onPopInvokedWithResult(false, null)`. For `bubble`, consume `retain`; do not pop an ancestor merely because this menu requested dismissal. For `pop`, mark the request as the current synchronous commit, consume local history through ordinary `navigator.pop`, and let a successful route `didPop` resolve `close` at `requestedAt`. If local history consumes the pop, clear the mark and resolve `retain`. Then resume the target sample. No future or extra sample is introduced, so accepted synchronous replay is unchanged.
2. **Registered deprecated scoped guard:** consume `retain` and resume the model immediately. Create one `_PendingDismiss`, invoke route `willPop()` outside integration, and await it. The menu remains open and interactive. Resolve exceptions as denial, report the error once through Flutter's normal error reporting, clear the pending operation, and permit retry. Do not silently accept a throwing guard.
3. **Content policy not ready:** consume `retain`, resume, and hold one route-owned pending operation. After the revealed subtree's first build and post-frame registration barrier, run the same current policy/guard path. This is an asynchronous acceptance path even if its eventual modern check is synchronous; its original request timestamp is provenance. Do not call it the measured synchronous path. A source/menu hidden before reveal does not get built just to ask policy.

Policy readiness is a stricter prototype policy, not an SDK guarantee: Flutter cannot consult a guard in an unbuilt descendant. In this candidate, a revealed subtree gets one complete build before model-initiated dismissal is approved; use one route-owned post-frame barrier, not the menu builder invocation alone. Hidden content is never mounted merely to discover hypothetical guards. The completion checks route lifetime before touching anything. Later registration changes follow Flutter: reread current `popDisposition` before pop, and existing `willPop()` uses its SDK callback snapshot. This does not claim to discover guards that never mounted or to rerun newly registered async callbacks automatically.

### Async completion and causal time

After `willPop()` resolves, require all of: same pending object, same permission epoch, route mounted and not closing, route still current, session's active route identical, transfer lease identical. Reread `popDisposition`, not just the earlier async result. If either denies or bubbles, notify refusal as appropriate and clear. A covered/replaced/disposed operation is cancelled without navigation or refusal callbacks to detached content. Local history is reread immediately before `navigator.pop`: an entry added during await must consume the pop and retain the open model.

For an eligible acceptance, the continuation enqueues one owner command and wakes the owner clock. At the next ordinary writer step, sample using that clock's own local time and mapping, revalidate eligibility, then `navigator.pop` commits a current-state close in `didPop`. If another close is already pending/committed during this sampling, discard the completion. The pending object identity also de-duplicates this queued command. No past request is passed to public `close(t)`, and no wall-clock duration is pasted onto model time.

Three times have different meanings:

- `requestedAt`: original measured dismissal deadline, immutable.
- `acceptedAt`: canonical time of the owner writer step that consumes the accepted decision. The raw future-completion timestamp may be logged separately but is not motion time.
- `closeStartedAt`: actual close mutation time. Equals `requestedAt` for the synchronous boundary path; equals current sampled `acceptedAt` for the async path, and never precedes the model's sampled time.

The current clock pauses ordinary settled motion time. Keep that policy in this proof: a ten-second wall-clock wait does not imply a ten-second canonical jump. Async acceptance starts at the current owner sample, even if its canonical value remained fixed during settled idle. While opening/interaction are live, those owner samples continue and acceptedAt advances accordingly. Existing doze/dilation behavior also remains authoritative. A later switch to continuously elapsed settled time would be a separate clock-policy change, not a dismissal fix.

Programmatic `Navigator.pop` bypasses `willPop`/PopScope by SDK design. On actual successful `didPop`, invalidate any outstanding permission and close from the current owner's sampled time, preserving existing command policy. Local history still wins before `routeDidPop` is called. Double completion, a callback that already popped its own route, and late guard completion then become no-ops.

## Module map and depth

- `lib/src/motion/timeline.dart`: deadline-preserving yield, no SDK knowledge.
- `lib/src/widgets/menu_motion.dart`: close-request effect and resolve at a monotonic integration boundary, no futures or route types.
- `example/lib/proto/menu_route_probe.dart`: one driver plus route-owned permission state; all SDK policy and race handling live together.

Transfer retains geometry/lease/time-offset ownership. Do not create a separate public permission coordinator or routing facade. A caller needs only `driver.input`/`advance`; the complexity hidden is the complete permission lifecycle and exact sampled-time scheduling. The three-file route/model/timeline trace is the unavoidable knowledge boundary, and existing clocks remain the only source of canonical sample time.

## Alternatives considered

1. **Tri-state synchronous callback plus queued async actor.** It is the smallest patch: allow/deny/defer at the current `_requestClose` callback, route-owned pending future for defer. It can preserve today's synchronous replay. It loses because modern policy still executes under model integration and typed E migration later has to invent a resumable boundary anyway. Its shallow callback exposes the integrator's timing constraint to SDK code. Choose it only if the scope is explicitly limited to retaining a temporary callback and proving deprecated SDK compatibility; do not present it as the target protocol.
2. **Always emit close event and resolve after the frame.** This has a very small model surface and no resumable timeline. It loses exact synchronous fidelity: by the time the host sees the event, the model has already sampled beyond its deadline. Backdating is invalid; moving all close starts to the next frame changes measured behavior. This is a real simpler shape, but violates the current core requirement.
3. **Freeze the model until async permission returns.** The future can then resolve the original boundary without driven integration advancing, but displayed opening/input also freezes. It accepts an unbounded visible stall to hide a historical timestamp. Reject this as product behavior and as an API burden on pointer/lifecycle handling.

The selected yield protocol has more internal work than the tri-state patch, but it removes the callback-into-model problem structurally and supplies the exact boundary typed E/drainEvents will require. It should be rejected if the P2 scope cannot accept this small timeline/model extension; do not imitate it by rewinding state.

## Tradeoffs accepted

- We accept a later real close after async acceptance in exchange for live, causal opening and interaction. The plan's unconditional “original reaction time” must be rewritten to distinguish synchronous fidelity from asynchronous provenance.
- We accept a broader internal unit-0 seam in exchange for not cloning the model or preserving an integrating application callback as architecture.
- We accept cancellation on cover/uncover in exchange for never applying stale approval after presentation eligibility changed. This is stricter than SDK `maybePop` and must be documented as prototype policy.
- We accept deprecated `willPop` inspection only to prove existing Flutter compatibility; no new library public async guard is added.

## Falsifiable verification

1. Existing 20 recorded raw-input replays remain exact, including kicks and close deadlines at 60/120 Hz. Add an explicit coarse-frame deadline test that would fail if the yield adds a `_sample(requestedAt)` on rejection or samples the final target before synchronous acceptance.
2. `PopScope(false)` and local-history consumption retain open phase and all closing channels. A selected action still fires independently. Multiple equal-time scheduled actions retain original insertion ordering.
3. A `Completer<bool>` scoped guard is invoked exactly once for repeated outside taps while pending; progress/input keep updating; false retains; true closes from approval-time current state. Compare against a control model opening until acceptance and then closing at that exact current timestamp, not against immediate-close history.
4. Time record asserts `requestedAt <= acceptedAt == closeStartedAt` for a delayed approval, with strict inequality only when owner motion time actually advanced, plus the existing negative backdated-kick reproduction remains evidence. For modern ready sync acceptance, assert `requestedAt == closeStartedAt` with no future turn.
5. Pending then replace, force-remove, cover/uncover, dispose Navigator, explicit pop, source removal: only source removal keeps a living route eligible; all other stale completions are harmless. Test completion twice and application callback initiating navigation.
6. Add local history during await: one pop consumes history and leaves the menu open. Remove history during await: successful pop then closes. A PopScope toggled to false during await vetoes the final close.
7. A guard throwing reports once, does not close, clears pending and permits a later request. A guard registering during first revealed content build participates in the decision.
8. Approval after 10-second fully settled idle follows existing paused canonical-time policy without backdating below latest sample; cover 1x/5x dilation and doze versus ordinary idle. No extra ticking while just waiting on a future.

## Open questions and limits

- Is unit 0 allowed this explicit resumable timeline seam? The current bool-only seam cannot become the chosen typed-event structure without it; this is the synthesis decision to record, not an implicit implementation detail.
- This does not prove system predictive-back behavior or native optics, and SDK `WillPopScope` is deprecated. Public production API choice remains a later unit.
- Existing model action callbacks are still legacy synchronous callbacks; converting all model events belongs to unit 2.4. This protocol removes new permission callbacks from integration without falsely claiming every callback is already pure.

## Synthesis decision

Independent candidate B recommends the yield/route-owned-permission shape. No cross-candidate synthesis has been performed by this runner.

## Next implementation step

Build the pure timeline/model yield test first, preserving exact old sampling order on allow/retain, then attach the route-owned SDK permission path and run the existing failing async guard reproduction.
