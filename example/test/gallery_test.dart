import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

/// Every text on screen that fell through to the app's error text style:
/// a yellow double underline marks text outside any Material.
List<String> _unstyledTexts(WidgetTester tester) => [
  for (final element in find.byType(RichText).evaluate())
    if ((element.widget as RichText).text.style?.decorationStyle ==
        TextDecorationStyle.double)
      (element.widget as RichText).text.toPlainText(),
];

Future<void> _pumpGallery(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(const GalleryApp());
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

/// The gallery's page navigator: the navigation stack's.
NavigatorState _pages(WidgetTester tester) => tester.state<NavigatorState>(
  find
      .descendant(
        of: find.byType(MorphNavigationStack),
        matching: find.byType(Navigator),
      )
      .first,
);

/// Leaves a gallery page through the navigation bar's back button.
Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Back').last);
}

Finder _slowMotion(String factor) =>
    find.bySemanticsLabel('Slow motion $factor');

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

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
    expect(reports.single.library, 'morph glass');
    expect(
      reports.single.exception.toString(),
      contains(MorphGlassRenderer.liquidUnavailableReason!),
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('every page opens in ${brightness.name} with styled text', (
      tester,
    ) async {
      await _pumpGallery(tester, brightness: brightness);
      expect(
        tester
            .widget<MorphNavigationScaffold>(
              find.byType(MorphNavigationScaffold),
            )
            .backgroundColor,
        galleryBackgroundColor(brightness),
      );
      for (final entry in galleryEntries) {
        await tester.scrollUntilVisible(
          find.text(entry.title),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text(entry.title));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );
        expect(_unstyledTexts(tester), isEmpty, reason: entry.title);
        expect(_slowMotion('1x'), findsOneWidget, reason: entry.title);
        _pages(tester).popUntil((Route<Object?> route) => route.isFirst);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );
      }
      expect(_unstyledTexts(tester), isEmpty);
    });
  }

  testWidgets('the open menu has styled rows', (tester) async {
    await _pumpGallery(tester);
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    final center = find
        .byType(MorphMenuButton)
        .evaluate()
        .map((Element e) => tester.getCenter(find.byWidget(e.widget)));
    const screen = Offset(201, 437);
    final nearest = center.reduce(
      (a, b) => (a - screen).distance < (b - screen).distance ? a : b,
    );
    await tester.tapAt(nearest);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('Duplicate'), findsOneWidget);
    expect(_unstyledTexts(tester), isEmpty);
  });

  testWidgets('the slow-motion button sits in the bar, clear of the tab bar', (
    tester,
  ) async {
    await _pumpGallery(tester);
    await tester.tap(find.text('Tab bar'));
    await _settle(tester);
    final toggle = tester.getRect(_slowMotion('1x'));
    final bar = tester.getRect(find.byType(MorphTabBar));
    expect(toggle.overlaps(bar), isFalse);
    expect(
      toggle.bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(MorphNavigationBar)).bottom),
    );
    expect(toggle.right, lessThanOrEqualTo(402 - 16));
    await tester.tap(_slowMotion('1x'));
    await tester.pump();
    expect(timeDilation, 5);
    await tester.pump(const Duration(seconds: 3));
    expect(_slowMotion('5x'), findsOneWidget);
    await tester.tap(_slowMotion('5x'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.tap(_slowMotion('10x'));
    await tester.pump();
    expect(timeDilation, 1);
    await _settle(tester);
    expect(_slowMotion('1x'), findsOneWidget);
  });

  testWidgets('holding the bar button of the menu page opens its menu', (
    tester,
  ) async {
    await _pumpGallery(tester);
    await tester.tap(find.text('Menu'));
    await _settle(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('More')),
    );
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    await gesture.moveBy(const Offset(0, 300));
    await gesture.up();
    await _settle(tester);
    expect(find.text('Copy'), findsOneWidget);
    expect(_unstyledTexts(tester), isEmpty);
  });

  testWidgets('the glass page settings reach every page', (tester) async {
    await _pumpGallery(tester);
    expect(find.byType(MorphGlass), findsOneWidget);
    await tester.tap(find.text('Glass renderer'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await tester.tap(find.text('Flat'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(
      MorphAdaptiveGlass.tierOf(tester.element(find.text('Flat'))),
      MorphGlassTier.flat,
    );
    await tester.scrollUntilVisible(
      find.text('Dark'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await _back(tester);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await tester.tap(find.text('Controls'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(
      MorphAdaptiveGlass.tierOf(tester.element(find.byType(MorphSwitch).first)),
      MorphGlassTier.flat,
    );
    expect(
      Theme.of(tester.element(find.byType(MorphSwitch).first)).brightness,
      Brightness.dark,
    );
    expect(_unstyledTexts(tester), isEmpty);
  });
}
