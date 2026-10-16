# P2: input ownership and SDK dismissal scope

2026-10-16. Base `cfade8834496cc0cf580230b0e097e172ec27514`, branch `wip/measured-liquid-glass`. Prototype only; main stays `b0c3fc20763ee15899ace5b820c6c29d89357ad9`. Product presentation architecture and full P2 remain open.

## Result

A closed source no longer acquires another page's pointer from matching coordinates. Source acquisition requires its genuine Listener hit, primary button, matching View and currentness through all modal/Navigator ancestors. Current non-closing popup acquisition remains binding-global; transport and authority are separate.

Cover revokes a held sequence immediately. Its model cancellation runs at canonical model time after the outermost model command, avoiding callback reentrancy into half-finished pointer work. The late physical tail cannot select after uncover. A valid release that already committed its measured delayed action retains that action, including under cover. No timeline clear or synthetic binding cancellation is used. Pre-advance and post-pointer checks validate exact transfer, lease, sequence and eligibility, so callback-driven cover/remove cannot commit a second release or publish an old event with a replacement frame.

Both closing page and barrier use one private live RenderProxyBox hit gate; logical closing disables hits before rebuild while drawing and hand-back continue. Original early push only when activeRoute is null is retained. Standard SDK TickerMode still mutes an opaque-covered source ticker; transparent-cover tails finish and opaque-covered tails finish after uncover. Production model, timeline, clocks, hosts, tuning and public exports are unchanged.

## Design and rejected experiments

`design/` preserves ground, how/why, two structural candidates, judge, refinements, implementation and comment reviews. A retains global transport with scoped acquisition, B uses per-pointer transport and local surfaces plus a temporary pre-render bridge. A won 13/15 versus 10/15; acquisition/transport separation and the synchronous closing hit gate were grafted from B. Independent roles used one inherited model, not different model families.

| Artifact | Observed result / decision |
|---|---|
| initial-before.log | 7 tests:4 pass / 3 fail; covered closed/open input reproduced, keyboard characterization retained |
| expanded-before.log | 15 tests:6 pass / 9 fail; held input, reentrancy and source-tail assumptions exercised |
| first-implementation.log | 35 tests:32 pass / 3 fail; real source provenance exposed stale closing hit surfaces, opaque-tail expectation was wrong |
| rejected-acquisition.patch.gz | Losslessly compressed source diff for initial acquisition implementation before closing hit gate/refinements, relative to base |
| refined-implementation.log | 37 tests:36 pass / 1 fail; tracking removal exposed stale observation; extra closing-source early push reduced fast-reopen hand-backs 4→2 despite geometry agreement |
| targeted-tests.log | 37 pass after rollback of extra early push and stale-work fixes;17 ownership + 20 replay; all 40 hand-backs restored |
| prototype-tests.log | Final23 ownership + 194 previous = 217 pass |

The intermediate refined implementation was not separately snapshotted; its log is retained as failure evidence rather than a reproducible source revision. No fixture, tolerance or measured tuning was weakened. No global coordinate fallback or key interceptor was added.

## Validation

Flutter 3.47.2 stable / Dart 3.13.2, framework `d3b14c876900e553bc736ca19295fc09e3853e8e`. Heavy jobs ran serially at nice 10, test concurrency 2.

```sh
cd example
nice -n 10 flutter test --no-pub -j 2 --timeout 60s test/proto
nice -n 10 flutter test --no-pub -j 2 --timeout 60s test
cd ..
nice -n 10 flutter analyze
```

- 217 prototype tests and 307 example tests pass; analyzer has0 issues; scoped formatter reports0 changed. One ignoredPointer dartdoc description was broadened after the prototype run; no behavior changed. Full example and analyzer completed afterward.
- 23 new ownership tests include covered source/popup, held source/menu with immediate uncover, committed release, tracking/due callbacks, forced/frame removal, source tail/TickerMode, two sources, revealed/hidden Escape and actual binding Back with root/priority-child Router dispatch.
- All 20 recorded replay metrics exactly match lifecycle summary: 2346 inputs, 40 routes and 40 hand-backs, including fast reopen 4/4 at both rates.
- All 8 async timing configurations and 3167 samples match; all 6 flat scenes/459 frames at 3× have0 changed pixels. Summary retains the backdating negative control. These are adapter/model and same-renderer comparisons, not native-device pixel proof.
- Production package suite was not rerun because no production code/caller changed; historical 2362 pass/2 skip remains in `../admission/report.md`. Full example includes the owner's unchanged bar WIP. No device/GUI run or performance claim.
- Final independent implementation/deslop review found no further concrete issue. Comment Sicko found 0 deletions/0 reshapes/0 restores/0 reruns/0 open constraints; public dartdoc and existing prototype suppressions retained under the project contract.

Passing logs are copied unchanged; failing/analyzer logs have trailing line whitespace stripped. `artifacts.json` records final source/evidence SHA256, unchanged core files and unrelated worktree context. It does not hash itself. Historical evidence directories remain unchanged.

## SDK outcomes and remaining limits

Revealed Escape closes the root popup in plain/nested WidgetsApp. Hidden Escape retains source focus and preparation; actual platform Back cancels it without invoking menuBuilder. Router root delegate forwards Back to Navigator, while a priority child that handles Back keeps root preparation current. These characterize actual SDK routing; no universal root-first guarantee is made.

Still open: accept/reject early push observer/currentness/traversal cost and choose product hidden-key behavior; pre-handback held reopen and stateful content/focus continuity; inherited context/accessibility, multi-View/view migration and transformed source geometry; remaining menu API, full bar/optical carry, device fidelity/frame time/energy and P3 ordering. The single advance still drains runDue before returning; selective interruption of already-issued effects belongs to unit 2.4. More atomic SDK-success-to-commit behavior is unproved. View ID filtering alone does not prove multiwindow correctness.

Protocol: `docs/architecture/menu-input-ownership.md`. P2 is not complete and this prototype has not passed the code gate for main.
