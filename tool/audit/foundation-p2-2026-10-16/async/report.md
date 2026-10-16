# P2: causal asynchronous dismissal

Date: 2026-10-16. Base: `9fcf9d19` on `wip/measured-liquid-glass`. Flutter 3.47.2 stable (`d3b14c876900e553bc736ca19295fc09e3853e8e`), Dart 3.13.2. Host: macOS `flutter_test`. Hashes and exact final counts are in `artifacts.json` and `summary.json`.

**P2 remains open.** This increment proves permission from already-mounted SDK policy, coalesced guard evaluation, a single consumable pop permission, causal closing, and cancellation while awaiting. It does not settle policy discovery before the first content mount, the early route's full observable lifecycle, complete menu/bar geometry, optical carry or device/performance gates.

## Grounding and design

The original pointer reproduction called no registered async guard at all: after outside input its callback count was zero instead of one. `async-before.log` preserves that failing initial small test. The positive version remains in `menu_route_async_test.dart` alongside the expanded cases. A separate negative control shows that `advance(2); close(1)` cannot reconstruct earlier kicks: analytic progress can agree while driven geometry differs. Its measured values are emitted as `P2_BACKDATE` in the final prototype log.

Architect grounding traced current model/clock/route behavior and the historical rationale in `7d0968a7`, `5bad38c8` and `9fcf9d19`. Two independent design attempts plus a fresh judge used the same inherited model; this is not multi-model consensus. Candidate A keeps a route-owned transaction and existing model admission. Candidate B yields integration at a typed request boundary and resumes the same timeline step. The selected P2 shape uses A, with B's existing paused-time policy and completion at an owner step. Yielded model/timeline stepping remains the future unit-2.4 change, not a new production migration here. A's new continuously elapsed idle clock and both candidates' mandatory first-build barrier were rejected for this increment.

`design/` contains the exact grounding, candidates, judge verdict and implementation review copied from this run's isolated temporary design directories. The local protocol is `docs/architecture/menu-dismissal-protocol.md`. There was no requested human checkpoint; implementation followed the synthesized design. No unrelated external account was searched to infer the motivation of this fresh local prototype.

## Runtime contract

Application call sites remain SDK `PopScope`, `Navigator.pop` and, for compatibility evidence, deprecated `WillPopScope`. No public async guard, dependency, production host caller or extra application setup is introduced. Only `example/lib/proto/menu_route_probe.dart` and prototype tests change behavior. The existing internal admission seam, production model, timeline and clock remain byte-for-byte unchanged from the base.

The route owns one pending attempt. Its object identity is the operation generation; invalidation clears it and never reuses that object. A separate numeric epoch was removed during deslop because it duplicated exactly the same invalidation. `didChangeNext` tracks real next-route identity changes; `didPopNext` also invalidates, so cover/uncover before resolution cannot revive an old attempt.

The admission callback only observes framework state and records the request. A mounted scoped async guard makes it refuse closing immediately, then the host invokes policy after input/advance returns. A prepublished Completer makes a guard that synchronously reenters SDK `maybePop` share the same evaluation. Pending requests coalesce. False retains the open model; a throwing guard reports once through `FlutterError`, fails closed and permits retry. Selection/action behavior is not rolled back by dismissal refusal.

After awaiting, the route checks identity, active presentation, currentness, mounted Navigator, lease ownership and nonclosing/nondisposed state. It rereads modern `popDisposition`. Approved model-origin work wakes existing clocks using `resumeAt(now())`; after a subsequent owner sample, before frame notification/painting, it revalidates and attempts pop. The instrumentation stream observes `.frame` and then `.close`; it is not itself the renderer's publication API. SDK `maybePop` may win before that queued owner step; actual `didPop` then closes from the current owner state and invalidates queued work. SDK local history is consulted first and can consume pop without changing closing channels.

Programmatic `Navigator.pop` keeps its unconditional SDK semantics and invalidates pending work even when it only consumes local history. Removal, replacement, relinquishment, entire Navigator disposal and temporary cover/uncover cancel pending permission. Source-only removal intentionally keeps an already-presented current route valid; it finishes without hand-back to a disposed source. Internal permission futures complete as refusal on cancellation, but arbitrary application futures cannot be cancelled; their later values are discarded.

## The shared-success failure and fix

Independent implementation review found a defect after the first 23 new async tests passed. Two SDK `maybePop` callers awaited the same successful permission future. With one `LocalHistoryEntry`, the first pop consumed history and invalidated the attempt, but the second SDK continuation already had success and popped the menu. `shared-permission-before.log` reproduces this failure. `rejected-shared-permission-route.dart.txt` is the exact rejected route implementation; the final two focused tests preserve its acceptance criterion.

The final protocol shares **guard evaluation**, not unlimited successful pop responses. Each `willPop` caller awaits the underlying permission future, rechecks live identity and atomically claims one success. Additional callers receive `doNotPop`. This produces at most one pop attempt for the coalesced operation, including history consumption. If SDK wins, `didPop` cancels the model's queued work; if the internal drain wins the claim, its owner step performs the sole pop. The judge inspected and accepted this narrow refinement; no new production gate or global `didPop` veto was added.

There is an explicit SDK boundary: success already returned to SDK cannot be revoked retroactively. SDK then applies its own final-entry/current-policy checks. The stronger guarantee of atomicity from issuing success through SDK navigation commit, including an instantaneous cover/uncover in that interval, remains open. Direct standalone `Route.willPop` querying without subsequent Navigator consumption is not a verified prototype API. The passing cancellation tests concern pending guard/queued model work, not an unqualified transactional replacement for SDK navigation.

## Causal time and proof

The plan's former unconditional “preserve original reaction time” is refined, not claimed silently satisfied. For immediate synchronous model admission, the original measured deadline still starts closing. For an asynchronous request, `requestedAt` identifies the first request; for SDK-first coalescing this is its current sample, not a later model deadline. A delayed close begins from the owner's current state and never backdates below its last sampled time. The dismissal delay is not added a second time.

Canonical settled time continues to pause as before. Ten wall-clock seconds waiting at rest do not become a ten-second jump in model time. Existing `resumeAt` retains delivery lag when restarting the ticker. No new command-stamp API, copied spring state, rewind, progress decorator or close-then-reopen rollback was added.

Eight configurations compare every observed command/frame against an independent model that receives identical pointers and remains open until the actual current-time close command: 60/120 Hz, 1x/5x, waiting during opening or settled idle. Progress, kicks, fusion, opacity and all tested blob coordinates agree within the same 1e-8/1e-9 bounds used by the harness. Opening continues during the guard wait; a real move/up while waiting still reaches the model and shares permission. Settled waiting adds no motion samples for ten seconds. Every route disposes, the source tail reaches rest, and scheduled callbacks finish. `P2_ASYNC_TIME` records requested/start times and sample counts.

These are current-state adapter-equivalence checks, not new native recording tolerances. Existing 20 strict replays, their 2346 recorded inputs/actions and 40 hand-backs remain unchanged. The six actual flat-scene comparisons still cover 459 frames with zero differing pixels. No fixture, tolerance or measured constant was edited. Route-level doze is not claimed: this reduced route returns `wakeTime: null`; separate existing clock doze/resume tests remain in the suite. Active changes of `timeDilation` during a transfer are still unproved.

## Verification

From `example/`:

```sh
nice -n 10 flutter test --no-pub -j 2 --timeout 60s test/proto
nice -n 10 flutter test --no-pub -j 2 --timeout 60s test
```

From the package root:

```sh
nice -n 10 flutter analyze --no-pub
```

The final prototype suite passes **175 checks**: previous 149 plus 25 async scenarios and one new backdating negative control. The final complete example suite passes **265 tests**; the package analyzer reports **no issues**. Final logs and `summary.json` retain these results. The earlier full example snapshot passed 263 tests before the two-SDK-history finding; it is preserved separately and is not mislabeled as final validation. The time-dilation test initially used addTearDown, which runs after Flutter's no-time-dilation invariant check; changing it to finally fixed the harness. A redundant gestures import was removed after analysis. Neither fix changes motion expectations.

Package production code/tests and their callers are unchanged; the prior complete package result, 2362 passing with two skipped, is linked from `../admission/report.md` rather than claimed rerun here. Source search confirms the prototype has no production/gallery entry-point caller. Native build/autodemo/device/performance checks are not performed because this remains a host-only, unwired experiment. No device lock was acquired or owner settings changed.

Passing test logs are copied unchanged. Trailing terminal padding in failure/analyzer logs is stripped for repository whitespace checks; diagnostic content is retained.

Scoped deslop removed the redundant numeric epoch and unnecessary import; it retained the separate approval/claim states because the reproduced double-pop failure needs that distinction. The independent review accepts the implemented shape and single-use fix with the SDK boundary above. Unit 0's future main code gate is still unpassed; this does not substitute for deslop/no-comments on production migration. Main and unrelated owner work are unchanged, historical reports are preserved, and no remote push is performed.
