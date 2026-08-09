import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/tour/lessons/chips_example.dart';
import 'package:morph_example/tour/lessons/goo_dock_example.dart';
import 'package:morph_example/tour/lessons/menu_lesson.dart';
import 'package:morph_example/tour/lessons/morph_scene.dart';
import 'package:morph_example/tour/lessons/page_scene.dart';

Widget host(Widget child) {
  return MaterialApp(
    theme: ThemeData(brightness: .dark),
    builder: (BuildContext context, Widget? c) => MorphScope(child: c!),
    home: Scaffold(body: child),
  );
}

Future<void> settle(WidgetTester tester, {int limit = 300}) async {
  for (int i = 0; i < limit; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    expect(tester.takeException(), isNull);
    if (!tester.binding.hasScheduledFrame) {
      break;
    }
  }
}

void main() {
  testWidgets('morph scene: compose opens and the torture storm survives', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const MorphScene(motion: .normal)));
    await tester.tap(find.text('New message'));
    await settle(tester);
    expect(find.text('New playlist'), findsOneWidget);

    // Dismiss through the scrim inside the phone, near the frame edge.
    await tester.tapAt(
      tester.getTopLeft(find.text('Inbox')) + const Offset(2, 40),
    );
    await settle(tester);
    expect(find.text('New playlist'), findsNothing);

    // The interruption storm: three flights closed mid-air.
    await tester.tap(find.text('Interrupt'));
    await settle(tester);
    await tester.tap(find.text('Interruption torture'));
    for (int i = 0; i < 500; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Interruption torture'), findsOneWidget);
  });

  testWidgets('menu: tugged skin pills survive a drag and still morph', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
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
    await settle(tester);
    expect(
      (tester.getCenter(find.text('Options')) - start).distance,
      lessThan(1),
    );
    // The pill still morphs into its menu from the piece.
    await tester.tap(find.text('Share'));
    await tester.pump();
    await settle(tester);
    expect(find.text('Copy link'), findsOneWidget);
  });

  testWidgets('goo dock: tapping a tab springs the blob, retarget mid-flight', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const GooDockExample(motion: .normal)));

    await tester.tap(find.byIcon(Icons.favorite_rounded));
    await tester.pump(const Duration(milliseconds: 80));
    // Retarget mid-flight: the interruption contract must hold.
    await tester.tap(find.byIcon(Icons.search_rounded));
    await settle(tester);
    expect(find.text('Search'), findsOneWidget);
  });

  testWidgets('chips: add and remove mid-motion stays continuous', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const ChipsExample(motion: .normal)));

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump(const Duration(milliseconds: 60));
    // Remove a chip while the newcomer is still flying in.
    await tester.tap(find.text('Lo-fi'));
    await settle(tester);
    expect(find.text('Lo-fi'), findsNothing);
    expect(find.text('Vapor'), findsOneWidget);
  });

  testWidgets('pages: the cover flies into the player; overlay locks Lyrics', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const PageScene(motion: .normal)));
    await tester.tap(find.text('Night Drive').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      find.byKey(const ValueKey<String>('morph-shared-fly-cover-0')),
      findsOneWidget,
    );
    await settle(tester);
    expect(find.text('Neon Waves - Midnight City'), findsOneWidget);
    // An overlay is not a page: nothing can stack on it.
    expect(find.text('Lyrics - needs a real route'), findsOneWidget);
  });

  testWidgets('pages: dragging the open player down dismisses it', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const PageScene(motion: .normal)));
    await tester.tap(find.text('Night Drive').first);
    await settle(tester);
    expect(find.text('Neon Waves - Midnight City'), findsOneWidget);

    // Fling the player body downward: the flight's drag mechanics must
    // close it.
    await tester.fling(
      find.text('Neon Waves - Midnight City'),
      const Offset(0, 220),
      2400,
    );
    await settle(tester, limit: 600);
    expect(find.text('Neon Waves - Midnight City'), findsNothing);
  });

  testWidgets('pages: route mode stacks Lyrics on top and pops back', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const PageScene(motion: .normal)));
    await tester.tap(find.text('Real route'));
    await settle(tester);

    await tester.tap(find.text('Night Drive').first);
    await settle(tester);
    await tester.tap(find.text('Lyrics'));
    await settle(tester);
    expect(find.text('Night Drive - lyrics'), findsOneWidget);

    // Pop the stacked page: the player is still there underneath -
    // it is real history, not an overlay.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await settle(tester);
    expect(find.text('Neon Waves - Midnight City'), findsOneWidget);

    // The displacement channel works on the settled PAGE too: the
    // card visibly follows the finger after the second latch, and a
    // sub-threshold release springs it home.
    final Offset grab = tester.getCenter(
      find.text('Neon Waves - Midnight City'),
    );
    final TestGesture drag = await tester.startGesture(grab);
    await drag.moveBy(const Offset(0, 90));
    await tester.pump();
    expect(
      tester.getCenter(find.text('Neon Waves - Midnight City')).dy - grab.dy,
      greaterThan(50),
    );
    await drag.up();
    await settle(tester);
    expect(find.text('Neon Waves - Midnight City'), findsOneWidget);

    await tester.fling(
      find.text('Neon Waves - Midnight City'),
      const Offset(0, 220),
      2400,
    );
    await settle(tester, limit: 600);
    expect(find.text('Neon Waves - Midnight City'), findsNothing);
  });
}
