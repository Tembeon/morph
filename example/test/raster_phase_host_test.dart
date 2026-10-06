import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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
      expect(worst, 0, reason: 'origin at $device device px');
    }
  });
}
