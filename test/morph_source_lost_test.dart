import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

/// A page whose source tag can be removed while its flight is up - a
/// row archived from its own menu.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool sourceMounted = true;
  MorphFlight? flight;

  void removeSource() => setState(() => sourceMounted = false);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (BuildContext context, Widget? child) =>
          MorphScope(child: child!),
      home: Scaffold(
        body: Center(
          child: sourceMounted
              ? MorphTag(
                  id: 'row',
                  child: Builder(
                    builder: (BuildContext context) => ElevatedButton(
                      onPressed: () {
                        flight = showMorphDialog(
                          context,
                          from: 'row',
                          builder: (BuildContext context, MorphFlight flight) =>
                              TextButton(
                                onPressed: () => flight.close(),
                                child: const Text('content'),
                              ),
                        );
                      },
                      child: const Text('open'),
                    ),
                  ),
                )
              : const Text('gone'),
        ),
      ),
    );
  }
}

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 600; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    expect(tester.takeException(), isNull);
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}

_HostState _host(WidgetTester tester) =>
    tester.state<_HostState>(find.byType(_Host));

void main() {
  testWidgets('a source lost mid-open: the flight keeps flying and the open '
      'content stays usable', (WidgetTester tester) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 50));
    _host(tester).removeSource();
    await settle(tester);
    final MorphFlight flight = _host(tester).flight!;
    expect(flight.isSourceLost, isTrue);
    expect(flight.dissolveOpacity, 1);
    expect(find.text('content'), findsOneWidget);
    // The content is live: its own button closes the flight.
    await tester.tap(find.text('content'));
    await settle(tester);
    expect(find.text('content'), findsNothing);
    expect(flight.isFinished, isTrue);
  });

  testWidgets('a source lost mid-close dissolves before the latch, without '
      'an assert', (WidgetTester tester) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('open'));
    await settle(tester);
    final MorphFlight flight = _host(tester).flight!;
    final Rect home = flight.sourceRect;
    flight.close();
    await tester.pump(const Duration(milliseconds: 40));
    _host(tester).removeSource();
    // The frame that drops the tag only DEACTIVATES it during build
    // (the unmount comes at the end of that frame): the loss is seen
    // on the next frame's refresh.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(flight.isSourceLost, isTrue);
    // The rect froze where the tag last stood.
    expect(flight.sourceRect, home);
    // The container fades on its way home: opacity is a pure function
    // of the spring value from the moment of the loss, continuous at 1
    // and gone well before the latch.
    double lowest = 1;
    for (int i = 0; i < 40 && !flight.controller.hasHandedOff; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      final double opacity = flight.dissolveOpacity;
      expect(opacity, lessThanOrEqualTo(lowest + 1e-9));
      lowest = opacity;
    }
    expect(lowest, 0);
    await settle(tester);
    expect(flight.isFinished, isTrue);
    expect(find.text('content'), findsNothing);
  });

  testWidgets('a source lost during the landing bounce: no assert', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('open'));
    await settle(tester);
    final MorphFlight flight = _host(tester).flight!;
    flight.close();
    for (int i = 0; i < 200 && !flight.isLanding; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(flight.isLanding, isTrue);
    _host(tester).removeSource();
    await settle(tester);
    expect(flight.isFinished, isTrue);
    expect(find.text('gone'), findsOneWidget);
  });

  testWidgets('the loss is sticky, and a re-open after it lifts the '
      'dissolve', (WidgetTester tester) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('open'));
    await settle(tester);
    final MorphFlight flight = _host(tester).flight!;
    _host(tester).removeSource();
    await tester.pump();
    flight.close();
    // Two frames: the first tick after a (re)start evaluates the
    // simulation at t = 0.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 80));
    expect(flight.isSourceLost, isTrue);
    expect(flight.dissolveOpacity, lessThan(1));
    flight.open();
    await tester.pump();
    expect(flight.dissolveOpacity, 1);
    await settle(tester);
    expect(find.text('content'), findsOneWidget);
    flight.close();
    await settle(tester);
    expect(flight.isFinished, isTrue);
  });
}
