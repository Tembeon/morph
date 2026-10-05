import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// Liquid glass paints nothing outside its shape: around a resting glass
/// button and a prominent one over black, every pixel between the shape's
/// contour and its filter clip stays black.
///
/// Guards the Vulkan regression on the Pixel 6a (Mali-G78), where the
/// final pass decoded every exterior pixel of the matte as lying on the
/// silhouette and drew half the glass over the whole filter clip. Run it
/// on the device with `flutter test -d` and the device's serial; it needs
/// the liquid tier.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('liquid glass leaves its exterior untouched', (
    WidgetTester tester,
  ) async {
    await MorphGlassRenderer.precache();
    expect(MorphGlassRenderer.liquidAvailable, isTrue);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark),
        home: MorphAdaptiveGlass(
          tier: MorphGlassTier.liquid,
          child: BackdropGroup(
            child: MorphScope(
              child: RepaintBoundary(
                key: boundary,
                child: ColoredBox(
                  color: const Color(0xFF000000),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MorphGlassButton(
                          key: const Key('plain'),
                          onPressed: () {},
                          child: const Text('Button'),
                        ),
                        const SizedBox(height: 40),
                        MorphGlassButton(
                          key: const Key('prominent'),
                          onPressed: () {},
                          tint: const Color(0xFF007AFF),
                          child: const Text('Prominent'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    final ratio = tester.view.devicePixelRatio;
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final origin = render.localToGlobal(Offset.zero);
    final image = await tester.runAsync(
      () => render.toImage(pixelRatio: ratio),
    );
    final bytes = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final width = image!.width;
    final height = image.height;

    for (final name in ['plain', 'prominent']) {
      final shape = tester.getRect(find.byKey(Key(name))).shift(-origin);
      final outer = shape.inflate(16);
      var lit = 0;
      var worst = 0;
      for (var y = (outer.top * ratio).floor(); y < outer.bottom * ratio; y++) {
        for (
          var x = (outer.left * ratio).floor();
          x < outer.right * ratio;
          x++
        ) {
          if (x < 0 || y < 0 || x >= width || y >= height) continue;
          final point = Offset(x + 0.5, y + 0.5) / ratio;
          if (shape.inflate(3).contains(point)) continue;
          final i = (y * width + x) * 4;
          final channel = [
            bytes!.getUint8(i),
            bytes.getUint8(i + 1),
            bytes.getUint8(i + 2),
          ].reduce((a, b) => a > b ? a : b);
          if (channel > worst) worst = channel;
          if (channel > 4) lit++;
        }
      }
      expect(lit, 0, reason: '$name: $lit lit exterior pixels, max $worst');
    }
  });
}
