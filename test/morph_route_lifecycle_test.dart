import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

void main() {
  for (final bool settled in <bool>[false, true]) {
    for (final String removal in <String>[
      'removeRoute',
      'pushReplacement',
      'pushAndRemoveUntil',
    ]) {
      testWidgets(
        '$removal retires a ${settled ? 'settled' : 'launching'} flight',
        (WidgetTester tester) async {
          late BuildContext sourceContext;
          await tester.pumpWidget(
            MaterialApp(
              builder: (BuildContext context, Widget? child) =>
                  MorphScope(child: child!),
              home: Scaffold(
                body: MorphTag(
                  id: 'source',
                  replica: const Text('replica'),
                  child: Builder(
                    builder: (BuildContext context) {
                      sourceContext = context;
                      return const Text('source');
                    },
                  ),
                ),
              ),
            ),
          );
          final NavigatorState navigator = Navigator.of(sourceContext);
          final MorphScopeState scope = MorphScope.of(sourceContext);
          final MorphPageRoute<void> route = MorphPageRoute<void>(
            from: 'source',
            target: MorphTargetSpec.dialog(),
            builder: (BuildContext context, MorphFlight flight) =>
                const Text('content'),
          );
          unawaited(navigator.push(route));
          await tester.pump();
          if (settled) {
            await tester.pumpAndSettle();
          }
          final MorphFlight flight = route.flight!;
          expect(flight.routeOwnsContent.value, settled);
          final MaterialPageRoute<void> replacement = MaterialPageRoute<void>(
            builder: (BuildContext context) =>
                const Scaffold(body: Text('replacement')),
          );
          switch (removal) {
            case 'removeRoute':
              navigator.removeRoute(route);
            case 'pushReplacement':
              unawaited(navigator.pushReplacement(replacement));
            case 'pushAndRemoveUntil':
              unawaited(
                navigator.pushAndRemoveUntil(
                  replacement,
                  (Route<Object?> route) => route.isFirst,
                ),
              );
          }
          await tester.pumpAndSettle();
          expect(flight.isFinished, isTrue);
          expect(scope.flightOf('source'), isNull);
          expect(flight.routeOwnsContent.value, isFalse);
          expect(await flight.closed, isNull);
          expect(tester.takeException(), isNull);
          if (removal != 'removeRoute') {
            navigator.pop();
            await tester.pumpAndSettle();
          }
          expect(
            tester
                .widget<Opacity>(
                  find.descendant(
                    of: find.byType(MorphTag),
                    matching: find.byType(Opacity),
                  ),
                )
                .opacity,
            1,
          );
          expect(find.text('content'), findsNothing);
        },
      );
    }
  }

  testWidgets('removing a route after its source unmounts aborts the flight', (
    WidgetTester tester,
  ) async {
    late BuildContext sourceContext;
    late StateSetter rebuild;
    bool source = true;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              rebuild = setState;
              return source
                  ? MorphTag(
                      id: 'source',
                      replica: const Text('replica'),
                      child: Builder(
                        builder: (BuildContext context) {
                          sourceContext = context;
                          return const Text('source');
                        },
                      ),
                    )
                  : const SizedBox();
            },
          ),
        ),
      ),
    );
    final NavigatorState navigator = Navigator.of(sourceContext);
    final MorphPageRoute<void> route = MorphPageRoute<void>(
      from: 'source',
      target: MorphTargetSpec.dialog(),
      builder: (BuildContext context, MorphFlight flight) =>
          const Text('content'),
    );
    unawaited(navigator.push(route));
    await tester.pumpAndSettle();
    final MorphFlight flight = route.flight!;
    final List<MorphFlightEvent> events = <MorphFlightEvent>[];
    final StreamSubscription<MorphFlightEvent> subscription = flight.events
        .listen(events.add);
    rebuild(() => source = false);
    await tester.pump();
    expect(flight.tag.mounted, isFalse);
    navigator.removeRoute(route);
    await tester.pumpAndSettle();
    expect(flight.isFinished, isTrue);
    expect(events, contains(MorphFlightEvent.aborted));
    expect(await flight.closed, isNull);
    expect(tester.takeException(), isNull);
    addTearDown(subscription.cancel);
  });

  for (final bool abort in <bool>[false, true]) {
    testWidgets(
      '${abort ? 'abort' : 'scrim-tail close'} before handoff retires the route',
      (WidgetTester tester) async {
        late BuildContext sourceContext;
        await tester.pumpWidget(
          MaterialApp(
            builder: (BuildContext context, Widget? child) =>
                MorphScope(child: child!),
            home: Scaffold(
              body: MorphTag(
                id: 'source',
                replica: const Text('replica'),
                child: Builder(
                  builder: (BuildContext context) {
                    sourceContext = context;
                    return const Text('source');
                  },
                ),
              ),
            ),
          ),
        );
        final NavigatorState navigator = Navigator.of(sourceContext);
        final MorphPageRoute<void> route = MorphPageRoute<void>(
          from: 'source',
          scrimMotion: const MorphScrimMotion(
            motion: MorphMotion.glacial,
            closeDelay: Duration(milliseconds: 100),
          ),
          target: MorphTargetSpec.dialog(),
          builder: (BuildContext context, MorphFlight flight) =>
              const Text('content'),
        );
        unawaited(navigator.push(route));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final MorphFlight flight = route.flight!;
        expect(flight.routeOwnsContent.value, isFalse);
        expect(flight.scrimValue, greaterThan(0));
        if (abort) {
          flight.abort();
        } else {
          flight.close();
        }
        await tester.pumpAndSettle();
        expect(flight.isFinished, isTrue);
        expect(route.isActive, isFalse);
        expect(navigator.canPop(), isFalse);
        expect(find.text('content'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
