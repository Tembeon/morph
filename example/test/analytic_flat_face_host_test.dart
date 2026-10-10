// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// The A/B toggles the renderer's own analytic path.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/renderer.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show AnalyticGeometryMode, RenderLiquidGlassLayer;
import 'package:morph/widgets.dart';

import '../integration_test/support/shader_harness.dart';

/// The analytic shader's flat-face skip against the full distance solve
/// on the host: every liquid case of the shader harness, plus stretched,
/// rotated, overlapping and nested rounded superellipses, rendered with
/// the skip on and off through flutter_tester's Impeller. They must match
/// to the last bit.
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/analytic_flat_face_host_test.dart
///
/// Delete build/unit_test_assets after editing a shader include. Without
/// Impeller the test does nothing.
const String _only = String.fromEnvironment('SHADER_CASES');

/// One shape of a transformed scene, in the transform's own coordinates.
typedef _Shape = (ui.Rect rect, LiquidShape shape, LiquidGlassAppearance look);

/// A scene whose shapes sit under [transform] about the region's origin.
typedef _Scene = (
  String name,
  LiquidGlassSettings settings,
  Matrix4 transform,
  List<_Shape> shapes,
);

LiquidShape _rse(double radius) =>
    LiquidRoundedSuperellipse(borderRadius: radius);

const LiquidGlassAppearance _dark = LiquidGlassAppearance.ios27RegularDark();

/// Shapes under non-uniform scales and rotations (the bound's distance
/// scale), overlapping and nested (two boxes hold the pixel: no skip),
/// square-cornered and full-radius ones.
final List<_Scene> _scenes = [
  (
    'stretched',
    const LiquidGlassSettings(frost: 0),
    Matrix4.diagonal3Values(1.5, 0.75, 1),
    [
      (const ui.Rect.fromLTWH(10, 60, 200, 220), _rse(40), _dark),
      (const ui.Rect.fromLTWH(10, 400, 160, 44), _rse(22), _dark),
      (
        const ui.Rect.fromLTWH(20, 520, 180, 200),
        _rse(30),
        const LiquidGlassAppearance.ios27RegularDark(tint: Color(0xCC007AFF)),
      ),
    ],
  ),
  (
    'rotated',
    LiquidGlassSettings.ios27ToolbarDark(),
    Matrix4.translationValues(170, 60, 0)
        .multiplied(Matrix4.rotationZ(0.35))
        .multiplied(Matrix4.diagonal3Values(1.2, 0.9, 1)),
    [
      (
        const ui.Rect.fromLTWH(-60, 40, 180, 140),
        _rse(30),
        const LiquidGlassAppearance.ios27ToolbarDark(),
      ),
      (
        const ui.Rect.fromLTWH(-20, 280, 200, 160),
        _rse(48),
        const LiquidGlassAppearance.ios27ToolbarDark(),
      ),
    ],
  ),
  (
    'overlapping',
    const LiquidGlassSettings(frost: 0),
    Matrix4.identity(),
    [
      (const ui.Rect.fromLTWH(20, 40, 200, 200), _rse(40), _dark),
      (
        const ui.Rect.fromLTWH(120, 140, 200, 200),
        _rse(48),
        const LiquidGlassAppearance.ios27RegularDark(tint: Color(0x9934C759)),
      ),
      (const ui.Rect.fromLTWH(20, 380, 320, 240), _rse(36), _dark),
      (
        const ui.Rect.fromLTWH(120, 450, 90, 90),
        _rse(20),
        const LiquidGlassAppearance.ios27RegularDark(tint: Color(0xCCFF9500)),
      ),
    ],
  ),
  (
    'corners',
    const LiquidGlassSettings(frost: 0),
    Matrix4.identity(),
    [
      (const ui.Rect.fromLTWH(20, 30, 200, 150), _rse(0), _dark),
      (const ui.Rect.fromLTWH(60, 220, 260, 160), _rse(0.5), _dark),
      (const ui.Rect.fromLTWH(30, 420, 300, 120), _rse(60), _dark),
      (const ui.Rect.fromLTWH(100, 560, 160, 64), _rse(200), _dark),
    ],
  ),
];

Widget _sceneWidget(
  _Scene scene,
  ui.Image backdrop,
  double devicePixelRatio,
  GlobalKey boundary,
  Key key,
) {
  final (_, settings, transform, shapes) = scene;
  return Directionality(
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
                  scale: devicePixelRatio,
                  filterQuality: FilterQuality.none,
                  fit: BoxFit.none,
                  alignment: Alignment.topLeft,
                ),
              ),
              Positioned.fill(
                key: key,
                child: LiquidGlassLayer(
                  settings: settings,
                  child: Transform(
                    transform: transform,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final (rect, shape, look) in shapes)
                          Positioned.fromRect(
                            rect: rect,
                            child: LiquidGlass(
                              shape: shape,
                              appearance: look,
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
}

void main() {
  // Large cases shade analytically too.
  setUp(() => RenderLiquidGlassLayer.debugAnalyticMaxPixels = double.infinity);
  tearDown(() => RenderLiquidGlassLayer.debugAnalyticMaxPixels = null);

  testWidgets('the flat-face skip draws what the full solve draws', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    RenderLiquidGlassLayer.debugAnalyticMode = AnalyticGeometryMode.always;
    RenderLiquidGlassLayer.debugAnalyticGeometry = true;
    addTearDown(() {
      RenderLiquidGlassLayer.debugAnalyticGeometry = null;
      RenderLiquidGlassLayer.debugAnalyticMode = null;
      RenderLiquidGlassLayer.debugAnalyticFlatFace = true;
      RenderLiquidGlassLayer.debugAnalyticCapsule = null;
    });
    await tester.runAsync(MorphGlassRenderer.precache);
    await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);
    final harness = ShaderHarness(tester);
    final backdrop = await harness.backdrop();
    final dpr = harness.devicePixelRatio;
    final boundary = GlobalKey();

    bool layerAnalytic() => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .any((layer) => layer.debugAnalytic);

    Future<HarnessShot> shootScene(_Scene scene) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _sceneWidget(scene, backdrop, dpr, boundary, UniqueKey()),
      );
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await tester.runAsync(
        () => render.toImage(pixelRatio: dpr),
      ))!;
      final data = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      image.dispose();
      return HarnessShot(image.width, image.height, data!.buffer.asUint8List());
    }

    var worst = 0;
    var compared = 0;
    void check(String name, HarnessShot solved, HarnessShot skipped) {
      final diff = HarnessDiff.of(solved, skipped);
      worst = math.max(worst, diff.max);
      compared++;
      // A summary line per case is the host run's output.
      // ignore: avoid_print
      print('$name flat face vs solve max ${diff.max} px ${diff.pixels}');
      expect(diff.max, 0, reason: name);
    }

    for (final glassCase in harnessCasesNamed(_only)) {
      if (glassCase.fake) continue;
      RenderLiquidGlassLayer.debugAnalyticFlatFace = false;
      await harness.show(glassCase, ShaderVariant.candidate);
      final analytic = layerAnalytic();
      final solved = await harness.shoot();
      RenderLiquidGlassLayer.debugAnalyticFlatFace = true;
      await harness.show(glassCase, ShaderVariant.candidate);
      expect(layerAnalytic(), analytic, reason: glassCase.name);
      check(glassCase.name, solved, await harness.shoot());
    }
    for (final capsule in [false, true]) {
      RenderLiquidGlassLayer.debugAnalyticCapsule = capsule;
      for (final scene in _scenes) {
        final name = '${scene.$1}${capsule ? '-capsule' : ''}';
        if (_only.isNotEmpty && !_only.split(',').contains(name)) continue;
        RenderLiquidGlassLayer.debugAnalyticFlatFace = false;
        final solved = await shootScene(scene);
        expect(layerAnalytic(), isTrue, reason: name);
        RenderLiquidGlassLayer.debugAnalyticFlatFace = true;
        check(name, solved, await shootScene(scene));
      }
    }
    // ignore: avoid_print
    print('flat face: $compared scenes, max channel difference $worst');
  });
}
