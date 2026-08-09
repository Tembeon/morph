import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

/// The tag's own visibility gate: the outermost Opacity under the tag.
double tagOpacity(WidgetTester tester) {
  final Opacity gate = tester.widget(
    find
        .descendant(of: find.byType(MorphTag), matching: find.byType(Opacity))
        .first,
  );
  return gate.opacity;
}

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 600; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}

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
                        const Text('dialog-content'),
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

void main() {
  testWidgets('beginScrub on a closing flight interrupts it, not destroys', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    await tester.pumpWidget(_Host(onFlight: (MorphFlight f) => flight = f));
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await settle(tester);

    flight!.close();
    await tester.pump(const Duration(milliseconds: 60));
    expect(flight!.isFinished, isFalse);

    flight!.controller.beginScrub();
    await tester.pump();
    expect(
      flight!.isFinished,
      isFalse,
      reason: 'a scrub parks the ticker; that is an interruption, not an end',
    );
    expect(find.text('dialog-content'), findsOneWidget);

    flight!.controller.updateScrub(0.5);
    await tester.pump();
    flight!.close();
    await settle(tester);
    expect(flight!.isFinished, isTrue);
    expect(tagOpacity(tester), 1);
    expect(find.text('dialog-content'), findsNothing);
  });

  testWidgets('abort mid-flight returns the source widget', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    await tester.pumpWidget(_Host(onFlight: (MorphFlight f) => flight = f));
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(tagOpacity(tester), 0);

    flight!.abort();
    await tester.pump();
    expect(flight!.isFinished, isTrue);
    expect(find.text('dialog-content'), findsNothing);
    expect(
      tagOpacity(tester),
      1,
      reason: 'a teardown that skips the latch must un-hide the tag itself',
    );
    await settle(tester);
  });

  testWidgets('closing after the host route was replaced does not crash', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
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
    await settle(tester);

    unawaited(
      nav.currentState!.pushReplacement(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              const Scaffold(body: Text('page-2')),
        ),
      ),
    );
    await settle(tester);

    flight!.close();
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(flight!.isFinished, isTrue);
  });

  testWidgets('a close -> open interruption restores the pop entry', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    await tester.pumpWidget(_Host(onFlight: (MorphFlight f) => flight = f));
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await settle(tester);

    flight!.close();
    await tester.pump(const Duration(milliseconds: 40));
    flight!.open();
    await settle(tester);
    expect(find.text('dialog-content'), findsOneWidget);

    // The system pop must close the TOPMOST surface - the reopened
    // flight - not fall through to the page.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(flight!.isFinished, isTrue);
    expect(find.text('dialog-content'), findsNothing);
    expect(find.text('open-me'), findsOneWidget);
  });

  testWidgets('a re-keyed tag carries its live flight to the new id', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    MorphScopeState? scope;
    Object tagId = 'a';
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              rebuild = setState;
              scope = MorphScope.of(context);
              return MorphTag(
                id: tagId,
                child: Builder(
                  builder: (BuildContext context) => ElevatedButton(
                    onPressed: () => flight = showMorphDialog(
                      context,
                      from: tagId,
                      builder: (BuildContext context, MorphFlight f) =>
                          const Text('dialog-content'),
                    ),
                    child: const Text('open-me'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    rebuild(() => tagId = 'b');
    await tester.pump();
    expect(scope!.flightOf('a'), isNull);
    expect(scope!.flightOf('b'), same(flight));

    final MorphFlight first = flight!;
    first.close();
    await settle(tester);
    expect(first.isFinished, isTrue);
    expect(scope!.flightOf('b'), isNull);

    // The tag under its new id launches a fresh flight.
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.text('dialog-content'), findsOneWidget);
    expect(scope!.flightOf('b'), isNot(same(first)));
    expect(scope!.flightOf('b'), same(flight));
    await settle(tester);
  });

  testWidgets('the drag API is inert on a finished flight', (
    WidgetTester tester,
  ) async {
    MorphFlight? flight;
    await tester.pumpWidget(_Host(onFlight: (MorphFlight f) => flight = f));
    await tester.tap(find.text('open-me'));
    await tester.pump();
    await settle(tester);
    flight!.close();
    await settle(tester);
    expect(flight!.isFinished, isTrue);

    flight!.beginDrag();
    flight!.dragBy(const Offset(5, 5));
    flight!.endDrag(const Offset(100, 0));
    expect(tester.takeException(), isNull);
    expect(flight!.dragOffset, Offset.zero);
  });
}
