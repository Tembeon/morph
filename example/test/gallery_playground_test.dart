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
  unawaited(Scrollable.ensureVisible(tester.element(finder), alignment: 0.5));
  await _settle(tester);
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
    MorphWidgetsTheme scope() => tester
        .widget<MorphWidgetsThemeScope>(
          find.byType(MorphWidgetsThemeScope).first,
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

  testWidgets('morph engine: every flight opens and closes', (tester) async {
    await _open(tester, 'Morph engine');
    Future<void> roundTrip(Finder opener, String shown) async {
      await _tapVisible(tester, opener);
      expect(find.text(shown), findsOneWidget, reason: shown);
      expect(_unstyledTexts(tester), isEmpty, reason: shown);
      await tester.tap(find.text('Close'));
      await _settle(tester);
      expect(find.text(shown), findsNothing, reason: shown);
    }

    await roundTrip(
      find.text('Tap: the card becomes a dialog'),
      'The cover is a MorphSharedElement: it travels from the card '
      'instead of fading through.',
    );
    expect(find.text('Album: landed'), findsOneWidget);
    await roundTrip(find.text('Share with MorphAnchor'), 'MorphAnchor');
    await roundTrip(find.text('showMorphRoute'), 'A whole page');
    await roundTrip(find.text('MorphPageRoute'), 'A Navigator route');
    await roundTrip(find.text('Dialog flight'), 'showMorphDialogFlight');
    await roundTrip(find.text('Sheet flight'), 'showMorphSheetFlight');
    await roundTrip(find.text('Open'), 'Out of the skin');

    final piece = find.byIcon(Icons.open_with).first;
    await _center(tester, piece);
    final before = tester.getCenter(piece);
    await tester.drag(piece, const Offset(60, 30));
    await _settle(tester);
    expect(tester.getCenter(piece) - before, const Offset(60, 30));

    await _openOptions(tester);
    await tester.tap(find.text('Instant'));
    await _settle(tester);
    await _toggle(tester, 'Link the pieces');
    final theme = Theme.of(
      tester.element(find.text('Tap: the card becomes a dialog')),
    ).extension<MorphTheme>();
    expect(theme?.motion, MorphMotion.instant);
    expect(
      tester.widget<MorphSkin>(find.byType(MorphSkin)).links,
      hasLength(1),
    );
  });
}
