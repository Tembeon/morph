import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

const MorphScrimMotion _scrim = MorphScrimMotion(
  motion: MorphMotion.springs(
    name: 'scrimTest',
    open: MorphSpring(0.4, 0.8),
    close: MorphSpring(0.9, 1.0),
  ),
  openDelay: Duration(milliseconds: 24),
  closeDelay: Duration(milliseconds: 32),
);

class _Host extends StatelessWidget {
  const _Host({
    required this.onFlight,
    this.scrim,
    this.disableAnimations = false,
    this.onPage,
  });

  final ValueChanged<MorphFlight> onFlight;
  final MorphScrimMotion? scrim;
  final bool disableAnimations;
  final VoidCallback? onPage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: MorphScope(child: child!),
      ),
      home: Scaffold(
        body: Stack(
          children: <Widget>[
            Positioned(
              left: 0,
              top: 0,
              child: TextButton(onPressed: onPage, child: const Text('page')),
            ),
            Center(
              child: MorphTag(
                id: 'btn',
                child: Builder(
                  builder: (BuildContext context) => TextButton(
                    onPressed: () => onFlight(
                      showMorph(
                        context,
                        from: 'btn',
                        maxScrimOpacity: 0.5,
                        scrimMotion: scrim,
                        target: MorphTargetSpec.dialog(),
                        builder: (BuildContext context, MorphFlight flight) =>
                            const Text('content'),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The painted scrim's opacity: the alpha of the black full-screen box.
double _painted(WidgetTester tester) {
  final Iterable<ColoredBox> boxes = tester
      .widgetList<ColoredBox>(find.byType(ColoredBox))
      .where(
        (ColoredBox box) =>
            box.color.r == 0 &&
            box.color.g == 0 &&
            box.color.b == 0 &&
            box.color.a > 0,
      );
  return boxes.isEmpty ? 0 : boxes.single.color.a;
}

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 600; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    expect(tester.takeException(), isNull);
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}

void main() {
  testWidgets('without a scrim motion the scrim follows the flight value', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    await tester.pumpWidget(_Host(onFlight: (MorphFlight f) => flight = f));
    await tester.tap(find.text('open'));
    await tester.pump();
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      final double expected =
          0.5 * (flight!.controller.progress / 0.7).clamp(0, 1);
      expect(flight!.scrimValue, isNull);
      expect(flight!.scrimOpacity, moreOrLessEquals(expected));
      expect(_painted(tester), moreOrLessEquals(expected, epsilon: 1e-3));
    }
  });

  testWidgets('a scrim motion dims on its own spring after its delay, and '
      'the flight value does not notice', (WidgetTester tester) async {
    MorphFlight? flight;
    await tester.pumpWidget(
      _Host(scrim: _scrim, onFlight: (MorphFlight f) => flight = f),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    final Simulation dim = _scrim.motion.openMotion.createSimulation(
      start: 0,
      end: 1,
    );
    final Simulation value = MorphMotion.liquid.openMotion.createSimulation(
      start: 0,
      end: 1,
    );
    // The first frame after the launch is the clocks' zero.
    await tester.pump();
    for (int i = 1; i <= 80; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      final double t = i * 0.008;
      final double expected = t < 0.024 ? 0 : dim.x(t - 0.024);
      expect(flight!.scrimValue, moreOrLessEquals(expected, epsilon: 1e-6));
      expect(
        flight!.controller.value,
        moreOrLessEquals(value.x(t), epsilon: 1e-3),
      );
      expect(
        _painted(tester),
        moreOrLessEquals(0.5 * expected.clamp(0, 1), epsilon: 2e-3),
      );
    }
  });

  testWidgets('a reversal carries the scrim velocity: no jump, and the dim '
      'keeps rising for a moment after a close', (WidgetTester tester) async {
    const MorphScrimMotion scrim = MorphScrimMotion(motion: _scrimNoDelay);
    MorphFlight? flight;
    await tester.pumpWidget(
      _Host(scrim: scrim, onFlight: (MorphFlight f) => flight = f),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    final double before = flight!.scrimValue!;
    expect(before, inExclusiveRange(0.05, 0.9));
    flight!.close();
    final List<double> after = <double>[before];
    for (int i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      after.add(flight!.isFinished ? 0 : flight!.scrimValue!);
    }
    for (int i = 1; i < after.length; i++) {
      expect((after[i] - after[i - 1]).abs(), lessThan(0.08));
    }
    expect(after[2], greaterThan(before));
    expect(after.last, 0);
  });

  testWidgets('the scrim outlives the handoff latch: the source is home and '
      'live, the page takes taps, and the flight lands after the dim', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    var pageTaps = 0;
    final List<MorphFlightEvent> log = <MorphFlightEvent>[];
    await tester.pumpWidget(
      _Host(
        scrim: _scrim,
        onFlight: (MorphFlight f) {
          flight = f;
          f.events.listen(log.add);
        },
        onPage: () => pageTaps++,
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    flight!.close();
    while (!flight!.controller.hasHandedOff) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    await tester.pump();
    expect(flight!.isFinished, isFalse);
    expect(flight!.isLanding, isTrue);
    expect(log, contains(MorphFlightEvent.latched));
    expect(log, isNot(contains(MorphFlightEvent.landed)));
    expect(find.text('content'), findsNothing);
    expect(flight!.scrimValue, greaterThan(0.1));
    expect(_painted(tester), moreOrLessEquals(0.5 * flight!.scrimValue!));
    await tester.tap(find.text('page'));
    expect(pageTaps, 1);
    await _settle(tester);
    expect(flight!.isFinished, isTrue);
    expect(_painted(tester), 0);
    expect(log.last, MorphFlightEvent.landed);
  });

  testWidgets('a re-open while the scrim lingers takes the same flight up '
      'again from the current dim', (WidgetTester tester) async {
    final List<MorphFlight> flights = <MorphFlight>[];
    await tester.pumpWidget(_Host(scrim: _scrim, onFlight: flights.add));
    await tester.tap(find.text('open'));
    await _settle(tester);
    final MorphFlight flight = flights.single;
    flight.close();
    while (!flight.controller.hasHandedOff) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    await tester.pump();
    final double lingering = flight.scrimValue!;
    expect(lingering, greaterThan(0.1));
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(flights, hasLength(2));
    expect(identical(flights.last, flight), isTrue);
    await tester.pump(const Duration(milliseconds: 8));
    expect(flight.scrimValue, moreOrLessEquals(lingering, epsilon: 0.05));
    await _settle(tester);
    expect(flight.isOpenOrOpening, isTrue);
    expect(flight.scrimValue, 1);
    expect(find.text('content'), findsOneWidget);
    expect(_painted(tester), moreOrLessEquals(0.5));
  });

  testWidgets('under reduced motion the scrim rides the instant profile '
      'with no delay', (WidgetTester tester) async {
    MorphFlight? flight;
    await tester.pumpWidget(
      _Host(
        scrim: const MorphScrimMotion(
          motion: _scrimNoDelay,
          openDelay: Duration(seconds: 1),
        ),
        disableAnimations: true,
        onFlight: (MorphFlight f) => flight = f,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final double instant = MorphMotion.instant.openMotion
        .createSimulation(start: 0, end: 1)
        .x(0.04);
    expect(flight!.scrimValue, moreOrLessEquals(instant, epsilon: 1e-6));
  });

  test('scrim motions compare by value', () {
    expect(
      const MorphScrimMotion(motion: MorphMotion.liquid),
      const MorphScrimMotion(motion: MorphMotion.liquid),
    );
    expect(
      const MorphScrimMotion(motion: MorphMotion.liquid),
      isNot(
        const MorphScrimMotion(
          motion: MorphMotion.liquid,
          closeDelay: Duration(milliseconds: 1),
        ),
      ),
    );
  });
}

const MorphMotion _scrimNoDelay = MorphMotion.springs(
  name: 'scrimNoDelay',
  open: MorphSpring(0.4, 0.8),
  close: MorphSpring(0.9, 1.0),
);
