# Fresh architect / arena judgment: input ownership

Base `cfade8834496cc0cf580230b0e097e172ec27514`. Read every requested ground/how/why/candidate/checklist document, the route and transfer implementations, the relevant production pointer/advance/selection methods, the current expanded ownership tests, and the initial three-failure/four-pass log. This is read-only design review; I did not run tests, edit repository source, acquire devices or delegate. The candidates and this judge use the same inherited model, so this is fresh-context review, not different-model consensus.

## Verdict

Choose A, conditionally on unchanged recorded replay and lifecycle evidence. It fixes the proven ownership hole inside the existing transport boundary. B is structurally credible but cannot actually eliminate global acquisition while preserving the pre-render pending-input contract: its publication bridge and possible closing render gate introduce more temporal ownership than they remove at this prototype stage. No app-wide broker or keyboard override is justified by the three observed failures.

| Criterion, 0–3 | A | B |
| --- | ---: | ---: |
| Genuine pointer / measured timing fidelity | 3 | 2 |
| Single input owner and cover revocation | 3 | 3 |
| Correct Escape / Back scope without caller burden | 2 | 2 |
| Lifecycle, reentrancy and multiple Navigator safety | 2 | 2 |
| Small coherent public Flutter SDK boundary | 3 | 1 |
| Total | **13 / 15** | **10 / 15** |

Scores evaluate design fitness, not passing implementation. Both lose a keyboard point because Router child priority and ordinary focus behavior are characterization targets, not established general app guarantees. Both lose a lifecycle point because their proposed edge handling requires actual replay/reentrancy evidence. B loses timing credit for unresolved publication gaps. A's fidelity credit assumes same-time pre-sampling passes the existing exact comparisons; a replay regression invalidates that score rather than permitting tolerance changes.

## Pick and graft

Keep A's lifetime transport for now, but separate its authority explicitly: only an actual source Listener down may acquire a source sequence; only this session's current non-closing presentation may acquire another global down. Bind both acquisition and continuation to the source View and one unique sequence object. Source eligibility must inspect every public modal/Navigator ancestor, since nearest nested currentness alone is false evidence under a root cover. Do not cache eligibility. Other sessions' hidden preparations must make the covered source ineligible even while hit testing still passes through them.

Graft B's clean conceptual distinction between acquisition and transport, not its extra registrations/bridge/render-publication protocol. Keep one private shared delivery path; do not implement the same policy separately in two handlers. Source identity/view migration, route loss and forced removal must invalidate stale sequence identity before any cleanup that may invoke client code. Preserve the existing model transfer and lease identity: a physical stream must survive legitimate source-to-route lease handoff without becoming tied to the old owner.

Keep keyboard behavior as SDK behavior. Hidden Escape with retained ordinary focus and binding Back have already produced different outcomes in the initial harness. No global key hook, implicit host integration API or root-first Router promise follows from these observations. Real Router root-delegate and prioritized-child tests should document which delegate handles Back rather than changing dispatcher priority to make a desired answer appear.

## Required correction: cancellation is an interaction command, not an advance-time interrupt

A's command-depth envelope and pre-advance/revalidation are justified by actual source, not precautionary abstraction. `pointerUp(t)` calls `advance(t)` before reading and clearing the held pointer. A due action can cover/remove the route during that advance. Clearing only adapter identity and deferring model cancel lets pointerUp resume and schedule another selection after revocation. Advancing once before dispatch, then checking the identical sequence/transfer and live eligibility, closes that particular window without changing production pointer semantics. Do not omit this revalidation just because the first seven tests become green.

The other concrete synchronous reentrancy site is `onTrackedHighlight` inside `_track`, called during pointerDown/Move, after which the same pointer method continues to schedule glow/flex work. Here pre-advance alone does not help: the outer command must finish, then the queued same-transfer cancellation must clear the model-held interaction and relax any work scheduled after the callback. The current expanded tracked-highlight test is necessary evidence. Cancellation must execute after the outer model command returns and before phase synchronization / subsequent input. Clear the pending-cancel slot before executing it so callbacks cannot recursively drain the same token. Resolve the current lease for that identical transfer rather than retain a lease invalidated by a valid handoff.

Every entry that can run timeline/client work needs the same small envelope, including clock advances and transfer/open/close paths where relevant. Do not turn it into a generic transaction scheduler: one depth count and one idempotent same-transfer cancellation are sufficient unless a concrete counterexample proves otherwise. A callback may synchronously force-remove/replace a route; after it returns, skip notifications, clock wakeups and pointer commands against a disposed owner. The old cancellation must not cancel a fresh replacement model or fresh physical sequence. Add that real removal counterexample if implementation touches these paths.

Do not overstate this mechanism as stopping all due work at the exact instant of cover. Existing `advance(t)` drains due callbacks before returning, and deferred `pointerCancel` does not interrupt its inner runDue loop. Already committed release effects are intentionally retained; a held-work deadline already crossed inside that same outer advance may have been evaluated before cancellation runs. If a stronger mid-advance selective invalidation contract becomes a requirement, it needs a production model/effect boundary and falls outside the unchanged-core prototype constraint. No hidden whole-timeline clear or pause is acceptable to claim that stronger contract.

## Release semantics and scope correction

The selected policy is coherent with existing admission evidence: a valid release commits its delayed action, which may run once while covered, while close admission protects the covering route. An interrupted held sequence cannot gain a later release by moving/up after cover-uncover. Keep an explicit regression for each; 'no actions while covered' is an incorrect description.

The how investigation's recommendation to invalidate pending interaction work is broader than the now-selected contract if interpreted as revoking every delayed callback. The why findings and ground distinguish held state from committed releases correctly. The synthesis should state that narrower contract rather than treating the investigation's broader recommendation as an implemented guarantee. `_activate` may call both onSelected and onActivate; cover initiated by the former must not be described as undoing the already committed action represented by the latter.

## Simplicity and delivery conditions

- Use the single sequence identity, not an additional numeric epoch or mirrored model pointer state.
- Add only the transfer domain cancel necessary to avoid manufacturing pointer events. Its canonical time is the model's current completed sample, not a backdated callback deadline.
- Preserve passive samples, closing, handback and committed deadlines under cover; `isCurrent` is an input rule, not a clock rule.
- Check a held sequence on logical pop/removal as well as cover. Revealed-closing reopen must acquire from a fresh actual source hit; stale menu continuation must not become an implicit reopening path.
- A duplicate original down seen first in the source Listener and then in the global route must reach the model exactly once.
- Same-view matching is necessary but does not by itself prove multiwindow focus or arbitrary cross-view Navigator hosting. Test multiple Views if claiming pointer isolation; state untested migration/host limitations explicitly.
- Require current cover/cancel/cover-uncover, nested source ancestry, multiple sources, committed-release, tracked-highlight and due-action-second-up checks; add reentrant removal. Then rerun all existing exact pointer replays and raster scenes without fixture/tuning changes.

This verdict authorizes implementation within the already requested prototype scope. It does not approve early-root observer/currentness behavior as the eventual library architecture, complete P2, or replace the future typed-effect boundary work.
