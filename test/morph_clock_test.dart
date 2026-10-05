import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/widgets.dart';

class _Host extends StatefulWidget {
  const _Host({required this.stamps, required this.advances, super.key});

  final List<double> stamps;
  final List<double> advances;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host>
    with SingleTickerProviderStateMixin<_Host>, MorphClock<_Host> {
  double settleAt = 0;
  double? wakeAt;

  @override
  double? get motionWakeTime => wakeAt;

  @override
  void advanceMotion(double t) => widget.advances.add(t);

  @override
  bool get motionSettled => clock >= settleAt;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (PointerDownEvent event) => widget.stamps.add(stamp(event)),
    onPointerUp: (PointerUpEvent event) => widget.stamps.add(stamp(event)),
    child: const SizedBox.expand(),
  );
}

void main() {
  late Duration lead;
  late Duration Function() savedNow;
  late Duration? Function() savedOffset;
  Duration? offset = Duration.zero;

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
    lead = Duration.zero;
    offset = Duration.zero;
    if (!listening) {
      listening = true;
      SchedulerBinding.instance.addPersistentFrameCallback((Duration _) {
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
  });

  Future<(GlobalKey<_HostState>, List<double>, List<double>)> host(
    WidgetTester tester, {
    required bool running,
  }) async {
    final stamps = <double>[];
    final advances = <double>[];
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      _Host(key: key, stamps: stamps, advances: advances),
    );
    if (running) {
      key.currentState!.settleAt = 10;
      key.currentState!.wake();
    }
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    return (key, stamps, advances);
  }

  Future<TestGesture> touch(WidgetTester tester, Duration timeStamp) async {
    final gesture = await tester.createGesture();
    await gesture.down(const Offset(10, 10), timeStamp: timeStamp);
    return gesture;
  }

  testWidgets('an event is stamped at its own time stamp', (
    WidgetTester tester,
  ) async {
    final (key, stamps, advances) = await host(tester, running: true);
    final clock = key.currentState!.clock;
    lead = const Duration(milliseconds: 6);
    final gesture = await touch(
      tester,
      frameStamp - const Duration(milliseconds: 20),
    );
    expect(stamps.single, moreOrLessEquals(clock - 0.020, epsilon: 1e-9));
    lead = Duration.zero;
    await tester.pump(const Duration(milliseconds: 8));
    expect(advances.last, moreOrLessEquals(clock + 0.008, epsilon: 1e-9));
    await gesture.up(timeStamp: frameStamp);
  });

  testWidgets('without a usable time stamp an event is stamped one frame '
      'after its delivery', (WidgetTester tester) async {
    final (key, stamps, _) = await host(tester, running: true);
    final clock = key.currentState!.clock;
    lead = const Duration(milliseconds: 6);
    offset = null;
    final gesture = await touch(tester, Duration.zero);
    expect(
      stamps.single,
      moreOrLessEquals(clock - 0.006 + 1 / 60, epsilon: 1e-6),
    );
    offset = Duration.zero;
    final stale = await tester.createGesture(pointer: 7);
    await stale.down(
      const Offset(20, 20),
      timeStamp: now() - const Duration(seconds: 1),
    );
    expect(
      stamps.last,
      moreOrLessEquals(clock - 0.006 + 1 / 60, epsilon: 1e-6),
    );
    lead = Duration.zero;
    await gesture.up(timeStamp: frameStamp);
    await stale.up(timeStamp: frameStamp);
  });

  testWidgets('the first frame after a wake counts from the time stamp', (
    WidgetTester tester,
  ) async {
    final (key, stamps, advances) = await host(tester, running: false);
    await tester.pump(const Duration(milliseconds: 500));
    final asleep = key.currentState!.clock;
    final gesture = await touch(
      tester,
      now() - const Duration(milliseconds: 15),
    );
    expect(stamps.single, asleep);
    key.currentState!.settleAt = 10;
    advances.clear();
    await tester.pump(const Duration(milliseconds: 25));
    expect(advances.first, moreOrLessEquals(asleep + 0.040, epsilon: 1e-9));
    await gesture.up(timeStamp: now());
  });

  testWidgets('an event during a doze counts the doze', (
    WidgetTester tester,
  ) async {
    final (key, stamps, _) = await host(tester, running: true);
    final state = key.currentState!;
    state.wakeAt = state.clock + 0.5;
    await tester.pump(const Duration(milliseconds: 16));
    final dozed = state.clock;
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.clock, dozed);
    final gesture = await touch(
      tester,
      now() - const Duration(milliseconds: 10),
    );
    expect(stamps.single, moreOrLessEquals(dozed + 0.09, epsilon: 1e-9));
    state.wakeAt = null;
    await gesture.up(timeStamp: now());
    await tester.pump(const Duration(milliseconds: 16));
  });

  testWidgets('a fake frame clock keeps the frame stamps', (
    WidgetTester tester,
  ) async {
    morphClockNow = savedNow;
    final (key, stamps, _) = await host(tester, running: true);
    final gesture = await touch(tester, Duration.zero);
    expect(stamps.single, key.currentState!.clock);
    await gesture.up();
  });

  test('a spring change never reaches back before the previous one', () {
    const spring = MorphSpring(0.4, 0.8);
    final a = MorphSpringState(spring, 0);
    a.retarget(1, 1);
    a.retarget(0.99, 0);
    final b = MorphSpringState(spring, 0);
    b.retarget(1, 1);
    b.retarget(1, 0);
    expect(a.value(1.2), b.value(1.2));
    expect(a.velocity(1.2), b.velocity(1.2));
  });
}
