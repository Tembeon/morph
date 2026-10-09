// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// The A/B toggles the renderer's own geometry path.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/glass_field.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/internal/flutter_gpu_geometry_renderer.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/renderer.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show RenderLiquidGlassLayer;
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/widgets.dart';

import '../integration_test/support/shader_harness.dart';

/// The analytic geometry against the geometry matte on the host: every
/// liquid case of the shader harness rendered both ways through
/// flutter_tester's Impeller and compared pixel by pixel.
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/analytic_geometry_host_test.dart
///
/// Delete build/unit_test_assets after editing a shader include (see
/// shader_parity_host_test.dart). Without Impeller the test does nothing.
/// `--dart-define=AUDIT_OUT=<dir>` keeps the report and, per case, the
/// matte, analytic and amplified difference PNGs.
const String _only = String.fromEnvironment('SHADER_CASES');

const String _out = String.fromEnvironment('AUDIT_OUT');

/// The covered region of a case: its shapes grown by the contour and the
/// antialiasing, in device pixels.
bool Function(int x, int y) _covered(HarnessCase glassCase, double dpr) {
  var rects = [for (final shape in glassCase.shapes) shape.rect.inflate(3)];
  // A fused body covers its necks too: the box around its shapes.
  if (glassCase.field is GlassBoxField) {
    rects = [rects.reduce((a, b) => a.expandToInclude(b))];
  }
  return (x, y) {
    final point = ui.Offset((x + 0.5) / dpr, (y + 0.5) / dpr);
    return rects.any((rect) => rect.contains(point));
  };
}

Map<String, Object> _compare(
  HarnessShot matte,
  HarnessShot analytic,
  bool Function(int x, int y) covered,
) {
  var max = 0;
  var sum = 0;
  var coveredPixels = 0;
  var over2 = 0;
  var over8 = 0;
  for (var p = 0; p < matte.width * matte.height; p++) {
    var pixelMax = 0;
    var pixelSum = 0;
    for (var c = 0; c < 4; c++) {
      final d = (matte.bytes[p * 4 + c] - analytic.bytes[p * 4 + c]).abs();
      if (d > pixelMax) pixelMax = d;
      if (c < 3) pixelSum += d;
    }
    if (pixelMax > max) max = pixelMax;
    if (pixelMax > 2) over2++;
    if (pixelMax > 8) over8++;
    if (covered(p % matte.width, p ~/ matte.width)) {
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

/// The difference of two shots, x16 and opaque, for the eye.
HarnessShot _amplified(HarnessShot a, HarnessShot b) {
  final bytes = Uint8List(a.bytes.length);
  for (var p = 0; p < a.width * a.height; p++) {
    for (var c = 0; c < 3; c++) {
      final d = (a.bytes[p * 4 + c] - b.bytes[p * 4 + c]).abs() * 16;
      bytes[p * 4 + c] = d > 255 ? 255 : d;
    }
    bytes[p * 4 + 3] = 255;
  }
  return HarnessShot(a.width, a.height, bytes);
}

/// A fused body of rounded boxes at [rects] with corner [radius] (a
/// capsule when null), merged by a glass container with [spacing], as a
/// liquid layer receives it with analytic geometry: the field is a
/// [GlassBoxField], fused on the CPU only when the matte path reads it.
HarnessCase _fusedCase(
  String name,
  double spacing,
  List<ui.Rect> rects, {
  double? radius,
  List<LiquidGlassAppearance>? appearances,
}) {
  double r(ui.Rect rect) => radius ?? rect.shortestSide / 2;
  final boxes = [
    for (final rect in rects)
      ui.RRect.fromRectAndRadius(rect, ui.Radius.circular(r(rect))),
  ];
  return HarnessCase(
    name,
    const LiquidGlassSettings(frost: 0),
    [
      for (final (i, rect) in rects.indexed)
        HarnessShape(
          rect,
          LiquidRoundedSuperellipse(borderRadius: r(rect)),
          appearances?[i] ?? const LiquidGlassAppearance.ios27RegularDark(),
        ),
    ],
    field: morphGlassOutlineField(
      morphGlassContainerBoxOutline(boxes, spacing),
    ),
  );
}

/// Capsule pairs, rows and steps over the three backdrop bands, a spacing
/// sweep and seeded rows.
List<HarnessCase> _fusedCases() {
  ui.Rect row(double left, double top, double width, [double height = 44]) =>
      ui.Rect.fromLTWH(left, top, width, height);
  final cases = [
    _fusedCase('fused-pair-s12', 12, [row(40, 100, 120), row(166, 100, 120)]),
    _fusedCase('fused-row3-s12', 12, [
      row(20, 300, 90),
      row(118, 300, 90),
      row(216, 300, 90),
    ]),
    _fusedCase('fused-row4-s16', 16, [
      row(20, 500, 70),
      row(100, 500, 70),
      row(180, 500, 70),
      row(260, 500, 70),
    ]),
    _fusedCase('fused-neck-s12', 12, [row(40, 240, 120), row(165, 240, 120)]),
    _fusedCase('fused-neck-s24', 24, [row(40, 330, 120), row(170, 330, 120)]),
    _fusedCase('fused-stepped-s20', 20, [
      row(40, 290, 140),
      row(190, 310, 140),
    ]),
    _fusedCase('fused-cards-s12', 12, [
      row(30, 120, 140, 90),
      row(178, 120, 140, 90),
    ], radius: 14),
    _fusedCase(
      'fused-tint-pair-s12',
      12,
      [row(40, 480, 120), row(166, 480, 120)],
      appearances: const [
        LiquidGlassAppearance.ios27RegularDark(),
        LiquidGlassAppearance.ios27RegularDark(tint: ui.Color(0x9934C759)),
      ],
    ),
    for (final spacing in [2.0, 6.0, 12.0, 18.0, 24.0])
      _fusedCase('fused-sweep-s${spacing.round()}', spacing, [
        row(40, 480, 130),
        row(170 + spacing * 0.6, 480, 130),
      ]),
  ];
  for (final seed in [1, 2, 3]) {
    final random = math.Random(seed);
    final count = 2 + random.nextInt(3);
    final spacing = 4 + random.nextDouble() * 20;
    final top = 60 + random.nextDouble() * 500;
    final rects = <ui.Rect>[];
    var left = 12.0;
    for (var i = 0; i < count; i++) {
      final width = 45 + random.nextDouble() * 20;
      rects.add(row(left, top + random.nextDouble() * 6, width, 36));
      left += width + spacing * (0.2 + random.nextDouble() * 0.7);
    }
    cases.add(_fusedCase('fused-seed$seed', spacing, rects));
  }
  return cases;
}

/// The mean difference a merged-box body may show against its sampled
/// field over the covered pixels: the field's 4 pt grid bends the normals
/// along curves, which striped and noisy backdrops amplify (host run
/// 2026-10-09: up to 9.1 over noise, 0.2 - 0.6 over the gradient).
const double _fusedMeanBound = 12;

/// The mean difference a merged-box body may show against the package's
/// fusion sampled eight times finer than it ships (host run 2026-10-09:
/// 0.07 - 0.12 over the gradient, 0.32 and 0.51 over the stripes).
const double _fineMeanBound = 0.75;

void main() {
  testWidgets('analytic geometry against the matte on the host', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    addTearDown(() => RenderLiquidGlassLayer.debugAnalyticGeometry = null);
    await tester.runAsync(MorphGlassRenderer.precache);
    await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);
    if (_out.isNotEmpty) Directory(_out).createSync(recursive: true);
    final harness = ShaderHarness(tester);
    final dpr = harness.devicePixelRatio;

    bool layerAnalytic() => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .any((layer) => layer.debugAnalytic);

    final report = <String, Object>{};
    final fused = [
      for (final c in _fusedCases())
        if (_only.isEmpty || _only.split(',').contains(c.name)) c,
    ];
    for (final glassCase in [...harnessCasesNamed(_only), ...fused]) {
      if (glassCase.fake) continue;
      RenderLiquidGlassLayer.debugAnalyticGeometry = false;
      await harness.show(glassCase, ShaderVariant.candidate);
      expect(layerAnalytic(), isFalse, reason: glassCase.name);
      final matte = await harness.shoot();
      RenderLiquidGlassLayer.debugAnalyticGeometry = true;
      await harness.show(glassCase, ShaderVariant.candidate);
      final analytic = layerAnalytic();
      final shot = await harness.shoot();
      final repeat = await harness.shoot();
      final entry = {
        'analytic': analytic,
        'repeat': HarnessDiff.of(shot, repeat).max,
        ..._compare(matte, shot, _covered(glassCase, dpr)),
      };
      report[glassCase.name] = entry;
      // A summary line per case is the host run's output.
      // ignore: avoid_print
      print(
        '${glassCase.name} analytic $analytic max ${entry['max']} '
        'mean ${(entry['mean_covered']! as double).toStringAsFixed(4)} '
        'px>2 ${entry['over_2']} px>8 ${entry['over_8']}',
      );
      if (_out.isNotEmpty) {
        final name = '$_out/${glassCase.name}';
        File('$name.matte.png').writeAsBytesSync(await harness.png(matte));
        File('$name.analytic.png').writeAsBytesSync(await harness.png(shot));
        File(
          '$name.diff.png',
        ).writeAsBytesSync(await harness.png(_amplified(matte, shot)));
      }
      expect(entry['repeat'], 0, reason: glassCase.name);
      final eligible =
          (glassCase.field == null || glassCase.field is GlassBoxField) &&
          glassCase.name != 'mixed-models';
      expect(analytic, eligible, reason: glassCase.name);
      if (analytic && glassCase.field is GlassBoxField) {
        // The sampled field itself strays from the exact shapes along
        // curves (see the far-apart test), so this is the field's error.
        expect(
          entry['mean_covered']! as double,
          lessThanOrEqualTo(_fusedMeanBound),
          reason: glassCase.name,
        );
      } else if (analytic) {
        expect(
          entry['mean_covered']! as double,
          lessThanOrEqualTo(0.5),
          reason: glassCase.name,
        );
      } else {
        expect(entry['max'], 0, reason: glassCase.name);
      }
    }
    if (_out.isNotEmpty) {
      File(
        '$_out/analytic_report.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    }
  });

  testWidgets('analytic frames fall back to the matte and back, and move', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    addTearDown(() => RenderLiquidGlassLayer.debugAnalyticGeometry = null);
    await tester.runAsync(MorphGlassRenderer.precache);
    await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);
    final harness = ShaderHarness(tester);
    final backdrop = await harness.backdrop();
    final boundary = GlobalKey();

    Widget scene(int count, ui.Offset shift, {Key? key}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: boundary,
          child: SizedBox.fromSize(
            size: harnessRegion,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RawImage(
                    image: backdrop,
                    scale: harness.devicePixelRatio,
                    filterQuality: FilterQuality.none,
                    fit: BoxFit.none,
                    alignment: Alignment.topLeft,
                  ),
                ),
                Positioned.fill(
                  key: key,
                  child: LiquidGlassLayer(
                    settings: const LiquidGlassSettings(frost: 0),
                    child: Transform.translate(
                      offset: shift,
                      child: Stack(
                        children: [
                          for (var i = 0; i < count; i++)
                            Positioned(
                              left: 20.0 + (i % 3) * 110,
                              top: 40.0 + (i ~/ 3) * 180,
                              width: 96,
                              height: 44,
                              child: LiquidGlass(
                                shape: const LiquidRoundedSuperellipse(
                                  borderRadius: 22,
                                ),
                                appearance:
                                    LiquidGlassAppearance.ios27RegularDark(
                                      tint: i.isEven
                                          ? const Color(0x00000000)
                                          : const Color(0x9934C759),
                                    ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Future<void> settle() async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<HarnessShot> shoot() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await tester.runAsync(
        () => render.toImage(pixelRatio: harness.devicePixelRatio),
      ))!;
      final data = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      image.dispose();
      return HarnessShot(image.width, image.height, data!.buffer.asUint8List());
    }

    Future<HarnessShot> fresh(int count, ui.Offset shift) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(scene(count, shift, key: UniqueKey()));
      await settle();
      return shoot();
    }

    bool layerAnalytic() => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .any((layer) => layer.debugAnalytic);

    RenderLiquidGlassLayer.debugAnalyticGeometry = true;
    final two = await fresh(2, ui.Offset.zero);
    expect(layerAnalytic(), isTrue);
    final nine = await fresh(9, ui.Offset.zero);
    expect(layerAnalytic(), isFalse);
    const moved = ui.Offset(13.3, 7.9);
    final twoMoved = await fresh(2, moved);

    // One mount through the transitions.
    const key = ValueKey('kept');
    await tester.pumpWidget(scene(2, ui.Offset.zero, key: key));
    await settle();
    expect(layerAnalytic(), isTrue);
    await tester.pumpWidget(scene(9, ui.Offset.zero, key: key));
    await tester.pump();
    expect(layerAnalytic(), isFalse);
    await settle();
    expect(HarnessDiff.of(await shoot(), nine).max, 0);
    await tester.pumpWidget(scene(2, ui.Offset.zero, key: key));
    await tester.pump();
    expect(layerAnalytic(), isTrue);
    await settle();
    expect(HarnessDiff.of(await shoot(), two).max, 0);
    // A uniform translation of the shapes moves the analytic shapes.
    await tester.pumpWidget(scene(2, moved, key: key));
    await settle();
    expect(layerAnalytic(), isTrue);
    expect(HarnessDiff.of(await shoot(), twoMoved).max, lessThanOrEqualTo(1));

    // Flipping the override in one mount takes effect on the next frame.
    RenderLiquidGlassLayer.debugAnalyticGeometry = false;
    await tester.pump();
    expect(layerAnalytic(), isFalse);
    await settle();
    final keptMatte = await shoot();
    RenderLiquidGlassLayer.debugAnalyticGeometry = true;
    await tester.pump();
    expect(layerAnalytic(), isTrue);
    await settle();
    expect(HarnessDiff.of(await shoot(), twoMoved).max, lessThanOrEqualTo(1));

    // The matte path with the same transitions draws the same as fresh.
    RenderLiquidGlassLayer.debugAnalyticGeometry = false;
    final matteMoved = await fresh(2, moved);
    expect(HarnessDiff.of(keptMatte, matteMoved).max, lessThanOrEqualTo(1));
    final compared = _compare(matteMoved, twoMoved, (x, y) => true);
    // ignore: avoid_print
    print('moved pair matte vs analytic $compared');
    expect(compared['mean_covered']! as double, lessThanOrEqualTo(0.5));
  });

  testWidgets('merged boxes far apart shade as their own shapes', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    addTearDown(() => RenderLiquidGlassLayer.debugAnalyticGeometry = null);
    await tester.runAsync(MorphGlassRenderer.precache);
    await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);
    final harness = ShaderHarness(tester);
    final dpr = harness.devicePixelRatio;
    final configs = [
      (
        'capsules',
        22.0,
        [
          const ui.Rect.fromLTWH(40, 100, 120, 44),
          const ui.Rect.fromLTWH(190, 100, 120, 44),
        ],
      ),
      (
        'cards',
        14.0,
        [
          const ui.Rect.fromLTWH(30, 300, 140, 90),
          const ui.Rect.fromLTWH(200, 300, 130, 90),
        ],
      ),
    ];
    for (final (name, radius, rects) in configs) {
      final shapes = [
        for (final rect in rects)
          HarnessShape(
            rect,
            LiquidRoundedRectangle(borderRadius: radius),
            const LiquidGlassAppearance.ios27RegularDark(),
          ),
      ];
      final separate = HarnessCase(
        'far-$name',
        const LiquidGlassSettings(frost: 0),
        shapes,
      );
      final merged = HarnessCase(
        'far-$name',
        const LiquidGlassSettings(frost: 0),
        shapes,
        field: morphGlassOutlineField(
          morphGlassContainerBoxOutline([
            for (final rect in rects)
              ui.RRect.fromRectAndRadius(rect, ui.Radius.circular(radius)),
          ], 12),
        ),
      );
      Future<HarnessShot> shot(HarnessCase c, {required bool analytic}) async {
        RenderLiquidGlassLayer.debugAnalyticGeometry = analytic;
        await harness.show(c, ShaderVariant.candidate);
        return harness.shoot();
      }

      final exact = await shot(separate, analytic: true);
      final shader = await shot(merged, analytic: true);
      final field = await shot(merged, analytic: false);
      final covered = _covered(merged, dpr);
      final analyticVsExact = _compare(exact, shader, covered);
      final fieldVsExact = _compare(exact, field, covered);
      // ignore: avoid_print
      print('far-$name merged analytic vs own shapes $analyticVsExact');
      // ignore: avoid_print
      print('far-$name sampled field vs own shapes $fieldVsExact');
      if (_out.isNotEmpty) {
        final out = '$_out/far-$name';
        File(
          '$out.analytic-vs-shapes.diff.png',
        ).writeAsBytesSync(await harness.png(_amplified(exact, shader)));
        File(
          '$out.field-vs-shapes.diff.png',
        ).writeAsBytesSync(await harness.png(_amplified(exact, field)));
      }
      expect(
        analyticVsExact['mean_covered']! as double,
        lessThanOrEqualTo(0.05),
      );
      expect(
        analyticVsExact['mean_covered']! as double,
        lessThanOrEqualTo(fieldVsExact['mean_covered']! as double),
      );
    }
  });

  testWidgets('merged necks against a fine sampled field', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    addTearDown(() => RenderLiquidGlassLayer.debugAnalyticGeometry = null);
    addTearDown(() {
      debugMorphFusionStep = 2;
      debugClearMorphGlassOutlines();
    });
    await tester.runAsync(MorphGlassRenderer.precache);
    await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);
    final harness = ShaderHarness(tester);
    final dpr = harness.devicePixelRatio;
    const names = {
      'fused-pair-s12',
      'fused-neck-s12',
      'fused-neck-s24',
      'fused-stepped-s20',
      'fused-row3-s12',
      'fused-cards-s12',
    };
    for (final merged in _fusedCases()) {
      if (!names.contains(merged.name)) continue;
      final boxes = (merged.field! as GlassBoxField).boxes;
      final spacing = (merged.field! as GlassBoxField).spacing;
      // The package's fusion on a grid eight times finer: a 0.25 pt trace
      // and a 0.5 pt field (four times finer leaves 1.1 on the cards over
      // the stripes, where the field smears the normal's turn across a
      // corner's diagonal; the difference halves with each refinement).
      debugMorphFusionStep = 0.25;
      debugClearMorphGlassOutlines();
      final fine = HarnessCase(
        merged.name,
        merged.settings,
        merged.shapes,
        field: morphGlassOutlineField(
          morphGlassContainerOutline(boxes, spacing),
        ),
      );
      debugMorphFusionStep = 2;
      debugClearMorphGlassOutlines();
      RenderLiquidGlassLayer.debugAnalyticGeometry = false;
      await harness.show(fine, ShaderVariant.candidate);
      final fineShot = await harness.shoot();
      RenderLiquidGlassLayer.debugAnalyticGeometry = true;
      await harness.show(merged, ShaderVariant.candidate);
      final analytic = await harness.shoot();
      final compared = _compare(fineShot, analytic, _covered(merged, dpr));
      // The comparison is the test's output.
      // ignore: avoid_print
      print('${merged.name} analytic vs fine field $compared');
      if (_out.isNotEmpty) {
        File(
          '$_out/${merged.name}.fine.png',
        ).writeAsBytesSync(await harness.png(fineShot));
        File(
          '$_out/${merged.name}.fine.diff.png',
        ).writeAsBytesSync(await harness.png(_amplified(fineShot, analytic)));
      }
      expect(
        compared['mean_covered']! as double,
        lessThanOrEqualTo(_fineMeanBound),
        reason: merged.name,
      );
    }
  });

  testWidgets('an analytic layer hands its matte textures back', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    addTearDown(() => RenderLiquidGlassLayer.debugAnalyticGeometry = null);
    await tester.runAsync(MorphGlassRenderer.precache);
    await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);
    final harness = ShaderHarness(tester);
    final glassCase = harnessCases.firstWhere((c) => c.name == 'tint-pair');

    Future<void> frames(int count) async {
      for (var i = 0; i < count; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    RenderLiquidGlassLayer layer() => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .single;

    RenderLiquidGlassLayer.debugAnalyticGeometry = false;
    await harness.show(glassCase, ShaderVariant.candidate);
    final matte = await harness.shoot();
    final renderer = layer().gpuGeometryRenderer!;
    expect(renderer.holdsOutput, isTrue);
    final releases = RenderLiquidGlassLayer.debugMatteReleases;
    final textures = FlutterGpuGeometryRenderer.debugActiveGeometryTextureCount;

    // Alternating frames keep the textures.
    for (var i = 0; i < 6; i++) {
      RenderLiquidGlassLayer.debugAnalyticGeometry = i.isEven;
      await frames(1);
    }
    expect(RenderLiquidGlassLayer.debugMatteReleases, releases);

    RenderLiquidGlassLayer.debugAnalyticGeometry = true;
    await frames(6);
    expect(layer().debugAnalytic, isTrue);
    expect(renderer.holdsOutput, isFalse);
    expect(RenderLiquidGlassLayer.debugMatteReleases, releases + 1);
    expect(
      FlutterGpuGeometryRenderer.debugActiveGeometryTextureCount,
      lessThan(textures),
    );

    RenderLiquidGlassLayer.debugAnalyticGeometry = false;
    await frames(6);
    expect(layer().debugAnalytic, isFalse);
    expect(renderer.holdsOutput, isTrue);
    expect(HarnessDiff.of(await harness.shoot(), matte).max, 0);
  });
}
