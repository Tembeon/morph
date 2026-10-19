# Implementation review: first mount and newly exposed clock disposal

Read-only review of the current working implementation against `d121d186`. Inspected route diff, full prototype clock, expanded lifecycle tests, `/tmp/morph-p2-lifecycle-mount-failure.log`, and relevant public SDK `Route.didPush`/`ChangeNotifier.dispose`. No tests, agents, devices or repository edits. Same inherited model as the earlier candidate/judge artifacts.

## First-mount implementation

The narrow implementation follows the accepted design: State identity plus `_ready`, one post-frame signal, child builder under that State, attempt-local `Completer<bool>`, a captured `consultPolicy` distinction, and current-identity cancellation before resumed SDK evaluation. Mounted synchronous model admission remains unchanged; the gate only defers unready or async-policy attempts. Invalidation wakes both wait channels. Ordinary subtree rebuild retains the State. No unnecessary `_PolicyMount` object or public API was added.

No blocking issue found in the reviewed mount gate itself. The recorded first run is 10 passing / 3 failing; it establishes that immediate revealed PopScope policy and coarse-frame veto are now reached, but does not finish acceptance. Pending request invalidation on remove/pop is exercised yet interrupted by independent lifecycle failures described below.

## Reentrant clock disposal: approved direction, incomplete two-guard proposal

The hidden Back and immediate programmatic pop failures directly justify a narrow prototype clock fix. A frame invokes route sampling; projection notification can synchronously finalize an unmounted overlay route, disposing its clock before `onFrame` returns. Writing `_frames.value++` afterward accesses a disposed notifier. Adding a private terminal `_disposed` flag set at the beginning of `dispose`, checked immediately after `onFrame`, is appropriate. It changes lifetime handling rather than time mapping, sampling order, motion state or measurement constants. It should return before notifier access, ticker stop, timer creation or other scheduling work on that disposed instance.

Checking again after frame notification is also appropriate for reentrant listener-driven disposal. However, **that second check alone cannot support disposal from a frame listener**: `ChangeNotifier.dispose` asserts `_notificationCallStackDepth == 0`. The current `clock.dispose` calls `_frames.dispose` synchronously, so a listener calling it fails inside notification before the proposed later check executes.

If listener disposal is part of the intended supported lifetime contract, use a private notification-scope flag and `try/finally`: mark the clock disposed and cancel timer/dispose ticker immediately; defer only `_frames.dispose` until `_frames.value++` has unwound. The flag does not own time or add a lifecycle API. Check `_disposed` after the finally before interpreting the returned outcome. An equivalent small internal mechanism is acceptable. Avoid merely swallowing the SDK assertion or deferring arbitrary clock work until a future frame. Ensure disposal of the notifier occurs exactly once. No need to make unrelated public post-disposal calls silently valid.

The proposed four tests (disposal from `onFrame` or a frame listener, each with settled and future-wake outcomes) are meaningful direct regression tests. Check no exception and no later frame/wake callbacks, not only `transientCallbackCount` immediately after disposal: a wrongly scheduled doze timer may not yet be visible as a frame callback. An undisposed control is already covered by existing clock tests; preserve them and strict route replay evidence.

## Immediate removal is a separate SDK callback hazard

The remove failure is **not** the clock issue. Its stack points to public SDK `Route.didPush` at navigator.dart:273: a completion continuation reads `requestFocus`, then dereferences `navigator!`. Immediate removal before the push microtask can leave navigator null while this route still reports `requestFocus == true` in command mode. A clock guard cannot address this.

The route's `requestFocus` should be false once it is no longer installed/live, while preserving the existing false-hidden/true-revealed behavior during ordinary push. A `navigator != null` condition directly protects the SDK dereference; a disposed flag is sufficient only if its assignment precedes every such callback. This is a lifecycle refinement, not fake currentness or observer suppression. Do not suppress focus solely because the route is temporarily covered unless that additional behavior is deliberately characterized. Preserve the separate hidden focus/traversal caveat.

## Genuine terminal input still required

The current hidden Back test sends up only after disposal. It cannot show that the existing input path is safe while a logically popped hidden route remains alive. Add the proposed real binding down → maybePop → move/up before a disposal frame, then advance to rest. Because production `motion.close` already clears model pointer and timeline, no hidden input guard is justified unless that test exhibits an actual mutation/reopen bug. Retain the post-disposal real terminal case as separate evidence. Do not replace terminal events with synthetic cancellation.

## Verdict

Mount gate accepted provisionally. Prototype-only reentrant clock lifetime fix approved in principle, with the concrete notifier-during-notification issue above requiring handling before claiming frame-listener disposal support. Immediate-remove focus continuation needs its own narrow protection. Final acceptance requires passing genuine pre-disposal terminal input, first-mount cancellation cases, the four direct clock lifetime tests, unchanged strict replays and appropriate full example/analyzer validation. P2 and production architecture selection remain open.

## Final refinement review

Inspected the final route/clock diff, both genuine hidden-terminal/new-down cases, all four `clock_disposal_test.dart` cases, the 18-case passing targeted log, and the preserved new-down failure log/source. No tests were run by this reviewer.

The clock fix now resolves the prior issue: disposal marks `_disposed` first, cancels timer and ticker immediately, and postpones only the notifier's disposal while `_publishing` is true. The `finally` disposes that notifier after notification unwinds, and the checks after `onFrame` and publication avoid later scheduling work. All original time/grid/stamp/doze calculations remain unchanged. The four tests pump 20 seconds past the proposed 10-second wake, so they cover stray delayed wake as well as immediate notification counts. Double-disposal and arbitrary calls after disposal are not newly promised.

Moving route `disposed = true` to the beginning of disposal and returning `!disposed && _revealed.value` for requestFocus handles the SDK push-focus continuation without changing hidden/revealed focus while the route is live. This refinement is accepted.

The new-down negative control justifies the narrow input guard that had previously been conditional on evidence. It reproduced a ghost new PopupRoute after a new press arrived while a hidden logically closed route still owned the session. The guard applies only to `activeRoute.closing && !activeRoute._revealed.value`, declines new acquisition and model mutation, and clears a matching genuine up/cancel session pointer before returning. It emits ignored input rather than inventing a binding event. Revealed closing reversal keeps the previous path. The two focused tests also demonstrate subsequent ordinary source taps can open again, detecting stuck pointer ownership. No broader covered-route input claim follows from this guard.

Final structural verdict: the first-mount gate, prototype clock disposal refinement and evidenced hidden-close input guard are accepted. The targeted log reports 18 passing checks before the newly added nineteenth case; the new-down failure log preserves the rejected behavior. Final nineteenth-case/full-prototype/example/analyzer results are the parent's verification responsibility and must be recorded before delivery.

Scope remains prototype-only. `git diff --exit-code d121d186 -- lib/src/widgets/clock.dart lib/src/widgets/menu_motion.dart lib/src/motion/timeline.dart` returned zero in this review. No public exports, production clock/model/timeline, measured tuning or native reference source was changed by these refinements. Reviewed material consists of own prototype/test evidence and public Flutter SDK; no private UIKit reverse-engineering source was introduced or consulted. Existing unrelated owner WIP was only visible in status, not edited. Early real SDK route/currentness and the post-issued-success atomicity limit remain as documented, and P2 remains incomplete.
