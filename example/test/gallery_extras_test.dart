import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph_example/gallery/gallery.dart';

/// Every text on screen that fell through to the app's error text style.
List<String> _unstyledTexts(WidgetTester tester) => [
  for (final element in find.byType(RichText).evaluate())
    if ((element.widget as RichText).text.style?.decorationStyle ==
        TextDecorationStyle.double)
      (element.widget as RichText).text.toPlainText(),
];

Future<void> _open(WidgetTester tester, String title) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const GalleryApp());
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
  final entry = find.widgetWithText(MorphListRow, title);
  await tester.scrollUntilVisible(
    entry,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(entry);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
  await tester.tap(entry);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
  expect(
    find.descendant(
      of: find.byType(MorphNavigationBar),
      matching: find.text(title),
    ),
    findsWidgets,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    try {
      await MorphTheme.precacheGlass();
    } finally {
      FlutterError.onError = previous;
    }
    expect(MorphTheme.liquidGlassAvailable, isFalse);
    expect(reports.single.library, 'morph glass');
    expect(
      reports.single.exception.toString(),
      contains(MorphTheme.liquidGlassUnavailableReason!),
    );
  });

  testWidgets('alerts: an alert and an anchored action sheet', (tester) async {
    await _open(tester, 'Alerts');
    await tester.tap(find.text('Three buttons, destructive, cancel last'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Delete this photo?'), findsOneWidget);
    expect(_unstyledTexts(tester), isEmpty);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Delete chosen'), findsOneWidget);
    await tester.tap(find.text('Action sheet from this button'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Share photo'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(_unstyledTexts(tester), isEmpty);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Share photo'), findsNothing);
    expect(find.text('Cancel chosen'), findsOneWidget);
  });

  testWidgets('search: the toolbar filters, the tab bar morphs', (
    tester,
  ) async {
    await _open(tester, 'Search');
    expect(find.text('Banana'), findsOneWidget);
    await tester.tap(find.byType(MorphSearchField));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await tester.enterText(find.byType(EditableText), 'ber');
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Banana'), findsNothing);
    expect(find.text('Blueberry'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Banana'), findsOneWidget);
    await tester.tap(find.text('Tab bar'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.byType(MorphTabBar), findsOneWidget);
    expect(_unstyledTexts(tester), isEmpty);
  });

  testWidgets('date picker: the calendar opens and picks', (tester) async {
    await _open(tester, 'Date picker');
    await tester.tap(find.text('Oct 3, 2026').first);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('October 2026'), findsOneWidget);
    expect(_unstyledTexts(tester), isEmpty);
    await tester.tap(find.text('20'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.textContaining('2026-10-20'), findsOneWidget);
    await tester.tapAt(const Offset(200, 860));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('October 2026'), findsNothing);
  });

  testWidgets('sheets: the zoom button zooms its sheet out of itself', (
    tester,
  ) async {
    await _open(tester, 'Sheets');
    final button = find.text('Zoom from this button');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await tester.tap(button);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Zoomed from its button'), findsOneWidget);
    final route = ModalRoute.of(
      tester.element(find.text('Zoomed from its button')),
    );
    expect(route, isA<MorphSheetRoute<String>>());
    expect((route! as MorphSheetRoute<String>).from, isNotNull);
    expect(_unstyledTexts(tester), isEmpty);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Done in Zoomed from its button'), findsOneWidget);
  });

  testWidgets('navigation: holding Back opens its menu over the glass', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GalleryApp());
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    final entry = find.widgetWithText(MorphListRow, 'Navigation');
    await tester.scrollUntilVisible(
      entry,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await tester.tap(entry);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await tester.tap(find.text('Message 1'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    final back = find.bySemanticsLabel('Back');
    final gesture = await tester.startGesture(tester.getCenter(back.last));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull, reason: 'frame $i of the hold');
    }
    expect(find.text('Inbox'), findsWidgets);
    await gesture.moveBy(const Offset(0, 400));
    await gesture.up();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('context menu: a held row opens its actions, a pick closes', (
    tester,
  ) async {
    await _open(tester, 'Context menu');
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Anna')),
    );
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull, reason: 'frame $i of the hold');
    }
    await gesture.up();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Reply'), findsOneWidget);
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Reply: Anna'), findsOneWidget);
    expect(find.text('Reply'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigation: badges on bar buttons, subtitles under titles', (
    tester,
  ) async {
    // Wide enough for the detail page's title between its groups in the
    // test font, whose glyphs are as wide as they are tall.
    tester.view.physicalSize = const Size(2622, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GalleryApp());
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    final entry = find.widgetWithText(MorphListRow, 'Navigation');
    await tester.scrollUntilVisible(
      entry,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await tester.tap(entry);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('12'), findsOneWidget);
    expect(find.text('12 unread, updated just now'), findsWidgets);
    await tester.tap(find.text('Message 1'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('From Anna, today'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tab bar: a count badge on a tab', (tester) async {
    await _open(tester, 'Tab bar');
    expect(find.text('3'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
