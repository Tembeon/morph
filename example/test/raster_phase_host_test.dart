// ignore_for_file: invalid_use_of_internal_member

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
// The test reads which geometry path the renderer takes.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show RenderLiquidGlassLayer;
import 'package:morph/widgets.dart';

/// Glass container members against their own layers on the host's
/// Impeller, at origins on and around a texel edge of the matte:
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/raster_phase_host_test.dart
///
/// Without Impeller there is no liquid tier and the test does nothing.
void main() {
  testWidgets('container members draw their own layers at raster ties', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(600, 600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(MorphGlassRenderer.precache);
    if (!MorphGlassRenderer.liquidAvailable) return;
    if (RenderLiquidGlassLayer.analyticGeometryEnabled) {
      await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);
    }
    final boundary = GlobalKey();
    Future<Uint8List> shot(double top, {required bool container}) async {
      final buttons = Stack(
        children: [
          Positioned(
            left: 20 + 1 / 6,
            top: top,
            width: 80,
            height: 44,
            child: MorphGlassButton(onPressed: () {}, child: const Text('a')),
          ),
          Positioned(
            left: 110,
            top: 20,
            width: 60,
            height: 44,
            child: MorphGlassButton(onPressed: () {}, child: const Text('b')),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(platform: TargetPlatform.iOS, brightness: .dark),
          home: MorphAdaptiveGlass(
            tier: MorphGlassTier.liquid,
            child: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: const Color(0xFF406080),
                child: container
                    ? MorphGlassContainer(child: buttons)
                    : buttons,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => render.toImage(pixelRatio: 3));
      final data = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      image!.dispose();
      return data!.buffer.asUint8List();
    }

    // Analytic frames evaluate every shape where it is: they have no matte
    // grid to share, so a member's rim matches its own layer's within the
    // rasterization of the two passes (NEAR, glass-renderer.md "Glass
    // container") instead of bit for bit.
    final analytic = RenderLiquidGlassLayer.analyticGeometryEnabled;
    final worstAt = <double, int>{};
    for (final device in <double>[
      60.49,
      60.499,
      60.4999,
      60.5 - 1e-9,
      60.5,
      60.5 + 1e-9,
      60.500003,
      60.5001,
      60.51,
    ]) {
      final own = await shot(device / 3, container: false);
      final shared = await shot(device / 3, container: true);
      var worst = 0;
      for (var i = 0; i < own.length; i++) {
        final d = (own[i] - shared[i]).abs();
        if (d > worst) worst = d;
      }
      worstAt[device] = worst;
    }
    // The comparison per origin is the test's output.
    // ignore: avoid_print
    print('analytic $analytic worst channel step per origin $worstAt');
    for (final MapEntry(key: device, value: worst) in worstAt.entries) {
      expect(
        worst,
        lessThanOrEqualTo(analytic ? 1 : 0),
        reason: 'origin at $device device px',
      );
    }
  });
}
