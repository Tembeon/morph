# Candidate A: reserve navigation, preserve the current sampler until opening

## Usage (caller's view)

The consumer API stays unchanged. A source still supplies one builder; a new actual presentation builds a fresh content tree. Physical input needs no reservation API.

```dart
ProbeMenuSource(
  button: buttonRect,
  bounds: screenSize,
  menuBuilder: (context) => MenuEditor(controller: externalController),
)
```

Two real paths establish the internal usage before the types:

1. A menu logically pops, its old editor and closing geometry remain visible, and the user presses and holds the actual source. The leaf source Listener first applies this genuine down to the existing model, then reserves one hidden successor PopupRoute before Navigator records that down. The old route continues sampling and painting. The measured hold deadline, not reservation, opens the model. That frame promotes the reserved successor, releases the predecessor, mounts one fresh editor/policy tree and requests focus through SDK route behavior. A subsequent real move and up select exactly once.
2. A source is pressed during a closing tail, but its closing progress crosses zero before the hold deadline. The predecessor hands the whole model back at the existing boundary and disposes normally. The already-installed hidden successor remains a navigation reservation; the source clock continues the same model. At the measured hold opening the successor acquires that model from the source. Its earlier push cannot cancel the still-held pointer because it happened on down. No fictitious predecessor hand-back is created or suppressed.
3. A hold is cancelled or a covering route arrives before it opens. Cancel revokes the physical sequence in the real current sampler. The exact hidden reservation is removed, not whichever route is now current. The old route/source keeps sampling the remaining press relaxation. A release that has already committed a delayed tap-open is a separate existing domain contract: retain that reservation for its opening, including under a cover, while SDK currentness prevents new input/focus authority there.

Internal call sites are deliberately small:

```dart
onPointerDown: (event) {
  session.handlePointer(event, sourceHit: true);
  if (session.acceptedSourceDown(event)) {
    preparePhysicalSuccessor(event);
  }
}

// Existing model sampling boundary, route clock or source clock.
void syncInputPhase() {
  drainExistingDismissals();
  if (transfer.isOpen) {
    promoteReservationIfPresent();
    revealCurrentOwnerOrPresentNormally();
  }
  retireAbandonedReservation();
  updatePendingBarrier();
}
```

`acceptedSourceDown` is not a new public method; it can remain an inline identity check at the existing Listener. `preparePhysicalSuccessor` owns admission and navigation as one operation; callers must not assemble a reservation in multiple steps.

## Problem

Pushing only when the held model opens loses the SDK physical sequence: Navigator already knows the pointer and cancels it on push. Transferring the model immediately on down would solve that cancellation but dismiss the predecessor's still-visible content and skip first-zero hand-backs. The route identity needed to reserve a navigation boundary is not yet the identity that should sample or render the motion. The smallest sufficient change is to represent that distinction explicitly inside the existing prototype session.

## Shape

All changes remain in `example/lib/proto/menu_route_probe.dart`. The model, timeline, transfer and clock files stay unchanged. No generic portal, cached motion frame or content reparenting is introduced.

```dart
final class _MenuReservation {
  _MenuReservation({
    required this.route,
    required this.transfer,
    required this.sequence,
  });

  final ProbeMenuRoute route;
  final ProbeMenuTransfer transfer;
  final _PointerSequence sequence;
}

class _MenuSession {
  ProbeMenuRoute? activeRoute; // Existing sole sampling owner, not topmost SDK entry.
  _MenuReservation? _reservation;

  bool get _heldReservationCanContinue => throw UnimplementedError();
  bool get _reservationStillNeedsPresentation => throw UnimplementedError();

  // Called only by the accepted leaf source-down path; constructor/push stays
  // with source State so no BuildContext is retained in the session.
  bool canReserve(PointerDownEvent event) => throw UnimplementedError();
  void reserve(ProbeMenuRoute route, _PointerSequence sequence) =>
      throw UnimplementedError();

  // Consumes the reservation, then uses the existing acquire transition.
  void _promoteReservation() => throw UnimplementedError();

  // Clears the exact identity before navigation/model callbacks can reenter.
  void _retireReservation(ProbeMenuRoute route) => throw UnimplementedError();
}

class ProbeMenuRoute extends PopupRoute<void> {
  bool get _isReserved => identical(_session._reservation?.route, this);

  @override
  TickerFuture didPush() {
    // Retain existing SDK push signal. A reserved route starts preparing with
    // projection zero, but does not acquire, resume a model clock or reveal.
    // Ordinary routes keep current acquire behavior.
    throw UnimplementedError();
  }
}
```

The concrete implementation may inline these small private predicates, but the knowledge must stay in the session. A reservation is one immutable triple: exact route, exact whole-model transfer, exact accepted pointer sequence. It cannot silently attach to a replacement model after forced removal. The route's root source-page identity already exists; do not duplicate it. The reservation relation is represented once in the session; no synchronized `reserved` bool or second model-owner field is needed. This follows single-source-of-truth and encode-lessons-in-structure.

### Admission and ownership

Reserve only after the genuine source down was accepted, while `activeRoute` is either absent or `closingContent`, and while the complete source ancestry is eligible. Cold acquisition can keep its current immediate-owner path; the new reservation case is specifically the existing revealed closing owner. Never reserve over `closingPreparation`, an unrelated cover or an unaccepted pointer/view/button. There is at most one reservation.

Install `_reservation` before `Navigator.push`, since `didPush` and change-next callbacks are synchronous. Roll it back if push fails. Register the reserved route in the session's `_routes` lifetime set even though it owns no model. Its clock is installed but remains idle; no second ticker samples. `activeRoute`, `transfer.owner` and existing owner clocks retain their current meaning until promotion.

While reserved, a held sequence may continue only when the reservation is active/current, its transfer is still identical, its original sequence remains `_pointer`, and the entire source chain remains current except the exact retained active root source page covered by this reservation. A nested page pushed after down still revokes authority. A removed retained page is never exempt merely because its State has not unmounted. The source-eligibility closure may accept the existing named `coveredRoot` argument rather than teaching global input about Flutter ancestor details.

The reserved route's `didChangeNext` must revoke this exact reservation's pointer when an unrelated cover arrives. Do not make `_menuCanAcquire` true simply because a hidden reservation exists. The ordinary active-route authority remains unchanged; only continuation of the already accepted sequence receives the reservation exception. Its actual terminal PointerCancel continues to reach the model.

At the measured `transfer.isOpen` transition, consume a still-valid reservation and call the current whole-model `acquire` using the current owner clock, which may now be predecessor or source. Recheck route/transfer/source lifetime before and after callback-producing model operations. A removed successor, detached source or changed transfer must not become owner. A reservation under a cover may be promoted only for already committed opening work after its held pointer has been cancelled; this preserves existing delayed-release work rather than granting covered input. SDK modality still blocks focus and semantics behind that cover. If implementation cannot prove this distinction from current domain flags and the captured sequence, stop and add a targeted characterization rather than broadly exempting noncurrent routes.

### Source semantics and SDK Back while reserved

A hidden reservation may receive a genuine semantic source activation, just like a cold hidden preparation. Validate the exact reservation/current root and full source ancestry (with only its retained active source root exempt), cancel the captured physical sequence on the current actual sampler, revalidate transfer/route/source identities, promote that reservation and run the existing semantic/manual `activate` operation. This is an explicit open command, not a fabricated hold event. Stale source handlers under an unrelated cover, removed source page, closingPreparation or changed transfer remain no-ops. There is no interval of early optical retirement while waiting for a hold: this explicit activation opens/reveals in the same operation.

Reserved `willPop` cannot reuse `_isLive` unchanged: that predicate currently requires model ownership, so it would incorrectly veto hidden SDK Back forever. For a current, active, still-hidden reservation with a not-open model, allow SDK dismissal without mounting content/policy; `didPop` only retires its physical reservation and keeps predecessor sampling. If the model has already opened by the time Back is consulted, promote first and use the ordinary first-mount policy path. Never allow a not-yet-mounted successor policy to be bypassed merely because an asynchronous Back began earlier. Direct forced removal retires without consulting policy, as SDK removeRoute does. Test the held Back case separately from a committed delayed-release opening: cancellation of committed release work is an existing domain policy and must not be silently redefined in this host fix.

### Optical and content lifetime

The old route remains owner, painter and Flow lease holder until actual opening or the old first-zero hand-back. Consequently its editor remains mounted and its measured contentOpacity is rendered during the reservation; no optical-tail cache is necessary. At hand-back it disposes at the same boundary as before. If opening occurs first, promotion uses existing `_relinquish` and `_reveal` in the same frame: the new owner paints the same model, and its new content tree mounts for the next paint. Verify this exact boundary with a visible colored content probe; an equal model frame alone cannot prove no blank content frame.

The fresh tree remains under that new route's `_MountedMenuPolicy`. It cannot reuse predecessor LocalHistory, old async dismissal answers, policy registrations or FocusScope. Existing first-mount admission waits until the new policy is registered. Hidden reservation asks for no focus and exposes no route/menu semantics. Old closing content remains inert through existing closing gates. Ordinary animation frames and the successor's shown-to-closing transition still use the stable child; never rebuild policy/editor on sampled frames.

### Cancellation, retirement and reentry

- Actual cancel or forfeited release with no committed opening: clear `_reservation` first, seal the reserved route, remove that exact route entry, and leave model ownership/clock with the predecessor or source. `routeDisposed` already must reset only the actual active model route, so a never-owning reserved route cannot reset it.
- A valid up with `isOpenPending` keeps one reservation until its measured opening, retaining existing two-presentation route counts. Removing and recreating it would add spurious SDK route events.
- Slop movement alone does not retire while a physical sequence is still held: the model does not expose hold-forfeiture and no inference from `isArming` is valid during closing. Retaining an inert reservation until terminal input is finite and avoids a new motion API.
- SDK Back/explicit removal of a reservation revokes its held sequence and drops only its reservation. It must not call `_beginClosing` using the unowned successor lease or accidentally emit a close against the predecessor. Any already committed release work follows the existing model cancellation contract; do not clear its timeline merely to hide the host lifecycle issue.
- Source detach clears presentation callbacks, revokes its physical reservation, removes the exact reserved route, then disposes the source clock. The predecessor can finish on its own clock as today; it must not dereference the detached source.
- Forced removal of the predecessor while it is still model owner legitimately invalidates the reservation's captured transfer. Retire the stale reservation before any fresh source model can receive a late promotion. Forced removal after promotion only touches that current owner; the old predecessor's later disposal cannot reset it.
- Clear reservation identity before remove/dispose callbacks. All retirement paths are idempotent. Do not use `Navigator.pop` for a possibly covered reservation; it can pop the cover.
- Rapid additional source down cannot allocate a second reservation while `_pointer` or a reservation exists. Reentrant observed callbacks must revalidate exact transfer, route and sequence identities before publishing frames.

## Interface depth and red-flag screen

The public surface is unchanged and callers continue to supply one builder. The only new state models a real distinction, installed-but-not-sampling route, rather than copying geometry or phase. Complexity is concentrated in the existing session and real PopupRoute; no extra file chain, public lifecycle option or hand-synchronized owner list is added. `_routes` remains the existing disposal-lifetime set; `_reservation` adds one relationship, not a competing model owner. The chief red flag is promotion and authority policy spread between route callbacks and source Listener: keep their predicates in session, and let source State provide only Flutter context capture/navigation construction.

## Synthesis decision

Candidate A is SDK reservation before ownership. Parent synthesis pending; this file does not claim comparison against another candidate or empirical success.

## Tradeoffs accepted

- We accept one small private reservation relation in exchange for preserving measured sampling and hand-back semantics without an outgoing-content framework.
- We accept that the root SDK history contains an inert hidden successor before content exists in exchange for receiving the genuine held pointer tail; this is the same early-push cost already accepted for cold source input.
- We accept fresh route-local State on actual reopen in exchange for clear new route policy/focus ownership, as the existing plan specifies.
- We accept retaining a slop-forfeited reservation until its genuine terminal event in exchange for avoiding a new model introspection flag or duplicated hold algorithm.

## Alternatives considered

1. **Early prepare plus immediate whole-model acquire.** Smallest diff and no public API change, but old `_relinquish` dismisses its route, while old Flow refuses the new owner's lease. It can remove still-visible old content and skip normal first-zero hand-backs. Equal geometry does not cure either lifetime defect. Reject unless the ownership/content contract is deliberately weakened, which this assignment forbids.
2. **Immediate acquire with bounded outgoing content retention.** Retain a predecessor as an inert paint-only reader of the session's current frame until new reveal. This can fix the content gap without cloning the motion, but it still transfers sampling early and reduces historical hand-backs. Restoring hand-backs would require simulated observations or additional ownership moves. It also introduces a content-render authority separate from the real sampler and a second retirement policy. The public API is equally small, but internal interface depth is worse for this exact invariant set.
3. **One permanent popup or content portal.** Avoids repeated push cancellation and can preserve editor State, but changes route semantics, LocalHistory/PopScope ownership, focus and fresh-content behavior across presentations. It solves a broader different problem and exposes much more policy to future component authors.

## Open questions and risks

- Can a transparent-cover content probe show old content on every pre-reveal frame and fresh successor content on the first reveal frame with no blank, duplicate or stale interactive editor?
- Do genuine 60/120 Hz held gestures remain accepted when normal hand-back occurs between reservation and hold-open, with exactly one model and no binding cancel?
- Does already committed tap-open under an unrelated cover preserve today's behavior without granting focus, semantic dismissal or pointer authority to that covered successor?
- Can all existing replay route/hand-back totals remain identical, including early-up traces, while cancelled reservation cases are accounted separately rather than relabelled presentations?
- Do source loss and forced removal at each callback boundary retire only the reservation belonging to the captured transfer?

These are implementation-test gates, not reasons for an additional human approval checkpoint. Device VoiceOver/TalkBack/native IME and measured native held-reopen fidelity remain unproven.

## Next implementation step

First make the genuine pre-handback down/hold/move/up characterization fail for the actual late-push cancellation, then add the reservation relation and reserved `didPush` path while preserving the existing transfer/clock/hand-back code byte for byte.
