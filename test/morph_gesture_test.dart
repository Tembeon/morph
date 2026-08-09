import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

Widget _host(ValueChanged<MorphFlight> onFlight) {
  return MaterialApp(
    builder: (BuildContext context, Widget? child) => MorphScope(child: child!),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const .all(20),
          child: MorphTag(
            id: 'btn',
            shape: const StadiumBorder(),
            child: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () => onFlight(
                  showMorphDialog(
                    context,
                    from: 'btn',
                    width: 300,
                    height: 260,
                    builder: (BuildContext context, MorphFlight flight) =>
                        const Text('dialog-content'),
                  ),
                ),
                child: const Text('open-me'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 600; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}

void main() {
  test('morphCloseHintScale clamps on both ends', () {
    expect(morphCloseHintScale(0), 0.75);
    expect(morphCloseHintScale(320), 1.0);
    expect(morphCloseHintScale(10000), 1.9);
  });

  testWidgets('close from rest scales the hint by flight distance', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    await tester.pumpWidget(_host((MorphFlight f) => flight = f));
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await _settle(tester);

    final double travel =
        (flight!.lastTargetRect.center - flight!.sourceRect.center).distance;
    flight!.close();
    expect(
      flight!.controller.velocity,
      moreOrLessEquals(
        MorphMotion.normal.closeVelocityHint * morphCloseHintScale(travel),
      ),
    );
    await _settle(tester);
  });

  group('rubber-band', () {
    test('zero at zero, slope ~c near the edge', () {
      expect(morphRubberband(0, dimension: 300), 0);
      final double nearZeroSlope = morphRubberband(1, dimension: 300);
      expect(nearZeroSlope, moreOrLessEquals(0.55, epsilon: 0.01));
    });

    test('monotonic and asymptotically bounded by dimension', () {
      double last = 0;
      for (double x = 0; x < 5000; x += 50) {
        final double y = morphRubberband(x, dimension: 300);
        expect(y, greaterThanOrEqualTo(last));
        expect(y, lessThan(300));
        last = y;
      }
    });
  });

  group('momentum projection', () {
    test('with no velocity the projection equals the position', () {
      expect(morphProjectValue(0.7, 0), 0.7);
    });

    test('a fling toward close drags the projection past the threshold', () {
      expect(morphProjectValue(0.9, -2), lessThan(0.5));
      expect(morphProjectValue(0.85, -0.2), greaterThan(0.5));
    });
  });

  group('controller scrub (a primitive for custom gesture driving)', () {
    testWidgets('the finger owns the value, the simulation is removed', (
      WidgetTester tester,
    ) async {
      final MorphController c = MorphController(vsync: const TestVSync());
      addTearDown(c.dispose);
      c.open();
      for (int i = 0; i < 600 && c.isAnimating; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }

      c.beginScrub();
      expect(c.isAnimating, isFalse);
      expect(c.isScrubbing, isTrue);
      c.updateScrub(0.5);
      expect(c.value, 0.5);
      expect(c.phase, MorphPhase.travelling);

      c.close();
      expect(c.isScrubbing, isFalse);
      expect(
        c.velocity,
        0,
        reason: 'close after a scrub takes the scrub velocity, not the hint',
      );
      for (int i = 0; i < 600 && c.isAnimating; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
    });

    testWidgets('open with a gesture velocity injects it into the spring', (
      WidgetTester tester,
    ) async {
      final MorphController c = MorphController(vsync: const TestVSync());
      addTearDown(c.dispose);
      c
        ..beginScrub()
        ..updateScrub(0.6)
        ..open(velocity: 3);
      expect(c.target, 1);
      expect(c.velocity, 3);
      for (int i = 0; i < 600 && c.isAnimating; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
    });
  });
}
