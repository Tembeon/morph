// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/renderer.dart'
    show GlassStrategy, RenderGlassMember;
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
  const page = Color(0xFF1C1C1E);

  // A solid container over the page, then a picture with clear glass, in
  // one backdrop group; the container's button drawn under [scale].
  Widget scene(GlobalKey boundary, {double scale = 1}) => MaterialApp(
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
                    child: Transform.scale(
                      scale: scale,
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
  );

  Future<bool> setUpLiquid(WidgetTester tester) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return false;
    tester.view.physicalSize = const ui.Size(900, 1200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(GlassBuiltInPainter.precache);
    return MorphTheme.liquidGlassAvailable;
  }

  Future<void> frames(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  // The pixels of the clear glass over the picture and around it.
  Future<Uint8List> shot(WidgetTester tester, GlobalKey boundary) async {
    final over = tester.getRect(find.text('Over')).inflate(30);
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = (await tester.runAsync(() => render.toImage(pixelRatio: 3)))!;
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

  int worst(Uint8List a, Uint8List b) {
    var worst = 0;
    for (var i = 0; i < a.length; i++) {
      final d = (a[i] - b[i]).abs();
      if (d > worst) worst = d;
    }
    return worst;
  }

  testWidgets('a pressed member of a solid container moves no backdrop copy', (
    WidgetTester tester,
  ) async {
    if (!await setUpLiquid(tester)) return;
    final boundary = GlobalKey();
    await tester.pumpWidget(scene(boundary));
    await frames(tester, 30);
    final rest = await shot(tester, boundary);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Top')),
    );
    var left = false;
    for (var frame = 0; frame < 24; frame++) {
      if (frame == 12) await gesture.up();
      await frames(tester, 1);
      left |= tester.allRenderObjects.whereType<RenderGlassMember>().any(
        (member) =>
            member.plane != null &&
            member.census.strategy != GlassStrategy.merged,
      );
      expect(
        worst(await shot(tester, boundary), rest),
        lessThanOrEqualTo(1),
        reason: 'frame $frame',
      );
    }
    // The press took the button out of its container into a layer of its
    // own, the case under test.
    expect(left, isTrue);
  });

  // A pressed button's glow ends while its spring's tail still scales it
  // (on the iPhone, 0.8 s after a tap, for about 4 frames at 60 Hz), and a
  // member the plane has not seen unscaled yet counts as scaled too: the
  // plane keeps it out of its pass, and it must still shade over the
  // container's color.
  testWidgets('a scaled member of a solid container moves no backdrop copy', (
    WidgetTester tester,
  ) async {
    if (!await setUpLiquid(tester)) return;
    final boundary = GlobalKey();
    await tester.pumpWidget(scene(boundary));
    await frames(tester, 30);
    final rest = await shot(tester, boundary);
    await tester.pumpWidget(scene(boundary, scale: 1.02));
    await frames(tester, 30);
    final top = tester.allRenderObjects.whereType<RenderGlassMember>().where(
      (member) => member.plane != null,
    );
    expect(top.map((member) => member.census.strategy).toSet(), {
      GlassStrategy.painted,
    }, reason: 'the scaled button draws a layer of its own over the color');
    expect(worst(await shot(tester, boundary), rest), lessThanOrEqualTo(1));
  });
}
