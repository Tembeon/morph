// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
// The A/B toggles the renderer's own paths.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/internal/glass_defaults.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/internal/flutter_gpu_geometry_renderer.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/internal/glass_warm_up.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/renderer.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/shaders.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show AnalyticGeometryMode, RenderLiquidGlassLayer;
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_container.dart';
import 'package:morph/widgets.dart';

import '../integration_test/support/shader_harness.dart';

/// Glass over a declared solid backdrop against the backdrop filter over
/// the same color, on the host's Impeller.
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/solid_backdrop_host_test.dart
///
/// A layer with [LiquidGlassLayer.solidBackdrop] draws its glass as a
/// paint shaded over that color instead of a backdrop filter. Over an
/// opaque fill of the same color both must draw the same pixels. Prints
/// one line per case: the largest channel difference, the mean over the
/// pixels the shapes cover and the pixels over 2 and over 8. List section
/// cards and an app's MorphGlassContainer declaring its page color draw
/// the same way, and the liquid pipeline warm-up paints every final
/// variant over a solid backdrop too.
/// Without Impeller the test does nothing.
const double _dpr = 2.625;

/// `--dart-define=AUDIT_OUT=<dir>` keeps both shots of every case as PNGs.
const String _out = String.fromEnvironment('AUDIT_OUT');

/// `--dart-define=SOLID_CASES=a,b` runs only the named layer cases.
const String _only = String.fromEnvironment('SOLID_CASES');

final GlobalKey _boundary = GlobalKey();

/// The pixels a case's [rects] cover, grown by the contour, the shadow's
/// reach and the antialiasing, in device pixels.
bool Function(int x, int y) _covered(List<Rect> rects) {
  final grown = [for (final rect in rects) rect.inflate(3)];
  return (x, y) {
    final point = Offset((x + 0.5) / _dpr, (y + 0.5) / _dpr);
    return grown.any((rect) => rect.contains(point));
  };
}

Map<String, Object> _compare(
  HarnessShot a,
  HarnessShot b,
  bool Function(int x, int y) covered,
) {
  var max = 0;
  var sum = 0;
  var coveredPixels = 0;
  var over2 = 0;
  var over8 = 0;
  for (var p = 0; p < a.width * a.height; p++) {
    var pixelMax = 0;
    var pixelSum = 0;
    for (var c = 0; c < 4; c++) {
      final d = (a.bytes[p * 4 + c] - b.bytes[p * 4 + c]).abs();
      if (d > pixelMax) pixelMax = d;
      if (c < 3) pixelSum += d;
    }
    if (pixelMax > max) max = pixelMax;
    if (pixelMax > 2) over2++;
    if (pixelMax > 8) over8++;
    if (covered(p % a.width, p ~/ a.width)) {
      coveredPixels++;
      sum += pixelSum;
    }
  }
  return {
    'max': max,
    'mean_covered': coveredPixels == 0 ? 0.0 : sum / (coveredPixels * 3),
    'covered_pixels': coveredPixels,
    'over_2': over2,
    'over_8': over8,
  };
}

Future<HarnessShot> _shoot(WidgetTester tester) async {
  final render =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(
    () => render.toImage(pixelRatio: _dpr),
  ))!;
  final data = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  image.dispose();
  return HarnessShot(image.width, image.height, data!.buffer.asUint8List());
}

Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// The backdrop filters in the last frame's layer tree.
int _filters() => _filterLayers().length;

/// The glass backdrop filters in the last frame's layer tree, in paint
/// order.
List<BackdropFilterLayer> _filterLayers() {
  final found = <BackdropFilterLayer>[];
  void walk(Layer layer) {
    // The composition probe's seed layer is a subclass: count the glass.
    if (layer.runtimeType == BackdropFilterLayer) {
      found.add(layer as BackdropFilterLayer);
    }
    if (layer is ContainerLayer) {
      for (
        var child = layer.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        walk(child);
      }
    }
  }

  for (final view in RendererBinding.instance.renderViews) {
    final root = view.debugLayer;
    if (root != null) walk(root);
  }
  return found;
}

/// One layer case: glass [shapes] over an opaque [color].
class _Case {
  const _Case(this.name, this.color, this.settings, this.shapes);

  final String name;
  final Color color;
  final LiquidGlassSettings settings;
  final List<(Rect, LiquidShape, LiquidGlassAppearance, bool)> shapes;
}

(Rect, LiquidShape, LiquidGlassAppearance, bool) _button(
  double left,
  double top,
  LiquidGlassAppearance appearance, {
  double width = 72,
  double height = 34,
  bool shadow = true,
}) => (
  Rect.fromLTWH(left, top, width, height),
  LiquidRoundedSuperellipse(borderRadius: height / 2),
  appearance,
  shadow,
);

const LiquidGlassAppearance _light = LiquidGlassAppearance.ios27RegularLight();
const LiquidGlassAppearance _dark = LiquidGlassAppearance.ios27RegularDark();

final List<_Case> _cases = [
  _Case(
    'light-cell-buttons',
    const Color(0xFFFFFFFF),
    const LiquidGlassSettings(frost: 0),
    [
      _button(260, 40, _light),
      _button(260.4, 100.3, _light),
      _button(259.7, 160.6, _light),
      _button(20.2, 220.5, _light, width: 120, height: 44),
    ],
  ),
  _Case(
    'dark-cell-buttons',
    const Color(0xFF1C1C1E),
    const LiquidGlassSettings(frost: 0),
    [
      _button(260, 40, _dark),
      _button(260.4, 100.3, _dark),
      _button(259.7, 160.6, _dark),
      _button(20.2, 220.5, _dark, width: 120, height: 44),
    ],
  ),
  _Case(
    'dark-cell-tinted',
    const Color(0xFF1C1C1E),
    const LiquidGlassSettings(frost: 0),
    [
      _button(40, 300, _dark),
      _button(
        140.3,
        300.6,
        const LiquidGlassAppearance.ios27RegularDark(tint: Color(0xFF34C759)),
      ),
      _button(240.5, 300.2, _dark, shadow: false),
    ],
  ),
  _Case(
    'grouped-light-no-shadow',
    const Color(0xFFF2F2F7),
    const LiquidGlassSettings(frost: 0),
    [
      _button(30.5, 420.5, _light, shadow: false),
      _button(150.25, 420.75, _light, shadow: false, width: 44, height: 44),
    ],
  ),
  _Case(
    'dark-dispersion',
    const Color(0xFF1C1C1E),
    const LiquidGlassSettings(
      frost: 0,
      dispersion: -0.25,
      refractionAmount: 120,
    ),
    [
      _button(40, 520, _dark, width: 140, height: 64),
      _button(220.4, 520.4, _dark, width: 64, height: 64),
    ],
  ),
];

Widget _scene(_Case glassCase, {required bool solid, Key? key}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _boundary,
          child: SizedBox.fromSize(
            size: harnessRegion,
            child: ColoredBox(
              color: glassCase.color,
              child: LiquidGlassLayer(
                key: key,
                settings: glassCase.settings,
                solidBackdrop: solid ? glassCase.color : null,
                child: Stack(
                  children: [
                    for (final (rect, shape, appearance, shadow)
                        in glassCase.shapes)
                      Positioned.fromRect(
                        rect: rect,
                        child: LiquidGlass(
                          shape: shape,
                          appearance: appearance,
                          shadows: shadow
                              ? const [MorphGlassDefaults.bodyShadow]
                              : const [],
                          child: const SizedBox.expand(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

final GlobalKey _sectionShot = GlobalKey();

Widget _section({
  required Brightness brightness,
  ScrollController? controller,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(platform: TargetPlatform.iOS, brightness: brightness),
  home: MorphAdaptiveGlass(
    renderer: const MorphGlassRenderer(),
    tier: MorphGlassTier.liquid,
    child: RepaintBoundary(
      key: _sectionShot,
      child: ColoredBox(
        color: brightness == Brightness.dark
            ? const Color(0xFF000000)
            : const Color(0xFFF2F2F7),
        child: SingleChildScrollView(
          controller: controller,
          child: Column(
            children: [
              // Each section in a backdrop group of its own: in the page's
              // shared group the second section's filter reads the backdrop
              // as it stood at the first, before its own card was painted
              // (the shared-group rule), so the reference would show the
              // page under the second card's buttons.
              for (final header in ['Accessories', 'More'])
                BackdropGroup(
                  child: MorphListSection(
                    header: header,
                    children: [
                      for (var i = 0; i < 3; i++)
                        MorphListRow(
                          title: Text('$header $i'),
                          onTap: () {},
                          trailing: SizedBox(
                            width: 72,
                            height: 34,
                            child: MorphGlassButton(
                              onPressed: () {},
                              child: Text('Go $i'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    ),
  ),
);

Future<HarnessShot> _shootSection(
  WidgetTester tester, [
  GlobalKey? boundary,
]) async {
  final render =
      (boundary ?? _sectionShot).currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
  final image = (await tester.runAsync(
    () => render.toImage(pixelRatio: _dpr),
  ))!;
  final data = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  image.dispose();
  return HarnessShot(image.width, image.height, data!.buffer.asUint8List());
}

final GlobalKey _clusterShot = GlobalKey();

/// Four resting glass buttons in an app's [MorphGlassContainer] on the
/// page's own background, the container declaring [solidBackdrop].
Widget _cluster({
  required Brightness brightness,
  required Color? Function(Color page) solidBackdrop,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(platform: TargetPlatform.iOS, brightness: brightness),
  home: MorphAdaptiveGlass(
    renderer: const MorphGlassRenderer(),
    tier: MorphGlassTier.liquid,
    child: Builder(
      builder: (BuildContext context) {
        final page = MorphListStyle.resolve(context, null).backgroundColor;
        return RepaintBoundary(
          key: _clusterShot,
          child: ColoredBox(
            color: page,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20.3, 60.6, 20, 0),
              child: Align(
                alignment: Alignment.topLeft,
                child: MorphGlassContainer(
                  solidBackdrop: solidBackdrop(page),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (var i = 0; i < 4; i++)
                        SizedBox(
                          width: 96,
                          height: 44,
                          child: MorphGlassButton(
                            onPressed: () {},
                            child: Text('Go $i'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  ),
);

Iterable<RenderLiquidGlassLayer> _layers(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().toSet();

void main() {
  tearDown(() => debugMorphGlassStageSolidBackdrops = true);

  testWidgets('the liquid warm-up paints every final variant over a solid '
      'backdrop and leaves the layers drawing as before', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    await tester.runAsync(MorphGlassRenderer.precache);
    await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);
    RenderLiquidGlassLayer.debugAnalyticMode = AnalyticGeometryMode.always;
    RenderLiquidGlassLayer.debugAnalyticGeometry = true;
    addTearDown(() {
      RenderLiquidGlassLayer.debugAnalyticGeometry = null;
      RenderLiquidGlassLayer.debugAnalyticMode = null;
    });

    final reports = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) reports.add(message);
    };
    addTearDown(() => debugPrint = previous);
    debugMorphLiquidWarmUpDraws = null;
    await tester.runAsync(() async {
      final geometry = await FlutterGpuGeometryRenderer.fromAsset(
        ShaderKeys.gpuGeometryShaderBundle,
      );
      try {
        await morphWarmLiquidPipelines(geometry, ShaderKeys.liquidGlassRenders);
      } finally {
        geometry.dispose();
      }
    });
    debugPrint = previous;
    expect(reports, isEmpty);
    // Every matte and analytic variant: once as a filter, alone and over
    // each of the four frost sigmas, and once as a solid paint; then the
    // four plain blurs.
    final variants =
        ShaderKeys.liquidGlassRenders.length +
        ShaderKeys.liquidGlassAnalyticRenders.length +
        ShaderKeys.liquidGlassAnalyticFusedRenders.length;
    expect(debugMorphLiquidWarmUpDraws, (
      filters: variants * 5 + 4,
      solidPaints: variants,
    ));

    // The layers mounted after it draw both paths as before.
    final glassCase = _cases[1];
    final shots = <bool, HarnessShot>{};
    for (final solid in [false, true]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_scene(glassCase, solid: solid));
      await _settle(tester);
      expect(_layers(tester).single.debugDrawsOverSolidBackdrop, solid);
      expect(_filters(), solid ? 0 : 1);
      shots[solid] = await _shoot(tester);
    }
    final compared = _compare(
      shots[false]!,
      shots[true]!,
      _covered([for (final s in glassCase.shapes) s.$1]),
    );
    // ignore: avoid_print
    print('SOLID after warm-up ${glassCase.name} $compared');
    expect(compared['max'], lessThanOrEqualTo(2));
  });

  for (final analytic in [true, false]) {
    testWidgets('glass over a solid backdrop draws what the filter draws over '
        'it (${analytic ? 'analytic' : 'matte'})', (WidgetTester tester) async {
      if (!ui.ImageFilter.isShaderFilterSupported) return;
      tester.view.physicalSize = const ui.Size(1080, 2400);
      tester.view.devicePixelRatio = _dpr;
      addTearDown(tester.view.reset);
      // Load first: the override's setter starts the loads in this test's
      // fake zone otherwise, whose futures never complete in the next test.
      await tester.runAsync(MorphGlassRenderer.precache);
      await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);
      RenderLiquidGlassLayer.debugAnalyticMode = AnalyticGeometryMode.always;
      RenderLiquidGlassLayer.debugAnalyticGeometry = analytic;
      addTearDown(() {
        RenderLiquidGlassLayer.debugAnalyticGeometry = null;
        RenderLiquidGlassLayer.debugAnalyticMode = null;
      });

      for (final glassCase in _cases) {
        if (_only.isNotEmpty && !_only.split(',').contains(glassCase.name)) {
          continue;
        }
        final shots = <bool, HarnessShot>{};
        final filters = <bool, int>{};
        for (final solid in [false, true]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(_scene(glassCase, solid: solid));
          await _settle(tester);
          final layer = _layers(tester).single;
          expect(layer.debugAnalytic, analytic, reason: glassCase.name);
          expect(layer.debugDrawsOverSolidBackdrop, solid);
          filters[solid] = _filters();
          shots[solid] = await _shoot(tester);
          expect(
            HarnessDiff.of(shots[solid]!, await _shoot(tester)).max,
            0,
            reason: '${glassCase.name} repeat',
          );
        }
        final compared = _compare(
          shots[false]!,
          shots[true]!,
          _covered([for (final s in glassCase.shapes) s.$1]),
        );
        if (_out.isNotEmpty) {
          Directory(_out).createSync(recursive: true);
          final harness = ShaderHarness(tester);
          final name =
              '$_out/${analytic ? 'analytic' : 'matte'}-${glassCase.name}';
          File(
            '$name.filter.png',
          ).writeAsBytesSync(await harness.png(shots[false]!));
          File(
            '$name.solid.png',
          ).writeAsBytesSync(await harness.png(shots[true]!));
        }
        // A summary line per case is the host run's output.
        // ignore: avoid_print
        print(
          'SOLID ${analytic ? 'analytic' : 'matte'} ${glassCase.name} '
          'max ${compared['max']} '
          'mean ${(compared['mean_covered']! as double).toStringAsFixed(4)} '
          'px>2 ${compared['over_2']} px>8 ${compared['over_8']} '
          'filters ${filters[false]} -> ${filters[true]}',
        );
        expect(filters[false], 1, reason: glassCase.name);
        expect(filters[true], 0, reason: glassCase.name);
        expect(compared['max'], lessThanOrEqualTo(2), reason: glassCase.name);
      }
    });
  }

  testWidgets('a solid layer follows its shapes and the compositor', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    await tester.runAsync(MorphGlassRenderer.precache);
    await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);
    final base = _cases[1];

    Widget moved(Offset shift, {required bool solid, Key? key}) => _scene(
      _Case(base.name, base.color, base.settings, [
        for (final (rect, shape, appearance, shadow) in base.shapes)
          (rect.shift(shift), shape, appearance, shadow),
      ]),
      solid: solid,
      key: key,
    );

    // One mount through a move, against fresh mounts of the backdrop path.
    const key = ValueKey('kept');
    await tester.pumpWidget(moved(Offset.zero, solid: true, key: key));
    await _settle(tester);
    for (final shift in [const Offset(13.3, 7.9), const Offset(-4.6, 30.15)]) {
      await tester.pumpWidget(moved(shift, solid: true, key: key));
      await _settle(tester);
      final kept = await _shoot(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(moved(shift, solid: false));
      await _settle(tester);
      final filter = await _shoot(tester);
      final compared = _compare(filter, kept, (x, y) => true);
      // ignore: avoid_print
      print('SOLID moved $shift $compared');
      expect(compared['max'], lessThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(moved(shift, solid: true, key: key));
      await _settle(tester);
    }

    // Turning the solid backdrop off in one mount returns to the filter.
    await tester.pumpWidget(moved(Offset.zero, solid: true, key: key));
    await _settle(tester);
    await tester.pumpWidget(moved(Offset.zero, solid: false, key: key));
    await _settle(tester);
    expect(_layers(tester).single.debugDrawsOverSolidBackdrop, isFalse);
    expect(_filters(), 1);
    final off = await _shoot(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(moved(Offset.zero, solid: false));
    await _settle(tester);
    expect(HarnessDiff.of(off, await _shoot(tester)).max, 0);
  });

  for (final brightness in Brightness.values) {
    testWidgets('a list section shades its buttons over its card '
        '(${brightness.name})', (WidgetTester tester) async {
      if (!ui.ImageFilter.isShaderFilterSupported) return;
      tester.view.physicalSize = const ui.Size(1080, 2400);
      tester.view.devicePixelRatio = _dpr;
      addTearDown(tester.view.reset);
      await tester.runAsync(MorphGlassRenderer.precache);
      await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);

      final shots = <bool, List<HarnessShot>>{};
      final filters = <bool, int>{};
      for (final solid in [false, true]) {
        debugMorphGlassStageSolidBackdrops = solid;
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          _section(brightness: brightness, controller: controller),
        );
        await _settle(tester, 10);
        final stages = [
          for (final layer in _layers(tester))
            if (layer.shapesWithGeometry.length == 3) layer,
        ];
        expect(stages, hasLength(2));
        for (final stage in stages) {
          expect(stage.debugDrawsOverSolidBackdrop, solid);
        }
        filters[solid] = _filters();
        if (!solid) {
          // The reference reads each section's own backdrop.
          final keys = {for (final f in _filterLayers()) f.backdropKey};
          expect(keys, hasLength(2));
        }
        final atRest = await _shootSection(tester);
        // A fractional scroll moves the sections on the compositor.
        controller.jumpTo(37.62);
        await _settle(tester);
        final scrolled = await _shootSection(tester);
        shots[solid] = [atRest, scrolled];
        // A held row's highlight sends its button into a layer of its own,
        // which reads its backdrop as before; the stage keeps the others.
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('More 1')),
        );
        await _settle(tester, 12);
        final held = [
          for (final layer in _layers(tester))
            if (layer.shapesWithGeometry.isNotEmpty) layer,
        ];
        expect([
          for (final layer in held)
            if (layer.debugDrawsOverSolidBackdrop)
              layer.shapesWithGeometry.length,
        ], solid ? unorderedEquals([3, 2]) : isEmpty);
        expect(_filters(), solid ? 1 : 3);
        await gesture.up();
        await _settle(tester);
        expect(_filters(), solid ? 0 : 2);
      }
      for (final (i, moment) in ['rest', 'scrolled'].indexed) {
        final compared = _compare(
          shots[false]![i],
          shots[true]![i],
          (x, y) => true,
        );
        if (_out.isNotEmpty) {
          Directory(_out).createSync(recursive: true);
          final harness = ShaderHarness(tester);
          final name = '$_out/section-${brightness.name}-$moment';
          File(
            '$name.filter.png',
          ).writeAsBytesSync(await harness.png(shots[false]![i]));
          File(
            '$name.solid.png',
          ).writeAsBytesSync(await harness.png(shots[true]![i]));
        }
        // ignore: avoid_print
        print(
          'SOLID section ${brightness.name} $moment $compared '
          'filters ${filters[false]} -> ${filters[true]}',
        );
        expect(compared['max'], lessThanOrEqualTo(2));
      }
      // The two stages' filters go; nothing else in the scene reads.
      expect(filters[false]! - filters[true]!, 2);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('an app container on its page color shades its buttons over '
        'it (${brightness.name})', (WidgetTester tester) async {
      if (!ui.ImageFilter.isShaderFilterSupported) return;
      tester.view.physicalSize = const ui.Size(1080, 2400);
      tester.view.devicePixelRatio = _dpr;
      addTearDown(tester.view.reset);
      await tester.runAsync(MorphGlassRenderer.precache);
      await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);

      final variants = <String, Color? Function(Color page)>{
        'none': (page) => null,
        'translucent': (page) => page.withValues(alpha: 0.5),
        'solid': (page) => page,
      };
      final shots = <String, HarnessShot>{};
      for (final MapEntry(key: name, value: solidBackdrop)
          in variants.entries) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          _cluster(brightness: brightness, solidBackdrop: solidBackdrop),
        );
        await _settle(tester, 10);
        final container = _layers(tester).single;
        expect(container.shapesWithGeometry, hasLength(4), reason: name);
        expect(
          container.debugDrawsOverSolidBackdrop,
          name == 'solid',
          reason: name,
        );
        expect(_filters(), name == 'solid' ? 0 : 1, reason: name);
        shots[name] = await _shootSection(tester, _clusterShot);
      }
      for (final name in ['translucent', 'solid']) {
        final compared = _compare(shots['none']!, shots[name]!, (x, y) => true);
        if (_out.isNotEmpty) {
          Directory(_out).createSync(recursive: true);
          final harness = ShaderHarness(tester);
          File(
            '$_out/cluster-${brightness.name}-$name.png',
          ).writeAsBytesSync(await harness.png(shots[name]!));
        }
        // ignore: avoid_print
        print('SOLID cluster ${brightness.name} $name $compared');
        expect(compared['max'], lessThanOrEqualTo(2), reason: name);
      }
    });
  }
}
