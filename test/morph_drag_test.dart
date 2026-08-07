import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';

Widget host() {
  return MaterialApp(
    builder: (BuildContext context, Widget? child) => MorphScope(child: child!),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: MorphTag(
          id: 'sheet',
          child: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showMorphDialog(
                context,
                from: 'sheet',
                semanticLabel: 'Player',
                builder: (BuildContext context, MorphFlight flight) =>
                    const Text('content'),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<MorphFlight> openFlight(WidgetTester tester) async {
  await tester.pumpWidget(host());
  await tester.tap(find.text('go'));
  for (int i = 0; i < 300; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    if (!tester.binding.hasScheduledFrame) {
      break;
    }
  }
  final MorphScopeState scope = tester.state<MorphScopeState>(
    find.byType(MorphScope),
  );
  return scope.flightOf('sheet')!;
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

void main() {
  test('the arm ramp is zero below the commit distance and tops at 1', () {
    expect(morphDragArm(0), 0);
    expect(morphDragArm(morphDragCommitDistance), 0);
    final double mid = morphDragArm(morphDragCommitDistance + 30);
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));
    expect(morphDragArm(morphDragCommitDistance + 60), 1);
    expect(morphDragArm(morphDragCommitDistance + 500), 1);
  });

  testWidgets('isDragArmed previews the distance-based commit', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final MorphFlight flight = await openFlight(tester);
    flight
      ..beginDrag()
      ..dragBy(const Offset(0, 100));
    expect(flight.isDragArmed, isFalse);
    flight.dragBy(const Offset(0, 100));
    expect(flight.isDragArmed, isTrue);
    // Backing off disarms: the cue is reversible.
    flight.dragBy(const Offset(0, -100));
    expect(flight.isDragArmed, isFalse);
    flight.endDrag(.zero, commit: false);
    await settle(tester);
    flight.abort();
  });

  testWidgets('dragBy moves the whole container 1:1, not the value', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final MorphFlight flight = await openFlight(tester);
    expect(flight.controller.value, 1);

    final Offset before = tester.getCenter(find.text('content'));
    flight.beginDrag();
    expect(flight.isDragging, isTrue);
    flight.dragBy(const Offset(30, 80));
    await tester.pump();
    // The value spring is untouched: no morph midstates can show.
    expect(flight.controller.value, 1);
    expect(flight.dragOffset, const Offset(30, 80));
    // Direct manipulation: the container (content included) moved by
    // exactly the finger delta.
    final Offset after = tester.getCenter(find.text('content'));
    expect(after - before, offsetMoreOrLessEquals(const Offset(30, 80)));
    flight.abort();
  });

  testWidgets('a short release springs the card home and stays open', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final MorphFlight flight = await openFlight(tester);
    flight
      ..beginDrag()
      ..dragBy(const Offset(0, 60))
      ..endDrag(.zero);
    expect(flight.isDragging, isFalse);
    expect(flight.isOpenOrOpening, isTrue);
    await settle(tester);
    expect(flight.dragOffset, Offset.zero);
    expect(flight.controller.value, closeTo(1, 0.01));
    flight.abort();
  });

  testWidgets('a release past the commit distance plays the close flight', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final MorphFlight flight = await openFlight(tester);
    flight
      ..beginDrag()
      ..dragBy(const Offset(0, 200))
      ..endDrag(.zero);
    expect(flight.controller.isClosing, isTrue);
    await settle(tester);
    expect(flight.isFinished, isTrue);
  });

  testWidgets('a hard fling commits regardless of distance', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final MorphFlight flight = await openFlight(tester);
    flight
      ..beginDrag()
      ..dragBy(const Offset(0, 10))
      ..endDrag(const Offset(0, 1600));
    expect(flight.controller.isClosing, isTrue);
    await settle(tester);
    expect(flight.isFinished, isTrue);
  });

  testWidgets('an explicit commit override wins over the heuristics', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final MorphFlight flight = await openFlight(tester);
    flight
      ..beginDrag()
      ..dragBy(const Offset(0, 300))
      ..endDrag(.zero, commit: false);
    expect(flight.isOpenOrOpening, isTrue);
    await settle(tester);
    expect(flight.dragOffset, Offset.zero);
    expect(flight.controller.value, closeTo(1, 0.01));
    flight.abort();
  });

  testWidgets('value scrubbing remains available on the controller', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final MorphFlight flight = await openFlight(tester);
    flight.controller.beginScrub();
    expect(flight.controller.isScrubbing, isTrue);
    flight.controller.updateScrub(0.4);
    await tester.pump();
    expect(flight.controller.value, closeTo(0.4, 0.001));
    flight.close();
    await settle(tester);
    expect(flight.isFinished, isTrue);
  });

  testWidgets('the open overlay exposes barrier and route semantics', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final SemanticsHandle semantics = tester.ensureSemantics();
    final MorphFlight flight = await openFlight(tester);
    expect(find.bySemanticsLabel('Dismiss'), findsOneWidget);
    expect(find.bySemanticsLabel('Player'), findsOneWidget);
    flight.abort();
    semantics.dispose();
  });
}
