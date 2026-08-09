import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/tour/lessons/chips_example.dart';
import 'package:morph_example/tour/lessons/comet_example.dart';
import 'package:morph_example/tour/lessons/goo_dock_example.dart';
import 'package:morph_example/tour/lessons/menu_lesson.dart';
import 'package:morph_example/tour/lessons/player_example.dart';
import 'package:morph_example/tour/lessons/route_example.dart';

Widget host(Widget child) {
  return MaterialApp(
    theme: ThemeData(brightness: .dark),
    builder: (BuildContext context, Widget? c) => MorphScope(child: c!),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('player example: the cover flies into the full player', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const PlayerExample(motion: .normal)));
    await tester.tap(find.text('Night Drive'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      find.byKey(const ValueKey<String>('morph-shared-fly-gallery-cover')),
      findsOneWidget,
    );
    for (int i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(find.text('Neon Waves - Midnight City'), findsOneWidget);
  });

  testWidgets('menu: tugged skin pills survive a drag and still morph', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const MenuLesson(motion: .normal)));
    // Tug Options toward Share: the piece rect moves, the skin
    // re-traces (necking exercised), no asserts may fire.
    final Offset start = tester.getCenter(find.text('Options'));
    final TestGesture gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 0));
    // The offset chases the finger on a follow spring - give it a few
    // frames to arrive before measuring.
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      (tester.getCenter(find.text('Options')) - start).distance,
      greaterThan(5),
    );
    await gesture.up();
    for (int i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(
      (tester.getCenter(find.text('Options')) - start).distance,
      lessThan(1),
    );
    // The pill still morphs into its menu from the piece.
    await tester.tap(find.text('Share'));
    await tester.pump();
    for (int i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(find.text('Copy link'), findsOneWidget);
  });

  testWidgets('goo dock: tapping a tab springs the blob, retarget mid-flight', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const GooDockExample(motion: .normal)));

    await tester.tap(find.byIcon(Icons.favorite_rounded));
    await tester.pump(const Duration(milliseconds: 80));
    // Retarget mid-flight: the interruption contract must hold.
    await tester.tap(find.byIcon(Icons.search_rounded));
    for (int i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
  });

  testWidgets('chips: add and remove mid-motion stays continuous', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const ChipsExample(motion: .normal)));

    await tester.tap(find.text('Add chip'));
    await tester.pump(const Duration(milliseconds: 60));
    // Remove a chip while the newcomer is still flying in.
    await tester.tap(find.text('Lo-fi'));
    for (int i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(find.text('Lo-fi'), findsNothing);
    expect(find.text('Vapor'), findsOneWidget);
  });

  testWidgets('player: dragging the open sheet down dismisses it', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const PlayerExample(motion: .normal)));
    await tester.tap(find.text('Night Drive'));
    for (int i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(find.text('Neon Waves - Midnight City'), findsOneWidget);

    // Fling the sheet body downward: the flight's drag mechanics must
    // close it.
    await tester.fling(
      find.text('Neon Waves - Midnight City'),
      const Offset(0, 260),
      2400,
    );
    for (int i = 0; i < 600; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(find.text('Neon Waves - Midnight City'), findsNothing);
  });

  testWidgets('comet: pointer drags retarget the chain without exceptions', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const CometExample()));
    await tester.pump();
    final TestGesture gesture = await tester.startGesture(
      const Offset(400, 300),
    );
    for (int i = 0; i < 30; i++) {
      await gesture.moveBy(const Offset(9, 5));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    await gesture.up();
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('route: typed text survives the handover and the pop', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const RouteExample(motion: .normal)));

    await tester.tap(find.text('Open a note - as a real route'));
    for (int i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    // Settled: the note is a real page - type into it.
    await tester.enterText(find.byType(TextField), 'still here');
    await tester.pump();

    // Stack a plain dialog on top and dismiss it: the note must stay.
    await tester.tap(find.text('Stack a dialog'));
    await tester.pumpAndSettle();
    expect(find.text('A plain dialog'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('still here'), findsOneWidget);

    // Pop: the text rides the close flight home in the shuttle.
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('still here'), findsOneWidget);
    for (int i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(find.text('still here'), findsNothing);
    expect(find.text('Open a note - as a real route'), findsOneWidget);
  });
}
