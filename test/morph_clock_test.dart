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
  late Duration Function() saved;

  var frameStamp = Duration.zero;
  var frameWall = DateTime(2026);
  var listening = false;

  setUp(() {
    saved = morphClockNow;
    lead = Duration.zero;
    if (!listening) {
      listening = true;
      SchedulerBinding.instance.addPersistentFrameCallback((Duration _) {
        frameStamp = SchedulerBinding.instance.currentSystemFrameTimeStamp;
        frameWall = TestWidgetsFlutterBinding.instance.clock.now();
      });
    }
    morphClockNow = () =>
        frameStamp +
        TestWidgetsFlutterBinding.instance.clock.now().difference(frameWall) -
        lead;
  });

  tearDown(() => morphClockNow = saved);

  testWidgets('an event is stamped one frame after its delivery', (
    WidgetTester tester,
  ) async {
    final stamps = <double>[];
    final advances = <double>[];
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      _Host(key: key, stamps: stamps, advances: advances),
    );
    key.currentState!.settleAt = 10;
    key.currentState!.wake();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    final clock = key.currentState!.clock;
    lead = const Duration(milliseconds: 6);
    final gesture = await tester.startGesture(const Offset(10, 10));
    expect(
      stamps.single,
      moreOrLessEquals(clock - 0.006 + 1 / 60, epsilon: 1e-9),
    );
    lead = Duration.zero;
    await tester.pump(const Duration(milliseconds: 8));
    expect(advances.last, moreOrLessEquals(clock + 0.008, epsilon: 1e-9));
    await gesture.up();
  });

  testWidgets('the first frame after a wake counts from a frame after the '
      'delivery', (WidgetTester tester) async {
    final stamps = <double>[];
    final advances = <double>[];
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      _Host(key: key, stamps: stamps, advances: advances),
    );
    await tester.pump(const Duration(milliseconds: 8));
    await tester.pump(const Duration(milliseconds: 500));
    final asleep = key.currentState!.clock;
    final gesture = await tester.startGesture(const Offset(10, 10));
    expect(stamps.single, asleep);
    key.currentState!.settleAt = 10;
    advances.clear();
    await tester.pump(const Duration(milliseconds: 25));
    expect(
      advances.first,
      moreOrLessEquals(asleep + 0.025 - 1 / 60, epsilon: 1e-9),
    );
    await gesture.up();
  });

  testWidgets('an event during a doze counts the doze', (
    WidgetTester tester,
  ) async {
    final stamps = <double>[];
    final advances = <double>[];
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      _Host(key: key, stamps: stamps, advances: advances),
    );
    final host = key.currentState!;
    host.settleAt = 10;
    host.wake();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    host.wakeAt = host.clock + 0.5;
    await tester.pump(const Duration(milliseconds: 16));
    final dozed = host.clock;
    await tester.pump(const Duration(milliseconds: 100));
    expect(host.clock, dozed);
    final gesture = await tester.startGesture(const Offset(10, 10));
    expect(
      stamps.single,
      moreOrLessEquals(dozed + 0.1 + 1 / 60, epsilon: 1e-9),
    );
    host.wakeAt = null;
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
  });

  testWidgets('a fake frame clock keeps the frame stamps', (
    WidgetTester tester,
  ) async {
    morphClockNow = saved;
    final stamps = <double>[];
    final advances = <double>[];
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      _Host(key: key, stamps: stamps, advances: advances),
    );
    key.currentState!.settleAt = 10;
    key.currentState!.wake();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    final gesture = await tester.startGesture(const Offset(10, 10));
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
