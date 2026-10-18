# Native selection / close / reopen after IME

- [x] Read prior endpoint evidence, native scene and lock protocol.
- [x] Extend public scene/test with counted callbacks, retained source token, selection/closed/reopened samples and focus typing.
- [x] Run real iPhone modes none/show/hide twice with ten rows.
- [x] Validate keyboard phase ordering, selected callbacks, closed source reuse and fresh reopen placement; negative control for bad event ordering.
- [x] Update plan/specs, deslop/no-comments; include completed results in a scoped local commit.

Shape: reuse plain UIWindow/UITextField/UIButton probe; first menu trigger schedules the one keyboard change, later triggers only record identity. Test opens, observes actual IME change, taps Native first, waits menu absent/count1/source hittable, reopens same button, taps Native second, waits absent/count2. Show mode types native via application without tapping the editor. Record monotonic query intervals, source token/presentation/selection counters and public field focus events. No settings, private runtime APIs, simulator or desktop GUI.

Scope: functional endpoint reuse, action cardinality/order, fresh placement and input focus. Static source frames/hittability do not prove optical morph landing or transient continuity. Do not remove prototype detach based on this protocol alone. Canonical capture CLI goes in native lab; prior audit scripts/data stay unchanged. Heavy jobs serial/nice10; raw Xcode evidence remains outside git.

Status: prepared stage20e8724f and failed selection01 remain in report.md. Selection02/03 now complete six real scenes and pass analysis; a corrupted selection callback time is rejected. See results.md. Documentation/review delivery is tracked separately; optical landing and the Flutter ownership design remain open.
