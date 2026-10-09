import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glyph_scale.dart';

const _frameKey = ValueKey<String>('frame');

Future<Uint8List> _frame(WidgetTester tester, double ratio) async {
  final boundary =
      tester.renderObject(find.byKey(_frameKey)) as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData();
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

/// The largest channel difference of two frames, their mean channel
/// difference per changed pixel and the share of pixels over 15, in
/// percent of the pixels either frame covers.
({int max, double mean, double over}) _diff(Uint8List a, Uint8List b) {
  var max = 0;
  var sum = 0;
  var over = 0;
  var covered = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i + 3] == 0 && b[i + 3] == 0) continue;
    covered++;
    var m = 0;
    for (var k = 0; k < 4; k++) {
      m = math.max(m, (a[i + k] - b[i + k]).abs());
    }
    max = math.max(max, m);
    sum += m;
    if (m > 15) over++;
  }
  if (covered == 0) return (max: 0, mean: 0, over: 0);
  return (max: max, mean: sum / covered, over: over / covered * 100);
}

/// The glyphs drawn by the one-pass blur, by the exact layers
/// ([MorphGlyphScale.debugExact]) or by the previous Android path: a
/// raster under a blur layer under an opacity layer.
/// [sharp] (premultiplied RGBA, [width] pixels wide) blurred by a true
/// Gaussian of [sigma] pixels with clear outside, and faded to [opacity]:
/// what every blur path approximates.
Uint8List _truth(Uint8List sharp, int width, double sigma, double opacity) {
  final height = sharp.length ~/ 4 ~/ width;
  final radius = (3 * sigma).ceil() + 1;
  final kernel = [
    for (var i = -radius; i <= radius; i++)
      sigma <= 0
          ? (i == 0 ? 1.0 : 0.0)
          : math.exp(-i * i / (2 * sigma * sigma)),
  ];
  final total = kernel.reduce((a, b) => a + b);
  for (var i = 0; i < kernel.length; i++) {
    kernel[i] /= total;
  }
  final pass = Float64List(sharp.length);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      for (var c = 0; c < 4; c++) {
        var sum = 0.0;
        for (var i = -radius; i <= radius; i++) {
          final xx = x + i;
          if (xx < 0 || xx >= width) continue;
          sum += kernel[i + radius] * sharp[(y * width + xx) * 4 + c];
        }
        pass[(y * width + x) * 4 + c] = sum;
      }
    }
  }
  final out = Uint8List(sharp.length);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      for (var c = 0; c < 4; c++) {
        var sum = 0.0;
        for (var i = -radius; i <= radius; i++) {
          final yy = y + i;
          if (yy < 0 || yy >= height) continue;
          sum += kernel[i + radius] * pass[(yy * width + x) * 4 + c];
        }
        out[(y * width + x) * 4 + c] = (sum * opacity).round().clamp(0, 255);
      }
    }
  }
  return out;
}

Widget _glyphs(double blur, double opacity, double scale, {bool old = false}) {
  const glyphs = SizedBox(
    width: 160,
    height: 44,
    child: Center(
      child: Text(
        'Inbox 42',
        style: TextStyle(fontSize: 22, color: Color(0xFF0A84FF)),
      ),
    ),
  );
  final Widget item = old
      ? Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: blur,
                sigmaY: blur,
                tileMode: TileMode.decal,
              ),
              child: MorphGlyphRaster(
                active: AlwaysStoppedAnimation(
                  blur * scale >= MorphGlyphRaster.minBlur,
                ),
                sampleLogicalBounds: true,
                child: glyphs,
              ),
            ),
          ),
        )
      : Transform.scale(
          scale: scale,
          child: MorphGlyphBlur(blur: blur, opacity: opacity, child: glyphs),
        );
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: RepaintBoundary(
        key: _frameKey,
        child: SizedBox(width: 240, height: 120, child: Center(child: item)),
      ),
    ),
  );
}

void main() {
  setUpAll(() => isLocalTest = true);

  testWidgets('the one-pass blur matches a blur layer under an opacity layer', (
    tester,
  ) async {
    await tester.runAsync(MorphGlyphBlur.precache);
    const ratio = 2.0;
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.resetDevicePixelRatio);
    var worse = 0;
    var cases = 0;
    // A bar item's scale, blur and opacity all follow its presence p
    // (MorphBarItemsSpec: appearScale 0.2, appearBlur 10).
    final sharps = <double, Uint8List>{};
    for (final p in [0.02, 0.1, 0.25, 0.5, 0.75, 0.9, 0.97, 0.99, 0.995]) {
      final scale = 0.2 + 0.8 * p;
      final blur = 10 * (1 - p);
      final opacity = p;
      MorphGlyphScale.debugExact = true;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_glyphs(0, 1, scale));
      final sharp = sharps[scale] ??= await _frame(tester, ratio);
      final truth = _truth(sharp, 480, blur * scale * ratio, opacity);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_glyphs(blur, opacity, scale));
      final exact = _diff(truth, await _frame(tester, ratio));
      MorphGlyphScale.debugExact = false;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_glyphs(blur, opacity, scale));
      final now = _diff(truth, await _frame(tester, ratio));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_glyphs(blur, opacity, scale, old: true));
      final before = _diff(truth, await _frame(tester, ratio));
      cases++;
      if (now.mean > before.mean + 0.5) worse++;
      String f(({int max, double mean, double over}) d) =>
          '${d.max}/${d.mean.toStringAsFixed(2)}/${d.over.toStringAsFixed(1)}%';
      debugPrint(
        'p $p (scale ${scale.toStringAsFixed(2)} blur '
        '${blur.toStringAsFixed(2)}) vs Gaussian (max/mean/over15): '
        'layers ${f(exact)} one-pass ${f(now)} previous ${f(before)}',
      );
      // Within a channel step of the mean error of the blur layers it
      // replaces, or of the previous raster path.
      expect(
        now.mean,
        lessThan(math.max(exact.mean, before.mean) + 1),
        reason: 'presence $p',
      );
    }
    debugPrint('$cases cases, $worse worse than the previous path');
    expect(MorphGlyphBlur.debugRasterCount, greaterThan(0));
  });

  testWidgets('the pyramids one frame needs are taken together, once', (
    tester,
  ) async {
    await tester.runAsync(MorphGlyphBlur.precache);
    final created = <int>[];
    Widget row(double blur) => Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          for (var i = 0; i < 6; i++)
            MorphGlyphBlur(
              blur: blur,
              opacity: 0.8,
              child: SizedBox(width: 40, height: 40, child: Text('$i')),
            ),
        ],
      ),
    );
    MorphGlyphBlur.debugRasterCount = 0;
    MorphGlyphBlur.debugAtlasCount = 0;
    await tester.pumpWidget(row(3));
    created.add(MorphGlyphBlur.debugRasterCount);
    await tester.pumpWidget(row(2.9));
    created.add(MorphGlyphBlur.debugRasterCount);
    // A blur that changes reads another level of the same pyramids.
    await tester.pumpWidget(row(1.4));
    created.add(MorphGlyphBlur.debugRasterCount);
    expect(created, [6, 6, 6]);
    // The first frame draws one raster atlas and one pyramid atlas.
    expect(MorphGlyphBlur.debugAtlasCount, 2);
  });
}
