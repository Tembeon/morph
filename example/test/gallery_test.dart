import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_page.dart';
import 'package:morph_example/gallery/liquid_glass_painter.dart';

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
  await tester.pumpAndSettle();
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
        await tester.pumpAndSettle();
        expect(_unstyledTexts(tester), isEmpty, reason: entry.title);
        expect(find.byType(SlowMotionToggle), findsOneWidget);
        await _back(tester);
        await tester.pumpAndSettle();
      }
      expect(_unstyledTexts(tester), isEmpty);
    });
  }

  testWidgets('the open menu has styled rows', (tester) async {
    await _pumpGallery(tester);
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    final center = find
        .byType(MorphMenuButton)
        .evaluate()
        .map((Element e) => tester.getCenter(find.byWidget(e.widget)));
    final screen = tester.getCenter(find.byType(Scaffold));
    final nearest = center.reduce(
      (a, b) => (a - screen).distance < (b - screen).distance ? a : b,
    );
    await tester.tapAt(nearest);
    await tester.pumpAndSettle();
    expect(find.text('Duplicate'), findsOneWidget);
    expect(_unstyledTexts(tester), isEmpty);
  });

  testWidgets('the slow-motion toggle sits in the bar, clear of the tab bar', (
    tester,
  ) async {
    await _pumpGallery(tester);
    await tester.tap(find.text('Tab bar'));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    final inBar = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(MorphMenuButton),
    );
    expect(tester.getRect(inBar).right, 402 - 16);
  });

  testWidgets('the frosted painter keeps the surface color as its tint', (
    tester,
  ) async {
    const surface = MorphGlassSurface(
      kind: MorphGlassKind.track,
      shape: RRect.fromLTRBXY(0, 0, 60, 30, 15, 15),
      color: Color(0xFF34C759),
      brightness: Brightness.light,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 60,
            height: 30,
            child: Builder(
              builder: (BuildContext context) =>
                  const FrostedGlassPainter().buildSurface(context, surface),
            ),
          ),
        ),
      ),
    );
    final painted = [
      for (final box in tester.widgetList<DecoratedBox>(
        find.byType(DecoratedBox),
      ))
        if (box.decoration case final BoxDecoration d
            when d.color == surface.color && d.gradient == null)
          d,
    ];
    expect(painted, isNotEmpty);
  });

  test('the liquid painter bends a lens by its lift like UIKit', () {
    const painter = LiquidGlassRendererPainter(refraction: 2, blur: 0.5);
    MorphGlassSurface lens(MorphGlassOptics optics, double lift) =>
        MorphGlassSurface(
          kind: MorphGlassKind.lens,
          shape: const RRect.fromLTRBXY(0, 0, 80, 28, 14, 14),
          color: const Color(0xFFFFFFFF),
          brightness: Brightness.light,
          lift: lift,
          optics: optics,
        );
    final resting = painter.settingsFor(lens(MorphGlassOptics.large, 0));
    final lifted = painter.settingsFor(lens(MorphGlassOptics.large, 1));
    expect(resting.refractionAmount, 0);
    expect(lifted.refractionAmount, 36);
    expect(lifted.dispersion, LiquidGlassRendererPainter.lensDispersion);
    expect(lifted.highlight, greaterThan(resting.highlight));
    final frosted = painter.settingsFor(lens(MorphGlassOptics.small, 0));
    final clear = painter.settingsFor(lens(MorphGlassOptics.small, 1));
    expect(frosted.frost, 3);
    expect(clear.frost, 0);
  });

  testWidgets('a lifted segmented lens shows its label at its own size', (
    tester,
  ) async {
    const surfaces = [
      MorphGlassSurface(
        kind: MorphGlassKind.track,
        shape: RRect.fromLTRBXY(0, 0, 300, 36, 18, 18),
        color: Color(0x14787880),
        brightness: Brightness.light,
        glass: false,
      ),
      MorphGlassSurface(
        kind: MorphGlassKind.lens,
        shape: RRect.fromLTRBXY(10, 2, 110, 34, 16, 16),
        color: Color(0x00FFFFFF),
        brightness: Brightness.light,
        lift: 1,
        optics: MorphGlassOptics.large,
      ),
    ];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 36,
            child: Builder(
              builder: (BuildContext context) =>
                  const LiquidGlassRendererPainter().buildLayer(
                    context,
                    surfaces,
                    content: const Text('Label'),
                  ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    expect(find.text('Label'), findsNWidgets(4));
    expect(_lensShrink(tester, 0), LiquidGlassRendererPainter.segmentedShrink);
    expect(_lensShrinkRim(tester, 0), LiquidGlassRendererPainter.lensShrinkRim);
    final base = tester.getRect(find.text('Label').first);
    final seen = _seenThroughLens(tester, 0, null, 'Label');
    expect(seen.center.dx, moreOrLessEquals(base.center.dx, epsilon: 0.01));
    expect(seen.center.dy, moreOrLessEquals(base.center.dy, epsilon: 0.01));
    expect(seen.width, moreOrLessEquals(base.width, epsilon: 0.01));
    expect(
      find.ancestor(
        of: find.text('Label').last,
        matching: find.byType(ExcludeSemantics),
      ),
      findsWidgets,
    );
  });

  testWidgets('the liquid painter draws a plain surface flat', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 36,
            child: Builder(
              builder: (BuildContext context) =>
                  const LiquidGlassRendererPainter().buildLayer(context, const [
                    MorphGlassSurface(
                      kind: MorphGlassKind.track,
                      shape: RRect.fromLTRBXY(0, 0, 300, 36, 18, 18),
                      color: Color(0x14787880),
                      brightness: Brightness.light,
                      glass: false,
                    ),
                    MorphGlassSurface(
                      kind: MorphGlassKind.lens,
                      shape: RRect.fromLTRBXY(2, 2, 100, 34, 16, 16),
                      color: Color(0xFFFFFFFF),
                      brightness: Brightness.light,
                      optics: MorphGlassOptics.large,
                    ),
                  ]),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(LiquidGlassLayer), findsNothing);
  });

  testWidgets('a label seen through a dragged lens stays on its slot', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 360,
            child: MorphGlass(
              painter: const LiquidGlassRendererPainter(),
              child: MorphSegmentedControl(
                segments: const ['Day', 'Night'],
                selected: 1,
                onChanged: (int _) {},
              ),
            ),
          ),
        ),
      ),
    );
    final base = tester.getRect(find.text('Night').first);
    final gesture = await tester.startGesture(base.center);
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final lens = find.descendant(
      of: find.byKey(const ValueKey<(String, int)>(('glass', 0))),
      matching: find.byType(LiquidGlass),
    );
    expect(_lensShrink(tester, 0), greaterThan(0.1));
    final start = tester.getRect(lens).center;
    final seen = <Rect>[];
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(-2, 0));
      await tester.pump(const Duration(milliseconds: 16));
      seen.add(_seenThroughLens(tester, 0, 1, 'Night'));
    }
    expect((tester.getRect(lens).center - start).dx, lessThan(-10));
    for (final label in seen) {
      expect(label.center.dx, moreOrLessEquals(base.center.dx, epsilon: 0.01));
      expect(label.center.dy, moreOrLessEquals(base.center.dy, epsilon: 0.01));
      expect(
        label.width,
        moreOrLessEquals(
          base.width * (1 + LiquidGlassRendererPainter.segmentedMagnification),
          epsilon: 0.01,
        ),
      );
    }
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a lifted lens on a bar refracts the bar glass beneath it', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 62,
            child: Builder(
              builder: (BuildContext context) =>
                  const LiquidGlassRendererPainter().buildLayer(context, const [
                    MorphGlassSurface(
                      kind: MorphGlassKind.bar,
                      shape: RRect.fromLTRBXY(0, 0, 300, 62, 31, 31),
                      color: Color(0xB81C1C1E),
                      brightness: Brightness.dark,
                    ),
                    MorphGlassSurface(
                      kind: MorphGlassKind.lens,
                      shape: RRect.fromLTRBXY(10, -6, 120, 68, 37, 37),
                      color: Color(0x1FFFFFFF),
                      brightness: Brightness.dark,
                      lift: 1,
                      optics: MorphGlassOptics.large,
                    ),
                  ], content: const Text('Home')),
            ),
          ),
        ),
      ),
    );
    final layers = tester
        .widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
        .toList();
    expect(layers, hasLength(2));
    expect(layers.map((LiquidGlassLayer l) => l.useBackdropGroup), [
      false,
      false,
    ]);
    final stack = tester.widget<Stack>(
      find
          .ancestor(
            of: find.byKey(const ValueKey<(String, int)>(('glass', 0))),
            matching: find.byType(Stack),
          )
          .first,
    );
    final keys = [for (final child in stack.children) child.key];
    expect(
      keys.indexOf(const ValueKey<(String, int)>(('copy', 0))),
      lessThan(keys.indexOf(const ValueKey<(String, int)>(('glass', 0)))),
    );
    expect(
      keys.indexOf(const ValueKey<String>('body')),
      lessThan(keys.indexOf(const ValueKey<(String, int)>(('glass', 0)))),
    );
  });

  testWidgets('a lifted lens on a bar minifies the bar, not the label', (
    tester,
  ) async {
    const lens = RRect.fromLTRBXY(10, -6, 120, 68, 37, 37);
    const slot = Rect.fromLTWH(0, 0, 100, 62);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 62,
            child: Builder(
              builder: (BuildContext context) =>
                  const LiquidGlassRendererPainter().buildLayer(
                    context,
                    const [
                      MorphGlassSurface(
                        kind: MorphGlassKind.bar,
                        shape: RRect.fromLTRBXY(0, 0, 300, 62, 31, 31),
                        color: Color(0xB81C1C1E),
                        brightness: Brightness.dark,
                      ),
                      MorphGlassSurface(
                        kind: MorphGlassKind.lens,
                        shape: lens,
                        color: Color(0x1FFFFFFF),
                        brightness: Brightness.dark,
                        lift: 1,
                        optics: MorphGlassOptics.large,
                      ),
                    ],
                    content: const Row(
                      children: [
                        SizedBox(width: 100, child: Center(child: Text('A'))),
                      ],
                    ),
                    contentSlots: const [slot],
                  ),
            ),
          ),
        ),
      ),
    );
    final layers = tester
        .widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
        .toList();
    expect(layers.first.settings.backdropShrink, 0);
    expect(_lensShrink(tester, 0), LiquidGlassRendererPainter.tabBarShrink);
    final base = tester.getRect(find.text('A').first);
    final seen = _seenThroughLens(tester, 0, 0, 'A');
    expect(seen.center.dx, moreOrLessEquals(base.center.dx, epsilon: 0.01));
    expect(seen.center.dy, moreOrLessEquals(base.center.dy, epsilon: 0.01));
    expect(
      seen.width,
      moreOrLessEquals(
        base.width * (1 + LiquidGlassRendererPainter.tabBarMagnification),
        epsilon: 0.01,
      ),
    );
  });

  testWidgets('the glass page settings reach every page', (tester) async {
    await _pumpGallery(tester);
    expect(find.byType(MorphGlass), findsOneWidget);
    await tester.tap(find.text('Glass renderer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flat'));
    await tester.pumpAndSettle();
    expect(find.byType(MorphGlass), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Dark'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Controls'));
    await tester.pumpAndSettle();
    expect(find.byType(MorphGlass), findsNothing);
    expect(
      Theme.of(tester.element(find.byType(MorphSwitch).first)).brightness,
      Brightness.dark,
    );
    expect(_unstyledTexts(tester), isEmpty);
  });
}

LiquidGlassSettings _lensSettings(WidgetTester tester, int lens) => tester
    .widget<LiquidGlassLayer>(
      find.descendant(
        of: find.byKey(ValueKey<(String, int)>(('glass', lens))),
        matching: find.byType(LiquidGlassLayer),
      ),
    )
    .settings;

/// The backdrop shrink the glass of floating surface [lens] renders with.
double _lensShrink(WidgetTester tester, int lens) =>
    _lensSettings(tester, lens).backdropShrink;

/// The rim weight of that shrink.
double _lensShrinkRim(WidgetTester tester, int lens) =>
    _lensSettings(tester, lens).backdropShrinkRim;

/// Where [text] in content slot [slot], or in the one slot when null,
/// shows through the glass of floating surface [lens]: its copy under the
/// glass, minified the way the renderer reads the backdrop - a point on
/// the face shows the backdrop `1 + (1 / (1 - shrink) - 1) * visibility`
/// times farther from the nearest point of the glass's center line, which
/// runs along its longer side over `rim` times the long side less the
/// short side.
///
/// The copy is cut into strips at the line's ends; the text is read in
/// the strip that holds its center.
Rect _seenThroughLens(WidgetTester tester, int lens, int? slot, String text) {
  final glass = find.descendant(
    of: find.byKey(ValueKey<(String, int)>(('glass', lens))),
    matching: find.byType(LiquidGlass),
  );
  final visibility =
      tester.widget<LiquidGlass>(glass).appearance?.visibility ?? 1;
  final scale = 1 + (1 / (1 - _lensShrink(tester, lens)) - 1) * visibility;
  final bounds = tester.getRect(glass);
  final center = bounds.center;
  final rim = _lensShrinkRim(tester, lens);
  final half = rim * (bounds.longestSide - bounds.shortestSide) / 2;
  final axis = bounds.width >= bounds.height
      ? Offset(half, 0)
      : Offset(0, half);
  final copy = find.byKey(ValueKey<(String, int)>(('copy', lens)));
  Finder textIn(Finder scope) => find.descendant(
    of: slot == null
        ? scope
        : find.descendant(of: scope, matching: find.byKey(ValueKey<int>(slot))),
    matching: find.text(text),
  );
  final strips = [
    for (final strip in ['start', 'band', 'end'])
      find.descendant(of: copy, matching: find.byKey(ValueKey<String>(strip))),
  ];
  Rect? rect;
  var along = 0.0;
  if (half == 0) {
    rect = tester.getRect(textIn(copy));
  } else {
    final length = axis.distanceSquared;
    for (final (i, strip) in strips.indexed) {
      final candidate = tester.getRect(textIn(strip));
      final t =
          ((candidate.center - center).dx * axis.dx +
              (candidate.center - center).dy * axis.dy) /
          length;
      if (i == 0 && t < -1 || i == 1 && t.abs() <= 1 || i == 2 && t > 1) {
        rect = candidate;
        along = t;
      }
    }
  }
  final seen = rect!;
  final anchor = center + axis * along.clamp(-1.0, 1.0);
  final inBand = half > 0 && along.abs() <= 1;
  return Rect.fromCenter(
    center: anchor + (seen.center - anchor) / scale,
    width: inBand && axis.dy == 0 ? seen.width : seen.width / scale,
    height: inBand && axis.dx == 0 ? seen.height : seen.height / scale,
  );
}
