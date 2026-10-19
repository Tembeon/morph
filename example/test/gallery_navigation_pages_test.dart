import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/knobs.dart';

/// Every text on screen that fell through to the app's error text style.
List<String> _unstyledTexts(WidgetTester tester) => [
  for (final element in find.byType(RichText).evaluate())
    if ((element.widget as RichText).text.style?.decorationStyle ==
        TextDecorationStyle.double)
      (element.widget as RichText).text.toPlainText(),
];

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

Future<void> _open(WidgetTester tester, String title) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const GalleryApp());
  await _settle(tester);
  final entry = find.widgetWithText(MorphListRow, title);
  await Scrollable.ensureVisible(tester.element(entry), alignment: 0.5);
  await _settle(tester);
  await tester.tap(entry);
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

/// The title [text] inside the navigation bar.
Finder _barTitle(String text) => find.descendant(
  of: find.byType(MorphNavigationBar),
  matching: find.text(text),
);

/// Taps the leading part of the last back button, clear of a centered
/// title.
Future<void> _back(WidgetTester tester) async {
  final rect = tester.getRect(find.bySemanticsLabel('Back').last);
  await tester.tapAt(rect.centerLeft + const Offset(24, 0));
}

/// Scrolls the options sheet to [finder] and taps it.
Future<void> _knob(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await _tap(tester, finder);
}

/// The switch of the knob [label].
Finder _switch(String label) => find.descendant(
  of: find.widgetWithText(GalleryToggle, label),
  matching: find.byType(MorphSwitch),
);

/// Opens the page's options sheet, runs [change] in it, and closes it.
Future<void> _options(
  WidgetTester tester,
  Future<void> Function() change,
) async {
  await tester.tap(find.bySemanticsLabel('Page options'));
  await _settle(tester);
  await change();
  final inSheet = find.byType(ListView).last;
  Navigator.of(tester.element(inSheet)).pop();
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    try {
      await MorphTheme.precacheGlass();
    } finally {
      FlutterError.onError = previous;
    }
  });

  testWidgets('navigation bar: badge, back button modes, zoom, bars', (
    tester,
  ) async {
    await _open(tester, 'Navigation bar');
    expect(find.bySemanticsLabel('Mail'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.text('Bars, buttons, badges'), findsWidgets);
    expect(find.byType(MorphToolbar), findsOneWidget);
    expect(find.byType(MorphScrollEdgeEffect), findsWidgets);
    expect(find.text('Folders'), findsOneWidget);

    await _tap(tester, find.text('Open Mailboxes'));
    expect(find.text('Mailboxes'), findsWidgets);
    await _tap(tester, find.text('Inbox'));
    expect(find.text('Inbox'), findsWidgets);
    expect(find.text('Hold the back button for its menu.'), findsOneWidget);
    expect(_barTitle('Mailboxes'), findsOneWidget);
    await _back(tester);
    await _settle(tester);
    await _back(tester);
    await _settle(tester);
    expect(find.text('Open Mailboxes'), findsOneWidget);

    await _options(tester, () async {
      await tester.tap(find.text('Text'));
      await _settle(tester);
      await _tap(tester, find.text('Minimal'));
      await _knob(tester, _switch('Own back button with a menu'));
      await _knob(tester, _switch('Large title'));
    });
    expect(find.text('New'), findsWidgets);
    expect(find.text('Back button: minimal, own with a menu'), findsOneWidget);
    await _tap(tester, find.text('Open Mailboxes'));
    await _tap(tester, find.text('Drafts'));
    expect(find.text('Drafts'), findsWidgets);
    await _back(tester);
    await _settle(tester);
    expect(find.text('Inbox'), findsOneWidget);
    await _back(tester);
    await _settle(tester);

    await _tap(tester, find.bySemanticsLabel('Zoom photo 1'));
    expect(_barTitle('Photo 1'), findsOneWidget);
    await _back(tester);
    await _settle(tester);
    expect(find.text('Open Mailboxes'), findsOneWidget);

    await _options(tester, () async {
      await _knob(tester, _switch('Toolbar'));
      await _knob(tester, _switch('Standalone large title'));
    });
    expect(find.byType(MorphToolbar), findsNothing);
    expect(find.byType(MorphLargeTitle), findsWidgets);
    expect(_unstyledTexts(tester), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigator pages: a list of pages pushes, zooms and pops', (
    tester,
  ) async {
    await _open(tester, 'Navigator pages');
    await _tap(tester, find.text('Open the stack'));
    expect(find.text('Pages: Library'), findsOneWidget);
    await _tap(tester, find.text('Album 2'));
    expect(find.text('Pages: Library / Album 2'), findsOneWidget);
    await _tap(tester, find.text('Album 3'));
    expect(find.text('Pages: Library / Album 2 / Album 3'), findsOneWidget);
    await _tap(tester, find.text('Remove this page'));
    expect(find.text('Pages: Library / Album 2'), findsOneWidget);
    await _back(tester);
    await _settle(tester);
    expect(find.text('Pages: Library'), findsOneWidget);

    await _tap(tester, find.bySemanticsLabel('Photo 1'));
    expect(_barTitle('Photo 1'), findsOneWidget);
    await _back(tester);
    await _settle(tester);
    expect(find.text('Pages: Library'), findsOneWidget);

    await tester.tap(_barTitle('Album 3'));
    await _settle(tester);
    expect(
      find.text('Pages: Library / Album 1 / Album 2 / Album 3'),
      findsOneWidget,
    );
    await tester.tap(_barTitle('Library'));
    await _settle(tester);
    expect(find.text('Pages: Library'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Close'));
    await _settle(tester);
    expect(find.text('Open at Album 3'), findsOneWidget);
    await _tap(tester, find.text('Open at Album 3'));
    expect(
      find.text('Pages: Library / Album 1 / Album 2 / Album 3'),
      findsOneWidget,
    );
    expect(_unstyledTexts(tester), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
