# How grounding

Read-only explainer placement_how, HEADf96094e4. Parent baseline run:62 geometry cases pass; independent source and inset contour oracles each64 frames/0 changed pixels. No device run.

One _MenuGeometry stores both source endpoint and placement conditions. _readGeometry checks source/overlay attachment, layout/Offstage, positive uniform transforms, then computes max(safe,IME)/DPR projected to root overlay. It already rejects invalid/empty availability, minimum-fit failure and source outside available; null is not exclusively endpoint loss.

Snapshot holds source/overlay identity, map, button, bounds, available and scaled source shape. padding derives from available/bounds. position separately rereads overlay→global for input; preserve allowed whole-root movement.

admitGeometry alone relayouts the same model at fully closed source-owned idle: no route/reservation/pointer, no presented/arming/pending and settled. Snapshot is installed before readiness. Recheck model identity/attachment/geometry AFTER callback: readiness can reentrantly open and mutate metrics. Invalid active admission sticky-retires even if metrics are restored before a pump.

checkGeometry lets idle mismatch await admission; active mismatch calls loseGeometry, detaches old session, schedules new attachment by microtask. Shown popup retains old snapshot/model/content/clock and input. Hidden preparation/reservation terminate; abandoned source tail stops without hidden ticker.

Callsite constraints:
- source clock714 consumes false to stop sampling.
- admission797–834 includes persistent-phase and callback recheck.
- land1050 checks attachment and snapshot before lease transfer.
- handlePointer1205 intentionally ignores geometry false as a universal popup-input gate; only current command stops during _retiringSource, later old shown popup remains interactive.
- route _sample1708 likewise continues route sampling after detach.
- painter1938 checks before owner; its extra fresh read/agrees prevents idle-permitted mismatch from painting stale carried contour. Same-frame land→layout movement must suppress tail even after successful handback.

Removing available from agrees alone is wrong: reader null/containment still mixes policy. Weakening null reader alone also changes admission/paint. Native functional reuse does not establish optical landing, continuous close or early return reopen. Source movement/loss/hidden reservation are separate. Preserve conservative effective-availability retirement until optical gate plus policy design justify change.

References: example/lib/proto/menu_route_probe.dart194,585,647,787,797,1050,1205,1708,1938; example/test/proto/menu_source_geometry_test.dart (all62); docs/architecture/menu-source-geometry.md, menu-viewport.md, menu-native-ime.md; native-ime-reopen/results.md.
