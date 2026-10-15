# P1 timing follow-up

Date: 2026-10-15. Base revision and SDK are the same as the parent P1 report: `78a22418`, Flutter 3.47.2 stable, Dart 3.13.2. Host tests only for this follow-up; no phone was acquired or launched. The earlier iPhone measurements still refer to the unchanged base route prototype.

Status: 55 host checks pass: 32 existing P1 lifecycle checks, 16 clock comparisons and seven SDK controller scheduling checks. This does not complete the product or device gates of P1.

## What was built

- `example/lib/proto/motion_clock_probe.dart`: the existing `MorphClock` behavior extracted into an object supplied with a `TickerProvider`, current-time function, pointer-clock offset and per-frame scheduling outcome.
- `example/test/proto/motion_clock_probe_test.dart`: the original State mixin and extracted object run side by side on the same scheduler. Every sampled time and event stamp is checked against the existing contract. The object is not wired into the base route prototype or production widgets.
- `example/lib/proto/controller_vsync_probe.dart`: one SDK controller ticker with a timer and combined ambient/doze muting. It observes `TickerMode.getValuesNotifier`, including `forceFrames`, and can refresh its inherited notifier when the navigator context changes.
- `example/test/proto/controller_clock_probe_test.dart`: real `pushReplacement` scenarios plus a display-grid simulation experiment. Negative controls reproduce two approaches that are insufficient.
- `host-tests.log`: passing combined run; `artifacts.json`: source and log hashes for this follow-up.
- `regression-tests.log`: 22 existing clock, zoom replay and route ownership checks pass with unchanged fixtures. Root `flutter analyze --no-pub` reports no issues.

Reproduce from `example/`:

```sh
nice -n 10 flutter test --no-pub -j 2 --timeout 30s test/proto/motion_clock_probe_test.dart test/proto/controller_clock_probe_test.dart test/proto/route_probe_test.dart
```

## Clock extraction

The object preserves the existing clock policy without changing measured constants, spring models or replay tolerances. The tests compare sample sequences within 1e-9 seconds; analytical expectations additionally check specific event times and wake delays. Covered scenarios:

- 60/120 Hz, timestamp jitter and skipped display frames.
- OS pointer/frame-clock offset, event delivery lag, absent offset, stale and future timestamps, unrelated fake frame clock.
- Settled sleep, first-frame delivery lag and multiple pointer events before the first frame.
- Input interrupting a doze, timed waking and no samples while asleep.
- Normal and 5x slowed clocks, including delayed input and timed doze.
- Ambient `TickerMode` suspension and elapsed time after resuming.
- Settled idle and disposal while a wake timer is pending.

The test alone does not validate the platform FFI offset against the device; the offset source is injected. Rebase and absolute-time hand-back between different owners remain P2 work. Full event ordering and controlled-value reconciliation remain later units.

The prototype imports the existing frame grid. Its 250 ms event-age and 50 ms clock-agreement bounds are copied from the current clock contract, not newly chosen tuning. The test oracle intentionally accesses package internals under a test-only lint suppression. Production analysis rules are unchanged.

## SDK controller findings

1. A simulation can map elapsed time onto the existing `MorphFrameGrid`. Under injected jitter, a gridded SDK controller keeps fixed sample spacing while the raw controller follows the jitter, with corrections inside the existing 1 ms grid reach.
2. An active controller ticker can be muted during a delay. No frame callbacks run, elapsed time continues, the original push future stays pending and `pushReplacement` keeps the old page until measured visual rest.
3. **Negative control: `controller.stop()` is unsuitable for that doze.** It cancels the push future; Navigator's completion/cancellation handling disposes the old page while the delayed visual motion remains unfinished. The passing negative-control test reproduces this failure, not acceptable behavior.
4. **Negative control: setting a Navigator-owned ticker's `muted` flag directly is insufficient.** Parent `TickerMode` disable/enable writes the same flag and can resume frames before the doze timer expires.
5. `ProbeDozingVsync` resolves the observed ownership conflict with one rule: muted when ambient mode is disabled or the motion is dozing. Parent re-enable does not end doze; timer expiry does not override a disabled parent. The route still retains its SDK push future. Removal cancels the timer and mode subscription.

The test route delays a measured zoom for 500 ms to expose these scheduling paths. That delay is an experimental fixture, not a change to UIKit tuning or proposed production presentation timing.

## Consequences for the architecture

Frame-grid sampling and doze are feasible with SDK `AnimationController`; they cannot justify rejecting it as impossible. It still needs an adapter for the library's event/time policy and correct ticker ownership. The separate projection remains a viable candidate, not a requirement established by the timing checks.

The extracted clock and controller-vsync prototype demonstrate two pieces independently. They must not be combined by running two clocks for the same motion. A final route adapter must have one ticker/time owner and one scheduling policy, with input stamps, delays and transfer/rebase checked together.

No production choice is made here. Next is P2 ownership transfer for menu motion, including interrupted reopen and sleeping clocks, followed by the complete product scenario under the existing build-count ceiling and Pixel frame-time/energy budget. The full API sketch is not an implemented library merely because these prototypes pass.
