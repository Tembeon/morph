import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

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

  group('drag composition functions', () {
    test('rest passes through untouched', () {
      expect(morphDragScrimFactor(0, 0), 1);
      expect(morphDragScale(0, 0), 1);
    });

    test('recede and arm each deepen the thinning and the recede', () {
      expect(
        morphDragScrimFactor(0.5, 0),
        lessThan(morphDragScrimFactor(0.2, 0)),
      );
      expect(
        morphDragScrimFactor(0.5, 1),
        lessThan(morphDragScrimFactor(0.5, 0)),
      );
      expect(morphDragScale(0.5, 0), lessThan(morphDragScale(0.2, 0)));
      expect(morphDragScale(0.5, 1), lessThan(morphDragScale(0.5, 0)));
    });

    test('full recede and arm stay subtle, never degenerate', () {
      expect(morphDragScrimFactor(1, 1), greaterThan(0));
      expect(morphDragScale(1, 1), greaterThan(0.8));
    });
  });

  testWidgets('appliedDragOffset fades with progress toward the latch', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.tap(find.text('go'));
    await tester.pump();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('sheet')!;
    // A few frames in: airborne, progress strictly inside (0, 1).
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    final double progress = flight.controller.progress;
    expect(progress, inExclusiveRange(0, 1));
    flight
      ..beginDrag()
      ..dragBy(const Offset(30, 80));
    // Below the commit distance no lean applies: the applied offset is
    // exactly the raw offset scaled by progress, so it vanishes at the
    // handoff latch and the swap back home happens at zero offset.
    expect(
      flight.appliedDragOffset,
      offsetMoreOrLessEquals(const Offset(30, 80) * progress),
    );
    flight.abort();
  });

  testWidgets('past the commit distance the card leans toward home', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final MorphFlight flight = await openFlight(tester);
    flight
      ..beginDrag()
      ..dragBy(const Offset(0, 250));
    final Offset raw = flight.dragOffset;
    expect(morphDragArm(raw.distance), 1);
    // Fully armed and settled (progress 1): the applied offset carries
    // exactly the 12 px drift on top of the raw offset.
    final Offset lean = flight.appliedDragOffset - raw;
    expect(lean.distance, moreOrLessEquals(12, epsilon: 0.001));
    // Pointed at the source: the destination of a release is legible
    // before the release.
    final Offset toHome =
        flight.sourceRect.center - (flight.lastTargetRect.center + raw);
    expect(
      lean,
      offsetMoreOrLessEquals(toHome / toHome.distance * 12, epsilon: 0.01),
    );
    flight.abort();
  });

  testWidgets(
    'the shuttle draws the drag: rigid shift, recede scale, thinner scrim',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final MorphFlight flight = await openFlight(tester);
      final Finder shuttle = find.byWidgetPredicate(
        (Widget w) => w is Material && w.animationDuration == .zero,
      );
      final Finder scrim = find.descendant(
        of: find.byType(BlockSemantics),
        matching: find.byType(ColoredBox),
      );
      final Rect rest = tester.getRect(shuttle);
      final double restAlpha = tester.widget<ColoredBox>(scrim).color.a;

      // Below the commit distance only the recede plays.
      flight
        ..beginDrag()
        ..dragBy(const Offset(0, 100));
      await tester.pump();
      double recede = morphDragRecede(flight.appliedDragOffset.distance);
      double arm = morphDragArm(flight.dragOffset.distance);
      expect(arm, 0);
      Rect dragged = tester.getRect(shuttle);
      expect(
        dragged.center,
        offsetMoreOrLessEquals(rest.center + flight.appliedDragOffset),
      );
      expect(
        dragged.width,
        moreOrLessEquals(
          rest.width * morphDragScale(recede, arm),
          epsilon: 0.1,
        ),
      );
      final double alphaFree = tester.widget<ColoredBox>(scrim).color.a;
      expect(
        alphaFree,
        moreOrLessEquals(
          restAlpha * morphDragScrimFactor(recede, arm),
          epsilon: 1e-5,
        ),
      );

      // Past the threshold the arm cue deepens both.
      flight.dragBy(const Offset(0, 120));
      await tester.pump();
      recede = morphDragRecede(flight.appliedDragOffset.distance);
      arm = morphDragArm(flight.dragOffset.distance);
      expect(arm, 1);
      dragged = tester.getRect(shuttle);
      expect(
        dragged.center,
        offsetMoreOrLessEquals(rest.center + flight.appliedDragOffset),
      );
      expect(
        dragged.width,
        moreOrLessEquals(
          rest.width * morphDragScale(recede, arm),
          epsilon: 0.1,
        ),
      );
      final double alphaArmed = tester.widget<ColoredBox>(scrim).color.a;
      expect(
        alphaArmed,
        moreOrLessEquals(
          restAlpha * morphDragScrimFactor(recede, arm),
          epsilon: 1e-5,
        ),
      );
      expect(alphaArmed, lessThan(alphaFree));
      flight.abort();
    },
  );

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
