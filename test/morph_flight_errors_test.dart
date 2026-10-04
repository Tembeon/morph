import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

void main() {
  testWidgets('route mode rejects a live overlay without mutating it', (
    WidgetTester tester,
  ) async {
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
    final MorphFlight overlay = showMorphDialog(
      sourceContext,
      builder: (BuildContext context, MorphFlight flight) =>
          const Text('overlay'),
    );
    await tester.pump();
    expect(
      () => MorphFlight.launch(
        sourceContext,
        from: 'source',
        routeMode: true,
        target: MorphTargetSpec.dialog(),
        builder: (BuildContext context, MorphFlight flight) =>
            const Text('route'),
      ),
      throwsA(
        isA<FlutterError>().having(
          (FlutterError error) => error.toString(),
          'message',
          contains('Close the overlay first'),
        ),
      ),
    );
    final ModalRoute<Object?> page = ModalRoute.of(sourceContext)!;
    expect(
      () => showMorphRoute<void>(
        sourceContext,
        builder: (BuildContext context, MorphFlight flight) =>
            const Text('route'),
      ),
      throwsA(isA<FlutterError>()),
    );
    expect(page.isCurrent, isTrue);
    expect(overlay.routeContentKey, isNull);
    expect(overlay.isOpenOrOpening, isTrue);
    overlay.close();
    await tester.pumpAndSettle();
  });

  for (final bool settled in <bool>[false, true]) {
    testWidgets(
      'removing the ${settled ? 'settled' : 'unmounted shuttle'} overlay aborts and reveals its source',
      (WidgetTester tester) async {
        late StateSetter rebuild;
        late BuildContext sourceContext;
        bool nested = true;
        final GlobalKey tagKey = GlobalKey();
        final Widget source = MorphTag(
          key: tagKey,
          id: 'source',
          replica: const Text('replica'),
          child: Builder(
            builder: (BuildContext context) {
              sourceContext = context;
              return const Text('source');
            },
          ),
        );
        final OverlayEntry entry = OverlayEntry(
          builder: (BuildContext context) => Center(child: source),
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (BuildContext context, Widget? child) =>
                MorphScope(child: child!),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) {
                  rebuild = setState;
                  return nested
                      ? Overlay(initialEntries: <OverlayEntry>[entry])
                      : Center(child: source);
                },
              ),
            ),
          ),
        );
        final MorphFlight flight = showMorphDialog(
          sourceContext,
          builder: (BuildContext context, MorphFlight flight) =>
              const Text('overlay'),
        );
        if (settled) {
          await tester.pumpAndSettle();
        }
        rebuild(() => nested = false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester.takeException(),
          isA<FlutterError>().having(
            (FlutterError error) => error.toString(),
            'message',
            contains('its Overlay has been unmounted'),
          ),
        );
        await tester.pump();
        expect(flight.isFinished, isTrue);
        expect(await flight.closed, isNull);
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
        expect(tester.takeException(), isNull);
        entry.remove();
        entry.dispose();
      },
    );
  }

  testWidgets('flight scope misuse throws a descriptive FlutterError', (
    WidgetTester tester,
  ) async {
    late BuildContext outside;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (BuildContext context) {
            outside = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      () => MorphFlightScope.of(outside),
      throwsA(
        isA<FlutterError>().having(
          (FlutterError error) => error.toString(),
          'message',
          contains('only work inside the content of a morph overlay'),
        ),
      ),
    );
  });
}
