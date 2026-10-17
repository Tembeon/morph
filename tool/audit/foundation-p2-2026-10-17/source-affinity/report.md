# P2 source presentation affinity

2026-10-17, base `d9973893a0cd91c7eff6c68efe6571594033c81c`, branch `wip/measured-liquid-glass`. Prototype only. Main remains `b0c3fc20763ee15899ace5b820c6c29d89357ad9`; no push or merge. P2 and production code gate remain open.

## Result and caller contract

A retained GlobalKey source State can move to a different root Navigator or FlutterView. Its current observations and synchronous `open()` now address a fresh private session. The previous shown popup retains its original Navigator/View, complete model, clock, content State, focus and SDK dismissal policy. It accepts menu input only from its original View and never lands into the moved source. Old disposal cannot reset a new model. Returning A → B → A creates a third lifetime. Moving between nested Navigators under one unchanged root/View preserves the original session.

One immutable affinity contains root Navigator identity, source FlutterView identity and the actual root overlay FlutterView identity. Session identity is the callback token. Source callbacks capture it and check current/live attachment. Active-element tracking prevents illegal ancestor reads during deactivation without treating every temporary deactivation as permanent source loss. The session's input View is immutable; the mutable source viewId/update method is deleted. The public State uses TickerProviderStateMixin so sequential source clocks are legal; at most one source clock remains live. Original route clocks keep their original Navigator vsync.

Source authority/held sequence and source clock are sealed immediately during dependency refresh. Observable cancellation and exact old-route retirement run at a deferred microtask seam. Command unwind cannot bypass that seam. Hidden preparation and reservation retire finitely without promoting a stale attempt or popping another root/cover. The original clock completes route-owned work; no additional retirement ticker exists. A source-owned tail whose physical attachment disappears is explicitly abandoned, possibly unsettled, with no more sampling or migration. It is not reported as settled.

`land` validates live source attachment, pinned route Navigator, active owner and lease before resuming/transferring. No source State callback is retained by a detached session. Source and overlay in different Views cannot present with this fixed-space probe: explicit `open()` throws StateError before push, raw/semantic activation decline.

Caller usage and limitations: `docs/architecture/menu-source-affinity.md`.

## Design and review

Two independent inherited-model candidates compared direct session rotation (A) and keyed inner source host/handle (B). Both scored 14/15. A wins by keeping the existing session as the whole attachment lifetime instead of adding another forwarding owner. Mandatory grafts from B are the active-element boundary and explicit source-owned-tail abandonment. The fresh judge fixed sticky source loss and safe deferred cancellation before implementation. These are distinct runs of one model family, not cross-model evidence.

Implementation/deslop review found no blocking defect and one redundant construction flag. `_current == null` already represents unpublished construction; public open now rejects it before refreshing, eliminating `_creatingSession`. Initial construction still enters through didChangeDependencies. The factory-reentry test exercises this boundary. The 292-check standalone prototype job precedes this cleanup; the final full-example run includes all prototype cases on the simplified source. Only public dartdoc and equivalent flow-control braces were subsequently clarified.

Comment Sicko recommended three public-contract corrections, all accepted: theme updates are limited to the surviving attachment, detached popups retain their model independently, and open documents its pre-push StateError. Zero comment deletions, restorations, reruns, encoding offers or open constraints. Two existing internal rationale comments reflect real SDK ordering/removal constraints; unchanged prototype-only implementation/deprecation suppressions were inspected rather than exported to production.

`design/` preserves grounding, how, candidates, synthesis and independent review reports. Parent owns all source edits and serial jobs.

## Reproductions and harness corrections

- `baseline-before.log` plus `baseline-harness.dart.txt`: corrected minimal harness, 0 pass / 3 fail on the base. The moved source exposes the old activeRoute, old closing publishes hand-back, and a new-View pointer selects an old-popup item. These are ownership failures independent of the deferred geometry work.
- Initial harness-only drafts used a Row without textDirection and a pointer-up without the same View as pointer-down. Those drafts are not baseline evidence. The preserved three-case baseline fixes both before implementation. The TestPointer API does not retain the down's View for an unspecified up.
- `first-implementation.log`: all three reproductions pass after affinity rotation.
- `expanded-tests.log`: all 14 first expanded cases pass, including actual second View/render tree, unsupported foreign overlay View, source-owned abandonment and factory reentry.
- `content-before.log`: 16 pass / 1 fail. Behavior assertions pass; the editor test holds a SemanticsHandle past the SDK end-of-body check because addTearDown runs later. The harness now disposes it inside try/finally. No source behavior changed for that correction.
- `targeted-tests.log`: all 17 final new cases pass before the redundant construction flag cleanup. The final full example job repeats them after that cleanup.

The new tests cover independent old/new popup overlap; old disposal versus current model; sticky return; same-root nested preservation; closing continuity; frozen, honestly unsettled lost source-owned tail; hidden held preparation with/without cover; reservation before/after hand-back; stale source semantic/raw closures; a real foreign source/overlay View; factory reentry; retained editor/controller/focus/PopScope and semantic dismissal; new-root open from deferred cancellation; and committed hidden release source loss. Completed paths assert zero remaining transient callbacks. The retirement callback test opens the new root from cancellation and would expose a tree-locked Navigator publication.

The second TestFlutterView renders a separate real framework View tree but no-ops engine Scene and Semantics forwarding. Tests exercise View identity and view-aware binding pointer dispatch, not native windows or assistive technology. The editor/focus case uses two roots in one View; it is not native multiwindow focus evidence.

## Verification

Flutter 3.47.2 stable, Dart 3.13.2, framework `d3b14c876900e553bc736ca19295fc09e3853e8e`. Heavy jobs run serially, nice 10, concurrency 2.

```sh
cd example
nice -n 10 flutter test --no-pub -j 2 --timeout 60s test/proto
nice -n 10 flutter test --no-pub -j 2 --timeout 60s
cd ..
nice -n 10 flutter analyze
```

All 292 standalone prototype checks and all 382 final example tests pass; analyzer reports zero issues. The final example job includes all 17 new cases and all previous prototype cases after deslop cleanup. All 20 strict replay records, 8 async timing records, 6 flat scene records and the backdating negative control match both in the standalone prototype log and final example log: 2346 recorded inputs, 40 routes/40 hand-backs, 3167 async samples and 459 flat frames with zero changed pixels. No old test, fixture or tolerance was modified. These are host adapter/model and same-renderer equivalence results, not native fidelity or multiwindow device evidence.

The root package suite is not rerun for this prototype-only change; historical 2362 pass / 2 skip belongs to `../../foundation-p2-2026-10-16/admission/report.md`. Core and owner-context hashes remain identical to held-reopen evidence. Production model/host/clock/timeline, prototype clock/transfer adapter, tuning, dependencies and public exports are unchanged. The example suite includes the unchanged owner bar WIP as context, not as this stage's work.

Passing logs are copied unchanged. Failed/analyzer logs strip trailing line whitespace; the baseline harness is our own Dart source. Prior audits are not rewritten. `artifacts.json` excludes its own digest and records scope/core/context hashes. Negative grep scans check production imports, removed mutable state and new test comments; staged private-material scan and scoped diff checks are part of final admission.

## Remaining gates

Fixed geometry remains deliberate: no live RenderBox-to-overlay measurement, pointer conversion for offset/scaled roots, visibility/scroll/rotation/insets policy, active geometry retargeting or arbitrary transformed source support is introduced. The existing motion relayout remains idle-only. Distinct View geometry is rejected, not converted. Affinity does not prove coordinate coincidence even within the same View.

No GUI, device, native multiwindow/IME/VoiceOver/TalkBack, shader parity, frame-time or energy run is performed. Early root push product acceptance, hidden keyboard policy, source-local locale/RTL, remaining menu API, full bar/optical carry, selective runDue interruption, SDK-answer-to-commit atomicity, P1/P3 and device/perf remain open. Main is not migrated and release readiness is not claimed.
