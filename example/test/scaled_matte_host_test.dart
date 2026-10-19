// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
// The test drives the renderer's own layers.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show AnalyticGeometryMode, RenderLiquidGlassLayer;
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_renderer.dart';

import '../integration_test/support/shader_harness.dart';

/// A liquid layer under a uniform scale rests on a matte encoded at its
/// pass's pixels: a held tab bar swells its bar and its lens by a
/// transform, and the rest frame matches the analytic frame along the
/// bar's end and through the lens. A matte of the layer's own device
/// pixels under the swell repeats texels, sets the rim a pixel off every
/// few rows, and the lens magnifies those steps (host run 2026-10-19,
/// before: the end's rim off by up to 0.92 device px with ten row-to-row
/// jumps over half a pixel, the lens 1.73 mean channel steps from the
/// analytic frame).
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/scaled_matte_host_test.dart
///
/// Without Impeller the test does nothing.
void main() {
  testWidgets('a held tab bar rests on mattes at the swell\'s pixels', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    const dpr = 3.0;
    tester.view.physicalSize = const ui.Size(1206, 1920);
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    addTearDown(() {
      RenderLiquidGlassLayer.debugAnalyticGeometry = null;
      RenderLiquidGlassLayer.debugAnalyticMode = null;
    });
    await tester.runAsync(GlassBuiltInPainter.precache);
    await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);
    RenderLiquidGlassLayer.debugAnalyticGeometry = true;
    final boundary = GlobalKey();

    Future<void> frames(int count) async {
      for (var i = 0; i < count; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<HarnessShot> shoot() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await tester.runAsync(
        () => render.toImage(pixelRatio: dpr),
      ))!;
      final data = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      image.dispose();
      return HarnessShot(image.width, image.height, data.buffer.asUint8List());
    }

    Widget app() => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: boundary,
        child: MorphTheme(
          data: const MorphThemeData(
            glass: .tier(MorphGlassTier.liquid),
            brightness: Brightness.dark,
          ),
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _Page())),
              Positioned(
                left: 0,
                right: 0,
                bottom: 40,
                child: Center(
                  child: MorphTabBar(
                    items: const [
                      MorphTabItem(icon: Icons.home, label: 'Home'),
                      MorphTabItem(icon: Icons.search, label: 'Browse'),
                      MorphTabItem(icon: Icons.person, label: 'Profile'),
                    ],
                    selected: 2,
                    onChanged: (int i) {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Iterable<RenderLiquidGlassLayer> layers() => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .where((layer) => layer.shapesWithGeometry.isNotEmpty);

    ui.Rect shapeBox(RenderLiquidGlassLayer layer) {
      final (geometry, _, _) = layer.shapesWithGeometry.first;
      return MatrixUtils.transformRect(
        geometry.getTransformTo(null),
        geometry.paintBounds,
      );
    }

    // Holds the lens on the last tab, dragged past the bar's end, until
    // nothing moves.
    Future<(HarnessShot, ui.Rect, ui.Rect)> held(
      AnalyticGeometryMode mode,
    ) async {
      RenderLiquidGlassLayer.debugAnalyticMode = mode;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(app());
      await frames(10);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Profile')),
      );
      for (var i = 0; i < 30; i++) {
        await gesture.moveBy(const Offset(1, 0.6));
        await frames(1);
      }
      await frames(90);
      final bar = layers().firstWhere((layer) => !layer.blursOwnBackdrop);
      final lens = layers().firstWhere((layer) => layer.blursOwnBackdrop);
      for (final layer in [bar, lens]) {
        final resting = mode == AnalyticGeometryMode.changes;
        expect(layer.debugResting, resting);
        expect(layer.debugAnalytic, !resting);
        if (resting) expect(layer.debugMatteDensity, greaterThan(1));
      }
      final shot = await shoot();
      final boxes = (shapeBox(bar), shapeBox(lens));
      await gesture.up();
      await frames(60);
      return (shot, boxes.$1, boxes.$2);
    }

    final (rest, bar, lens) = await held(AnalyticGeometryMode.changes);
    final (moving, _, _) = await held(AnalyticGeometryMode.always);
    // The lens hangs over the bar's end.
    expect(lens.right, greaterThan(bar.right));

    final outside = _regionDiff(
      rest,
      moving,
      ui.Rect.fromLTRB(bar.left, bar.top, lens.left, bar.bottom),
      dpr,
    );
    final through = _regionDiff(rest, moving, lens, dpr);
    final rim = _rimSteps(rest, moving, bar, dpr);
    // ignore: avoid_print
    print(
      'rest vs moving: bar max ${outside.max} '
      'mean ${outside.mean.toStringAsFixed(3)}, lens max ${through.max} '
      'mean ${through.mean.toStringAsFixed(3)}, bar end rim off '
      '${rim.offset.toStringAsFixed(3)} px, row jump '
      '${rim.jump.toStringAsFixed(3)} px',
    );
    // NEAR: the matte's quantization and its exact pixel centers; the
    // lens keeps the dispersed fringes of the page's black lines.
    expect(rim.offset, lessThan(0.25));
    expect(rim.jump, lessThan(0.25));
    expect(outside.max, lessThanOrEqualTo(16));
    expect(through.mean, lessThan(0.6));
  });
}

/// A light page of black lines with a blue disc behind the bar's end.
class _Page extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final page = Paint();
    page.color = const Color(0xFFF2F2F7);
    canvas.drawRect(Offset.zero & size, page);
    final line = Paint();
    line.color = const Color(0xFF1C1C1E);
    for (var y = 0.0; y < size.height; y += 18) {
      canvas.drawRect(Rect.fromLTWH(16, y, size.width - 32, 3), line);
    }
    final blue = Paint();
    blue.color = const Color(0xFF007AFF);
    canvas.drawCircle(Offset(size.width - 60, size.height - 90), 30, blue);
  }

  @override
  bool shouldRepaint(_Page oldDelegate) => false;
}

/// The largest channel difference and the mean RGB difference of [a] and
/// [b] over [region] (logical pixels at [dpr]).
({int max, double mean}) _regionDiff(
  HarnessShot a,
  HarnessShot b,
  ui.Rect region,
  double dpr,
) {
  var max = 0;
  var sum = 0;
  var count = 0;
  final left = (region.left * dpr).floor().clamp(0, a.width);
  final right = (region.right * dpr).ceil().clamp(0, a.width);
  final top = (region.top * dpr).floor().clamp(0, a.height);
  final bottom = (region.bottom * dpr).ceil().clamp(0, a.height);
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final p = (y * a.width + x) * 4;
      for (var c = 0; c < 3; c++) {
        final d = (a.bytes[p + c] - b.bytes[p + c]).abs();
        if (d > max) max = d;
        sum += d;
      }
      count++;
    }
  }
  return (max: max, mean: count == 0 ? 0.0 : sum / (count * 3));
}

/// How far the rim of [bar]'s leading end in [a] lies from the one in [b],
/// device pixel row by device pixel row: the largest offset and the
/// largest change of the offset between two rows. The rim of each row is
/// where its luminance first falls halfway from the page to the bar.
({double offset, double jump}) _rimSteps(
  HarnessShot a,
  HarnessShot b,
  ui.Rect bar,
  double dpr,
) {
  double luminance(HarnessShot shot, int x, int y) {
    final p = (y * shot.width + x) * 4;
    return 0.299 * shot.bytes[p] +
        0.587 * shot.bytes[p + 1] +
        0.114 * shot.bytes[p + 2];
  }

  double? rim(HarnessShot shot, int y, int from, int to) {
    final page = luminance(shot, from, y);
    // A row that starts on one of the page's lines has no page to fall
    // from.
    if (page < 128) return null;
    var low = page;
    for (var x = from; x < to; x++) {
      final l = luminance(shot, x, y);
      if (l < low) low = l;
    }
    final half = (page + low) / 2;
    for (var x = from + 1; x < to; x++) {
      final before = luminance(shot, x - 1, y);
      final l = luminance(shot, x, y);
      if (l < half) return x - 1 + (before - half) / (before - l);
    }
    return null;
  }

  final from = ((bar.left - 3) * dpr).floor();
  final to = ((bar.left + bar.height / 2) * dpr).ceil();
  var offset = 0.0;
  var jump = 0.0;
  double? last;
  for (
    var y = ((bar.top + 8) * dpr).ceil();
    y < ((bar.bottom - 8) * dpr).floor();
    y++
  ) {
    final ra = rim(a, y, from, to);
    final rb = rim(b, y, from, to);
    if (ra == null || rb == null) {
      last = null;
      continue;
    }
    final off = ra - rb;
    if (off.abs() > offset) offset = off.abs();
    if (last != null && (off - last).abs() > jump) jump = (off - last).abs();
    last = off;
  }
  return (offset: offset, jump: jump);
}
