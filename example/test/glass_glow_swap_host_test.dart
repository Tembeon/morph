// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';
// The test drives the renderer's own layer.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/liquid_glass_glow.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/renderer.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show RenderLiquidGlassLayer;
import 'package:morph/src/widgets/glass_renderer.dart';

/// A frame that changes only a liquid layer's touch glow draws the new
/// glow without painting the layer, the same pixels a paint draws, through
/// its backdrop filter and over a solid backdrop, on the host's Impeller:
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/glass_glow_swap_host_test.dart
///
/// Without Impeller there is no glass and the test does nothing.
void main() {
  for (final solid in [false, true]) {
    _glowSwap(solid: solid);
  }
}

void _glowSwap({required bool solid}) {
  testWidgets('a glow-only frame draws the glow without a paint '
      '(${solid ? 'over a solid backdrop' : 'through the filter'})', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(600, 600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(GlassBuiltInPainter.precache);
    if (!MorphTheme.liquidGlassAvailable) return;

    final live = ChangeNotifier();
    final glows = ChangeNotifier();
    addTearDown(live.dispose);
    addTearDown(glows.dispose);
    LiquidGlassGlow? glow;
    const box = Rect.fromLTWH(20, 40, 96, 44);
    LiquidGlassGlow glowAt(double x) => LiquidGlassGlow(
      clip: RRect.fromRectAndRadius(box, const Radius.circular(22)),
      center: Offset(x, 62),
      radius: 30,
      gain: 0.4,
      wash: 0.05,
    );

    final boundary = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: _page,
          child: RepaintBoundary(
            key: boundary,
            child: LiquidGlassLayer.live(
              live: live,
              settingsOf: () => const LiquidGlassSettings(frost: 0),
              glowOf: () => glow,
              glows: glows,
              solidBackdrop: solid ? _page : null,
              child: Stack(
                children: [
                  Positioned.fromRect(
                    rect: box,
                    child: const LiquidGlass(
                      shape: LiquidRoundedSuperellipse(borderRadius: 22),
                      appearance: LiquidGlassAppearance.ios27RegularDark(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    final layer = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .single;
    expect(layer.debugDrawsOverSolidBackdrop, solid);

    Future<List<int>> shot() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await tester.runAsync(
        () => render.toImage(pixelRatio: 3),
      ))!;
      final data = (await tester.runAsync(image.toByteData))!;
      image.dispose();
      return data.buffer.asUint8List();
    }

    var previous = await shot();
    for (final x in [40.0, 60.0, 80.0]) {
      final paints = layer.debugPaintCount;
      glow = glowAt(x);
      glows.notifyListeners();
      await tester.pump(const Duration(milliseconds: 16));
      expect(layer.debugPaintCount, paints, reason: 'x $x');
      final swapped = await shot();
      layer.markNeedsPaint();
      await tester.pump(const Duration(milliseconds: 16));
      final painted = await shot();
      expect(swapped, isNot(equals(previous)), reason: 'x $x');
      expect(swapped, equals(painted), reason: 'x $x');
      previous = painted;
    }
    expect(layer.glow, glowAt(80));
  });
}

const Color _page = Color(0xFF406080);
