# P2 source environment

2026-10-16, base `65b080d3a0ff178d57509f2f5fc9613ef88fafce`, branch `wip/measured-liquid-glass`. Prototype only. No main/push, production migration or full P2 acceptance.

## Result and contract

Source-local DefaultTextStyle, IconTheme and custom InheritedTheme reach root popup content through public SDK InheritedTheme.capture/CapturedThemes.wrap. Capture stops at the exact root Navigator selected for push. Source subscribes only to actual nearest ancestor theme elements; didChangeDependencies acquires new snapshots. No motion tick walks ancestors.

Every route owns its accepted snapshot and one pending slot. Source dependency/build changes only queue data; post-frame publication avoids notification into a sibling popup during build. Pending replacement precedes equality suppression. There is no separate queued flag, initial-kind list, revision counter, global carrier or new caller API. Stable child placement and unchanged wrapper kinds preserve editor State, controller, focus and PopScope.

Route callbacks do not read or retain a source context. Source removal leaves the latest acquired data independently owned by the popup; normal root theme/system updates continue. Disposed routes clear pending data and notifier. Same-Navigator identity bounds refresh acquisition; closing-but-live presentations may update their own themes without receiving motion/input authority.

Non-theme inherited environment comes from the destination. Root MediaQuery, locale/delegates, Directionality, Navigator/ModalRoute, Focus and Actions remain live. Page-local services, locale/RTL and MediaQuery overrides are not automatically cloned. Explicit content scopes/controllers work; there is no additional loader, generic provider copier or MediaQuery field merge. Source-local locale/RTL remains a product decision.

Captured nearest theme runtime-type order is fixed per presentation. Incompatible insertion/removal/reordering retains the last accepted snapshot; a new route adopts the new chain. This matches the old continuity tradeoff. Arbitrary custom wrap topology, mutable payloads and destination-sensitive resolution are SDK limits, not guaranteed State preservation. Protocol: `docs/architecture/menu-source-environment.md`.

## Design and rejection evidence

`design/` retains how/why, candidate packages, fresh judge, final implementation/deslop review and Comment Sicko. A source subscription + route publication wins 14/15 versus B immutable snapshot 11/15 because recorded live-local behavior is required. B would freeze values after reveal and even between hidden preparation and reveal. Its independent presentation-owned snapshot principle is retained after detach. Separate initial-kind/queued fields from A were removed. Roles use the same inherited model, not multiple model families.

Direct popup subscription to source inherited elements was rejected against SDK descendant invariants. Source-owned portal would keep source modal/focus ancestry. Neither is used. Old carrier/history is evidence for behavior, not imported machinery; its extra wrapText solved the old Material shuttle. The new probe needs no Material or Cupertino.

- `initial-before.log`: six tests, two passing/four failing, on base prototype. Source-local initial/update/detach assertions reproduce the loss.
- `expanded-before.log`: nine tests, four passing/five failing, before implementation. Hidden pre-reveal refresh adds another discriminator; root system environment and explicit page scopes pass.
- `targeted-tests.log`: all 13 final context scenarios pass after implementation.

The harness grew from six to nine to thirteen checks; earlier harness sources were not separately snapshotted. Logs are retained as observed failures, not a claim of byte-identical final harness at every earlier run. Base prototype is recoverable from git. No rejected source implementation, fixture weakening or retuning was needed.

## Verification

Flutter 3.47.2 stable / Dart 3.13.2, framework `d3b14c876900e553bc736ca19295fc09e3853e8e`. One heavy job at a time, nice 10 and concurrency 2.

```sh
cd example
nice -n 10 flutter test --no-pub -j 2 --timeout 60s test/proto/menu_context_test.dart
nice -n 10 flutter test --no-pub -j 2 --timeout 60s test/proto
nice -n 10 flutter test --no-pub -j 2 --timeout 60s test
cd ..
nice -n 10 flutter analyze
```

230 prototype checks pass, including 13 new context checks. All 20 replay metrics match the preceding input-ownership summary, including 2346 inputs, 40 routes and 40 hand-backs. All 8 async timing configurations with 3167 samples match. All 6 flat scenes/459 frames at 3× retain 0 changed pixels. Full example passes 320 tests; analyzer has zero issues. These are adapter/model and same-renderer comparisons, not device/native fidelity.

Production model, transfer adapter, clock, timeline, hosts, exports, measured tuning and fixtures remain unchanged. Root package suite was not rerun; historical 2362 pass/2 skip is in `../admission/report.md`. Full example also includes the owner's unchanged bar WIP. Scoped formatter and diff whitespace checks remain part of delivery. No device/GUI, native keyboard or energy/performance run.

Only one test description was narrowed after the prototype run to describe safe removal/reopen rather than overclaim callback timing; its behavior is unchanged. The final targeted run passes all 13 checks in final-targeted-tests.log.

Final source/deslop review found no blocking issue or useful further mechanism removal. Comment Sicko found 0 deletions/0 restores/0 reruns/0 open constraints; one public API contract block kept under the project's dartdoc lint. No suppression added.

## Exact evidence limits and remaining work

The latest-value test changes an application ValueNotifier twice before pump; it does not force two separate pending route snapshots. A→B→A queue behavior is supported by code review, not an independently forced runtime schedule. The source-removal test retains an already-published snapshot; pending-publication-after-source-disposal is supported structurally, not directly forced.

Navigator.removeRoute requests removal before theme publication in the test but SDK may dispose only after overlay unmount on the next frame. The test proves safe removal/reopen and independent new-route data, not necessarily execution of the callback-after-disposed guard. That guard is reviewed in source. The report deliberately distinguishes these bounds rather than adding a test-only production seam.

Remaining P2 gates include early root-push observer/currentness/traversal cost, product keyboard policy and source-local locale/RTL, native accessibility semantics, pre-handback held reopen/content/focus, transformed source geometry, cross-root/multi-View migration, remaining menu API, full bar/optical carry and device frame time/energy. Stronger typed-effects/runDue interruption and SDK-success-to-commit atomicity are not established. P2/code gate for main remain open.

Passing logs are copied unchanged; failing/analyzer logs strip only trailing line whitespace. `artifacts.json` hashes final source/evidence, unchanged core and owner context, excluding itself. Historical evidence is untouched.
