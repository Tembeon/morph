import 'dart:async';

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
  await tester.scrollUntilVisible(
    entry,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(entry);
  await _settle(tester);
  await tester.tap(entry);
  await _settle(tester);
  expect(
    find.descendant(
      of: find.byType(MorphNavigationBar),
      matching: find.text(title),
    ),
    findsWidgets,
  );
}

Future<void> _openOptions(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Page options').first);
  await _settle(tester);
}

Finder _switch(String label) => find.byWidgetPredicate(
  (Widget w) => w is MorphSwitch && w.semanticLabel == label,
);

Future<void> _toggle(WidgetTester tester, String label) async {
  await tester.tap(_switch(label));
  await _settle(tester);
}

Future<void> _scrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 300,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).last,
  );
  await _settle(tester);
}

Future<void> _center(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) await _scrollTo(tester, finder);
  unawaited(Scrollable.ensureVisible(tester.element(finder), alignment: 0.5));
  await _settle(tester);
}

/// Scrolls the page back up to its status line and expects [text] there.
Future<void> _expectStatus(WidgetTester tester, String text) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).last)
      .position
      .jumpTo(0);
  await _settle(tester);
  expect(find.text(text), findsOneWidget);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await _center(tester, finder);
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    try {
      await MorphGlassRenderer.precache();
    } finally {
      FlutterError.onError = previous;
    }
    expect(MorphGlassRenderer.liquidAvailable, isFalse);
  });

  testWidgets('glass effects: shapes, a container and the inspector', (
    tester,
  ) async {
    await _open(tester, 'Glass effects');
    expect(find.byType(MorphGlassEffect), findsNWidgets(14));
    expect(find.byType(MorphGlassContainer), findsOneWidget);
    await _openOptions(tester);
    await _toggle(tester, 'In a glass container');
    await _toggle(tester, 'Interactive');
    await tester.tap(find.bySemanticsLabel('Purple'));
    await _settle(tester);
    expect(find.byType(MorphGlassContainer), findsNWidgets(2));
    final effect = tester.widget<MorphGlassEffect>(
      find.byType(MorphGlassEffect).first,
    );
    expect(effect.interactive, isFalse);
    expect(effect.tint, const Color(0xFFAF52DE));
    await _toggle(tester, 'Glass inspector here');
    await tester.tap(find.text('Top'));
    await _settle(tester);
    final inspector = tester.widget<MorphGlassInspector>(
      find.byType(MorphGlassInspector).last,
    );
    expect(inspector.enabled, isTrue);
    expect(inspector.alignment, AlignmentDirectional.topStart);
    expect(_unstyledTexts(tester), isEmpty);
  });

  testWidgets('theming: a local accent, haptics and side-by-side settings', (
    tester,
  ) async {
    await _open(tester, 'Theming');
    MorphThemeData scope() => tester
        .widget<MorphTheme>(
          find
              .ancestor(
                of: find.text(
                  'Accent from the theme scope',
                  skipOffstage: false,
                ),
                matching: find.byType(MorphTheme),
              )
              .first,
        )
        .data;
    expect(scope().tint, const Color(0xFFAF52DE));
    await _scrollTo(tester, find.text('Reduce Motion, side by side'));
    final contrast = find.byWidgetPredicate(
      (Widget w) => w is MediaQuery && w.data.highContrast,
      skipOffstage: false,
    );
    expect(contrast, findsWidgets);
    final reduced = find.byWidgetPredicate(
      (Widget w) => w is MediaQuery && w.data.disableAnimations,
      skipOffstage: false,
    );
    expect(reduced, findsWidgets);
    await _scrollTo(
      tester,
      find.text('Accent from the theme scope'),
      delta: -300,
    );
    await _openOptions(tester);
    await tester.tap(find.bySemanticsLabel('Orange'));
    await _settle(tester);
    expect(scope().tint, const Color(0xFFFF9500));
    await _toggle(tester, 'Haptics');
    expect(scope().haptics, isFalse);
    await _toggle(tester, 'Own appearances');
    expect(
      tester.widget<MorphSwitch>(_switch('Own switch')).appearance,
      isNull,
    );
    await tester.tap(find.text('Apple'));
    await _settle(tester);
    expect(_unstyledTexts(tester), isEmpty);
  });

  testWidgets('alerts: text field options and a sheet from a rect', (
    tester,
  ) async {
    await _open(tester, 'Alerts');
    expect(find.text('Two buttons in a row'), findsOneWidget);

    await _tapVisible(tester, find.text('OK waits for text'));
    expect(find.text('New playlist'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await _settle(tester);
    expect(find.text('New playlist'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'Road trip');
    await _settle(tester);
    await tester.tap(find.text('OK'));
    await _settle(tester);
    await _expectStatus(tester, 'Created Road trip');

    await _tapVisible(tester, find.text('A password field'));
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).obscureText,
      isTrue,
    );
    await tester.enterText(find.byType(EditableText), 'secret');
    await _settle(tester);
    await tester.tap(find.text('Join'));
    await _settle(tester);
    await _expectStatus(tester, 'Joined with 6 characters');

    await _tapVisible(tester, find.text('Capitalized words, digits only'));
    final fields = find.byType(EditableText);
    expect(fields, findsNWidgets(2));
    expect(
      tester.widget<EditableText>(fields.first).textCapitalization,
      TextCapitalization.words,
    );
    await tester.enterText(fields.first, 'Ada Lovelace');
    await tester.enterText(fields.last, 'a1234567');
    await _settle(tester);
    await tester.tap(find.text('Save'));
    await _settle(tester);
    await _expectStatus(tester, 'Ships to Ada Lovelace, 12345');

    final box = find.text('Tap anywhere here: an action sheet from that point');
    await _tapVisible(tester, box);
    expect(find.text('Share photo'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    await tester.tapAt(const Offset(200, 20));
    await _settle(tester);
    await _expectStatus(tester, 'Cancel chosen');

    await _openOptions(tester);
    await _toggle(tester, 'Messages');
    await _toggle(tester, 'Action sheet title');
    await tester.tap(find.text('Two buttons in a row'));
    await _settle(tester);
    expect(find.text('Allow notifications?'), findsOneWidget);
    expect(
      find.text('Alerts, sounds and badges keep you in the loop.'),
      findsNothing,
    );
    expect(_unstyledTexts(tester), isEmpty);
  });

  testWidgets('lists: checkmarks, info buttons, a disabled row, lazy rows', (
    tester,
  ) async {
    await _open(tester, 'Lists');
    MorphListRow row(String title) =>
        tester.widget<MorphListRow>(find.widgetWithText(MorphListRow, title));

    await _tapVisible(tester, find.text('Date added'));
    expect(row('Date added').accessory, MorphListAccessory.checkmark);
    expect(row('Name').accessory, isNull);
    await _expectStatus(tester, 'Sorted by Date added');

    await _center(tester, find.text('Kitchen speaker'));
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(MorphListRow, 'Kitchen speaker'),
        matching: find.bySemanticsLabel('More info'),
      ),
    );
    await _settle(tester);
    await _expectStatus(tester, 'Info for Kitchen speaker');
    await _tapVisible(tester, find.text('Kitchen speaker'));
    await _expectStatus(tester, 'Selected Kitchen speaker');

    await _tapVisible(tester, find.text('Garage door'));
    await _expectStatus(tester, 'Selected Kitchen speaker');

    await _scrollTo(tester, find.text('Item 40'));
    expect(find.text('Item 400'), findsNothing);
    await _tapVisible(tester, find.text('Item 40'));
    expect(find.text('Item 40'), findsOneWidget);

    await _openOptions(tester);
    await tester.tap(find.text('50'));
    await _settle(tester);
    await _toggle(tester, 'Enable the row');
    expect(find.text('50 lazy rows', skipOffstage: false), findsOneWidget);
    expect(_unstyledTexts(tester), isEmpty);
  });
}
