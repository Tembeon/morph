// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show RenderLiquidGlassLayer;
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/glass_tier.dart';

/// A press in a container over a solid backdrop leaves the glass further
/// down the page, over a picture in the same backdrop group, as it was,
/// on the host's Impeller:
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/container_press_backdrop_host_test.dart
///
/// The gallery's Glass buttons page: a pressed button leaves its
/// container and draws a layer of its own. Read from the group's one
/// backdrop copy, that layer would be the group's first reader, above the
/// picture, and every glass over the picture would show the page instead
/// until the button settled back. Without Impeller the test does nothing.
void main() {
  testWidgets('a pressed member of a solid container moves no backdrop copy', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(900, 1200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(GlassBuiltInPainter.precache);
    if (!MorphTheme.liquidGlassAvailable) return;

    const page = Color(0xFF1C1C1E);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: GlassAdaptiveScope(
          renderer: const GlassBuiltInPainter(),
          tier: MorphGlassTier.liquid,
          child: BackdropGroup(
            child: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: page,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: MorphGlassContainer(
                        solidBackdrop: page,
                        child: SizedBox(
                          width: 120,
                          height: 44,
                          child: MorphGlassButton(
                            onPressed: () {},
                            child: const Text('Top'),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      height: 160,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF1B3B6F), Color(0xFFF2A65A)],
                        ),
                      ),
                      padding: const EdgeInsets.all(40),
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: 120,
                        height: 44,
                        child: MorphGlassButton.clear(
                          onPressed: () {},
                          child: const Text('Over'),
                        ),
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

    Future<void> frames(int count) async {
      for (var i = 0; i < count; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    final over = tester.getRect(find.text('Over')).inflate(30);
    Future<Uint8List> shot() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await tester.runAsync(
        () => render.toImage(pixelRatio: 3),
      ))!;
      final data = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      final width = image.width;
      image.dispose();
      final all = data.buffer.asUint8List();
      return Uint8List.fromList([
        for (var y = (over.top * 3).round(); y < (over.bottom * 3).round(); y++)
          ...all.sublist(
            (y * width + (over.left * 3).round()) * 4,
            (y * width + (over.right * 3).round()) * 4,
          ),
      ]);
    }

    await frames(30);
    final rest = await shot();
    final layers = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .length;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Top')),
    );
    var own = 0;
    for (var frame = 0; frame < 24; frame++) {
      if (frame == 12) await gesture.up();
      await frames(1);
      own = own > 0
          ? own
          : tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().length -
                layers;
      final now = await shot();
      var worst = 0;
      for (var i = 0; i < rest.length; i++) {
        final d = (now[i] - rest[i]).abs();
        if (d > worst) worst = d;
      }
      expect(worst, lessThanOrEqualTo(1), reason: 'frame $frame');
    }
    // The press took the button out of its container into a layer of its
    // own, the case under test.
    expect(own, greaterThan(0));
  });
}
