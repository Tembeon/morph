# P2: synchronous dismissal admission and carried flat contours

Date: 2026-10-16. Base: `5bad38c8` on `wip/measured-liquid-glass`. Flutter 3.47.2 stable (`d3b14c876900e553bc736ca19295fc09e3853e8e`), Dart 3.13.2. Host: macOS `flutter_test`. File hashes are in `artifacts.json`.

**P2 remains open.** Synchronous `PopScope` admission now precedes measured closing in the reduced raw-input route. Its actual flat widget preserves the menu contour across route/source ownership and through the remaining tail. Async admission, the complete bar and optical field, early-route lifecycle, remaining menu API and device/performance gates are still outstanding.

## Scope and architectural exception

The existing model only exposed the closing phase after changing its channels. Decorating `MorphMenuProgress.close` would run too late: phase, fusion, relaxation and kick state already changed. Copying the complete model into `example/` would create a second implementation to maintain.

This increment therefore adds one internal, unexported function, `morphMenuSetCloseAdmission`, to `lib/src/widgets/menu_motion.dart`. It installs a synchronous check on input-driven close requests before `_close` mutates the model. The callback receives the original scheduled reaction time and must not mutate the model. With no check installed, autonomous closing is unchanged. Explicit `close` remains an unconditional command. No measured tuning, fixture, tolerance, dependency or package export changes.

Only the prototype host installs this check; existing production hosts do not use it. This is an explicit exception to unit 0's placement rule, recorded in the plan and architecture documents. It is an experimental seam to remove during unit 2.4's typed-event migration, not an API proposed for the new `main`. Unit 0's prototype gate does not count as the future production code gate.

## Synchronous route admission

At each input-driven closing deadline, the host reads the current route's public SDK `popDisposition`. A refusal leaves the opening model running. After the command/advance returns, the host delivers `onPopInvokedWithResult(false, null)`. A permitted dismissal starts the measured close at its original deadline and then performs logical Navigator pop. Notification never invokes application code from inside the admission callback. Covered or superseded owners cannot request a pop of the top route.

Five real binding scenarios verify rejection followed by a permitted retry: outside tap, row selection, early outside release before opening, Back and Escape. Six pure-model tests cover outside/selection/early-outside/early-row requests, explicit close and removal of the check. They verify original reaction times, continued open state after refusal and successful retry. The model still runs an action whose dismissal is refused; admission controls presentation, not the action. Two additional lifecycle tests retain a model externally and prove the admission is removed on forced route removal and unmount.

An additional positive test initially failed: a permitted pointer pop was consumed by `LocalHistoryEntry`, leaving a live route whose motion had already closed (progress 0.0000463 after one second instead of 1). SDK Back already handled this correctly. `rejected-local-history-route.dart.txt` and `local-history-before.log` preserve that version and failure. Admission now distinguishes permission to ask SDK for pop from permission to close the motion: `willHandlePopInternally` keeps the motion open while SDK consumes its history entry. Pointer and Back both leave the menu open, and a subsequent outside tap closes it. An internal pop does not leave a false closing timestamp.

This is a synchronous proof, not an async handshake. The raw-pointer path does not await deprecated `willPop` callbacks. Async permission with original event time, owner replacement/disposal while awaiting, reentrancy, multiple requests in one advance and policy registration before the first content build still need a defined contract and tests. Back/Escape continue through SDK behavior. None of these unchecked cases is marked complete by the five passing synchronous scenarios.

## Actual widget contour comparison

Both owners now paint the same scene: the bar container path for the source button and its fixed neighbor, unioned with the menu's own Gaussian outline while that model supplies one. The menu blobs are not reinterpreted under container spacing at hand-back. The source keeps reading that outline until the whole model reaches idle, when only the resting bar remains.

`menu_route_scene_test.dart` captures the actual rendered widget with `RenderRepaintBoundary.toImage`. An independent, uninterrupted model receives the observed canonical commands/times and produces a separate expected image. Every frame from logical close through final rest is compared, rather than comparing only two values obtained from the same scene getter. Capture is 3x over a 402x320 logical viewport; each expected path is asserted entirely inside that viewport. The motion retains its fixed 402x874 placement bounds. This scene has no text or glass shader.

| Frame cadence | Neighbor gap | Compared frames | Route-owned | Source-owned | Differing pixels |
| --- | --- | --- | --- | --- | --- |
| 60 Hz | 0 / 8 / 12 pt, each | 51 | 19 | 32 | 0 |
| 120 Hz | 0 / 8 / 12 pt, each | 102 | 38 | 64 | 0 |

All six scenes total **459 frames**, 171 route-owned and 288 source-owned. Transfer snapshots are equal, the route disposes while the source tail is still moving, and ten subsequent idle seconds add no source samples or scheduled callbacks. Control PNGs capture closing, hand-back and rest; these are our own flat renders. The first harness attempt included WidgetsApp's debug banner, creating 2984 unrelated differing pixels. Disabling that banner in the test app fixed the harness; the exact-zero criterion was retained.

This proves adapter equivalence for the reduced flat composition. It does not choose the production scene's field-composition law, validate glass normals/refraction/shadows, establish native bar parity or measure frame cost. The existing negative contour controls remain unchanged: immediate Gaussian-to-container replacement is still rejected. Full bar geometry/content, moving source links, scene ordering and optical carry remain required.

## Verification and reproduction

From the package root:

```sh
nice -n 10 flutter test --no-pub -j 2 --timeout 60s
nice -n 10 flutter analyze --no-pub
```

From `example/`:

```sh
nice -n 10 flutter test --no-pub -j 2 --timeout 60s --dart-define=P2_SCENE_OUTPUT=/tmp/morph-p2-scene-proof test
```

`P2_SCENE_OUTPUT` is optional. The isolated unit test is `test/menu_close_admission_test.dart`; the prototype suite is `example/test/proto/`. The aggregate prototype count is 149: the previous 135 plus four additional veto cases, two admission-cleanup cases, two local-history cases and six widget-scene checks. The prior pointer-veto negative control is replaced by a positive acceptance test; four previous negative controls remain. Twenty recording replays still contain 2346 input events and 40 hand-backs.

Final full-suite and analyzer results are recorded in `summary.json` and the accompanying logs: 2362 package tests pass with two skipped; all 239 example tests pass, including the 149 prototype checks; root analysis reports no issues. Scoped formatting reports zero changes. Analyzer and failure logs have terminal line-end padding trimmed; passing test logs are unchanged. No device lock was acquired, phone launched, settings changed or native performance claim made. A macOS app launch/autodemo is not performed: the prototype is not wired into the gallery entry point and the production seam has no production host caller. Existing owner edits to bar buttons, their passport and capture harness are preserved and excluded from this change; their hashes are recorded as context only.

The scoped deslop pass retains one complete model, one owner and one painter; no mirrored model, spring reset, close-then-reopen rollback, new dependency or app setup requirement is added. The retained-model checks justify explicit callback cleanup. Historical reports and their evidence are not overwritten. `main` is unchanged and nothing is pushed.
