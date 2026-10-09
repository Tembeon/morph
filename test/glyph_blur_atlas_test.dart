import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glyph_blur_atlas.dart';

void main() {
  setUpAll(() async {
    isLocalTest = true;
    await MorphGlyphBlurAtlas.precache();
  });

  testWidgets('blur motion reuses pixels and content changes invalidate them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(240, 240);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const frameKey = ValueKey('atlas-frame');
    Widget app(double sigma, double opacity, Color color) => WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, child) => RepaintBoundary(
        key: frameKey,
        child: ColoredBox(color: const Color(0xFF000000), child: child),
      ),
      home: Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: MorphGlyphBlurAtlas(
            sigma: sigma,
            opacity: opacity,
            child: ColoredBox(color: color),
          ),
        ),
      ),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
      ),
    );

    Future<List<int>> center() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(frameKey),
      );
      final result = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final index = (120 * image.width + 120) * 4;
        final pixels = data!.buffer.asUint8List().sublist(index, index + 4);
        image.dispose();
        return pixels;
      });
      return result!;
    }

    final initial = MorphGlyphBlurAtlas.captures;
    await tester.pumpWidget(app(0.5, 0.5, const Color(0xFFFF0000)));
    final red = await center();
    expect(red[0], closeTo(128, 1));
    expect(red.sublist(1), [0, 0, 255]);
    expect(MorphGlyphBlurAtlas.captures, initial + 1);
    final retainedBytes = MorphGlyphBlurAtlas.liveBytes;
    expect(retainedBytes, greaterThan(0));

    await tester.pumpWidget(app(2, 0.75, const Color(0xFFFF0000)));
    final faded = await center();
    expect(faded[0], closeTo(191, 1));
    expect(MorphGlyphBlurAtlas.captures, initial + 1);
    expect(MorphGlyphBlurAtlas.liveBytes, retainedBytes);

    await tester.pumpWidget(app(2, 0.75, const Color(0xFF0000FF)));
    final blue = await center();
    expect(blue[0], 0);
    expect(blue[2], closeTo(191, 1));
    expect(MorphGlyphBlurAtlas.captures, initial + 2);
    expect(MorphGlyphBlurAtlas.liveBytes, retainedBytes);

    await tester.pumpWidget(const SizedBox());
    expect(MorphGlyphBlurAtlas.liveBytes, 0);
  });
}
