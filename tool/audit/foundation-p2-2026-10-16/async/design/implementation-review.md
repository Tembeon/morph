# Phase D review against async-dismiss synthesis

Read-only review of current working tree, 2026-10-16. Read menu_route_probe.dart, complete menu_route_async_test.dart, menu_async_time_test.dart, menu-dismissal-protocol.md, and relevant local SDK navigator/routes code. No jobs, tests, devices, subagents or repository edits. Running suite outcomes are not known to this reviewer.

## Verdict

The implementation follows the chosen shape well, including the justified identity-only simplification. **One concrete shared-SDK-success race needs a reproduction before claiming all coalescing/cancellation guarantees.** No reason found to migrate production model/clock/timeline now. The potential defect belongs to handing one successful future to multiple SDK continuations, not the removal of numeric epochs.

## Finding: successful shared SDK future survives identity invalidation

Priority P2, high-confidence code-derived reproduction; not executed here.

`menu_route_probe.dart:482-487` gives every SDK willPop caller the same Future. On approval `_resolvePermission` completes it with pop at :501-504,524. Each `Navigator.maybePop` continuation then independently rechecks only final present entry and current popDisposition before calling pop (local navigator.dart:5582-5624). `_invalidateDismissal` at :545-550 can replace an unresolved future result, but it cannot revoke a pop already delivered to waiting SDK continuations.

Concrete public-SDK sequence:

1. Open route with mounted async guard; call `navigator.maybePop()` twice before resolving guard. Only one guard should run because the future is shared.
2. Add one LocalHistoryEntry before approving (or arrange an entry initially).
3. Complete guard true.
4. SDK continuation A calls pop. Route didPop invalidates the attempt, then `super.didPop` consumes local history and returns false (:622-626). The menu intentionally remains open.
5. SDK continuation B already received pop from the same completed future. It sees the same still-present route entry and now-allowed disposition, so it calls pop again and closes the route, without consulting a new guard.

If the intended operation-level guarantee is one permission transaction/at most one pop attempt, this violates it. Existing tests :296-322 have one SDK caller plus model; the model queue does revalidate identity and therefore cancels correctly. They do not cover two SDK callers plus local history. Add this focused test while other coverage is green. If two concurrent SDK user requests are deliberately considered two authorized pop attempts, document that SDK-preserving limitation explicitly instead of claiming the single transaction coalesces their effects. Guard coalescing alone and navigation-operation coalescing are different guarantees.

A related edge is success delivered to SDK, followed by a temporary cover/uncover before SDK commit. Identity invalidates queued model work, but SDK maybePop only compares final route-entry identity, so stronger cancellation does not automatically extend beyond delivery of a successful future. Existing lifecycle tests :365-411 invalidate before completing the application guard. Add a post-permission/pre-commit test if the documentation promises the stronger boundary. Merely restoring an epoch counter would not fix either problem: SDK does not inspect it.

Do not bolt a global didPop veto onto this: explicit Navigator.pop must continue bypassing policy and local history must remain authoritative. If fixing operation-level coalescing requires changing how SDK callers receive permission versus how the model starts its internal check, revise that narrow route transaction sketch explicitly. Core typed-E migration is not required by this finding.

## What matches the synthesis

- Production model, timeline and clock unchanged. The measured synchronous bool path still reads framework policy without calling the app and queues navigation delivery outside integration (:222-236,324-348).
- Pending identity lives only in route (:390-396,413). Replacing an identity on invalidation is an adequate operation generation: old objects are never reused, and `didChangeNext`/`didPopNext` cancel cover/uncover (:559-572). Numeric epoch removal is a sound simplification for internal/model continuations.
- Prepublishing Completer before calling `super.willPop` (:484-486) makes synchronous reentrant maybePop share the guard. New reentrancy test :251-268 covers that important case.
- Scoped guard runs after model advance/input returned; no app permission callback runs within admission. `_resolvePermission` rechecks live owner and modern popDisposition after await. False/throw retain motion and retry; future failures do not become approval (:494-524).
- Model-origin approval uses existing resumeAt(now), then the next writer step advances before consuming approval (:504,641-648). No command stamps, backdated close or wall-clock idle jump were introduced. didPop preserves unconditional programmatic-pop semantics and only commands motion after SDK local history returns a successful pop (:622-638).
- Source-only loss remains valid while route lives; removal/replacement/disposal invalidate. Source-loss, pre-resolution lifecycle and explicit-pop replacement tests are present.
- Mounted policy detection is live (`hasScopedWillPopCallback` and popDisposition), not cached at initial reveal. Pre-first-build behavior is expressly left open, matching the narrowed synthesis.
- Timing tests compare every reported progress/kick/fusion/opacity and geometry to an independent reference that stays open while awaiting and closes at the actual close command (:108-150,154-249). Negative backdating evidence remains separate. 60/120 and 1x/5x opening/settled idle scenarios are present.

## Nonblocking limits / documentation precision

- The sample observer receives `.frame` before `_consumeApprovedDismissal` (:646 versus :648), then `.close` reports the mutation. Rendering/notifier publication happens later (:664-668), so this is coherent as a test observation stream. Documentation's “before publication” should mean frame notification/paint, not “before any observer callback”; do not let onSample become product publication API.
- No new route-level doze test exists: current route sample always returns wakeTime null, so async tests cannot claim dozing route coverage. Clock doze behavior is separately covered by existing clock tests. State that distinction in the report; it is not a reason to add unrelated scheduling here.
- “RequestedAt” currently represents the first pending attempt time for SDK-first coalescing (:473-477), not necessarily the later measured model deadline; `_deferDismissal` only toggles fromModel on an existing SDK attempt (:452-456). That is reasonable operation provenance but document it; do not call SDK-first provenance a measured gesture deadline.
- First mounted guard is exercised via waits for WillPopScope element and subsequent real input (:178-190). The pre-mount decision remains open and should not be marked resolved by those passing cases.

## Acceptance recommendation

Accept the architecture with the recorded refinements. Before a blanket async-proof claim, reproduce the two-SDK-plus-history case and either fix the narrow permission delivery protocol or explicitly reduce the operation-coalescing guarantee with an archived negative control. Keep the rest of P2 gaps open as already documented. No style or broad redesign requests from this review.

## Accepted narrow fix after reproduction

Reviewed current `willPop` at menu_route_probe.dart:473-495 and `_DismissAttempt.claimed` at :397. Parent reproduced the two-SDK-plus-history failure and preserved rejected source/log; this reviewer did not run a job. Current tests include two-SDK cases with/without history (menu_route_async_test.dart:156 onward).

The refinement addresses the exact finding: one underlying permission future still runs the application guard once, but each caller resumes through its own `willPop` wrapper. After awaiting, the wrapper revalidates live identity and synchronously claims the sole successful result (:489-495), with no await between check and claim. Extra SDK callers receive doNotPop, so they cannot independently consume history and then close the same route from one permission. The prototype's own drain may be the claimant; that is coherent because its model-origin approved work performs the single navigation attempt at the next owner sample, while SDK callers treat doNotPop as handled. If an SDK caller wins, didPop invalidates queued model work as before. No clock/core migration or numeric epoch is needed.

**Status of exact review finding: fixed by inspection, pending parent suite result.** This is a sensible narrow refinement to the sketch, not a broad redesign.

A separate boundary remains expressly OPEN: once one `willPop` wrapper has returned pop to SDK, that answer cannot be revoked before SDK's subsequent Navigator.maybePop commit. SDK rechecks final entry/current disposition, not the prototype attempt identity or temporary cover/uncover history. Therefore document cancellation as applying while permission remains owned/pending or queued in the prototype; do not claim atomic navigation or stronger cancellation after a success has already been handed to SDK. This is distinct from the now-fixed multiple-success bug and does not block this scope if labelled accurately. No additional implementation changes requested by this reviewer.
