# P1: measured zoom and Flutter route lifecycle

Date: 2026-10-15. Base: `78a22418d570bd0e077c80f6bb569224211727e8`, branch `wip/measured-liquid-glass`, with the local prototype files listed below. Flutter 3.47.2 stable (`d3b14c876900e553bc736ca19295fc09e3853e8e`), Dart 3.13.2. Host: macOS `flutter_test`. Device follow-up: iPhone 16 Pro, iOS 27.0.1, profile, physical display reporting 120 Hz.

Status: the first host pass and reduced-scene iPhone pass are complete. P1 as a whole is not passed. Neither route driver is selected for production.

Timing follow-up: `timing/report.md` records 55 passing combined host checks, extraction of the measured clock and SDK doze/grid experiments. The base route and earlier iPhone results are unchanged.

## Work state

- [x] Ground: existing `MorphZoomMotion`, `MorphClock`, `MorphMotionRouteMixin`, SDK `TransitionRoute` and `ModalRoute` lifecycle.
- [x] Sketch: compare the accepted projection candidate against SDK `createSimulation` on the same measured model and content.
- [x] Agree: implementation starts with a prototype outside `lib/`; main stays unchanged.
- [x] Implement: 32 host checks and a rebuild counter, recorded in `host-tests.log`.
- [x] Device follow-up: native editor/focus/input checks and 16 open/close cycles, with raw FrameTiming samples and screenshots in `iphone/`.
- [x] First timing follow-up: 16 clock comparisons and seven controller scheduling checks, including two negative controls, in `timing/`.
- [ ] Final architecture decision: clock policies, product counters, Pixel frame time and energy, iPhone parity are still required.
- [ ] Scrap or simplify: reconsider full progress projection if its verified cost exceeds the existing budget; no budget has been relaxed.

## Files and reproduction

- `example/lib/proto/route_probe.dart`: `ProbeSheetRoute` with `projected` and `sdkController` drivers.
- `example/test/proto/route_probe_test.dart`: the same 16 scenarios run for both drivers.
- `example/integration_test/route_probe_device_test.dart`: live profile harness for editor behavior and an ABBAABBA route timing run.
- `host-tests.log`: passing test output and raw rebuild counts.
- `regression-tests.log`: 14 passing existing zoom replay and route ownership checks.
- `artifacts.json`: SHA-256 of the local prototype, tests and captured logs, identifying the changes on top of the base revision.
- `iphone/report.json` and `iphone/summary.json`: complete device run and statistics; `iphone/*-editor.png`: Flutter view screenshots; `iphone/build.log` and `iphone/console.log`: build/launch output.

Trailing terminal padding is trimmed from the build log; frame data and screenshots are unchanged.

From `example/`:

```sh
nice -n 10 flutter test --no-pub -j 2 --timeout 30s test/proto/route_probe_test.dart
dart analyze lib/proto/route_probe.dart test/proto/route_probe_test.dart
```

The prototype reuses the existing measured `MorphZoomMotion` without changes. A `FlowDelegate` changes the painted rectangle while the content subtree remains mounted. It is a reduced sheet with a plain fill, not a copy of the complete sheet, its detents, source replica or glass rendering. The gallery does not import it; the device harness has its own integration-test entry point.

The projected driver uses a route-owned ticker and the existing frame grid. A muted ticker supplies the push completion signal without scheduling its own frames. The SDK driver uses `TransitionRoute.createSimulation()` and the SDK's bounded controller. Both keep raw overshoot inside the measured model and expose bounded progress to SDK consumers. Simulation completion depends on every measured channel, not on the center first reaching 1. Terminal SDK progress is explicitly 0 or 1.

`didAdd` settles the model immediately. `didReplace` either settles an already completed page or transfers the in-flight model and time, stopping the old driver's clock. This transfers ownership within the prototype; the production snapshot/rebase contract is not implemented here.

The prototype imports internal `MorphFrameGrid` under one `implementation_imports` suppression. This keeps the production files and exports unchanged; it is not an example of the future public consumer API.

`nice -n 10 flutter analyze --no-pub` from the package root reports no issues. From the same root, `nice -n 10 flutter test --no-pub -j 2 test/sheet_zoom_test.dart test/motion_route_ownership_test.dart` passes all 14 checks with unchanged fixtures and tolerances. Full package and example suites have not been run; production code is unchanged.

## Functional observations

All 32 host checks pass, 16 per driver:

1. SDK progress, logical pop result before visual completion, disposal at rest.
2. Input and focus released on the first closing frame.
3. `pushReplacement` retains the old page until all measured channels rest; opacity changes at completion.
4. Initial `Pages` start completed and do not animate an entrance.
5. `Navigator.replace` transfers an entrance in progress without a geometry jump.
6. Replacing a settled route leaves model, SDK progress and opacity consistent.
7. A restored route is completed and can still dismiss.
8. `PopScope` veto leaves the route open and its result pending.
9. Injected 32 ms input age is reflected in the first motion sample.
10. A nested editor preserves State, text and focus through insets and a covering route.
11. Content builds once while painted geometry changes; no motion frames or transient callbacks remain in quiet time.
12. SDK rebuild work is recorded during a steady entrance.
13. Raw progress overshoots while SDK progress stays bounded; completed status waits for visible rest.
14. Pop during entrance preserves the starting geometry of the reversal.
15. Forced removal disposes the clock and push signal without leaving frames scheduled.
16. Push and pop Hero flights run with an explicitly installed `HeroController`.

Hero is tested between this probe and a stock `PageRouteBuilder`. This is evidence for the SDK connection, not a promise about the future `MorphNavigationRoute` API or all Hero configurations.

## Rebuild cost

The counter records every widget build during 40 entrance frames at 16 ms per pump, after the initial page structure is built. Content and page builders each run once over the complete entrance.

| Driver | Sampled frames | Widget builds | Mean builds per sampled frame |
| --- | ---: | ---: | ---: |
| Separate projection | 40 | 176 | 4.4 |
| SDK controller | 40 | 320 | 8.0 |

For the projection, 88 builds belong to SDK `ListenableBuilder` and 22 each to `AnimatedModalBarrier`, `ModalBarrier`, `_ModalBarrierGestureDetector` and `RawGestureDetector`. For the controller these are 160 and 40 each. The projection notifies only when its clamped value changes; the controller notifies on every simulation tick, including a plateau at the bound.

This disproves the plan's estimate of approximately two rebuilt elements as a count of total SDK work for this scene. It does not establish a device frame-time or energy regression. Existing product sheet ceilings are 1.1 builds/frame for flat and 1.2 for fake/liquid in `test/fixtures/perf/counts.json`, but those averages cover a different complete scene and interaction. This reduced entrance cannot replace that benchmark or establish that the product gate passes. The existing ceilings are unchanged.

## iPhone profile pass

The owner made the iPhone available. The run acquired `/tmp/morph-native/device.lock` atomically, built the separate integration entry point and installed it under the existing example bundle. No phone settings changed. After retrieving the evidence, the pre-run local example app was reinstalled, the local build artifact restored and the lock released.

The physical device reports 120 Hz, 1206 × 2622 pixels at DPR 3. Native keyboard view insets reached about 327/328 logical pixels for the two drivers. Both retain the same `EditableTextState`, text and focus after a covering route is popped. On the first closing frame the editor releases focus and a synthesized tap reaches the underlying page. Screenshots come from the Flutter view capture; native keyboard pixels are not part of that capture.

After the editor checks, the harness runs ABBAABBA (A = projection, B = SDK controller), two complete open/close cycles per phase: eight cycles per driver. Each cycle checks completed progress, no motion-clock frames during a 120 ms rest, logical pop result before visual disposal, reverse status, eventual disposal and one page build. This does not assert that the whole integration-test app schedules zero frames; live test pumps can schedule their own.

The harness collects 2881 raw FrameTiming samples. Statistics below select samples by `vsyncStart` within each recorded phase's timeline window, excluding editor setup and inter-phase pauses: 1232 samples per driver. Durations are milliseconds.

| Driver | Build p95 | Raster p95 | Total span p95 | Maximum total span | Total span over 8.33 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Separate projection | 0.403 | 1.629 | 2.383 | 3.963 | 0 / 1232 |
| SDK controller | 0.397 | 1.414 | 2.170 | 4.583 | 0 / 1232 |

Both fit the reported 120 Hz budget in this reduced run. FrameTiming does not prove that every frame was presented on time; this is not a dropped-frame measurement. The small difference between these runs does not establish a performance winner. There is no glass, product scene, Pixel result or energy measurement here. The greater rebuild count alone is therefore insufficient to reject either driver.

Reproduction from `example/`, while holding the phone lock:

```sh
nice -n 10 flutter build ios --profile --no-pub -t integration_test/route_probe_device_test.dart
xcrun devicectl device install app --device <iphone> build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device <iphone> --terminate-existing --console dev.tembeon.morphExample
xcrun devicectl device copy from --device <iphone> --domain-type appDataContainer --domain-identifier dev.tembeon.morphExample --source tmp/foundation-p1 --destination <output>
```

`report.json.complete` is set only after all checks and timing cycles finish. The profile app remains alive after completion; the console command ended when the saved app was reinstalled, rather than providing a test-runner exit status.

## Limits and next checks

- The base route still injects `eventAge` and has no complete event-clock adapter. The timing follow-up separately checks clock extraction, sleeping events, doze/wake, spacing, time dilation, grid sampling and coordinated SDK ticker muting. These pieces have not been integrated into one route time owner, and OS clock conversion is injected in those host tests.
- No source capture, hand-back, `MorphSourceLink`, reduced-motion policy or predictive-back integration is implemented here. These belong to later prototypes/units.
- Device checks confirm native keyboard appearance, editor State/text and focus restoration in this reduced route. Full product IME behavior, shader pixels, detents and source crossfade remain unverified.
- The first restoration run stopped on a missing VM entry-point annotation in the test callback. The annotation is now present; the passing run includes restoration for both drivers.
- Next: test menu motion ownership transfer in P2, combine the timing policy under one route owner, and measure the full product scenario with unchanged counters. If the full-progress path cannot meet the budget, test the planned status-only projection and document the loss of smooth SDK progress.
- Pixel frame time and energy and parity against UIKit remain unverified. The iPhone follow-up measures the reduced Flutter scene only; no production architecture decision follows from the green tests and these timing samples alone.
