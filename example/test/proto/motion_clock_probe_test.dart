import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph_example/proto/motion_clock_probe.dart';

abstract class _Host extends StatefulWidget {
  const _Host({super.key});
}

class _OldHost extends _Host {
  const _OldHost({super.key});

  @override
  State<_Host> createState() => _OriginalHost();
}

class _NewHost extends _Host {
  const _NewHost({super.key});

  @override
  State<_Host> createState() => _ObjectHost();
}

abstract class _ClockHost extends State<_Host> {
  final samples = <double>[];
  double settleAt = 0;
  double? wakeAt;
  double get time;
  double? get period;
  double stamp(PointerEvent event);
  void wake();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _OriginalHost extends _ClockHost
    with SingleTickerProviderStateMixin<_Host>, MorphClock<_Host> {
  @override
  double get time => clock;

  @override
  double? get period => framePeriod;

  @override
  void advanceMotion(double t) => samples.add(t);

  @override
  bool get motionSettled => clock >= settleAt;

  @override
  double? get motionWakeTime => wakeAt;
}

class _ObjectHost extends _ClockHost
    with SingleTickerProviderStateMixin<_Host> {
  late final clock = ProbeMotionClock(
    vsync: this,
    now: () => morphClockNow(),
    pointerOffset: () => morphPointerClockOffset(),
    onFrame: (time) {
      samples.add(time);
      return (settled: time >= settleAt, wakeTime: wakeAt);
    },
  );

  @override
  double get time => clock.time;

  @override
  double? get period => clock.framePeriod;

  @override
  double stamp(PointerEvent event) => clock.stamp(event);

  @override
  void wake() => clock.wake();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rate = View.of(context).display.refreshRate;
    clock.frameRate = rate.round() == 60 ? 60 : 120;
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }
}

void main() {
  late Duration Function() savedNow;
  late Duration? Function() savedOffset;
  late double savedDilation;
  Duration? offset = Duration.zero;
  var lead = Duration.zero;
  var frameStamp = Duration.zero;
  var frameWall = DateTime(2026);
  var listening = false;

  Duration now() =>
      frameStamp +
      TestWidgetsFlutterBinding.instance.clock.now().difference(frameWall) -
      lead;

  setUp(() {
    savedNow = morphClockNow;
    savedOffset = morphPointerClockOffset;
    savedDilation = timeDilation;
    lead = Duration.zero;
    offset = Duration.zero;
    if (!listening) {
      listening = true;
      SchedulerBinding.instance.addPersistentFrameCallback((_) {
        frameStamp = SchedulerBinding.instance.currentSystemFrameTimeStamp;
        frameWall = TestWidgetsFlutterBinding.instance.clock.now();
      });
    }
    morphClockNow = now;
    morphPointerClockOffset = () => offset;
  });

  tearDown(() {
    morphClockNow = savedNow;
    morphPointerClockOffset = savedOffset;
    timeDilation = savedDilation;
  });

  Future<List<_ClockHost>> hosts(
    WidgetTester tester, {
    bool running = true,
    ValueNotifier<bool>? tickerMode,
  }) async {
    final keys = [GlobalKey<_ClockHost>(), GlobalKey<_ClockHost>()];
    final body = Directionality(
      textDirection: .ltr,
      child: Row(
        children: [
          Expanded(child: _OldHost(key: keys[0])),
          Expanded(child: _NewHost(key: keys[1])),
        ],
      ),
    );
    await tester.pumpWidget(
      tickerMode == null
          ? body
          : ValueListenableBuilder<bool>(
              valueListenable: tickerMode,
              builder: (_, enabled, child) =>
                  TickerMode(enabled: enabled, child: child!),
              child: body,
            ),
    );
    final result = keys.map((key) => key.currentState!).toList();
    if (running) {
      for (final host in result) {
        host.settleAt = 10;
        host.wake();
      }
    }
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    return result;
  }

  void parity(List<_ClockHost> pair) {
    expect(pair[1].samples.length, pair[0].samples.length);
    for (var i = 0; i < pair[0].samples.length; i++) {
      expect(pair[1].samples[i], closeTo(pair[0].samples[i], 1e-9));
    }
    expect(pair[1].time, closeTo(pair[0].time, 1e-9));
  }

  for (final rate in [60.0, 120.0]) {
    testWidgets(
      '$rate Hz: jitter and dropped frames preserve measured samples',
      (tester) async {
        tester.view.display.refreshRate = rate;
        addTearDown(tester.view.display.resetRefreshRate);
        final pair = await hosts(tester);
        final period = (1e6 / rate).round();
        for (var i = 0; i < 40; i++) {
          final jitter = [0, 30, -20, 45, -35, 10, -5, 25][i % 8];
          final missed = i == 20 ? 3 : 1;
          await tester.pump(Duration(microseconds: period * missed + jitter));
        }
        parity(pair);
        expect(pair[1].period, pair[0].period);
        expect(pair[1].period, isNotNull);
      },
    );
  }

  testWidgets('OS pointer offset and delayed delivery keep the event time', (
    tester,
  ) async {
    final pair = await hosts(tester);
    offset = const Duration(seconds: 35);
    lead = const Duration(milliseconds: 6);
    final event = PointerDownEvent(
      timeStamp: frameStamp - offset! - const Duration(milliseconds: 20),
    );
    for (final host in pair) {
      expect(host.stamp(event), closeTo(host.time - 0.020, 1e-9));
    }
    lead = Duration.zero;
    await tester.pump(const Duration(milliseconds: 8));
    parity(pair);
  });

  for (final invalid in [
    'missing offset',
    'stale timestamp',
    'future timestamp',
  ]) {
    testWidgets('$invalid uses the measured fallback', (tester) async {
      final pair = await hosts(tester);
      lead = const Duration(milliseconds: 6);
      offset = invalid == 'missing offset' ? null : Duration.zero;
      final at = invalid == 'future timestamp'
          ? now() + const Duration(seconds: 1)
          : now() - const Duration(seconds: 1);
      for (final host in pair) {
        expect(
          host.stamp(PointerDownEvent(timeStamp: at)),
          closeTo(host.time - 0.006 + 1 / 60, 1e-6),
        );
      }
      lead = Duration.zero;
      await tester.pump(const Duration(milliseconds: 8));
      parity(pair);
    });
  }

  testWidgets('wake after settled sleep includes input delivery lag', (
    tester,
  ) async {
    final pair = await hosts(tester, running: false);
    await tester.pump(const Duration(milliseconds: 500));
    final at = now() - const Duration(milliseconds: 15);
    for (final host in pair) {
      expect(host.stamp(PointerDownEvent(timeStamp: at)), 0);
      host.settleAt = 10;
    }
    await tester.pump(const Duration(milliseconds: 25));
    parity(pair);
    expect(pair[1].time, closeTo(0.040, 1e-9));
  });

  testWidgets('multiple inputs before the first frame preserve their spacing', (
    tester,
  ) async {
    final pair = await hosts(tester, running: false);
    for (final host in pair) {
      expect(
        host.stamp(
          PointerDownEvent(timeStamp: now() - const Duration(milliseconds: 40)),
        ),
        0,
      );
      expect(
        host.stamp(
          PointerUpEvent(timeStamp: now() - const Duration(milliseconds: 20)),
        ),
        closeTo(0.020, 1e-9),
      );
      host.settleAt = 10;
    }
    await tester.pump(const Duration(milliseconds: 10));
    parity(pair);
    expect(pair[1].time, closeTo(0.050, 1e-9));
  });

  testWidgets('an input interrupts doze without losing time asleep', (
    tester,
  ) async {
    final pair = await hosts(tester);
    for (final host in pair) {
      host.wakeAt = host.time + 0.5;
    }
    await tester.pump(const Duration(milliseconds: 16));
    final dozed = pair[0].time;
    final counts = pair.map((host) => host.samples.length).toList();
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < pair.length; i++) {
      expect(pair[i].samples.length, counts[i]);
      expect(
        pair[i].stamp(
          PointerDownEvent(timeStamp: now() - const Duration(milliseconds: 10)),
        ),
        closeTo(dozed + 0.09, 1e-9),
      );
      pair[i].wakeAt = null;
    }
    await tester.pump(const Duration(milliseconds: 16));
    parity(pair);
    expect(pair[1].time, closeTo(dozed + 0.116, 1e-9));
  });

  for (final dilation in [1.0, 5.0]) {
    testWidgets('timed doze resumes on the same clock at ${dilation}x', (
      tester,
    ) async {
      timeDilation = dilation;
      try {
        final pair = await hosts(tester);
        for (final host in pair) {
          host.wakeAt = host.time + 0.5;
        }
        await tester.pump(const Duration(milliseconds: 16));
        final dozed = pair[0].time;
        final counts = pair.map((host) => host.samples.length).toList();
        await tester.pump(Duration(milliseconds: (100 * dilation).round()));
        for (var i = 0; i < pair.length; i++) {
          expect(pair[i].samples.length, counts[i]);
        }
        await tester.pump(Duration(milliseconds: (400 * dilation).round()));
        parity(pair);
        expect(pair[1].time, closeTo(dozed + 0.5, 2e-6));
      } finally {
        timeDilation = savedDilation;
      }
    });
  }

  testWidgets('slow motion scales delayed pointer time', (tester) async {
    timeDilation = 5;
    try {
      final pair = await hosts(tester);
      final at = frameStamp - const Duration(milliseconds: 20);
      for (final host in pair) {
        expect(
          host.stamp(PointerDownEvent(timeStamp: at)),
          closeTo(host.time - 0.004, 1e-9),
        );
      }
      await tester.pump(const Duration(milliseconds: 40));
      parity(pair);
    } finally {
      timeDilation = savedDilation;
    }
  });

  testWidgets('settled clocks schedule no more samples', (tester) async {
    final pair = await hosts(tester);
    for (final host in pair) {
      host.settleAt = host.time + 0.05;
    }
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    parity(pair);
    final counts = pair.map((host) => host.samples.length).toList();
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < pair.length; i++) {
      expect(pair[i].samples.length, counts[i]);
    }
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a frame clock unrelated to platform time uses frame samples', (
    tester,
  ) async {
    final pair = await hosts(tester);
    morphClockNow = savedNow;
    await tester.pump(const Duration(milliseconds: 8));
    for (final host in pair) {
      expect(host.stamp(const PointerDownEvent()), host.time);
    }
    await tester.pump(const Duration(milliseconds: 8));
    parity(pair);
  });

  testWidgets('TickerMode silences callbacks and resumes elapsed time', (
    tester,
  ) async {
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    final pair = await hosts(tester, tickerMode: enabled);
    enabled.value = false;
    await tester.pump();
    final frozen = pair[0].time;
    final counts = pair.map((host) => host.samples.length).toList();
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < pair.length; i++) {
      expect(pair[i].samples.length, counts[i]);
    }
    enabled.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    parity(pair);
    expect(pair[1].time, closeTo(frozen + 0.116, 1e-9));
  });

  testWidgets('disposing during doze cancels its timer and ticker', (
    tester,
  ) async {
    final pair = await hosts(tester);
    for (final host in pair) {
      host.wakeAt = host.time + 0.5;
    }
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final dilation in [1.0, 5.0]) {
    testWidgets(
      'absolute resume outside a frame includes elapsed doze at ${dilation}x',
      (tester) async {
        await tester.pumpWidget(const SizedBox());
        var samples = 0;
        var dozing = true;
        final clock = ProbeMotionClock(
          vsync: const TestVSync(),
          now: () => Duration(
            microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
          ),
          pointerOffset: () => Duration.zero,
          onFrame: (time) {
            samples++;
            return (settled: !dozing, wakeTime: dozing ? time + 2 : null);
          },
        );
        final original = timeDilation;
        timeDilation = dilation;
        try {
          clock.wake();
          await tester.pump();
          await tester.pump(Duration(milliseconds: (100 * dilation).round()));
          expect(samples, 1);
          final anchor = clock.resumeAt(clock.now());
          expect(anchor, closeTo(0.1, 1e-9));
          dozing = false;
          await tester.pump(Duration(milliseconds: (8 * dilation).round()));
          expect(clock.time, closeTo(0.108, 1e-9));
          expect(samples, 2);
          expect(tester.binding.transientCallbackCount, 0);
        } finally {
          clock.dispose();
          timeDilation = original;
        }
      },
    );
  }

  testWidgets('relinquishing a dozing clock cancels its pending wake', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    var samples = 0;
    var dozing = true;
    final clock = ProbeMotionClock(
      vsync: const TestVSync(),
      now: () => Duration(
        microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
      ),
      pointerOffset: () => Duration.zero,
      onFrame: (time) {
        samples++;
        return (settled: !dozing, wakeTime: dozing ? time + 0.5 : null);
      },
    );
    try {
      clock.wake();
      await tester.pump();
      expect(samples, 1);
      await tester.pump(const Duration(milliseconds: 100));
      clock.pause();
      final pausedAt = clock.time;
      await tester.pump(const Duration(seconds: 1));
      expect(samples, 1);
      expect(tester.binding.transientCallbackCount, 0);
      dozing = false;
      final anchor = clock.resumeAt(clock.now());
      expect(anchor, pausedAt);
      await tester.pump(const Duration(milliseconds: 8));
      expect(clock.time - anchor, closeTo(0.008, 1e-9));
      expect(samples, 2);
      expect(tester.binding.transientCallbackCount, 0);
    } finally {
      clock.dispose();
    }
  });
}
// ignore_for_file: invalid_use_of_internal_member
