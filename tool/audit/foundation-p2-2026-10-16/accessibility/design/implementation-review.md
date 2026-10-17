# Readonly implementation review

Reviewed actual `menu_route_probe.dart` diff against `65dce59f` and the final 16-check accessibility harness. No edits, test runs or delegation by this reviewer. Parent reports all 16 passing; that execution is parent evidence, not an independent rerun.

## Accepted implementation

- `_MenuStage` replaces both writable old fields rather than mirroring them. ClosingContent retains the exact wrapper/Flow/content shape; semantics exclusion changes without remounting the policy subtree.
- Raw source down and model-driven presentation preserve `_prepare`; public/semantic opening uses the existing model/lease and never manufactures a pointer event.
- Activation snapshots transfer/lease and rechecks route/source authority after cancellation, model advance/open and the observable `.open` emission. A callback-induced cover/removal cannot continue through the remaining phase synchronization.
- Semantic dismiss is scoped to its captured live/current/shown owner and uses SDK `maybePop`; the existing async admission and PopScope protocol remain authoritative. Setting `semanticsDismissible` false avoids the command barrier duplicating the single route-level dismiss action while retaining physical pointer behavior.
- Tree presence follows shown stage; root cover semantics remain SDK-owned. The custom renderer repairs only Flow paint-to-semantics invalidation, without adding listener attachment or semantic-admission machinery.
- Existing timing/model/clock code is untouched. The source expanded flag is only built from current state; it is not independently subscribed, so this patch should not claim a separately observable expanded-source state while a modal menu hides that source.

## One concrete correctness issue before acceptance

The captured-root exception in `_sourceCanAcquire(coveredRoot: ...)` permits a captured source root ModalRoute to be noncurrent without requiring it to remain active. A root source page can be removed synchronously with `Navigator.removeRoute(sourcePage)` while its own hidden popup stays current. Before the next pump disposes the removed source State/semantics subtree, a retained source tap callback remains callable; the current guard treats the removed source page exactly like the valid page covered only by its preparation and activates the menu.

The exception should require the captured root route to remain `isActive`; do not merely rely on `State.mounted`, which ends later in this lifecycle. Add a genuine stored semantics tap performed after removeRoute and before pump, with a hidden preparation already present, and assert no domain open/reveal. This change affects source acquisition only; an independently live popup must keep its semantic dismissal after source loss.

## Verification bounds

The 16 tests establish the principal source/open/dismiss/lifetime/geometry paths. Closed-source root/nested covers are exercised, while the own-hidden-preparation exception under a new nested cover and source acquisition callbacks that cover/remove during `.cancelInput`/`.open` need direct characterization if claimed individually. The guards are structurally in the right place; these coverage limits do not imply additional source defects. Native screen-reader behavior remains unproved.

## Accepted corrections after reproduction

The parent reproduced the removed-source-page race with one executable failing test (`/tmp/morph-p2-accessibility-removal-before.log`). The updated helper first normalizes the exempt root to null unless its captured route remains `isActive`, then applies the same narrow identity exemption throughout local/nested ancestry checks. This directly closes the reported admission defect without touching independent popup dismissal after source loss.

The first full prototype run exposed eight legacy builder-count failures. The updated source now provides the scoped/named Semantics, Flow, captured themes and policy widget as `ValueListenableBuilder.child`, while the stage builder only decides the lazy mount and ExcludeSemantics value. That is the correct identity-preserving correction: shown to closingContent retains the identical expensive widget child and only changes semantic exclusion. Old lifecycle/test assertions have not been weakened. `_reveal` is additionally restricted to preparing to shown, so a closingPreparation cannot be resurrected by a stale reveal.

The four added genuine-action checks target removed source before pump, an own hidden popup with a newly covered nested source page, cover from `.cancelInput`, and removal from `.open` observation. They exercise the previously recorded admission/reentrancy gaps without synthetic binding pointer events. Their run was still in progress during this readonly review. In the removed-source test, cleanup must not require a surviving source State after its route is disposed; waiting for the popup disposal and idle transient callbacks is the applicable contract.

No further concrete source correctness finding remains in the final inspected diff. This is architectural/code acceptance, contingent on the parent's final new/legacy test jobs, replay metrics and analyzer passing. It is not a claim that those running jobs have completed or that native accessibility is proved.

## Reentrant cover regression found by the added action test

The current refined run is 49 pass / 1 fail: all eight legacy builder-count regressions are resolved, while the new cover-from-cancellation test demonstrates a genuine pre-existing authority bug. `syncInputPhase` cancels an abandoned hidden preparation using unqualified `route.navigator.pop()`. If a `.cancelInput` callback has placed a cover above that preparation, this pops the cover instead of the canceled popup.

Removal must target the hidden route identity when it is not current; an ordinary current preparation can retain the previous pop path. `Navigator.removeRoute(route)` is SDK-supported identity-specific teardown, unlike popping the now-current cover. Merely waiting until uncover retains a canceled prepared route and is not equivalent cleanup.

One consequence requires an explicit implementation decision: existing `_MenuSession.routeDisposed` resets the whole transfer on forced removal of the active route. A noncurrent hidden preparation may still have a source-press relaxation tail visible through a transparent cover. Unconditional removeRoute therefore prevents the incorrect cover pop but may cut this passive source tail. There is no committed item release in the abandoned hidden condition, yet that does not prove all motion channels are settled. If exact passive-tail continuity is required in this case, the teardown must preserve/land the existing model before generic forced-removal reset; otherwise report the forced hidden-preparation teardown boundary rather than claiming unchanged passive-tail semantics. No broader visible-menu dismissal or arbitrary route removal is justified by this reproduction.

The earlier cleanup warning was stale: the current harness already checks for a surviving source State before awaiting its motion settlement. That nullable cleanup is appropriate and does not weaken any legacy assertion.

## Accepted refinement for covered preparation teardown

Do not accept cutting the passive tail. The proposed smaller correction reuses the existing model-close lifecycle instead of adding a transfer bypass: factor only the post-success `didPop` body into private `_beginClosing(approved)`. For an abandoned noncurrent hidden preparation, invalidate permission and invoke this private logical transition without calling Navigator.pop or pretending SDK didPop succeeded. `closingPreparation` seals all interaction/semantics while the existing route clock finishes the original model channels.

At the existing closing completion boundary, an `isActive` route still retained in Navigator history is removed by exact identity; an already SDK-popped route retains its previous dismissed-projection path. No new flag or copied motion is necessary. Where the existing handback succeeds, generic route disposal no longer owns the transfer and cannot reset its live tail. Where an idle hidden model never enters a closing phase, wait for whole-model settlement before removing/resetting it. This is finite private closing, not an interactive zombie waiting for uncover.

After identity-specific removal, return from the sample without further publication: removal observers may reenter, dispose or replace state. Recheck disposal/lease after phase synchronization as appropriate. Current route cancellation continues through the existing ordinary SDK pop path. Visible covered menus and committed release actions are outside this abandoned-hidden condition.

Acceptance needs transparent-cover model-identity and source-press continuity evidence through settlement, plus unchanged legacy replay/handback checks. The reported remaining targeted failure is teardown bookkeeping: the cover uses SDK's default reverse duration, so await its `completed` future before the existing final zero-transient-callback assertion. Preserve that assertion rather than reducing it.

## Final inspected tail-preserving implementation

Read the actual final diff and transparent-cover replay test, and inspected `/tmp/morph-p2-accessibility-tail-fixed.log`: 51 targeted accessibility/route/lifecycle checks passed. No independent test job was started by this reviewer. The wider prototype suite was still running at this review point.

`syncInputPhase` preserves the existing ordinary pop when the abandoned hidden preparation is current; otherwise it invokes `_abandonCoveredPreparation` on that exact route. The latter invalidates permission and shares `_beginClosing(false)` with the existing successful-pop implementation. It does not call Navigator.pop against the cover, manufacture SDK lifecycle success, create a second model, or force-remove the live press relaxation. The stage is closingPreparation and both pointer/semantic admission remain sealed.

In `_sample`, identity removal occurs only at the existing closing completion branch. If handback has succeeded, the source already owns the unchanged transfer and `routeDisposed` will not reset it. If the hidden model is idle and never qualifies for handback, this branch requires whole-model settlement; only then can active-route forced-disposal reset it. The removal branch returns immediately, avoiding publication after observer reentrancy. The added disposed/owner check after phase synchronization protects the remaining sample path.

The executable transparent-cover test creates a live pressed source, replays raw/cancel/close/frame commands into a separate reference motion, compares the original model's pressScale and time at `1e-9`, checks every replacement allocation sees its predecessor settled, and confirms the cover stays current until the route is disposed. More than ten observations and final original-model settlement are required. This directly establishes that the wrong-cover pop and premature live-tail reset are both repaired for the reproduced case. The final no-transient-callback assertion remains intact.

No remaining actionable correctness/deslop finding in the inspected implementation. Accept the bounded host accessibility/lifecycle change subject to the parent's full prototype/example suites, baseline metrics, analyzer and final evidence checks. Native screen-reader behavior and the explicitly deferred product boundaries remain unproved.
