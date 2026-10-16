# Cross-judge verdict: P2 async dismissal

Read-only judge, 2026-10-16. Read ground.md, how/findings.md, why/findings.md and both candidate designs end to end, plus current prototype clock/transfer/route implementation and clock tests. No repository edits, tests, devices or subagents. These are two independent runs of the same inherited model, not a multi-model consensus.

## Decision

Use **A's route-owned permission transaction as the P2 base**, graft **B's next-owner-step completion and existing paused-idle clock semantics**. Keep the existing internal bool admission seam unchanged. Reserve B's yielded timeline/typed-effect migration for unit 2.4. Do **not** add A's fresh continuously elapsed idle clock or either candidate's unconditional first-build/post-frame barrier in this async patch.

This is not a smallest-diff vote: A concentrates asynchronous SDK lifecycle knowledge in the route without adding protocol stages to every motion caller. B is the stronger eventual integration boundary, but its advance/drain/resolve and input-preflight protocol changes the model stepping contract and timeline scheduling, precisely the future unit 2.4 work. Its safety depends on proving all nested pointer/advance and equal-deadline continuations, which is a new production migration rather than necessary evidence for pending SDK permission (B:94-118,138-144,166-170). Ground explicitly excludes further production API migration in P2 unless justified; async SDK compatibility alone does not justify it. A explicitly identifies the same target shape and its future necessity rather than denying the architecture debt (A:167-179).

## Rubric (0-3, judged as submitted for P2)

| Axis | A | B | Concrete basis |
| --- | ---: | ---: | --- |
| Causal time / unchanged synchronous fidelity | 2 | 3 | Both prohibit past mutation after await. A:131-137 needlessly changes ordinary-idle time policy; B:152-160 retains owner-clock policy and defines acceptance at consumption. B's yielded timeline preserves deadline without final-frame backdating (B:113), but still needs proof that no extra sample enters driven integration. |
| Refusal / single-writer safety | 3 | 3 | A:124-127 preserves the existing pre-close admission and commits deferred motion only after successful SDK pop; B:138-144 centralizes the same rule with an explicit writer. Both retain local-history refusal and independent selection actions. |
| SDK lifecycle / async races | 3 | 2 | A:126,146-163 expressly shares the route willPop future with SDK maybePop and handles next-route epochs, source loss and history. B:150-162 covers most races, but its concrete signatures omit the willPop sharing required for simultaneous SDK maybePop; deduplicating only model requests is insufficient. Neither is proved yet. |
| Small API / removable provisional seams | 3 | 1 | A:167-173 confines new transaction types to prototype and retains one temporary production bool seam. B:94-118 adds request/disposition/effect, advance-until-effect/drain/resolve plus timeline yielding, and driver call rules, an early unit 2.4 migration. |
| Falsifiable tests / feasibility now | 2 | 2 | A:205-215 has direct strict replay/lifecycle tests but additionally requires new clock policy and first-build semantics. B:187-196 adds valuable coarse-frame sampling/order checks, yet implementation feasibility depends on unproved nested stepping assumptions explicitly admitted at B:115. |
| Total | 13 | 11 | Scope-adjusted recommendation, not proof of correctness. |

## Essential contract and signatures

Application call sites remain Flutter PopScope/WillPopScope and Navigator.pop. No public async guard API or integration widget.

One private route-owned attempt stores requestedAt, lease, epoch and identity. One cached SDK permission future belongs to that attempt/epoch; model outside/select and SDK maybePop must share it. No parallel session map of pending futures.

Minimal private operations are:

- bool _admitMotionClose(double requestedAt): pure framework observations plus attempt recording. While a scoped guard/permission is pending return false before any closing mutation. Preserve existing immediate PopScope/local-history fast path exactly.
- void _drainDismissal(): run after input/advance, outside integration. Start at most one SDK permission future and perform existing synchronous pop/refusal notifications.
- Future<RoutePopDisposition> willPop(): prototype deprecated compatibility override sharing the cached guard future. Guard exceptions report once, deny and allow retry. Do not call app callbacks under the bool seam.
- bool _isLive(_DismissAttempt attempt): check pending identity, epoch, attached navigator, current route, active session route, lease ownership, not closing/disposed at **each** continuation boundary.
- void _consumeApprovedDismissal(double ownerLocalTime): after an ordinary owner sample but before publishing that sample, recheck current PopScope and lifecycle, then pop this current route. didPop first delegates SDK local history; only a successful pop closes the model at the just-sampled owner time.
- void _invalidateDismissal(): invalidate identity and cached future on changed next-route identity, relinquish, disposal and any programmatic pop attempt. Source-only loss intentionally does not invalidate a living current route.

Use records/small classes as useful; _ApprovedPop and a separate _DismissKind are not essential if existing synchronous admittedCloseTime plus a single pending state encode the distinctions. Avoid separate queued-approved and pending-permission owners that can diverge. If explicit programmatic pop invalidates pending even when local history consumes it, test and document that stricter choice.

Async approval queues owner work and calls the **existing resumeAt(now())**, then the ordinary writer step advances the model and consumes the queued decision. If permission completes during another integration step, no navigation/model command executes until that step has returned. Revalidate after sampling because timed callbacks may have changed ownership. Existing immediate deadline handling remains unchanged; never turn every dismissal into maybePop/await.

## Time ruling

Graft B:152-160; reject A's stampCommand requirement at A:112-116,137. Current clock stops settled time (_tick settled branch at motion_clock_probe.dart:142-147); resumeAt begins from _time, adding elapsed doze when present (:198-209). Existing tests explicitly prove initial/settled input sleep starts at canonical zero and includes delivery lag after wake (motion_clock_probe_test.dart:239-251), and paused clock resume stays at pausedAt then advances by 8 ms (:453-490). A's raw-idle anchor creates a new policy, not a prerequisite for causal closing.

requestedAt remains provenance. For synchronous acceptance closeStartedAt == requestedAt. For async, acceptedAt is **the canonical owner sample that consumes approval**, closeStartedAt == acceptedAt >= latest sampled model time. Permission-completion wall time is distinct if recorded. Canonical acceptedAt can equal requestedAt after settled idle; require strict inequality only where model time continued advancing. resumeAt(now()) preserves elapsed doze and first-frame delivery lag without injecting the whole ordinary idle duration. Add settled/doze and 1x/5x tests rather than assume this works. No stale local timestamp should be captured in the future continuation and replayed later.

## First-build ruling

Both propose a stronger new policy than SDK: defer every model request until a post-frame barrier after revealed content mounts (A:139-143; B:144-146). This is a separate decision with known replay implications. **It can be omitted now without weakening the actual mounted-policy acceptance contract:** synchronous admission reads registered PopScope and registered scoped callbacks, final async acceptance rereads current policy, and a real first-built menu policy must be tested before any later dismissal request. Do not bypass a guard that is already registered just because cached state predates the content build.

This does **not** solve or claim to solve a dismissal requested before descendants mount. No SDK call can inspect a nonexistent future descendant guard. Keep that early-before-first-build case expressly OPEN in P2 documentation; do not mark full P2 complete, do not invent first-build discovery via builder side effects, and do not weaken a test of a guard that really has mounted. If actual tests expose bypass of a mounted policy due to registration timing, fix that boundary; if the request precedes mounting, archive the counterexample as the separate readiness decision. A later readiness barrier must explicitly confront strict replay compatibility rather than silently delaying measured sync closes.

## Required verification / rejection signals

1. Unchanged strict 20 recorded replay trajectories/actions/hand-backs and synchronous requestedAt == closeStartedAt. No tuning or tolerance edits.
2. Completer guard false/true/retry/throw, opening/live interaction through wait; compare delayed close to a control that closes at the same accepted sample, not at the old deadline.
3. Repeated model requests + concurrent SDK maybePop invoke one guard and yield at most one logical pop; explicit Navigator.pop keeps bypass semantics. SDK-origin maybePop winning a shared completion must also invalidate queued model work.
4. Replacement, remove, dispose Navigator, cover/uncover, relinquish and explicit pop before completion cannot touch other owners. Source-only disappearance remains allowed for the still-current route.
5. Existing/new local history and modern PopScope toggling during await retain open motion when SDK consumes/refuses; selected actions remain independent.
6. Ordinary settled idle, active opening, doze, 1x/5x and first future frame monotonicity; no extra ticking solely while awaiting. Pending work cannot be lost because an onFrame outcome reports settled before the queued decision is consumed.
7. First content-build registered PopScope/WillPopScope is honored for a request made after registration. Document pre-mount policy discovery as still open.

Reject this synthesis if implementing it needs snapshots/rewind, model mutation within permission callbacks, an arbitrary wall-clock-to-motion retarget, or growing production callback families. Then use architect Phase E rather than bolt exceptions onto the bool seam. B's yielded boundary remains the coherent future alternative; it is not a halfway event-after-final-sample substitute.

## Plan refinements

Replace unqualified 'preserve original reaction time after permission' with separate synchronous measured deadline and async requestedAt provenance/current-sample close guarantees. Label deprecated WillPopScope as SDK compatibility evidence. Preserve explicit open gaps: early hidden-route observer/isCurrent and pre-first-build policy, complete bar scene, optics/device behavior, active dilation changes, typed-E migration. These host proofs neither finish P2 nor select the P1 driver.
