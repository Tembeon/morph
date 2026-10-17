# Source affinity implementation and deslop review

Read-only review, 2026-10-17, against `d9973893a0cd91c7eff6c68efe6571594033c81c`. Scope: `example/lib/proto/menu_route_probe.dart` and `example/test/proto/menu_source_affinity_test.dart`. Read the current diff and source/callers, complete new harness, synthesized judge decision, repository rules, deslop/runtime instructions and the corrected baseline/first expanded evidence. No source edits, heavy jobs, devices, GUI or delegation were performed. The parent owns the running verification and all changes.

## Verdict

No blocking correctness finding in the scoped implementation. The implementation follows the selected A shape and incorporates the active-element and source-owned-tail decisions from B. Acceptance remains conditional on the parent's corrected 17-case run, unchanged full prototype/example checks, replay/async/scene records and analyzer. The inspected expanded log proves 14 passing checks; this review does not claim the later jobs passed.

## Ownership and reentrancy inspected

- `_MenuAffinity` pins Navigator, source FlutterView and actual overlay FlutterView by object identity. `canPresent` derives the same-View requirement, and raw input filters by the immutable presentation View id. `updateSourceView` and mutable `_viewId` are removed.
- `_refreshAttachment` severs `_current` before detaching or invoking the new model factory. Callback installation captures the created session. Source build captures the same session for painter, semantic, Listener and GestureDetector callbacks. The old popup retains its old session instead of reaching back through the public State.
- `_isAttached` combines the current token, active element and live affinity. Deactivation itself does not retire a compatible same-root session. Stale callbacks decline, unsupported foreign-overlay View cannot reach push, and returning to a previous root does not reconnect an old session.
- `detachSource` clears source context callbacks and pointer authority, disposes the old source clock, and defers observer/route publication. `_retiringSource` blocks command-unwind cancellation and phase synchronization until that safe seam. Its lifetime is session-local; it is not a lock shared by old and new models.
- The deferred drain retires the reservation by identity and starts finite closing only for an old hidden preparation. A shown old popup keeps ordinary SDK dismissal and old-View menu input. A lost source-owned tail receives no replacement ticker, migration, fake settled frame or model reset.
- Old route disposal only mutates its own session, with a null old source clock preventing creation of a replacement source model. `_disposed` plus the retirement barrier makes final notifier/router disposal idempotent.
- `land` validates the active route, lease, pinned Navigator and live source authority before starting hand-back. Its transfer path samples the already-current closing time; the inspected adapter does not publish an external observer between transfer and hand-back publication. There is no concrete additional reentrancy gap here that warrants a speculative guard.

## One substantive simplification

`_creatingSession` duplicates the unpublished state already represented by `_current == null`. It can be deleted if public `open()` begins by rejecting a null `_current` with the existing transition StateError. `_refreshAttachment` has exactly two callers: `didChangeDependencies` is the authorized initial construction path; `open()` is a command path requiring an already published source session. Factory reentry then fails before recursively entering `_refreshAttachment`, while normal attachment replacement still works. Keep mounted/active validation in `_refreshAttachment` and preserve the factory-reentry regression test.

This is a deslop recommendation, not a correctness blocker. The present explicit flag works, but maintaining both null and bool adds a second fact about the same transition. No host/handle/controller abstraction, generation counter or generic lifecycle registry should replace it.

Other new lifecycle state has distinct purpose and should stay: `_elementActive` protects legal ancestor reads; `_retiringSource` distinguishes sealed-but-not-yet-drained work; `_disposed` prevents duplicate notifier/router finalization. Removing those based solely on the presence of a null source clock would erase different invariants.

## Harness correction reviewed

The new editor/policy test initially retained a SemanticsHandle via `addTearDown`, which this SDK checks too late. The parent reported that as the sole failure of the first 17-case run and changed the test to dispose the handle inside `try/finally`. The current file contains that correction. Keeping semantics enabled through the body is appropriate for its content/policy/focus lifetime coverage. This was a harness-lifetime issue, not evidence of a source implementation failure.

The second View fixture creates a separate View render tree with a TestFlutterView wrapper and view-aware gesture dispatch. Its no-op engine render/semantics forwarding is a host-fixture limitation; it must not be described as a real OS-window or device test. The two-root fixture deliberately retains fixed model geometry, so this stage does not establish arbitrary offset/scale/root-space pointer conversion. Existing public prototype documentation states the fixed-input boundary.

No changes to old tests, model/clock/transfer code, measured values, dependencies or exported API are introduced by the inspected diff. Scoped `git diff --check` returned clean. No cosmetic cleanup beyond the duplicated construction flag is required.
