import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';

/// Coverage for three core paths that had none: the snapshot ghost, the
/// entry-removal timing at the handoff latch, and two concurrent
/// flights of different tags.

final Finder shuttleFinder = find.byWidgetPredicate(
  (Widget w) => w is Material && w.animationDuration == .zero,
);

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
  testWidgets('snapshot ghost: captured async, rendered, disposed', (
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
              id: 'ghost',
              snapshotGhost: true,
              child: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => showMorphDialog(
                    context,
                    from: 'ghost',
                    builder: (BuildContext context, MorphFlight flight) =>
                        const Text('content'),
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
    await tester.pump();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('ghost')!;

    // toImage completes on the real event loop, not inside FakeAsync:
    // give it real time in slices, flushing the fake zone in between.
    for (int i = 0; i < 100 && flight.sourceSnapshot == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(flight.sourceSnapshot, isNotNull);
    // The markNeedsBuild from the capture lands after the same pump's
    // build phase: one more frame mounts the ghost.
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
    // The ghost flow hides the tag only after the shot (a hidden
    // subtree never repaints, so hiding first would starve toImage).
    final Opacity tagOpacity = tester.widget<Opacity>(
      find
          .descendant(of: find.byType(MorphTag), matching: find.byType(Opacity))
          .first,
    );
    expect(tagOpacity.opacity, 0);

    await settle(tester);
    flight.close();
    await settle(tester);
    expect(flight.isFinished, isTrue);
    // Finalization must release the image.
    expect(flight.sourceSnapshot, isNull);
  });

  testWidgets('the overlay entry is removed exactly at the handoff latch', (
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
              id: 'latch',
              child: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => showMorphDialog(
                    context,
                    from: 'latch',
                    builder: (BuildContext context, MorphFlight flight) =>
                        const Text('content'),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Opacity tagOpacity() => tester.widget<Opacity>(
      find
          .descendant(of: find.byType(MorphTag), matching: find.byType(Opacity))
          .first,
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('latch')!;
    await settle(tester);

    // Open and settled: the shuttle is up, the home widget is hidden.
    expect(shuttleFinder, findsOneWidget);
    expect(tagOpacity().opacity, 0);

    flight.close();
    // Airborne all the way to the latch: the shuttle must stay mounted
    // and the home widget hidden on every frame.
    int guard = 0;
    while (!flight.controller.hasHandedOff) {
      expect(shuttleFinder, findsOneWidget);
      expect(tagOpacity().opacity, 0);
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      expect(++guard, lessThan(600));
    }
    // The latch fired inside the last pump: the entry is gone and the
    // home widget is back IN THE SAME FRAME - no gap, no double vision.
    expect(shuttleFinder, findsNothing);
    expect(tagOpacity().opacity, 1);
    // The residual bounce still plays on the live widget: removal
    // happened at the latch, not at finalization.
    expect(flight.isFinished, isFalse);
    expect(flight.isLanding, isTrue);

    await settle(tester);
    expect(flight.isFinished, isTrue);
    expect(scope.flightOf('latch'), isNull);
  });

  testWidgets('two tags fly concurrently and finalize independently', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget tagButton(String id, Alignment alignment) {
      return Align(
        alignment: alignment,
        child: MorphTag(
          id: id,
          child: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showMorphDialog(
                context,
                from: id,
                width: 300,
                height: 200,
                builder: (BuildContext context, MorphFlight flight) =>
                    Text('content-$id'),
              ),
              child: Text('go-$id'),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              tagButton('a', .bottomLeft),
              tagButton('b', .topRight),
            ],
          ),
        ),
      ),
    );

    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );

    await tester.tap(find.text('go-a'));
    await tester.pump();
    // The barrier of flight A covers the screen: tap B through the
    // scope API instead of the pointer.
    final MorphFlight flightA = scope.flightOf('a')!;
    await settle(tester);
    showMorphDialog(
      tester.element(find.text('go-b')),
      from: 'b',
      width: 300,
      height: 200,
      builder: (BuildContext context, MorphFlight flight) =>
          const Text('content-b'),
    );
    await tester.pump();
    final MorphFlight flightB = scope.flightOf('b')!;
    await settle(tester);

    expect(flightA, isNot(same(flightB)));
    expect(shuttleFinder, findsNWidgets(2));
    expect(find.text('content-a'), findsOneWidget);
    expect(find.text('content-b'), findsOneWidget);

    // Closing A must not disturb B.
    flightA.close();
    await settle(tester);
    expect(flightA.isFinished, isTrue);
    expect(scope.flightOf('a'), isNull);
    expect(flightB.isFinished, isFalse);
    expect(flightB.isOpenOrOpening, isTrue);
    expect(scope.flightOf('b'), same(flightB));
    expect(shuttleFinder, findsOneWidget);
    expect(find.text('content-b'), findsOneWidget);

    flightB.close();
    await settle(tester);
    expect(flightB.isFinished, isTrue);
    expect(scope.flightOf('b'), isNull);
    expect(shuttleFinder, findsNothing);
  });

  testWidgets('from: is inferred from the enclosing MorphTag', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late BuildContext outsideContext;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) {
              outsideContext = context;
              return Align(
                alignment: Alignment.bottomCenter,
                child: MorphTag(
                  id: 'inferred',
                  child: Builder(
                    builder: (BuildContext context) => TextButton(
                      // No from: - the enclosing tag IS the source.
                      onPressed: () => showMorphDialog(
                        context,
                        builder: (BuildContext context, MorphFlight flight) =>
                            const Text('content'),
                      ),
                      child: const Text('go'),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    expect(scope.flightOf('inferred'), isNotNull);
    await settle(tester);
    scope.flightOf('inferred')!.abort();
    await tester.pump();

    // Outside any tag the omission is a programmer error.
    expect(
      () => showMorphDialog(
        outsideContext,
        builder: (BuildContext context, MorphFlight flight) =>
            const Text('content'),
      ),
      throwsAssertionError,
    );
  });
}
