# P2 host semantics and menu lifetime

Started 2026-10-16, completed 2026-10-17. Base `65dce59fba3e5990153588c13e993b7de0bc8ee1`, branch `wip/measured-liquid-glass`. Prototype-only increment; P2 and the code gate for main remain open.

## Result

The pointer source exposes one labelled button/tap action and activates the existing model through a domain command. Public open now opens in either probe mode; raw early down/model-driven presentation use private preparation with their old timing. Two optional naming strings are the only new caller parameters. No synthetic PointerEvent, second motion model, Material/Cupertino dependency or semantic controller is introduced.

One private presentation enum replaces the previous revealed notifier plus writable closing flag. SDK Semantics/ExcludeSemantics express lazy hidden preparation, scoped/named shown content, and semantic exclusion during retained optical closing. The full barrier branch is excluded while hidden/closing, including its BlockSemantics. The content/theme/policy subtree is the stable ValueListenableBuilder child, preserving editor and policy identity across transitions. Tree exposure does not impose a second currentness/modality policy on SDK covers.

Action authority checks exact live/current/shown ownership. Source activation additionally checks the entire modal/Navigator ancestor chain, with a narrow exception for its own preparing popup's captured root source page only while that page remains isActive. Source mounted alone is insufficient after removeRoute. Revalidation after cancellation, model operations and observable open prevents stale continuation after reentrant cover/removal.

One route-level semantic dismiss uses SDK maybePop and the existing sync/async permission protocol. PopScope veto, shared async permission and LocalHistoryEntry are preserved. The command barrier retains physical pointer behavior without duplicating the dismiss action. Stale callbacks cannot dismiss the cover or an underlying page.

Flow paint updates now invalidate semantic geometry through a private RenderFlow override. Inherited delegate/clip updates remain SDK-owned; no extra ticker, transform copy or per-frame content rebuild. Corrected physical-to-logical bounds reproduce a stale left of 29.993305998578332 versus 29.89416948953169. The original 1e-6 geometry tolerance is retained.

Protocol and caller usage: `docs/architecture/menu-accessibility-lifecycle.md`.

## Architecture and rejected implementations

`design/` contains grounding/how, two independent candidates, synthesis, implementation/deslop review and Comment Sicko. SDK semantic widgets win 14/15 against a generic render admission gate at 13/15. Separate exposure/action authority and explicit geometry verification are retained from the second candidate. All roles use the same inherited model; this is not evidence from multiple model families.

The first full prototype run exposed eight existing builder-count regressions, resolved by retaining the complete content wrapper as a stable child. Old assertions were not changed. Review also found and reproduced the removed-but-mounted source admission race, repaired with isActive on the narrow captured-root exception.

A new real-action reentrancy check exposed an older wrong-target pop: cancelInput can synchronously push a cover, after which abandoned hidden preparation called Navigator.pop against that cover. Immediate identity-specific removal solved targeting but reset the still-moving source press. The transparent-cover replay reproduced this second failure, so cutting the tail was rejected.

Final noncurrent preparation cancellation enters the existing private closing transition, seals input/semantics and retains the original model/clock. At the existing hand-back or whole-model settlement boundary, an entry still active in SDK history is removed by exact identity and the sample returns immediately. Ordinary current preparation still uses SDK pop. A hidden idle model that never enters closing waits for complete settlement, including its press channel. No new transfer bypass or lifecycle flag is introduced.

The reference replay compares original-model pressScale/time with a continuous model at 1e-9, requires more than ten observations, checks no replacement is allocated before predecessor settlement, retains the current transparent cover and observes zero content builds. Final reviewer accepted the actual code and this evidence. Generic arbitrary forced removal retains the earlier prototype reset behavior; this bounded cleanup does not redefine all Navigator removal semantics.

## Retained experiments

- `baseline-before.log`: corrected 16-check harness against exact base source, 1 pass / 15 fail. Final harness grew to 21; the earlier 16-check harness source was not separately snapshotted. Base source was temporarily restored and the implemented source restored by hash afterward.
- `prototype-regression.log`: 238 pass / 8 fail, all old builder-count assertions. `rejected/route-before-retention.dart.txt` preserves that source shape.
- `source-removal-before.log`: one failing stored-source action before pump, after source page removal.
- `cover-before.log`: 49 pass / 1 fail, wrong-current-route pop. `rejected/route-before-covered-cancel.dart.txt` preserves the prior source.
- `tail-before.log`: one failing transparent-cover press-tail test after immediate identity removal. `rejected/route-before-tail-preservation.dart.txt` preserves that rejected implementation.
- `analyze-before.log`: two redundant-import diagnostics, subsequently removed.

Earlier exploratory logs had harness compile getters, DPR interpretation and too-late SemanticsHandle/platform teardown errors. They are not counted as source failures; early design ground notes describe that investigation. After the correct harness cleanup, the initial eight checks passed. Later final baseline rerun above uses correct cleanup and units. Intermediate cover-cleanup failure was the SDK cover reverse animation still running; the harness now awaits cover.completed and keeps the zero-transient-callback assertion. No fixture, tolerance or measured tuning was changed.

## Verification

Flutter 3.47.2 stable / Dart 3.13.2, framework `d3b14c876900e553bc736ca19295fc09e3853e8e`. Heavy jobs run serially, nice 10, concurrency 2.

```sh
cd example
nice -n 10 flutter test --no-pub -j 2 --timeout 60s test/proto/menu_accessibility_test.dart test/proto/menu_route_lifecycle_test.dart test/proto/menu_route_probe_test.dart
nice -n 10 flutter test --no-pub -j 2 --timeout 60s test/proto
nice -n 10 flutter test --no-pub -j 2 --timeout 60s
cd ..
nice -n 10 flutter analyze
```

51 targeted checks, 251 full prototype checks and 341 full example tests pass. The 21 new checks cover actual semantic actions, plain/nested source admission, hidden/closing isolation, scope/name/single dismissal, veto/async/local history, stale before-pump callbacks, Flow bounds and reentrant lifecycle. Analyzer has zero issues after removal of two unnecessary test imports. Final 21 accessibility checks were rerun after that import-only cleanup; no behavior changed after the full suites. Formatter reports zero changes.

All 20 strict replay records match the prior source-environment summary, including 2346 inputs, 40 routes and 40 hand-backs. All 8 async timing records/3167 samples, the backdating negative control, and all 6 flat scenes/459 frames with zero changed pixels match exactly. These are host adapter/model and same-renderer comparisons, not new device fidelity measurements.

Production model/host/clock/timeline, prototype transfer/clock adapters, public exports, dependencies, fixtures and tuning remain unchanged. Historical package-suite result 2362 pass / 2 skip is in `../admission/report.md`; it was not rerun for this example-only change. Full example includes unchanged owner bar WIP. Core and owner-context hashes are checked against the preceding artifact manifest.

Final deslop review found no remaining actionable simplification. Comment Sicko: zero deletion/restoration/reruns or open constraints; two consumer label dartdocs and one narrowly scoped SDK WillPopScope deprecation suppression kept. The suppression permits testing the existing real descendant asynchronous policy path, not a new production API recommendation. No correctness/safety suppression added.

## Remaining gates

Host Semantics does not establish VoiceOver/TalkBack announcement, native assistive focus restoration, full item roles/actions, Reduce Motion, large text or real IME behavior. Source expanded is derived when the source builds; no separately observable expanded state beneath a modal barrier is promised. No device, GUI, performance, energy or native accessibility run was performed.

Early root push still changes observers/currentness/traversal before reveal; product acceptance and hidden keyboard policy remain open. Further P2 work includes pre-handback held reopening and content/focus continuity, source-local locale/RTL, transformed/cross-root/multi-View geometry, remaining menu API, full bar/optical carry and device gates. Selective runDue effects interruption and SDK-success-to-commit atomicity remain unproved. No migration to main or production readiness is claimed.

Passing logs are copied unchanged; failed/analyzer logs strip trailing line whitespace only. Rejected snapshots are our own Flutter prototype code. `artifacts.json` hashes final code/docs/evidence excluding itself; historical evidence and owner work are preserved.
