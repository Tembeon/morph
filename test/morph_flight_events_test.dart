import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

/// The launcher subscribes in the SAME synchronous run as showMorph -
/// the contract under which the launch itself is heard.
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
                  showMorphDialog(
                    context,
                    from: 'btn',
                    builder: (BuildContext context, MorphFlight flight) =>
                        const Text('content'),
                  ),
                ),
                child: const Text('open'),
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
    expect(tester.takeException(), isNull);
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}

/// A flight plus the log of what it announced.
class _Watched {
  MorphFlight? flight;
  final List<MorphFlightEvent> log = <MorphFlightEvent>[];
  bool done = false;

  void adopt(MorphFlight f) {
    flight = f;
    f.events.listen(log.add, onDone: () => done = true);
  }
}

void main() {
  testWidgets('the moments arrive in order, launch included, then the '
      'stream closes', (WidgetTester tester) async {
    final _Watched w = _Watched();
    await tester.pumpWidget(_Host(onFlight: w.adopt));
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(w.log, <MorphFlightEvent>[MorphFlightEvent.launched]);

    await settle(tester);
    expect(w.log, <MorphFlightEvent>[
      MorphFlightEvent.launched,
      MorphFlightEvent.settled,
    ]);

    w.flight!.close();
    await tester.pump();
    expect(w.log.last, MorphFlightEvent.closing);
    await settle(tester);
    expect(w.log, <MorphFlightEvent>[
      MorphFlightEvent.launched,
      MorphFlightEvent.settled,
      MorphFlightEvent.closing,
      MorphFlightEvent.latched,
      MorphFlightEvent.landed,
    ]);
    expect(w.done, isTrue);
    expect(w.flight!.isFinished, isTrue);
  });

  testWidgets('settled never precedes launched, even on an instant profile', (
    WidgetTester tester,
  ) async {
    final _Watched w = _Watched();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _Host(onFlight: w.adopt),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(w.flight!.controller.disableAnimations, isTrue);
    expect(w.log.first, MorphFlightEvent.launched);
    expect(w.log, contains(MorphFlightEvent.settled));
    expect(
      w.log.indexOf(MorphFlightEvent.settled),
      greaterThan(w.log.indexOf(MorphFlightEvent.launched)),
    );
  });

  testWidgets('a close interrupted by a re-open announces a second launch', (
    WidgetTester tester,
  ) async {
    final _Watched w = _Watched();
    await tester.pumpWidget(_Host(onFlight: w.adopt));
    await tester.tap(find.text('open'));
    await settle(tester);
    w.flight!.close();
    await tester.pump(const Duration(milliseconds: 60));
    w.flight!.open();
    await settle(tester);
    expect(w.log, <MorphFlightEvent>[
      MorphFlightEvent.launched,
      MorphFlightEvent.settled,
      MorphFlightEvent.closing,
      MorphFlightEvent.launched,
      MorphFlightEvent.settled,
    ]);
    // A re-open of an already open flight is not a launch.
    w.flight!.open();
    await settle(tester);
    expect(w.log.length, 5);
    w.flight!.abort();
    await tester.pump();
  });

  testWidgets('abort announces aborted and seals the stream', (
    WidgetTester tester,
  ) async {
    final _Watched w = _Watched();
    await tester.pumpWidget(_Host(onFlight: w.adopt));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 40));
    w.flight!.abort();
    await tester.pump();
    expect(w.log, <MorphFlightEvent>[
      MorphFlightEvent.launched,
      MorphFlightEvent.aborted,
    ]);
    expect(w.done, isTrue);
  });

  testWidgets('a listener may close the flight from inside its handler', (
    WidgetTester tester,
  ) async {
    final List<MorphFlightEvent> log = <MorphFlightEvent>[];
    await tester.pumpWidget(
      _Host(
        onFlight: (MorphFlight flight) {
          flight.events.listen((MorphFlightEvent event) {
            log.add(event);
            if (event == MorphFlightEvent.settled) {
              flight.close();
            }
          });
        },
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(log.last, MorphFlightEvent.landed);
    expect(find.text('content'), findsNothing);
  });

  testWidgets('a subscription made after an await misses the launch but '
      'hears the rest', (WidgetTester tester) async {
    MorphFlight? flight;
    await tester.pumpWidget(_Host(onFlight: (MorphFlight f) => flight = f));
    await tester.tap(find.text('open'));
    final List<MorphFlightEvent> log = <MorphFlightEvent>[];
    flight!.events.listen(log.add);
    await settle(tester);
    expect(log, <MorphFlightEvent>[MorphFlightEvent.settled]);
  });
}
