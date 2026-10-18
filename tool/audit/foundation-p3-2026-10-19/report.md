# P3: frame consistency between clocks

2026-10-19, base `c9fdbf6f`. Flutter 3.47.2 stable, host `flutter_test`.

## Question

P3 asks which mechanism keeps frame consistency between the library's clocks more cheaply. The candidates are clocks on each host plus one ordered phase after all tickers, or one Stage per `FlutterView` with advance, publish and commit phases.

## What exists today

The ordered phase already exists. Flutter runs every ticker of a frame as transient callbacks, then flushes microtasks, then builds. `MorphFrameSync` (`lib/src/live.dart:75`) and the glass host's `_framed` (`lib/src/widgets/glass_channel.dart:321`) defer their reads to that microtask phase, so those reads see all motions advanced for the frame, whatever the ticker order. Ticker order itself varies, because a clock that settles or dozes re-registers at the end when it wakes.

Not every read goes through that phase. `MorphLiveBinding` (`lib/src/live.dart:39`) applies synchronously when its listenable notifies, which for a raw `frames` source is inside the owner's tick. That is safe while it reads the owner's own motion and order-dependent when it reads another clock's state, as read 4 below does through the sheet (`sheet.dart:1264`).

An inventory of reads made inside a tick, of state advanced by another ticker, found four order-dependent reads.

1. The minimizing tab bar stamps scroll input with its own clock time (`tab_bar_chrome.dart:598-648`). During a fling the scroll notification arrives inside the scroll controller's tick. The stamp is the current frame's time when the bar ticked first and the previous frame's time otherwise, so the minimize springs start one frame early or late.
2. A menu clock retargets a moving flight's controller (`menu_host.dart:300-350`, `morph_context_menu.dart:892-903`). The flight holds one frame when the menu ticks first.
3. `_VesselFrame` reads the menu rect inside flight ticks (`flight.dart:2409-2418`). Nothing visible reads the result.
4. Sheet and push zoom capture the source transform inside a tick (`push_zoom.dart:110-113`, `sheet.dart:1215`). It is order-dependent only under an app transform animated by another clock.

Reads 2 and 3 live in the flight engine that unit 5.3 deletes. Read 4 depends on the app. It moves to the source link in units 5.1 and 5.2, and its order dependence has to be checked again there, because moving the code does not remove it. Read 1 remains.

## Experiment

`example/test/proto/frame_phase_probe_test.dart` runs a writer ticker that delivers input to a running reader clock inside its own tick, the way a fling delivers scroll notifications. It covers 60/120 Hz, 1x/5x and both tick orders, eight cases.

- A read deferred to a microtask equals the frame's sampled time in both orders, exactly.
- The reader's last sampled time, read inside the writer's tick, equals the previous frame's time when the writer ticks first and the current frame's time otherwise, exactly. This reproduces read 1.
- `ProbeMotionClock.frameTime` (`example/lib/proto/motion_clock_probe.dart`) maps the current frame stamp onto the clock. It equals the frame's sampled time in both orders within 10 microseconds, which is the microsecond rounding of dilated frame stamps.
- No frame is scheduled after both stop.

The full example run that includes these cases is `tool/audit/foundation-p2-2026-10-18/route-doze/host-tests.log`.

## Verdict

The ordered phase is the mid-frame microtask phase the package already uses. Unit 3 should merge `MorphFrameSync` and the glass host's path into one mechanism over it, which is a reader-load change, not a consistency fix. Input delivered from another ticker should be stamped with the frame time, as `frameTime` does, instead of the clock's last sampled time.

A Stage was not built. It cannot reorder Flutter's own tickers, such as the scroll controller behind read 1. It could remove read 1 only by queueing that input until its own phase after the tickers, which the existing microtask phase can do as well, and frame stamping removes it without queueing. A Stage therefore adds no capability for this defect. It also carries the three risks recorded in the foundation review (state in an Expando surviving `testWidgets`, the deprecated `TickerMode.getNotifier`, layout positions lagging a frame in the transient phase). This verdict rejects it on that reasoning, not on a measured comparison, and the experiment did not apply input to the real minimizing motion.

## Not covered

No device or energy measurement. The P3 device check (tab bar, segmented control and menu on the Pixel 6a) is still open, and the Pixel was not connected. The product clocks are unchanged; `frameTime` exists only in the prototype clock.
