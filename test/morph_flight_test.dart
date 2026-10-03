import 'dart:async';

import 'package:material_ui/material_ui.dart';
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

  testWidgets('the source lands still: no transform after the latch', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    await tester.pumpWidget(_Host(onFlight: (MorphFlight f) => flight = f));
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await settle(tester);

    flight!.close();
    bool latched = false;
    for (int i = 0; i < 600; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      if (flight!.isLanding) {
        latched = true;
        expect(
          find.descendant(
            of: find.byType(MorphTag),
            matching: find.byType(Transform),
          ),
          findsNothing,
          reason: 'the close spring\'s undershoot moves nothing on the source',
        );
      }
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }

    expect(latched, isTrue);
    expect(flight!.isFinished, isTrue);
  });

  testWidgets('RETARGET CONTRACT: a second showMorph keeps the flight', (
    WidgetTester tester,
  ) async {
    final List<MorphFlight> launches = <MorphFlight>[];
    late BuildContext tagContext;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: MorphTag(
            id: 'btn',
            child: Builder(
              builder: (BuildContext context) {
                tagContext = context;
                return const Text('anchor');
              },
            ),
          ),
        ),
      ),
    );

    launches.add(
      showMorphDialog(
        tagContext,
        from: 'btn',
        builder: (BuildContext context, MorphFlight f) =>
            const Text('first-content'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('first-content'), findsOneWidget);

    // The second call mid-air, from the same tag but a DIFFERENT
    // builder/motion: same flight, same content, one shuttle; only the
    // motion profile is updated (content lives in the shuttle and
    // cannot be swapped).
    launches.add(
      showMorphDialog(
        tagContext,
        from: 'btn',
        motion: .glacial,
        builder: (BuildContext context, MorphFlight f) =>
            const Text('second-content'),
      ),
    );
    await tester.pump();
    expect(launches, hasLength(2));
    expect(launches[1], same(launches[0]));
    expect(find.text('first-content'), findsOneWidget);
    expect(find.text('second-content'), findsNothing);
    expect(launches[0].controller.motion, MorphMotion.glacial);

    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    expect(scope.liveFlights, hasLength(1));

    // The repeated launch must not stack a second pop entry: one pop
    // closes the flight, the next one has nothing left to pop.
    final NavigatorState nav = tester.state<NavigatorState>(
      find.byType(Navigator),
    );
    expect(nav.canPop(), isTrue);
    await settle(tester);
    // Close on a quick profile so settle() converges within its window.
    launches[0].controller.motion = MorphMotion.instant;
    unawaited(nav.maybePop());
    await settle(tester);
    expect(launches[0].isFinished, isTrue);
    expect(nav.canPop(), isFalse);
  });

  testWidgets('closed completes with the close result', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    await tester.pumpWidget(_Host(onFlight: (MorphFlight f) => flight = f));
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await settle(tester);

    Object? received;
    unawaited(flight!.closed.then((Object? value) => received = value));
    flight!.close(result: 'picked');
    await settle(tester);
    expect(flight!.isFinished, isTrue);
    expect(received, 'picked');
  });

  testWidgets('closeAll lands every live flight', (WidgetTester tester) async {
    MorphFlight? flight;
    await tester.pumpWidget(_Host(onFlight: (MorphFlight f) => flight = f));
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await settle(tester);
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    expect(scope.liveFlights.single, same(flight));

    scope.closeAll();
    await settle(tester);
    expect(flight!.isFinished, isTrue);
    expect(scope.liveFlights, isEmpty);
    expect(find.text('sheet-content'), findsNothing);
    expect(find.text('open-me'), findsOneWidget);
  });

  testWidgets('the sheet and dialog presets accept a surface model', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: MorphTag(
            id: 'btn',
            child: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () => flight = showMorphDialog(
                  context,
                  from: 'btn',
                  surface: const MorphSurfaceSpec(
                    shape: StadiumBorder(),
                    color: Color(0xFF102030),
                    elevation: 12,
                  ),
                  builder: (BuildContext context, MorphFlight f) =>
                      const Text('dialog-content'),
                ),
                child: const Text('open-me'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-me'));
    await tester.pump();
    expect(flight!.target.shape, isA<StadiumBorder>());
    expect(flight!.target.surfaceColor, const Color(0xFF102030));
    expect(flight!.target.elevation, 12);
    await settle(tester);
    flight!.close();
    await settle(tester);
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
