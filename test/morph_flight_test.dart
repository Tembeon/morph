import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

class _Host extends StatelessWidget {
  const _Host({required this.onFlight});

  final ValueChanged<MorphFlight> onFlight;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (BuildContext context, Widget? child) =>
          MorphScope(child: child!),
      home: Scaffold(
        body: Center(
          child: MorphTag(
            id: 'btn',
            shape: const StadiumBorder(),
            child: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () => onFlight(
                  showMorphSheet(
                    context,
                    from: 'btn',
                    builder: (BuildContext context, MorphFlight flight) =>
                        const Text('sheet-content'),
                  ),
                ),
                child: const Text('open-me'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 600; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}

void main() {
  testWidgets('full cycle: open -> settled -> close -> handoff', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    await tester.pumpWidget(_Host(onFlight: (MorphFlight f) => flight = f));

    expect(find.text('sheet-content'), findsNothing);

    await tester.tap(find.text('open-me'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(flight, isNotNull);
    expect(find.text('sheet-content'), findsOneWidget);
    expect(flight!.controller.isAnimating, isTrue);
    expect(flight!.controller.phase, isNot(MorphPhase.settled));

    await settle(tester);
    expect(flight!.controller.phase, MorphPhase.settled);
    expect(flight!.isOpenOrOpening, isTrue);

    flight!.close();
    await settle(tester);

    expect(flight!.isFinished, isTrue);
    expect(flight!.controller.hasHandedOff, isTrue);
    expect(find.text('sheet-content'), findsNothing);
    expect(find.text('open-me'), findsOneWidget);
  });

  testWidgets(
    'a repeated showMorph retargets the flight, not spawns a new one',
    (WidgetTester tester) async {
      final List<MorphFlight> flights = <MorphFlight>[];
      await tester.pumpWidget(_Host(onFlight: flights.add));

      await tester.tap(find.text('open-me'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      final MorphFlight first = flights.single;
      first.close();
      await tester.pump(const Duration(milliseconds: 40));
      expect(first.controller.target, 0);
      expect(first.isFinished, isFalse);

      first.open();
      await tester.pump(const Duration(milliseconds: 16));
      expect(first.controller.target, 1);
      expect(find.text('sheet-content'), findsOneWidget);

      await settle(tester);
      expect(first.controller.phase, MorphPhase.settled);
      expect(first.isFinished, isFalse);

      first.close();
      await settle(tester);
      expect(first.isFinished, isTrue);
    },
  );

  testWidgets('the button recoils on landing: a recoil shift after the latch', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    await tester.pumpWidget(_Host(onFlight: (MorphFlight f) => flight = f));
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await settle(tester);

    flight!.close();
    double maxKick = 0;
    for (int i = 0; i < 600; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      final Finder bumpTransform = find.descendant(
        of: find.byType(MorphTag),
        matching: find.byType(Transform),
      );
      if (bumpTransform.evaluate().isNotEmpty) {
        final Transform t = tester.widget(bumpTransform.first);
        final Offset shift = Offset(
          t.transform.getTranslation().x,
          t.transform.getTranslation().y,
        );
        if (shift.distance > maxKick) {
          maxKick = shift.distance;
        }
      }
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }

    expect(
      maxKick,
      greaterThan(2),
      reason: 'undershoot must push the button along the impact axis',
    );
    expect(flight!.isFinished, isTrue);
    expect(
      find.descendant(
        of: find.byType(MorphTag),
        matching: find.byType(Transform),
      ),
      findsNothing,
      reason: 'the bump is removed after finalization',
    );
  });

  testWidgets('tapping the scrim mid-flight interrupts open', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    await tester.pumpWidget(_Host(onFlight: (MorphFlight f) => flight = f));

    await tester.tap(find.text('open-me'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(flight!.controller.target, 1);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(flight!.controller.target, 0);

    await settle(tester);
    expect(flight!.isFinished, isTrue);
    expect(find.text('sheet-content'), findsNothing);
  });
}
