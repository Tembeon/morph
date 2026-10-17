# Candidate B: reserve navigation, defer motion acquisition

## Problem

A genuine source down during a logically popped `closingContent` presentation already starts the measured hold. Pushing its replacement at the eventual hold deadline lets Navigator cancel that same physical sequence. Moving the entire existing acquisition to down fixes the cancellation boundary but changes old presentation lifetime, suppresses its still-visible content and can erase first-zero hand-backs. Reserve the SDK entry on down while leaving the current complete model and old content under their existing owner until actual measured reversal. No public parameter, new model, timeline, clock adapter or generic overlay layer is needed.

## Usage (caller’s view)

Existing app usage is unchanged:

```dart
ProbeMenuSource(
  pointerInput: true,
  menuBuilder: (context) => MyMenu(
    controller: appOwnedController,
  ),
)
```

Scenario 1: source down while old content visibly closes. The leaf Listener delivers the real down once, then reserves a new hidden root PopupRoute before Navigator’s ancestor Listener sees that down. The old route continues sampling and painting. At the model’s existing hold deadline the reserved route acquires that same complete model and reveals one fresh menu tree. The physical move and up still select the intended row. Editor State is stable within each presentation; an externally owned controller may carry data into the new tree.

Scenario 2: the old route reaches first-zero before the hold deadline. The old route hands the complete model back to the source exactly as today. The hidden reservation survives without a sampler. Source sampling eventually observes the existing hold reaction and promotes the already-installed successor. No second push occurs and the old hand-back remains counted.

Scenario 3: cancel or cover before hold. The reservation never builds menu content or claims focus. Cancel revokes the exact physical sequence, retires the reserved SDK entry by identity and leaves the predecessor/source sampler to finish its press relaxation. An unrelated cover stays current. A committed tap-open delay retains its existing model semantics; cancellation of a held sequence alone must not erase already-committed release work.

Internal caller shape:

```dart
onPointerDown: (event) {
  final accepted = session.handleSourceDown(event); // genuine command once
  if (accepted != null && mounted) {
    session.prepareAtSourceDown(accepted, makeRoute: makeRootRoute);
  }
}

// Called from the existing owning clock after every accepted command/sample.
session.syncInputPhase(); // promote existing reservation or retire it
```

`handleSourceDown` may instead remain the existing `handlePointer` plus an exact sequence identity result; do not add two public input paths. The essential boundary is that preparation receives evidence of the same accepted down, rather than using geometry or a non-null route as authority.

## Shape

All changes stay in `example/lib/proto/menu_route_probe.dart`; the model, transfer and clock files stay byte-identical. Add one private relationship value, not another motion phase or second live-boolean protocol:

```dart
final class _ReopenReservation {
  _ReopenReservation({
    required this.route,
    required this.predecessor,
    required this.sequence,
  });

  final ProbeMenuRoute route;
  final ProbeMenuRoute predecessor;
  final _PointerSequence sequence;
}

class _MenuSession {
  _ReopenReservation? _reservation;

  // Existing activeRoute continues to mean the route holding the model.
  // transfer.owner remains the only authority for sampling/commanding it.
  ProbeMenuRoute? activeRoute;

  void prepareAtSourceDown(
    _PointerSequence accepted, {
    required ProbeMenuRoute Function() makeRoute,
  }); // not implemented

  void registerPushedRoute(ProbeMenuRoute route); // not implemented
  void promoteReservation(); // not implemented
  void retireReservation({required bool cancelOpening}); // not implemented

  bool retainsSourceSequence(_PointerSequence sequence); // not implemented
  bool isOwnReservedCover(ProbeMenuRoute owner, Route<Object?> next);
  // not implemented
}
```

The optional reservation means only one installed, hidden successor exists. Its predecessor identity is immutable provenance, not another owner. Do not store a nullable predecessor plus several hand-back flags: the predecessor may be disposed while its identity remains useful, and `transfer.owner` plus `activeRoute` already establish where sampling resides. After first-zero it is perfectly valid that `_reservation != null`, `activeRoute == null`, and the source lease owns the complete model.

### Source-down preparation

Validate the real event and current source ancestry at the current owner, then command it once. Only reserve if the accepted `_PointerSequence` is still identical after all synchronous observer callbacks, the source remains mounted/current, the old active route is still the same revealed closing presentation, and no reservation exists. Initial idle preparation keeps the existing acquisition behavior. A `closingPreparation` route remains sealed.

Create the successor with the existing builder/theme/source-root capture. Publish the exact `_ReopenReservation` relationship before `Navigator.push` can deliver route-change callbacks. The new route’s `didPush` registers it in `_routes` but does **not** call `acquire`, start its clock or open the model. It stays `_MenuStage.preparing`, requests no focus, builds no menu and exposes no route semantics. Its SDK animation/push future remains finite through promotion or retirement.

If route installation fails or a callback changes source/sequence/transfer authority, clear this exact reservation and retire only its route. Reentrant removal must not reset the current predecessor/source model: `routeDisposed` resets motion only if the disposed route actually owns it.

### Authority and modal safety

The global router remains transport. While reserved, continued move/up can belong to the existing sequence even though its own root popup now covers the source. Permit this only when all are true:

- `_reservation.route` is current, installed and not disposed/closing;
- its captured source root is still active;
- the sequence is exactly `_reservation.sequence` and the active owner is still this session’s predecessor or source;
- the whole source ancestry passes existing checks with only that captured active root exempted.

This is an exception for one already accepted sequence, not permission for arbitrary global downs. A newly covered nested page still fails. A removed-but-mounted source root fails through `isActive`. A second source cannot borrow this reservation.

An own-reservation next-route notification must not revoke its accepted sequence. Any other covering route does. The successor’s own `didChangeNext` must also revoke/retire the session reservation even though it does not yet equal `activeRoute`; the old `revokePointerFor` condition alone is insufficient. Under a cover, identity `removeRoute(reservation.route)` retires the hidden entry without popping the cover or closing/resetting the predecessor’s model.

### Sampling and promotion

The predecessor’s ordinary clock still advances the one model and paints its own lease. Consequently no outgoing-content borrowing, frozen frame, duplicate painting or retained render subtree protocol is needed. It reaches exactly the same old first-zero boundary and records exactly the same hand-back unless the real model reverses before that boundary, in which case hand-back was never due.

After each existing accepted command/sample, `syncInputPhase` examines the reservation before invoking `present`. If the transfer has actually become open, promote the installed current reservation. Map the present owner’s clock to the successor lease with the existing complete-model transfer, pause only that former sampler, set `activeRoute`, synchronously reveal the successor, then relinquish the predecessor if still alive. The owner’s `_sample` must recheck its lease after this call and stop publishing stale frames, as it does already.

Promotion and reveal are a synchronous operation before the next paint, never an awaited sequence. Ordinary Flutter build/paint then replaces the old closing page with the successor’s fresh page in the same rendering turn. Verify this with captured outgoing content pixels: if first-mount timing produces a real blank frame, the design is not complete and should be revised rather than excused. Until the actual reversal, old content definitely retains its original live route/lease and its old Flow remains paintable. At normal first-zero hand-back its removal follows the existing contract even if another channel still has a tail.

For old-route hand-back while reserved, `land` keeps its current exact transfer and `handBack` record, clears only model-owner `activeRoute`, and preserves `_reservation`. Do not transfer to the successor early merely because it exists. `sourceClock` now owns delayed hold/tap sampling. The later open promotes from that actual source clock; this uses the same transfer offset machinery and creates no new time origin.

### Retirement and dismissal

After a terminal event, no held sequence plus neither `isOpenPending` nor `isArming` means the hidden reservation is no longer needed. A slop-forfeited physical hold can remain reserved until its genuine terminal event, like existing idle preparation; it must not reveal just because a pointer exists. Cancel/cover/source detach retire without rebuilding or forcing a live model reset. The model owner continues its optical/press tail.

A reserved route’s `didPop` must distinguish “retire navigation reservation” from the existing “close owned presentation.” It invalidates its own dismissal request, stops its own push signal, dismisses its own projection and removes the relationship; it must not command the model using its unowned lease. SDK Back explicitly cancelling pending opening can dispatch the existing model close on the **actual** owner clock through a session operation, with pointer revocation and identity/reentrancy checks. This is a user close command; passive cover cancellation retains committed tap work exactly as the existing cancellation contract requires.

If the successor is forcibly removed before promotion, clear its reservation and revoke only the matching sequence. Leave the predecessor/source owner intact. If it is removed after promotion, the existing active-owner forced-removal contract applies. If the predecessor is forcibly removed while it still owns motion, cancel/retire the reservation before applying the existing active-owner reset; never let a reserved route later acquire an unrelated replacement model. If source detaches, clear its eligibility, revoke the sequence and retire the reservation; any remaining old route owns its already-existing tail until its ordinary cleanup. Every late callback checks exact reservation/transfer identity before publication.

### Semantic activation while reserved

The source’s accessible action may encounter its own hidden reservation while `activeRoute` still names the closing predecessor. Resolve the eligible hidden presentation as the exact reservation first; do not reject it merely because the motion owner is closing, and do not let any retained old route action activate it. Validate current reserved route plus the full source chain with its one active captured-root exception, then revoke the physical sequence and revalidate after the cancel observer. A callback that covers/removes source or reservation aborts activation.

Perform explicit semantic `open` on the **actual owning lease and owning clock**, then run the normal reservation promotion at `transfer.isOpen`. This reverses because the user explicitly activated, not because the route was installed. Do not transfer early just to satisfy the existing `activate(route)` precondition, and do not fabricate a pointer. Reserve retirement must run after the enclosing command/activation finishes, so its own pointer revocation cannot prematurely delete the route that this still-valid semantic activation is about to reveal. Hidden route dismiss semantics remain absent; SDK Back uses the explicit reservation-retirement path above.

### Content, policy and focus

Old content never becomes a source of successor admission. Keep the new builder lazy until promotion. Its first mounted fresh `_MountedMenuPolicy`, PopScope, local history and asynchronous permission own all new dismissals; first-mount admission stays gated as today. Old content remains semantically hidden and hit-inert during closing even though it still paints. Its retained semantic callbacks remain stale.

The reservation requests no focus. Logical close already released the old route’s focus. Actual successor reveal uses the existing route focus mechanism, after its own content/policy mounts; external controllers may retain data but do not establish State identity. Stable child identity within a presentation remains unchanged, so frames, themes and covers do not rerun the builder.

## Interface depth

One private preparation operation hides SDK reservation, exact accepted-sequence authority and deferred acquisition. App callers still provide only their builder and ordinary controller ownership. The existing transfer remains the sole module that translates ownership time. The extra private relationship carries unavoidable host knowledge once, per single-source-of-truth and boundary-discipline. No API exposes reservation stages or makes callers coordinate acquire/reveal/cleanup.

## Red-flag screen

The only new representation is the private relationship whose two identities define the intentional modal exception. `transfer.owner` continues to own sampling, `_MenuStage` continues to own each route’s semantic/content lifetime, and Navigator owns SDK currentness. No hand-synchronized list, duplicate model phase, public transport type, alternate physical input path, policy relay or generic render retention is introduced. The private retirement distinction is necessary because a reserved route has never owned the model; forcing it through ordinary owned-route close would be a false abstraction.

## Synthesis decision

Candidate only; parent synthesis chooses the base and any grafts. No sibling candidate was inspected. This is an independent inherited-model run, not cross-model consensus.

## Tradeoffs accepted

- We accept one explicit private predecessor/successor relationship in exchange for preserving old optical content and counted hand-back timing without moving/reparenting widgets.
- We accept a real hidden SDK entry during a held attempt in exchange for pushing before Navigator records the genuine down.
- We accept fresh route-local State on actual reopen in exchange for the agreed replacement contract and independent policy/focus registration.
- We accept retaining a slop-forfeited reservation until terminal input in exchange for deriving intent from existing sequence/model state rather than recreating measured hold timing.

## Alternatives considered

1. **Early acquire only.** Small diff, wrong abstraction: it makes route existence imply motion ownership, immediately dismisses the predecessor and prevents its leased Flow from drawing. It also changes historical hand-back counts. Reject even if sampled geometry matches.
2. **Early acquire plus old optical/content borrowing.** Could retain the old widget tree and make its Flow read the new owner’s frame until successor reveal. This needs a new paint-authority lifetime, must split old background painting from content, must define cancellation/forced removal and old disposal against the new owner, and still has to reconstruct the old first-zero hand-back semantics. It hides less complexity than reservation because the caller/session must coordinate three authorities instead of separating one SDK installation from one existing owner. Reject for this stage.
3. **Late push with global cancellation suppression or pointer replay.** Reject because it bypasses real SDK cancellation or invents physical events and still leaves modal/input authority ambiguous.
4. **Global-key content shuttle or retained common portal.** It changes the agreed fresh-content contract and introduces route-local policy/focus reparenting unrelated to this input failure. Reject.

## Open questions and risks

- Can genuine 60/120 Hz held traces before and after first-zero prove identical whole-model samples, zero SDK-induced cancellation and one final selected action?
- Does captured outgoing content remain present through the entire pre-reveal close, and does the successor mount in the first actual revealed paint without an empty content frame?
- Can source detach, removed source root, cover-from-observer and forced predecessor/successor removal all terminate without a stale reset, wrong-current pop or leaked ticker?
- Do existing replay totals remain 40 hand-backs and all 459 flat-scene frames remain unchanged? A count change rejects this shape’s implementation, even if visual geometry matches.
- Do new controller/State/build/focus and first-mount PopScope tests confirm the bounded fresh-presentation contract? Host evidence still cannot establish native assistive focus or IME fidelity.

These are verification gates, not reasons to request a new human checkpoint.

## Next implementation step

Reproduce the genuine held source down during visible closing, then install the identity-linked reservation without acquiring its lease, and make the existing sampler promote it only when the unchanged model actually opens.
