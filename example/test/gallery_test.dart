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

/// Leaves a gallery page: through its app bar's back button, or, for a
/// page that brings its own navigation stack, by popping the gallery's
/// navigator.
Future<void> _back(WidgetTester tester) async {
  if (find.byType(BackButton).evaluate().isNotEmpty) {
    await tester.pageBack();
    return;
  }
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
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
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor ??
            Theme.of(
              tester.element(find.byType(Scaffold)),
            ).scaffoldBackgroundColor,
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
        expect(find.byType(SlowMotionToggle), findsOneWidget);
        await _back(tester);
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
    final screen = tester.getCenter(find.byType(Scaffold));
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

  testWidgets('the slow-motion toggle sits in the bar, clear of the tab bar', (
    tester,
  ) async {
    await _pumpGallery(tester);
    await tester.tap(find.text('Tab bar'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    final toggle = tester.getRect(find.byType(SlowMotionToggle));
    final bar = tester.getRect(find.byType(MorphTabBar));
    expect(toggle.overlaps(bar), isFalse);
    expect(
      toggle.bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
    );
    await tester.tap(find.byType(SlowMotionToggle));
    await tester.pump();
    expect(timeDilation, 5);
    expect(find.text('Slow-mo 5x'), findsOneWidget);
    await tester.tap(find.byType(SlowMotionToggle));
    await tester.pump();
    await tester.tap(find.byType(SlowMotionToggle));
    await tester.pump();
    expect(timeDilation, 1);
    expect(find.text('Slow-mo off'), findsOneWidget);
  });

  testWidgets('the menu button in the bar keeps the UIKit 16 pt inset', (
    tester,
  ) async {
    await _pumpGallery(tester);
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    final inBar = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(MorphMenuButton),
    );
    expect(tester.getRect(inBar).right, 402 - 16);
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
    await tester.pageBack();
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
