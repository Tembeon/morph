# P2: first content mount and early route lifetime

2026-10-16. Base `d121d18628242bfb7fefe54cc8df347542c82c79`, branch `wip/measured-liquid-glass`. Flutter 3.47.2 stable (`d3b14c876900e553bc736ca19295fc09e3853e8e`), Dart 3.13.2. Host `flutter_test`; no device or GUI launched. Exact source/artifact hashes and final results accompany this report.

**P2 remains open; no production presenter is selected.** This increment fixes first-policy-subtree readiness and early disposal in the reduced prototype. It characterizes real root/nested pointer and observer behavior. It does not approve the product cost of making an invisible preparation a real current root route.

## Ground, alternatives and chosen contract

`design/` preserves the local how/why findings, grounding, two structural candidates, fresh judge and implementation review. Source history and our reports establish that source-down push exists to avoid SDK cancellation of the original held pointer. The initial lifecycle test confirms root observer/currentness changes immediately, even when cancellation builds no content. Existing nested command-mode coverage did not establish raw pointer delivery; the new real down/move/up test does.

The first four-case run passed observer characterization and failed three checks: both immediate command-mode `maybePop` cases reported the public SDK `ModalRoute.willPop` assertion because its modal scope had not mounted; a coarse first frame opened and closed the model without ever constructing the vetoing PopScope. `initial-before.log` preserves it. The expanded pre-fix ten-case run passed two and failed eight (`expanded-before.log`). It predates later test additions; it is not a run of the final test count.

Architect compared A, deferred content with a first-subtree gate, and B, eagerly mounting inert hidden content. A retains zero builder/mount side effects for a canceled pre-hold press. B violates that existing obligation and still needs protection before the initial SDK modal build. A is selected (judge A13/15, B10/15); B contributes the explicit separation of route installation, actual policy existence and presentation/focus. The judge is a fresh run of the same inherited model as the candidates, not multi-model consensus. No human checkpoint was requested. Local source/history directly explains the decision; unrelated external personal accounts were not used to infer its rationale.

The private mounted State itself is the identity, rather than A's separate mount object. It builds the actual content, then signals once after frame completion, after ordinary descendant scope registration. The route derives readiness from this State's flag; no page-build count, reveal flag, modal-scope-only check or microtask is substituted for descendant mount. The existing dismissal attempt owns a cancellable mount wait and records whether it consults content policy. Model-origin close requests always do, including a close deadline before `_reveal`. SDK Back can cancel a still-hidden, not-yet-opening preparation without constructing hypothetical future policy. Revealed command-mode requests always await the real subtree. This is an explicitly chosen prototype early-cancel rule, not prior product approval.

All pending waiters use the same existing invalidation identity and one-success pop claim. Cover/uncover, remove/replace, unconditional programmatic pop and Navigator unmount wake canceled waiters as refusal; late mount signals cannot revive them. Ready synchronous model admission keeps its original measured deadline. A request delayed by mount uses the existing causal current-state close, not a backdated spring command. Arbitrarily later async-inserted widget policy follows ordinary currently mounted SDK semantics; the gate does not predict unknown future descendants.

## Verified lifetime refinements

The first mount implementation passed 10 of 13 checks. Remaining cases exposed two separate lifetime defects (`mount-before-disposal-fix.log`), rather than a reason to broaden the public policy interface:

- An unmounted overlay can finalize synchronously inside route sampling. Its clock was disposed before `onFrame` returned, then attempted to publish to a disposed notifier. Four direct clock tests also reproduce disposal from a frame listener, which additionally violates ChangeNotifier's no-dispose-during-notify rule (`clock-before.log`). The prototype clock now has terminal lifetime and notification-scope flags. Ticker/timer disposal is immediate; only notifier disposal waits for the current notification's finally. It skips publication/scheduling after a disposing sample and scheduling after a disposing listener. Tests pump 20 seconds past the proposed 10-second wake and assert one sample, expected publication count and no remaining frame callbacks. Ordinary clock timestamp/grid/dilation/doze formulas are unchanged.
- Immediate removal before the push microtask let SDK `Route.didPush` read true requestFocus and then dereference a detached Navigator. Route disposal now marks the route disposed first and requestFocus is false from that point. Live hidden/revealed focus behavior remains unchanged.

The genuine pre-disposal move/up case passes with the model's existing close clearing its pointer/timeline. No new model cancellation API was needed. A further fresh down during hidden closing did reproduce a ghost new PopupRoute (`rearm-before.log`): global input bypassed Navigator's temporary hit-test absorber and rearmed abandoned motion. The narrow handler guard declines model commands/new pointer acquisition only for a hidden closing route, clears matching genuine up/cancel session identity and reports ignored input. It does not suppress revealed reversal or invent binding events. A subsequent genuine source tap proves the session is not stuck. Terminal delivery after disposal is separately covered.

Rejected route/clock source snapshots accompany their failure logs. Final implementation review accepted the State simplification, bounded clock/focus lifetime changes and evidenced hidden-close guard. A new generic lifecycle API, epoch, duplicated policy tree, observer suppression, synthetic pointer replay and eager application content were not introduced. All code behavior changes remain under `example/lib/proto/`; production `lib/`, model, production clock, timeline, public exports, measured tuning and fixtures are unchanged.

## Navigation characterization and remaining limits

The nested real hold delivers down/move/up, opens the root popup, and mounts menu context under that popup/root Navigator. Source context remains in the nested Navigator. Root home is non-current immediately after source-down; local nested page remains current locally. Root observers see push/pop and `RouteObserver<ModalRoute>` covered/uncovered even for zero-content-build cancellation. These are genuine SDK effects. The prototype does not hide them or present them as final product approval.

Remaining gates include deciding whether that early root lifecycle is acceptable; hidden retained-focus traversal, nested Escape and Router/BackButtonDispatcher routing; inherited theme/context and accessibility; transformed/offset source coordinates; input under a different current route (including interruption of an already-held pointer); remaining menu API and full product bar/source-link geometry; carried optical field/native parity; device frame-time/energy; and P3 publication ordering. The new hidden-closing guard does not fix the independently discovered covered-visible-menu global-input path. The post-issued SDK-success/pre-commit atomicity limitation from the async report remains unchanged. No native fidelity or device performance claim follows from host evidence.

## Verification

From `example/`:

```sh
nice -n 10 flutter test --no-pub -j 2 --timeout 60s test/proto
nice -n 10 flutter test --no-pub -j 2 --timeout 60s test
```

From root:

```sh
nice -n 10 flutter analyze --no-pub
```

Final prototype suite: **194 passing** (previous175 +15 route-lifecycle +4 clock-disposal). The unchanged 20 strict recorded replays retain 2346 recorded inputs and 40 routes/handbacks. Six actual flat-scene comparisons retain 459 frames and zero differing pixels. Eight async timing configurations still pass. The complete example suite passes **284 tests**. Analysis then identified one redundant gestures import in the new test; it was removed and all **19 new targeted checks passed again** on final sources. This is the only source difference after the full runs. The final analyzer reports **no issues**, retained in `summary.json` and `analyze.log`.

The package suite was not rerun: production and package tests/callers are unchanged; the prior2362 passing/two skipped evidence is in `../admission/report.md`. No new production/gallery entry point invokes these prototypes. Formatting is scoped; analysis covers the whole package and example. Passing test logs are copied unchanged; trailing terminal whitespace in diagnostic/analyzer logs is stripped for repository checks without altering diagnostic content.

Scoped deslop removed the extra mount identity object in the sketch and used existing operation identity/state for wait cancellation and abandoned-press behavior. The retained wrapper is the actual descendant-mount boundary; both clock flags correspond to independently reproduced disposal failures. No-comments/main production code gate remains unpassed because this is unit0 prototype evidence. Main and unrelated owner work are preserved; no push is performed. No private UIKit source/tooling is used or stored in this increment.
