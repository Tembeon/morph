# Source environment implementation review

Reviewed the actual uncommitted `menu_route_probe.dart` diff and full new `menu_context_test.dart` against base `65b080d3`, the synthesized design, `/tmp/morph-p2-context-first.log` (13 checks passed), and installed public Flutter Navigator disposal implementation. Read-only; no source/test edits, runtime commands, devices or delegation. This is the inherited-model design judge's final review, not a separate model-family consensus.

## Verdict

No blocking correctness or deslop finding in the implemented boundary. Proceed with the parent-owned regression run. The implementation follows candidate A with the agreed subtraction: no retained initial-kind list, queued flag, revision counter, source-context callback or new caller API. Only the SDK theme capture/wrap path is used.

## Verified in source

- Capture stops at the exact root Navigator selected for push. Source dependency registration targets only actual ancestor InheritedElements and nearest unique theme kinds. Themes above the cutoff are not captured. No route Element subscribes across sibling branches.
- Initial capture is synchronous. `didChangeDependencies` refreshes only live session routes whose Navigator identity matches the selected root, including closing presentations. No motion callback performs capture.
- Each route owns accepted and pending snapshots. Kind compatibility is derived from accepted widget types; because accepted kinds never change, this preserves the initial invariant without extra state.
- `_queueThemes` replaces existing pending data before testing accepted-value equality. Consequently queued B followed by accepted A correctly ends as A, with no stale B publication. A→B→A is established by this code path, not by a direct runtime reproduction in the current packet.
- Publication is post-frame, clears pending state first, checks disposal before notifier access and closes over route-owned data only. Route disposal clears the pending slot and disposes its notifier. Source loss has no callback that can look up an inactive source context; a replacement route has an independent slot/notifier.
- Captured wrappers remain outside one stable policy child. Unchanged wrapper kinds and stable SDK/custom wrap topology permit inherited consumers to rebuild without reconstructing editor State. The documented limitation on custom wrap topology is necessary and truthful.
- Root non-theme environment remains destination-owned. No MediaQuery cloning, locale loader, source route identity, extra inherited provider transport, clock/model/tuning change or global subscription was added.

## Runtime evidence and exact limits

The 13-check log supports source theme acquisition under plain/nested Navigator, compatible updates with retained editor/focus/PopScope, live root system/global themes, source removal retention, explicit page-data scopes, hidden preparation/cancellation, new presentation topology, stable content across motion samples and route removal/reopen safety.

Two names must not be promoted into stronger timing claims than the harness observes:

1. `several local value changes publish latest without remounting` changes its ValueNotifier twice before pumping. Flutter can coalesce those changes before source dependency processing, so this proves the latest application value reaches content, not that two already queued route snapshots coalesce. The implementation handles the latter structurally; no extra low-level helper test is warranted solely to mirror it.
2. `queued refresh cannot publish into a removed or next popup` schedules `Navigator.removeRoute` before the theme publication callback. Flutter gracefully delays route disposal while overlay entries remain mounted (`navigator.dart`, `_RouteEntry.dispose`), so removal request precedes publication but actual `route.dispose` may follow in the next frame. The test proves safe removal/reopen behavior, not necessarily execution of the `disposed` callback guard. Report the ordering honestly. A callback-after-forced-disposal experiment would require deliberately controlling SDK Navigator teardown or a narrow harness seam; the existing straightforward guard and per-route ownership do not justify adding such machinery to this unit.

Likewise, source removal in the packet follows an already published capture; publishing a pending capture after source disposal is supported by the context-free implementation but is not separately forced by these tests. These are evidence bounds, not observed defects or reasons to broaden this change. Multi-View/root reparenting and hostile custom wraps remain explicit unproved contracts.

No additional runtime reproduction is necessary to address a concrete discovered bug, because none was found. Keep the before failures and regression metrics, and distinguish structural review from runtime coverage in the report.
