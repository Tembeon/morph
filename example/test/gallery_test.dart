import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';
import 'package:morph/src/widgets/glass_tier.dart';

import 'support/gallery_text.dart';

/// The Material app, themes and surfaces in the tree, offstage included.
List<Widget> _materialWidgets() => [
  for (final type in [MaterialApp, Theme, Material, Scaffold])
    for (final element in find.byType(type, skipOffstage: false).evaluate())
      element.widget,
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

/// Opens the home entry [title]: scrolls its row to the middle of the
/// screen, clear of the bars, and taps it.
Future<void> _open(WidgetTester tester, String title) async {
  final entry = find.widgetWithText(MorphListRow, title);
  await Scrollable.ensureVisible(tester.element(entry), alignment: 0.5);
  await _settle(tester);
  await tester.tap(entry);
  await _settle(tester);
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
      expect(find.byType(WidgetsApp), findsOneWidget);
      for (final entry in galleryEntries) {
        await _open(tester, entry.title);
        expect(unstyledTexts(), isEmpty, reason: entry.title);
        expect(_materialWidgets(), isEmpty, reason: entry.title);
        expect(_slowMotion('1x'), findsOneWidget, reason: entry.title);
        _pages(tester).popUntil((Route<Object?> route) => route.isFirst);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );
      }
      expect(unstyledTexts(), isEmpty);
    });
  }

  testWidgets('a text outside every morph surface reads as body text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const GalleryApp(home: Center(child: Text('Loose'))),
    );
    final style = tester
        .widget<RichText>(
          find.descendant(
            of: find.text('Loose'),
            matching: find.byType(RichText),
          ),
        )
        .text
        .style!;
    expect(style.fontSize, MorphTypography.body.fontSize);
    expect(style.color, MorphListAppearance.light.titleColor);
    expect(style.decoration, isNull);
    expect(unstyledTexts(), ['Loose']);
  });

  testWidgets('the open menu has styled rows', (tester) async {
    await _pumpGallery(tester);
    await _open(tester, 'Menu');
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
    expect(unstyledTexts(), isEmpty);
  });

  testWidgets('the slow-motion button sits in the bar, clear of the tab bar', (
    tester,
  ) async {
    await _pumpGallery(tester);
    await _open(tester, 'Tab bar');
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
    await _open(tester, 'Menu');
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
    expect(unstyledTexts(), isEmpty);
  });

  testWidgets('the glass page settings reach every page', (tester) async {
    await _pumpGallery(tester);
    expect(find.byType(GalleryGlassTuning), findsOneWidget);
    await _open(tester, 'Glass renderer');
    final flat = find.text('Flat');
    final settings = GalleryGlassScope.read(tester.element(flat));
    expect(settings.tier, isNull);
    await Scrollable.ensureVisible(tester.element(flat), alignment: 0.5);
    await _settle(tester);
    // The host draws flat on auto, so the tier goes through fake first to
    // see the tap on Flat change what is drawn.
    await tester.tap(find.text('Fake'));
    await _settle(tester);
    expect(settings.tier, MorphGlassTier.fake);
    expect(
      GlassAdaptiveScope.tierOf(tester.element(flat)),
      MorphGlassTier.fake,
    );
    await tester.tap(flat);
    await _settle(tester);
    expect(settings.tier, MorphGlassTier.flat);
    expect(
      GlassAdaptiveScope.tierOf(tester.element(find.text('Flat'))),
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
    await _open(tester, 'Controls');
    expect(
      GlassAdaptiveScope.tierOf(tester.element(find.byType(MorphSwitch).first)),
      MorphGlassTier.flat,
    );
    expect(
      MorphTheme.of(tester.element(find.byType(MorphSwitch).first)).brightness,
      Brightness.dark,
    );
    expect(unstyledTexts(), isEmpty);
  });

  testWidgets('section headers differ from entry titles, titles are unique', (
    tester,
  ) async {
    final titles = [for (final e in galleryEntries) e.title];
    expect(titles.toSet(), hasLength(titles.length));
    final headers = [for (final f in GalleryFamily.values) f.header];
    expect(headers.toSet(), hasLength(headers.length));
    expect(headers.toSet().intersection(titles.toSet()), isEmpty);
    final order = [for (final e in galleryEntries) e.family.index];
    final sorted = [...order];
    sorted.sort();
    expect(
      order,
      orderedEquals(sorted),
      reason: 'galleryEntries lists the families in the order of the home',
    );
    await _pumpGallery(tester);
    for (final family in GalleryFamily.values) {
      expect(find.text(family.header), findsOneWidget, reason: family.header);
    }
    for (final title in titles) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('the global settings reach the theme and the media query', (
    tester,
  ) async {
    await _pumpGallery(tester);
    BuildContext home() => tester.element(find.byType(GalleryHome));
    var theme = MorphTheme.of(home());
    expect(theme.tint, isNull);
    expect(theme.haptics, isTrue);
    expect(MediaQuery.disableAnimationsOf(home()), isFalse);
    expect(MediaQuery.highContrastOf(home()), isFalse);
    final settings = GalleryGlassScope.read(home());
    settings.reduceMotion = true;
    settings.highContrast = true;
    settings.haptics = false;
    settings.accent = const Color(0xFFFF9500);
    await _settle(tester);
    theme = MorphTheme.of(home());
    expect(theme.tint, const Color(0xFFFF9500));
    expect(theme.haptics, isFalse);
    expect(MediaQuery.disableAnimationsOf(home()), isTrue);
    expect(MediaQuery.highContrastOf(home()), isTrue);
  });

  testWidgets('a page with options opens them in a sheet that follows it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const GalleryApp(home: MorphNavigationStack(home: _OptionsProbe())),
    );
    await _settle(tester);
    expect(find.text('Probe off'), findsOneWidget);
    expect(find.byType(GalleryToggle), findsNothing);
    await tester.tap(find.bySemanticsLabel('Page options'));
    await _settle(tester);
    expect(find.byType(GalleryToggle), findsOneWidget);
    await tester.tap(find.byType(MorphSwitch).last);
    await _settle(tester);
    expect(find.text('Probe on'), findsOneWidget);
    expect(
      tester.widget<MorphSwitch>(find.byType(MorphSwitch).last).value,
      isTrue,
    );
    await tester.tap(find.bySemanticsLabel('Orange'));
    await _settle(tester);
    expect(find.text('Probe orange'), findsOneWidget);
    expect(unstyledTexts(), isEmpty);
  });
}

class _OptionsProbe extends StatefulWidget {
  const _OptionsProbe();

  @override
  State<_OptionsProbe> createState() => _OptionsProbeState();
}

class _OptionsProbeState extends State<_OptionsProbe> {
  bool _on = false;
  Color? _color;

  @override
  Widget build(BuildContext context) {
    return GalleryPage(
      title: 'Probe',
      options: (BuildContext context) => [
        MorphListSection(
          header: const Text('Probe options'),
          children: [
            GalleryToggle(
              label: 'Probe switch',
              value: _on,
              onChanged: (bool v) => setState(() => _on = v),
            ),
            GalleryColorChoice(
              label: 'Probe color',
              value: _color,
              onChanged: (Color? c) => setState(() => _color = c),
            ),
          ],
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: GalleryCaption(
            _color == null ? 'Probe ${_on ? 'on' : 'off'}' : 'Probe orange',
          ),
        ),
      ],
    );
  }
}
