import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
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
  await tester.pumpAndSettle();
  final entry = find.widgetWithText(ListTile, title);
  await tester.scrollUntilVisible(
    entry,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(entry);
  await tester.pumpAndSettle();
  await tester.tap(entry);
  await tester.pumpAndSettle();
  expect(find.widgetWithText(AppBar, title), findsOneWidget);
}

void main() {
  testWidgets('alerts: an alert and an anchored action sheet', (tester) async {
    await _open(tester, 'Alerts');
    await tester.tap(find.text('Three buttons, destructive, cancel last'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this photo?'), findsOneWidget);
    expect(_unstyledTexts(tester), isEmpty);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete chosen'), findsOneWidget);
    await tester.tap(find.text('Action sheet from this button'));
    await tester.pumpAndSettle();
    expect(find.text('Share photo'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(_unstyledTexts(tester), isEmpty);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(find.text('Share photo'), findsNothing);
    expect(find.text('Cancel chosen'), findsOneWidget);
  });

  testWidgets('search: the toolbar filters, the tab bar morphs', (
    tester,
  ) async {
    await _open(tester, 'Search');
    expect(find.text('Banana'), findsOneWidget);
    await tester.tap(find.byType(MorphSearchField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'ber');
    await tester.pumpAndSettle();
    expect(find.text('Banana'), findsNothing);
    expect(find.text('Blueberry'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Banana'), findsOneWidget);
    await tester.tap(find.text('Tab bar'));
    await tester.pumpAndSettle();
    expect(find.byType(MorphTabBar), findsOneWidget);
    expect(_unstyledTexts(tester), isEmpty);
  });

  testWidgets('date picker: the calendar opens and picks', (tester) async {
    await _open(tester, 'Date picker');
    await tester.tap(find.text('Oct 3, 2026').first);
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(_unstyledTexts(tester), isEmpty);
    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-10-20'), findsOneWidget);
    await tester.tapAt(const Offset(200, 860));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsNothing);
  });
}
