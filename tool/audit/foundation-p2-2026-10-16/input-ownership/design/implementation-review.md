# Implementation review, first ownership patch

Read-only review of the actual route/transfer diff, current ownership tests, reference-harness switch changes, and the parent's first-run log. No tests, source edits, devices or agents run here. Base `cfade8834496cc0cf580230b0e097e172ec27514`.

## Verdict: retain A, require corrections before delivery

The basic ownership implementation matches the chosen contract. Unique pointer+view identity, actual source-down provenance, root-current acquisition, source ancestry, same-time pre-advance and deferred same-transfer model cancel are coherent. The public ancestor walk is preferable to repeating Navigator.context lookups: `Navigator.maybeOf` can resolve the Navigator represented by that context, so the proposed repeated lookup could loop. Walking ancestor Elements and checking enclosing modal currentness at each Navigator StatefulElement avoids that loop and catches a current nested page beneath a covered root page. Do not replace it with nearest-modal-only currentness.

The command finally block correctly decrements depth and drains only at the outer exit. `_drainPointerCancel` clears its slot before entering another command, checks transfer identity, and resolves the current lease. That avoids recursive cancellation and preserves valid whole-model handoff. The new cancelInput observation is a domain command rather than a fabricated binding event; teaching the three reference switches to call their independent model's pointerCancel is appropriate, provided no unchanged replay gains unexplained cancellations.

### 1. Stale pointer observation after callback-driven removal

Inside handlePointer, target.pointer can synchronously call onTrackedHighlight, which can remove/dispose the active route and install a fresh transfer. The immediately following `emit(.pointer)` reads `session.transfer.frame`, not target.frame, so it can pair an old event/time with a new model frame. The later `identical(target, transfer)` check is too late to protect this observation. Revalidate target and live owner/session after pointer returns, before emitting. A callback that force-removes the route must not produce a fabricated observation of the replacement model or continue phase/frames work on disposed state.

### 2. The advance wrapper reports success for an obsolete completed command

`advance(lease,time)` currently returns the bool produced before its command-finally cancellation/reentrant effects. Source clock onFrame then increments and emits without the route sample's additional owner/disposed checks. The source lease object is reused across model replacement, so merely comparing owner to source does not establish that the sampled transfer is still the current one. Capture the transfer before invoking it and report success only if that identical transfer still owns the lease and session is live afterward. The same post-command condition makes source and route sampling honest instead of relying on different caller defenses.

The new real force-removal test should assert absence of stale .pointer/.frame observation, no exception, a clean replacement model, and continued usability. If the route can outlive its source, also avoid session.frames notification after that last route has been synchronously removed; transfer identity alone is insufficient when no new source model is created on teardown.

### 3. Exact reopening proof currently fails

The first parent run ended +32 -3: covered source landing-tail check, and center3-reopen2-50 at both rates. The reopen output reports only two routes/handbacks instead of the previous lifecycle log's four at both rates (previous samples452/883; first patch samples273/531). This is a substantive lost reopening path, not merely the observer's old ignoredPointer assertion. The failed observer assertion is downstream evidence: source-center down is now reported ignored while a closing route remains active. Do not weaken that assertion, route counts or reference application to accept the loss.

Candidate B explicitly predicted that a closing rendered barrier/page might still absorb the fresh actual source hit. Inspect the hit path and synchronous closing state before choosing a narrow correction. A hit-test gate that transparently disables obsolete closing acquisition surfaces may be justified, but adds a real rendering boundary and should trigger a documented design refinement. A global coordinate fallback for closing source acquisition abandons A's actual-source-hit invariant and reintroduces covered/inactive source authority; it is not a harmless replay fix.

## Remaining acceptance conditions

- Preserve committed-release-once and due-action-second-up tests without clearing timelines or retiming deadlines.
- Keep tracked-highlight cancellation after the outer model command, before phase synchronization, so glow/flex work scheduled after that callback is relaxed.
- Preserve closing/handback samples under cover; interaction currentness must not pause the motion clock.
- Keep keyboard code unchanged. Router root-delegate and prioritized-child cases are SDK characterizations, not permission to override their routing order.
- Re-run exact recorded inputs and raster scenes unchanged after corrections; all emitted event/time/frame combinations must refer to the same model generation.

No production/public API migration or P2 completion is approved by this review.

## Narrow refinement review

The parent proposed a synchronous private hit-test gate for both the closing page and modal barrier, only in measured pointer mode. Accepted as the minimal honest graft from B. Its RenderProxyBox hitTest must read live route.closing and return false for the entire obsolete closing surface; a rebuilt IgnorePointer alone would retain the pre-frame publication gap. The underlying source Listener then receives the genuine down and performs the existing early push. This does not manufacture source provenance or add a global coordinate fallback. Both surfaces need the gate; gating the barrier while the page's content remains hit-testable is incomplete. Keep the strict four-route/four-handback recorded reopening outcome and document the extra render boundary in the synthesis.

The covered source-tail failure is refined by the parent's identified standard TickerMode behavior: an opaque covering route mutes the source State's SingleTickerProvider after handback. Do not defeat framework muting to force a blanket 'covered motion always ticks' claim. Characterize opaque cover as no source ticks, followed by successful finish after uncover; separately show a transparent cover leaves visible tail sampling active. The adapter must add no currentness-driven pause of its own. Update wording accordingly: passive motion is not canceled by input revocation, but normal Flutter ticker muting still applies. These are proposed corrections; this judge has not executed their validation.

## Subtractive refinement: retain original early-push scope

Accepted the parent's rollback of the extra source-Listener early-push condition for an already closing active route. The ownership repair requires a genuine source hit, not a new presentation lease before measured reopening. Pushing immediately on that closing-source down can relinquish the previous route before its measured handback and install an unrevealed replacement, changing lifetime and visible closing content despite superficially equal motion snapshots.

Restore the original `activeRoute == null` early-push condition. Keep the synchronous closing hit gates and source-origin acquisition; let the existing measured model/open-phase synchronization determine when a closing presentation gets replaced. This is a subtraction of an unneeded behavior change, not an acquisition fallback. Require the baseline recorded total of forty route handbacks as well as strict frame equality. Geometry-only green is insufficient proof when ownership history changes.

Pre-handback held reopening, any late-push pointer cancellation in that case, and replacement-content/focus continuity remain explicitly unproved. Do not add carry/pending-presentation phases to claim them repaired in this input-ownership unit. Recorded fast-tap reopening and already-established source-tail input after handback are the bounded contracts to retain.

## Final read-only implementation / simplification review

Re-read the final route and transfer diff plus the expanded 23 ownership checks, including the six new frame-removal, competing-source, Router-priority and revealed-Escape cases. Read `/tmp/morph-p2-input-second.log`: the parent's 17 ownership +20 recorded replay run ended **37 passing**, and the two fast-reopen traces again show four routes/four handbacks with their original sample counts452/883. I did not run tests myself; the final expanded prototype run is owned by the parent.

The two concrete stale-work findings above are corrected in the final patch. The session advance wrapper now captures its transfer and revalidates transfer/lease after its command-finally work. Pointer delivery revalidates transfer, lease, sequence and eligibility both after pre-advance and after the actual pointer method before publishing .pointer. The force-removal checks cover both synchronous tracking and a frame-delivered selected action; they establish that a replacement model is not reported as the removed route's old sample and can remain usable.

The original early-push scope is restored exactly to `activeRoute == null`. Both page and barrier use the private RenderProxyBox gate, whose hitTest reads live closing/disposed state rather than waiting for widget publication. There is no coordinate fallback or replacement presentation phase. The one sequence object remains the interaction identity, current source view constrains events, and the source ancestry check remains public SDK code. The reference switches translate cancelInput into an independent model command rather than fake binding delivery.

Cancellation remains scoped to a held interaction through existing model pointerCancel at its current canonical sample. No production timeline clear, pause, model replacement for cover, callback retiming or new keyboard handler appears. The explicit committed-release and due-action-second-up checks preserve the chosen release semantics. Opaque/transparent source-tail tests now describe normal SDK TickerMode behavior rather than forcing animation under an opaque cover.

The six new checks exercise real SDK integration: a second actual source hit beneath a hidden root preparation cannot create another source owner; Router Back is delegated to the root Navigator mixin unless an explicitly prioritized child consumes it; revealed Escape follows the popup's ordinary SDK action for plain and nested sources. They do not claim arbitrary Router policy or multiwindow integration.

**No additional concrete correctness issue or useful simplification found in this final diff.** Keep the existing bounded limitations: pre-handback held reopening/content/focus continuity, general view migration/multiwindow behavior, and interruption inside a single production runDue operation are not established by these tests. This review approves the prototype scope subject to the parent's final prototype/example/analyzer verification; it does not complete P2 or approve early-root lifecycle behavior for production.
