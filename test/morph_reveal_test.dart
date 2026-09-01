import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int n = 0;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => n++),
      child: Text('count-$n'),
    );
  }
}

Future<void> settle(WidgetTester tester, {int frames = 600}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    expect(tester.takeException(), isNull);
    if (!tester.binding.hasScheduledFrame) {
      break;
    }
  }
}

Widget host(ValueChanged<MorphFlight> onFlight) {
  return MaterialApp(
    builder: (BuildContext context, Widget? child) => MorphScope(child: child!),
    home: Scaffold(
      body: Center(
        child: MorphTag(
          id: 'btn',
          child: Builder(
            builder: (BuildContext context) => ElevatedButton(
              onPressed: () => onFlight(
                showMorphSheet(
                  context,
                  from: 'btn',
                  builder: (BuildContext context, MorphFlight flight) =>
                      const Column(
                        children: <Widget>[
                          MorphReveal(
                            from: 0.35,
                            to: 0.6,
                            child: Text('early-block'),
                          ),
                          MorphReveal(
                            from: 0.7,
                            to: 0.95,
                            child: Text('late-block'),
                          ),
                        ],
                      ),
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

double opacityAbove(WidgetTester tester, String text) {
  final Opacity? widget = tester
      .widgetList<Opacity>(
        find.ancestor(of: find.text(text), matching: find.byType(Opacity)),
      )
      .firstOrNull;
  return widget?.opacity ?? 1;
}

void main() {
  testWidgets(
    'cascade: the early block leads the late one, both whole by settle',
    (WidgetTester tester) async {
      MorphFlight? flight;
      await tester.pumpWidget(host((MorphFlight f) => flight = f));
      await tester.tap(find.text('open-me'));
      await tester.pump();

      double? earlyAtMid;
      double? lateAtMid;
      for (int i = 0; i < 600; i++) {
        await tester.pump(const Duration(milliseconds: 8));
        final double p = flight!.controller.progress;
        if (earlyAtMid == null && p > 0.55 && p < 0.7) {
          earlyAtMid = opacityAbove(tester, 'early-block');
          lateAtMid = opacityAbove(tester, 'late-block');
        }
        if (!tester.binding.hasScheduledFrame) {
          break;
        }
      }

      expect(earlyAtMid, isNotNull, reason: 'mid-flight was not captured');
      expect(earlyAtMid, greaterThan(lateAtMid!));
      expect(lateAtMid, lessThan(0.05));

      expect(flight!.controller.phase, MorphPhase.settled);
      expect(opacityAbove(tester, 'early-block'), 1);
      expect(opacityAbove(tester, 'late-block'), 1);
    },
  );

  testWidgets(
    'unfolding: the block is squashed in flight, no transform at rest',
    (WidgetTester tester) async {
      MorphFlight? flight;
      await tester.pumpWidget(host((MorphFlight f) => flight = f));
      await tester.tap(find.text('open-me'));
      await tester.pump();

      bool sawSquash = false;
      for (int i = 0; i < 600; i++) {
        await tester.pump(const Duration(milliseconds: 8));
        final double p = flight!.controller.progress;
        if (p > 0.72 && p < 0.9) {
          final Finder f = find.ancestor(
            of: find.text('late-block'),
            matching: find.byType(Transform),
          );
          if (f.evaluate().isNotEmpty) {
            final Transform t = tester.widget(f.first);
            final double sy = t.transform.getRow(1).y;
            if (sy > 0 && sy < 0.99) {
              sawSquash = true;
            }
          }
        }
        if (!tester.binding.hasScheduledFrame) {
          break;
        }
      }

      expect(
        sawSquash,
        isTrue,
        reason:
            'in the middle of its range the block must be squashed (sy < 1)',
      );
      final Iterable<Transform> atRest = tester.widgetList<Transform>(
        find.ancestor(
          of: find.text('late-block'),
          matching: find.byType(Transform),
        ),
      );
      for (final Transform t in atRest) {
        expect(
          t.transform.getRow(1).y,
          greaterThanOrEqualTo(0.99),
          reason: 'at rest the block must not stay squashed',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a MorphTag and live state inside MorphReveal survive t=1', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MorphTag(
              id: 'card',
              child: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => showMorphDialog(
                    context,
                    from: 'card',
                    builder: (BuildContext context, MorphFlight flight) =>
                        const MorphReveal(
                          child: Column(
                            mainAxisSize: .min,
                            children: <Widget>[
                              MorphTag(id: 'inner', child: Text('inner')),
                              Counter(),
                            ],
                          ),
                        ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    // The open crosses t=1: no duplicate-tag assert may fire.
    await settle(tester);
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('card')!;

    // Mutate state at rest, then cross the boundary DOWN on close:
    // the element must stay alive, the state must ride the flight.
    await tester.tap(find.text('count-0'));
    await tester.pump();
    flight.close();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('count-1'), findsOneWidget);
    flight.open();
    await settle(tester);
    expect(find.text('count-1'), findsOneWidget);
    flight.abort();
  });

  testWidgets('an overshooting curve stays legal for Opacity', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Center(
            child: MorphTag(
              id: 'btn',
              child: Builder(
                builder: (BuildContext context) => ElevatedButton(
                  onPressed: () => flight = showMorphSheet(
                    context,
                    from: 'btn',
                    builder: (BuildContext context, MorphFlight f) =>
                        const MorphReveal(
                          curve: Curves.easeOutBack,
                          child: Text('springy-block'),
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
    await tester.tap(find.text('open-me'));
    await tester.pump();
    // The back-curve overshoots past 1 inside its range: the transform
    // rides the overshoot, Opacity must see a clamped value. settle()
    // asserts no exception on every frame.
    await settle(tester);
    expect(find.text('springy-block'), findsOneWidget);
    flight!.close();
    await settle(tester);
  });
}
