# Why: pointer ownership under cover and nested dismissal

Read-only source investigation, 2026-10-16, base `cfade8834496cc0cf580230b0e097e172ec27514`, repository `/Users/tembeon/IdeaProjects/morph`. No agents, tests, device, GUI, network, or external accounts used. Scope: rationale and change constraints for covered input and nested Escape/Back, not product approval of the early-root presentation architecture.

## Code anchor and lineage

- `example/lib/proto/menu_route_probe.dart`: source Listener at 132–143, global registration at 185–187, route admission at 233–243, `syncInputPhase` at 328–357, `handlePointer` at 360–396, `didChangeNext`/`didPopNext` at 598–611, focus at 614, real route/pop at 644–680.
- `example/lib/proto/menu_transfer_probe.dart`: complete model plus exclusive lease/canonical offset; `pointer` delegates real down/move/up/cancel at 81–99.
- `lib/src/widgets/menu_motion.dart`: explicit close at 2462, down at 2522, release at 2692, cancellation at 2744, `advance` at 2760, scheduled action/dismissal at 3030–3047 and 3100–3148. Line numbers identify the current base; declarations are authoritative if formatting later shifts them.
- `git log --follow`, blame of input adapter, and full commit messages inspected: `7d0968a7` root PopupRoute; `5bad38c8` recorded pointers/early push; `9fcf9d19` pre-close admission and flat outline; `d121d186` causal async dismissal; `cfade883` first policy mount and early lifetime. No PR/ticket references in these messages or the five stage reports (negative grep).

## What we found — direct rationale

1. **Whole-model transfer exists to preserve state beyond a spring.** `tool/audit/foundation-p2-2026-10-16/report.md` explicitly replaces per-spring rebase with canonical time and an owner offset because the menu also owns driven kicks, fusion history, scheduled reactions and a remaining tail. Unique route leases reject stale writers. This is an invariant, not a legacy mechanism to delete while fixing input.
2. **Early source-down root push exists to preserve the real held stream.** `input/report.md:55–59` records a negative control: a later imperative push calls SDK active-pointer cancellation, clears the original hit path and subsequent physical move/up no longer reach even the global route. Ignoring cancellation cannot reconstruct that path. The source therefore processes its down and pushes before the ancestor Navigator Listener records it. Content/focus stay deferred, and cancel-before-hold builds no menu content.
3. **The global subscription is part of continuity across source/route ownership.** `input/report.md:47–49,55–59` requires every accepted original event and canonical time, including hold/drag and pointer-clock offset; replay equivalence and subscription cleanup are recorded. Blame attributes the global stream adapter to `5bad38c8`, with only the hidden-closing exclusion added by `cfade883`. No historical statement approves input to a covered visible menu.
4. **Cover invalidation currently concerns dismissal permission only.** `menu-dismissal-protocol.md:34` specifies canceling pending async work on cover/uncover, replacement, removal and lease change. `menu_route_probe.dart:598–611` does that; the current `handlePointer` has no currentness check. The lifecycle report explicitly leaves covered-visible-menu global input and interruption of a held pointer open (`lifecycle/report.md:34`). This is an acknowledged gap, not a product requirement to keep tracking through cover.
5. **Admission protects presentation, not already selected actions.** `admission/report.md:17–21` preserves original scheduled synchronous close deadlines, leaves opening intact after veto, honors LocalHistoryEntry and explicitly states the model still runs an action whose dismissal is refused. The async report/protocol preserves first-request provenance but commands later approved closing from current state; no backdated kick reconstruction.
6. **Early root lifecycle remains an architectural cost.** The lifecycle report characterizes observer/currentness changes before reveal and explicitly declines to approve that product cost. Hidden Back canceling preparation without constructing hypothetical content policy is a chosen prototype rule. Actual revealed policy needs the mounted subtree. New input work cannot make early root observer/currentness invisible by assertion.

## What source establishes about cancellation — supported constraints

- `pointerCancel(t)` advances all events already due at `t` before clearing the model pointer, relaxing flex/press and clearing highlight. It neither clears the whole timeline nor closes the presentation. A pending hold callback checks pointer identity, so removing the pointer prevents a future hold; delayed action callbacks after a prior release do not require that pointer.
- Consequently cancellation must be expressed at the active owner's canonical boundary, and both adapter pointer identity and model pointer identity need coherent cleanup. Clearing only `_MenuSession._pointer` can strand the model's held state. Sending only cancel without forgetting the adapter can strand the adapter stream and reject the next genuine down.
- An already released selection is distinct from an interrupted held sequence. Cover does not retroactively undo an action already committed/scheduled by release. Explicit `close` would erase timeline/pointer and change phase, bypass SDK veto and alter visual behavior; it is not a replacement for input cancellation.
- The admission callback currently rejects a non-current route, but that alone is not input isolation: highlight/flex, submenu movement and action callbacks can still mutate/fire while covered. The fix needs to stop acceptance before those commands enter the model, not merely block Navigator pop later.
- Route cover can occur synchronously inside an action callback or navigation. Reentrancy and `pointerCancel`'s initial `advance` deserve care: avoid a second concurrent writer, recursive drain, stale lease call, or rereading route/clock after disposal without identity checks. No runtime failure is claimed here; these are source-supported risk paths for reproduction.

## Nested Escape/Back: SDK contract vs product promises

Public local Flutter SDK inspected, Flutter 3.47.2, framework `d3b14c876900e553bc736ca19295fc09e3853e8e`:

- `widgets/app.dart:1272` (and platform maps) maps Escape to DismissIntent.
- `widgets/routes.dart:975–989` installs `_DismissModalAction`: enabled by the route's `barrierDismissible`, invocation uses `Navigator.of(context).maybePop()` at the action's own modal context.
- `widgets/app.dart:1608–1620` handles platform Back using the WidgetsApp Navigator's `maybePop`; Router delegate configuration returns false here and delegates to BackButtonDispatcher.

Supported reading: focus determines the action resolution chain. A revealed root popup focus subtree can route Escape through its own modal action/root Navigator even when its source lives in a nested Navigator. A hidden route deliberately retains underlying focus, so nested action resolution can differ. Existing command-mode focus restoration test and nested raw-pointer replay do not prove hidden nested Escape or Router dispatcher behavior.

Unknown: whether the product wants hidden Escape always to cancel root preparation rather than follow the focused nested route; how an app's custom Actions, Shortcuts and Router dispatcher priority should interact; full accessibility dismissal behavior. There is no evidence for inventing a global keyboard handler, always choosing root for Back, suppressing nested behavior, or promising every nested route dismisses root first. Characterize ordinary SDK behavior and state the chosen prototype contract precisely; don't turn an observed focus path into a universal guarantee.

## Preserve / Change / Avoid / Risk

**Preserve**

- One complete motion object, unique lease, canonical occurrence/delivery timing and the actual pointer event stream.
- Existing recorded hold/drag selection/reopen and real-cancel behavior; early push ordering remains until an alternative proves it can retain the stream.
- SDK policy/local history/async coalescing; cancellation of a physical interaction is not permission to dismiss.
- Visible motion and queued committed actions continue unless a separately stated contract changes them.
- Zero content-builder side effects on canceled uncommitted press; source-independent live route lifetime; subscription cleanup.

**Change**

- Block new global input while the menu's presentation route is covered/non-current.
- Reconcile an already held sequence on coverage once, clear both stream-owner records, and prevent its physical late move/up from selecting after uncover.
- Verify source-only phase as well as active route phase: when activeRoute becomes null after hand-back, the original source may still sit beneath another root route. A null activeRoute is not evidence the source is eligible to arm.
- Characterize nested Escape/Back with actual binding/focus/SDK actions and distinguish hidden vs revealed presentation.

**Avoid**

- Auto-close on cover, close-then-reopen rollback, copying/replacing motion to clear input, timeline-wide clearing for ordinary cover, ignoring real cancels, synthetic down/move replay, process-wide Escape interception, observer suppression, invented guaranteed root-first nested Back behavior.
- Describing initial pre-mount/hidden cancellation semantics as policy from widgets that never mounted.

**Risk / unknown**

- Cancel's `advance(t)` can execute due action callbacks before pointer removal; already committed releases are not generally revocable.
- Nonopaque cover vs fully occluding page may have different visibility, but currentness determines route interaction ownership in the proposed guard; product choice about coexistence remains explicit.
- Source listener ordering, nested navigators, cover/uncover in one stack update, forced removal, source teardown and action-driven reentrancy need real checks.
- Existing post-issued SDK-success/pre-commit atomicity limit remains; this work cannot repair it by a pointer guard.
- P2 full bar, source transforms, optical field/native parity and device frame-time/energy remain open.

## Sources consulted / category coverage

- Source control: local git log/follow, blame, five commit messages, current source, tests, five stage reports and dismissal protocol. Directly relevant complete local rationale. No PR/ticket identifiers found in the scoped messages/reports; no remote query needed for this local unpublished prototype.
- Issue/ticket tracker: no linked artifact in inspected lineage; unrelated personal task accounts provably do not record this newly authored local protocol. Skipped external queries; not evidence no unrelated product tasks exist.
- Long-form documents: in-repository protocol/sketch/review/stage reports inspected. External personal documents have no linked authority for this freshly recorded decision; skipped external queries.
- Real-time team chat: no linked team discussion and this is owner/agent local prototype history. External personal chat has no established connection; skipped. User's visible conversation establishes library goals, not an unspoken nested keyboard guarantee.
- Infrastructure observability: skipped as provably irrelevant to rationale of deterministic local widget-test-only prototype; no deployed infra dependency.
- Error/exception tracking: failures are retained host test logs/rejected sources referenced by stage reports, not a deployed crash pipeline. No relevant connected error service; skipped external queries.
- Product analytics warehouse: skipped as provably irrelevant; no cohort/experiment or analytics-dependent threshold in this adapter, measured native tuning is unchanged.

## Confidence summary

High/direct: whole-model rationale, early push/global stream need, cancellation negative control, acknowledged cover-input gap, exact admission/time constraints, unapproved early-root lifecycle cost. High for source mechanics, supported for cancellation/change constraints. Supported SDK paths; inferred focus-dependent nested outcome until tested. Unknown product choice for hidden nested Escape, custom routing/Actions and Router integration. No tests run by this investigator; previous passing counts are historical evidence only.
