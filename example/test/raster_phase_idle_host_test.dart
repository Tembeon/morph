// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/pass/final_pass.dart';
import 'package:morph/morph.dart';
// The test drives the renderer's own layer.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/renderer.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show AnalyticGeometryMode, RenderLiquidGlassLayer;
import 'package:morph/src/widgets/glass_renderer.dart';

/// A resting liquid layer that holds a matte lets the app go idle, on the
/// host's Impeller:
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/raster_phase_idle_host_test.dart
///
/// Without Impeller there is no matte and the test does nothing.
void main() {
  Widget scene({double left = 20, double shift = 0}) => Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: const Color(0xFF406080),
      child: Transform.translate(
        offset: Offset(0, shift),
        child: RepaintBoundary(
          child: LiquidGlassLayer(
            settings: const LiquidGlassSettings(frost: 0),
            child: Stack(
              children: [
                Positioned(
                  left: left,
                  top: 40,
                  width: 96,
                  height: 44,
                  child: const LiquidGlass(
                    shape: LiquidRoundedSuperellipse(borderRadius: 22),
                    appearance: LiquidGlassAppearance.ios27RegularDark(),
                    child: SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> frames(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  for (final mode in [
    (analytic: false, label: 'matte'),
    (analytic: true, label: 'analytic changes'),
  ]) {
    testWidgets('a resting ${mode.label} layer asks for no frame', (
      WidgetTester tester,
    ) async {
      if (!ui.ImageFilter.isShaderFilterSupported) return;
      tester.view.physicalSize = const ui.Size(600, 600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      addTearDown(() {
        RenderLiquidGlassLayer.debugAnalyticGeometry = null;
        RenderLiquidGlassLayer.debugAnalyticMode = null;
      });
      await tester.runAsync(GlassBuiltInPainter.precache);
      if (!MorphTheme.liquidGlassAvailable) return;
      if (mode.analytic) {
        await tester.runAsync(GlassFinalPass.precacheAnalyticShaders);
        RenderLiquidGlassLayer.debugAnalyticMode = AnalyticGeometryMode.changes;
      }
      RenderLiquidGlassLayer.debugAnalyticGeometry = mode.analytic;

      await tester.pumpWidget(scene());
      await frames(tester, 6);
      final layer = tester.allRenderObjects
          .whereType<RenderLiquidGlassLayer>()
          .toSet()
          .single;
      expect(layer.debugGeometryImage, isNotNull);
      expect(tester.binding.hasScheduledFrame, isFalse);

      // A move settles too: the raster-phase check runs once after it.
      await tester.pumpWidget(scene(left: 20.4));
      await frames(tester, 6);
      expect(tester.binding.hasScheduledFrame, isFalse);

      // Compositor-only motion: an ancestor moves the layer above its
      // repaint boundary, then stops.
      for (var i = 1; i <= 4; i++) {
        await tester.pumpWidget(scene(left: 20.4, shift: i / 7));
      }
      await frames(tester, 6);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }
}
