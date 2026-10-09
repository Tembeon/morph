// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// The A/B toggles the renderer's own geometry path.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/renderer.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show RenderLiquidGlassLayer;
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
  final rects = [for (final shape in glassCase.shapes) shape.rect.inflate(3)];
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
    if (_out.isNotEmpty) Directory(_out).createSync(recursive: true);
    final harness = ShaderHarness(tester);
    final dpr = harness.devicePixelRatio;

    bool layerAnalytic() => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .any((layer) => layer.debugAnalytic);

    final report = <String, Object>{};
    for (final glassCase in harnessCasesNamed(_only)) {
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
          glassCase.field == null && glassCase.name != 'mixed-models';
      expect(analytic, eligible, reason: glassCase.name);
      if (analytic) {
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

    // The matte path with the same transitions draws the same as fresh.
    RenderLiquidGlassLayer.debugAnalyticGeometry = false;
    final matteMoved = await fresh(2, moved);
    final compared = _compare(matteMoved, twoMoved, (x, y) => true);
    // ignore: avoid_print
    print('moved pair matte vs analytic $compared');
    expect(compared['mean_covered']! as double, lessThanOrEqualTo(0.5));
  });
}
