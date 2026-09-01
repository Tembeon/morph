import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph_example/main.dart';

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
  testWidgets('a lesson card opens as a morph route and closes home', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MorphTourApp());
    await tester.pump();
    expect(find.text('The morph'), findsOneWidget);

    await tester.tap(find.text('The morph'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // The chapter title is a shared element: it must be FLYING between
    // the card and the page header mid-morph.
    expect(
      find.byKey(const ValueKey<String>('morph-shared-fly-lesson-morph-title')),
      findsOneWidget,
    );
    await settle(tester);
    // The chapter page is a real route with the scene inside.
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('New message'), findsOneWidget);

    // The demo inside the routed page still flies its own morphs -
    // inside the phone frame's own scope and overlay.
    await tester.tap(find.text('New message'));
    await settle(tester);
    expect(find.text('Save'), findsOneWidget);
    // Dismiss through the scrim inside the phone.
    await tester.tapAt(
      tester.getTopLeft(find.text('Inbox')) + const Offset(2, 40),
    );
    await settle(tester);
    expect(find.text('Save'), findsNothing);

    // Back plays the close flight into the card.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await settle(tester);
    expect(find.text('Inbox'), findsNothing);
    expect(find.text('Morph'), findsOneWidget);
    expect(find.text('The morph'), findsOneWidget);
  });

  testWidgets('the playground chapter opens with the sandbox inside', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MorphTourApp());
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Playground'), 200);
    await tester.tap(find.text('Playground'));
    await settle(tester);
    expect(find.text('MOTION'), findsOneWidget);
    expect(find.text('KEYFRAMES'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await settle(tester);
    expect(find.text('MOTION'), findsNothing);
  });

  testWidgets('toolbar merge: scroll drives the fusion with bounce', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MorphTourApp());
    await tester.pump();
    await tester.tap(find.text('Toolbar merge'));
    await settle(tester);
    expect(find.text('Item 1 - scroll me'), findsOneWidget);

    // Drag the list down and up: the merge spring retargets both ways
    // without exceptions (the raw overshooting value feeds geometry).
    await tester.drag(find.text('Item 1 - scroll me'), const Offset(0, -160));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.drag(find.text('Item 3 - scroll me'), const Offset(0, 120));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await settle(tester);
  });
}
