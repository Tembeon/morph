# Cross-judge: first content mount and early route lifecycle

Read-only architectural judgment against base `d121d18628242bfb7fefe54cc8df347542c82c79`. Ground, proposed early contract, how/why findings, candidates A/B, current route/transfer/model source, expanded lifecycle tests and the four-case failing log were read. No tests, agents, device work or repository edits were performed. These local candidates/judge share the inherited model; this is not different-model-family consensus.

## Choice and rubric

Choose A (deferred revealed content with a route-owned first-mount gate). B is a useful genuinely different alternative but inadmissible under the retained zero-build canceled-pre-hold obligation.

| Criterion (0..3) | A | B | Reason |
|---|---:|---:|---|
| Genuine pointer stream and strict replay preservation | 3 | 2 | Both retain early real push; A also retains deferred builder behavior. B must change an existing acceptance obligation. Both still need unchanged replay evidence. |
| Honest SDK observer/currentness semantics | 3 | 3 | Neither hides early real push or falsifies currentness. |
| Mounted-policy/first-mount safety without caller burden | 3 | 2 | A waits for real descendants and retains zero-build cancellation; B also needs a first-frame gate, while arbitrary eager child effects cannot be contained completely. |
| Nested Navigator/focus/Back correctness | 2 | 2 | Both specify standard root vs local behavior honestly; nested pointer, Escape and traversal require characterization. B additionally needs hidden eager autofocus containment. |
| Small implementation and clean cancellation | 2 | 1 | A needs one private wrapper/latch and existing request-local wait. B needs more presentation containment and cannot suppress arbitrary application build/mount side effects. |
| **Total** | **13/15** | **10/15** | Architectural scores, not substitute test results. |

## Base, grafts and rejections

Base A: keep the hidden branch empty; mount the actual builder subtree only on measured reveal. Its private State attaches before building children and publishes readiness in exactly one post-frame callback, after ordinary descendant `didChangeDependencies` registration. A bare reveal flag, page-build count, mounted Navigator, microtask or modal-scope readiness is insufficient. The first subtree can register policy; unknown future asynchronous descendants follow normal Flutter policy timing.

Graft B's explicit separation of installed route, content-policy existence and presentation/focus. Retain B's warning that unrelated new-pointer gating cannot prove covered held-pointer correctness. Keep the existing attempt's shared permission evaluation and single successful SDK claim, including local history. Preserve ready synchronous model admissions exactly; only pre-ready requests use the deferred causal path.

Reject eager hidden content, duplicate policy-only trees, public `canDismiss`/readiness APIs, late push without new genuine pointer proof, synthetic pointer replay, observer suppression and private Navigator-state adaptation. No production model/timeline/clock changes are justified by this gate.

## Approved simplification

A separate `_PolicyMount` object is unnecessary if the private wrapper State itself is the exact identity. A route-held `_MountedMenuPolicyState?` plus its one ready flag is sufficient for the one-shot revealed subtree. The State attaches in `initState`, schedules one post-frame signal, builds the supplied builder in its own context, and detaches the same identity in `dispose`. The signal checks `mounted` and identity; detaching cannot clear a newer State. Repeated notifier builds retain State, and readiness is not reset on ordinary rebuilds. Route readiness must not be inferred from `_revealed`.

The existing `_DismissAttempt` owns a nullable cancellable first-mount completer. Invalidation resolves that waiter false and permission `doNotPop`, clears the attempt, and every continuation rechecks the exact identity/current route/owner. Do not add an independent global awaitable that can leave a resolver suspended after cancellation. The one-shot mounted subtree may become ready while covered, but it must not authorize a canceled request. Marking readiness and approving a request are separate facts.

Either a private two-value enum or a clearly named boolean such as `consultPolicy` is sound. There are two meanings, not a growing public state machine. Derive the choice once at attempt creation: every model deadline is policy-bound even before `_reveal`; an SDK request may cancel preparation only while neither presentation is revealed nor the model is open. Command-mode open is revealed, so it always awaits mounted policy. Preserve publication of the permission completer before any callback/await.

## Hidden cancellation and genuine terminal events

The candidate correctly avoids claiming that an unbuilt `PopScope` vetoed preparation cancellation. This is a newly specified prototype rule, not historical product approval. Once presentation opening has begun, requests must wait for mounted policy. A coarse frame can cross both opening and close deadlines before the builder exists; admission must reject mutation, then reveal/mount, consult policy and close causally if allowed. Do not reveal inside `advance`.

Inspecting `MorphMenuMotion.close` shows it clears `_openPending`, timeline and model pointer before advancing. Therefore a hidden actual `didPop` already removes the held arm; adding a new generic production cancellation API is not needed for this path. Session `_pointer` is a separate identity and must clear on the real up/cancel. A narrow guard for a hidden closing route can decline further model commands while still accepting and clearing a genuine tracked terminal event. Do not return before terminal cleanup, and do not apply this to revealed closing reversals.

The current expanded Back test releases only after route disposal. It does **not** prove the dangerous interval. Before accepting implementation, add genuine down → root `maybePop` → move/up **before any disposal frame**, assert no menu build/reopen, then advance to rest. Also exercise a real terminal event after disposal while the source has been reset. Report whether the event was deliberately ignored for mutation versus consumed for pointer cleanup. No fabricated `PointerCancelEvent` should replace real binding delivery. If a new source-down can occur while the old hidden close still owns the session, it must not acquire/rearm that abandoned route; a hidden-closing early return must not leave a new pointer identity stuck.

For SDK permission selected while still hidden, the preparation decision must remain tied to that exact attempt, never become authorization for a replacement route. If implementation allows opening/reveal to race the outstanding cancellation before its `didPop`, test that transition explicitly or tighten the abort behavior; do not silently use a hypothetical unbuilt-policy answer as general menu permission.

## Evidence required and boundaries

Required positive evidence: immediate command-mode `maybePop` with PopScope true/false; async guard discovered on first mount with concurrent callers; coarse frame initial policy veto; hidden zero-build Back cancellation with pre-disposal terminal input; wait cancellation by cover/remove/replace/unmount/programmatic pop; stale post-frame callback harmless; root nested raw down/move/up retains the actual stream and root/local observer/currentness values; unchanged recorded replays and full example checks.

The current observer test is a valuable honest characterization: a root popup is current immediately, the root page becomes non-current, a local nested page remains current in its own Navigator, root observers see push/pop even with zero content builds. Those facts are unavoidable for the chosen early **real** route. They are not approval of this as final product architecture. `requestFocus:false` retains primary focus but does not preserve underlying route traversal participation. Nearest nested `Navigator.maybePop`, Escape under nested retained focus, Router/BackButtonDispatcher, transformed geometry, inherited context capture and accessibility remain explicit gaps unless independently tested.

Keep the already documented post-issued SDK-success atomicity limit. The gate can cancel pending work; it cannot revoke a pop answer already delivered to Navigator. Do not close P2 or choose a production driver from this bounded proof.

## Verdict

Proceed with A using State identity and a private readiness flag, plus the existing attempt-local cancellable wait and a two-meaning preparation/policy distinction. The design addresses the reproduced modal-scope assertion and unbuilt-policy bypass without new caller burden. Acceptance remains conditional on the genuine pre-disposal terminal-event test, pending-wait cancellation proof and unchanged replay validation; the current four-case negative log is not evidence that those additional cases already pass.
