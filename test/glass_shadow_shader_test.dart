// The test reads the renderer's internals.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/glass_shadow.dart';
import 'package:morph/src/glass/renderer/internal/glass_defaults.dart';
import 'package:morph/src/glass/renderer/internal/glass_shadow_shader.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

/// The floating platter shadow at [lift], as the lens, knob and thumb
/// draw it.
BoxShadow _floating(double lift) => BoxShadow(
  color: MorphGlassDefaults.floatingShadowColor,
  offset: Offset(
    0,
    MorphGlassDefaults.floatingShadowOffset +
        MorphGlassDefaults.floatingLiftOffset * lift,
  ),
  blurRadius:
      MorphGlassDefaults.floatingShadowBlur +
      MorphGlassDefaults.floatingLiftBlur * lift,
);

final Map<String, List<BoxShadow>> _shadowSets = {
  'body': const [MorphGlassDefaults.bodyShadow],
  'floating': [_floating(0)],
  'floating lifted': [_floating(1)],
  // No offset: each shadow stays outside its own shape (an outer blur).
  'outer': const [
    BoxShadow(color: Color(0x1F000000), blurRadius: 4, spreadRadius: 1),
  ],
  'pair': const [
    BoxShadow(color: Color(0x40000000), offset: Offset(0, 3), blurRadius: 12),
    BoxShadow(color: Color(0x1F000000), blurRadius: 4, spreadRadius: 1),
  ],
};

/// The shapes: a 96 x 44 capsule and a 200 x 120 card of corner 22.
const Map<String, (Size, double)> _shapes = {
  'capsule': (Size(96, 44), 22),
  'card': (Size(200, 120), 22),
};

const _frame = ValueKey<String>('frame');

const double _ratio = 3;

const Size _scene = Size(320, 220);

Widget _shadowScene(
  Offset at,
  Size size,
  LiquidShape shape,
  List<BoxShadow> shadows,
  double visibility, {
  Color background = const Color(0xFFFFFFFF),
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: RepaintBoundary(
      key: _frame,
      child: Container(
        width: _scene.width,
        height: _scene.height,
        color: background,
        child: Stack(
          children: [
            Positioned(
              left: at.dx,
              top: at.dy,
              width: size.width,
              height: size.height,
              child: GlassShadow(
                shape: shape,
                shadows: shadows,
                settings: const LiquidGlassSettings(),
                appearanceVisibility: visibility,
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

Future<Uint8List> _shot(WidgetTester tester) async {
  final boundary =
      tester.renderObject(find.byKey(_frame)) as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }))!;
}

/// Whether [point] lies within [reach] of the outline of [path]: some
/// point of the circle of that radius around it, or [point] itself, falls
/// on the other side.
bool _nearOutline(Path path, Offset point, double reach) {
  final inside = path.contains(point);
  for (var i = 0; i < 32; i++) {
    final angle = i * math.pi / 16;
    final probe =
        point + Offset(math.cos(angle) * reach, math.sin(angle) * reach);
    if (path.contains(probe) != inside) return true;
  }
  return false;
}

/// The largest and the mean channel difference of [a] and [b] over the
/// device pixels of [region] (scene coordinates), the channels over 8, and
/// how many of those lie farther than one device pixel from every outline
/// of [cuts].
({int max, double mean, int over, int farOver}) _diff(
  Uint8List a,
  Uint8List b,
  Rect region,
  List<Path> cuts,
) {
  final width = (_scene.width * _ratio).round();
  final height = (_scene.height * _ratio).round();
  final left = math.max((region.left * _ratio).floor(), 0);
  final top = math.max((region.top * _ratio).floor(), 0);
  final right = math.min((region.right * _ratio).ceil(), width);
  final bottom = math.min((region.bottom * _ratio).ceil(), height);
  var max = 0;
  var sum = 0;
  var count = 0;
  var over = 0;
  var farOver = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final at = (y * width + x) * 4;
      // Color channels: the scene is opaque.
      for (var k = 0; k < 3; k++) {
        final d = (a[at + k] - b[at + k]).abs();
        if (d > max) max = d;
        if (d > 8) {
          over++;
          final center = Offset((x + .5) / _ratio, (y + .5) / _ratio);
          if (!cuts.any((cut) => _nearOutline(cut, center, 1 / _ratio))) {
            farOver++;
          }
        }
        sum += d;
        count++;
      }
    }
  }
  return (
    max: max,
    mean: count == 0 ? 0 : sum / count,
    over: over,
    farOver: farOver,
  );
}

/// Runs [body] with blurred shadows, which flutter_test turns off.
Future<void> _withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

void main() {
  setUpAll(() => isLocalTest = true);
  tearDown(() => MorphGlassShadowShader.debugEnabled = null);

  testWidgets('the shader shadow draws what the clipped mask blur draws', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) {
      // The shader reproduces Impeller's blur; on Skia shadows keep their
      // clip path.
      markTestSkipped('needs --enable-impeller');
      return;
    }
    await tester.runAsync(MorphGlassShadowShader.precache);
    expect(MorphGlassShadowShader.ready, isTrue);
    tester.view.devicePixelRatio = _ratio;
    addTearDown(tester.view.resetDevicePixelRatio);
    var worstMean = 0.0;
    final worstMax = <String, int>{};
    await _withShadows(() async {
      for (final MapEntry(key: shapeName, value: (size, radius))
          in _shapes.entries) {
        final shape = LiquidRoundedSuperellipse(borderRadius: radius);
        for (final MapEntry(key: shadowName, value: shadows)
            in _shadowSets.entries) {
          for (final at in const [Offset(60, 50), Offset(60.3, 50.7)]) {
            for (final visibility in const [1.0, 0.4]) {
              MorphGlassShadowShader.debugEnabled = false;
              await tester.pumpWidget(
                _shadowScene(at, size, shape, shadows, visibility),
              );
              final clipped = await _shot(tester);
              MorphGlassShadowShader.debugEnabled = true;
              // Another place and visibility first, so the cached uniforms
              // are remade.
              await tester.pumpWidget(
                _shadowScene(at + const Offset(7, 3), size, shape, shadows, 1),
              );
              await tester.pumpWidget(
                _shadowScene(at, size, shape, shadows, visibility),
              );
              final shaded = await _shot(tester);
              final box = tester.renderObject(find.byType(GlassShadow));
              final region = (box as RenderBox).paintBounds.shift(at);
              // The outlines the shadows are cut at: the glass deflated by
              // half a pixel when a shadow is offset, else each shadow's own
              // shape (an outer blur).
              final glass = at & size;
              final cuts =
                  [
                    if (shadows.any((s) => s.offset != Offset.zero))
                      glass.deflate(.5)
                    else
                      for (final s in shadows) glass.inflate(s.spreadRadius),
                  ].map((rect) {
                    final cut = Path();
                    cut.addRSuperellipse(
                      RSuperellipse.fromRectAndRadius(
                        rect,
                        Radius.circular(radius),
                      ),
                    );
                    return cut;
                  }).toList();
              final d = _diff(clipped, shaded, region, cuts);
              debugPrint(
                '$shapeName $shadowName at $at visibility $visibility: '
                'max ${d.max} mean ${d.mean.toStringAsFixed(3)}, '
                '${d.over} channels over 8, ${d.farOver} off the cut',
              );
              // Every larger difference is the cut itself.
              expect(d.farOver, 0, reason: '$shapeName $shadowName');
              worstMax[shadowName] = math.max(worstMax[shadowName] ?? 0, d.max);
              worstMean = math.max(worstMean, d.mean);
            }
          }
        }
      }
    });
    debugPrint('worst max $worstMax mean ${worstMean.toStringAsFixed(3)}');
    expect(worstMean, lessThanOrEqualTo(0.5));
    // The blur alone is exact (the test below); what is left is the cut,
    // and every difference over 8 lies within one device pixel of it
    // (asserted per case above). The clip path lies inside the exact
    // rounded superellipse at its corners (its fill covers less than
    // drawRSuperellipse's) and Impeller covers it by multisampling, so
    // corner pixels next to the glass keep more shadow than the shader's
    // exact edge: a channel step over 8 at one pixel for the floating
    // shadow, and more where a spread shadow is darkest right at the cut.
    for (final name in ['body', 'floating', 'floating lifted', 'outer']) {
      expect(worstMax[name], lessThanOrEqualTo(9), reason: name);
    }
    expect(worstMax['pair'], lessThanOrEqualTo(32));
  });

  testWidgets('the shader paints nothing inside the glass shape', (
    tester,
  ) async {
    await tester.runAsync(MorphGlassShadowShader.precache);
    expect(MorphGlassShadowShader.ready, isTrue);
    for (final (size, radius) in _shapes.values) {
      for (final shadow in [MorphGlassDefaults.bodyShadow, _floating(1)]) {
        const at = Offset(60.3, 50.7);
        final glass = at & size;
        final sigma = Shadow.convertRadiusToSigma(shadow.blurRadius);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.scale(_ratio);
        // A dense shadow, so a leak inside the glass cannot round away.
        expect(
          MorphGlassShadowShader.paint(
            canvas,
            Offset.zero & _scene,
            MorphGlassShadowShader.blur(
              glass.shift(shadow.offset),
              radius,
              sigma,
              const Color(0xFF000000),
            ),
            MorphGlassShadowShader.coverage(glass.deflate(.5), radius),
            _ratio,
          ),
          isTrue,
        );
        final picture = recorder.endRecording();
        final width = (_scene.width * _ratio).round();
        final height = (_scene.height * _ratio).round();
        final pixels = (await tester.runAsync(() async {
          final image = await picture.toImage(width, height);
          final data = await image.toByteData();
          image.dispose();
          return data!.buffer.asUint8List();
        }))!;
        picture.dispose();
        final inside = Path();
        inside.addRSuperellipse(
          RSuperellipse.fromRectAndRadius(
            glass.deflate(2),
            Radius.circular(radius),
          ),
        );
        var checked = 0;
        var leaks = 0;
        var outsideMax = 0;
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            final p = Offset((x + .5) / _ratio, (y + .5) / _ratio);
            final alpha = pixels[(y * width + x) * 4 + 3];
            if (inside.contains(p)) {
              checked++;
              if (alpha != 0) leaks++;
            } else {
              outsideMax = math.max(outsideMax, alpha);
            }
          }
        }
        expect(checked, greaterThan(1000));
        expect(leaks, 0);
        // The shadow itself is drawn.
        expect(outsideMax, greaterThan(100));
      }
    }
  });

  testWidgets('the blur is the mask blur Impeller draws', (tester) async {
    if (!ui.ImageFilter.isShaderFilterSupported) {
      markTestSkipped('needs --enable-impeller');
      return;
    }
    await tester.runAsync(MorphGlassShadowShader.precache);
    final width = (_scene.width * _ratio).round();
    final height = (_scene.height * _ratio).round();
    Future<Uint8List> render(void Function(Canvas canvas) draw) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(_ratio);
      draw(canvas);
      final picture = recorder.endRecording();
      final pixels = (await tester.runAsync(() async {
        final image = await picture.toImage(width, height);
        final data = await image.toByteData();
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;
      picture.dispose();
      return pixels;
    }

    var worst = 0;
    for (final (size, radius) in _shapes.values) {
      for (final shadows in _shadowSets.values) {
        if (shadows.length != 1) continue;
        final shadow = shadows.single;
        for (final visibility in const [1.0, 0.4]) {
          final rect = (const Offset(60.3, 50.7) & size).shift(shadow.offset);
          final sigma = Shadow.convertRadiusToSigma(
            shadow.blurRadius * visibility,
          );
          // Opaque, so every step of the blur's profile shows.
          final color = const Color(0xFF000000).withValues(alpha: visibility);
          final masked = await render((canvas) {
            final paint = Paint();
            paint.color = color;
            paint.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
            canvas.drawRSuperellipse(
              RSuperellipse.fromRectAndRadius(rect, Radius.circular(radius)),
              paint,
            );
          });
          final shaded = await render((canvas) {
            // A glass shape far away covers nothing.
            MorphGlassShadowShader.paint(
              canvas,
              rect.inflate(MorphGlassShadowShader.reach(sigma)),
              MorphGlassShadowShader.blur(rect, radius, sigma, color),
              MorphGlassShadowShader.coverage(
                const Rect.fromLTWH(-500, -500, 10, 10),
                5,
              ),
              _ratio,
            );
          });
          for (var i = 0; i < masked.length; i++) {
            worst = math.max(worst, (masked[i] - shaded[i]).abs());
          }
        }
      }
    }
    debugPrint('blur alone: max $worst');
    expect(worst, lessThanOrEqualTo(1));
  });

  testWidgets('with the option off the shadow clips and blurs its shape', (
    tester,
  ) async {
    await tester.runAsync(MorphGlassShadowShader.precache);
    MorphGlassShadowShader.debugEnabled = false;
    const shape = LiquidRoundedSuperellipse(borderRadius: 22);
    const shadows = [MorphGlassDefaults.bodyShadow];
    await _withShadows(() async {
      await tester.pumpWidget(
        _shadowScene(
          const Offset(60, 50),
          const Size(96, 44),
          shape,
          shadows,
          1,
        ),
      );
      final box = tester.renderObject(find.byType(GlassShadow));
      expect(
        box,
        paints
          ..clipPath()
          ..rsuperellipse(),
      );
      expect(box, paintsExactlyCountTimes(#drawRect, 0));
    });
  });

  testWidgets('with the option on only Impeller draws the shader, and only '
      'for rounded superellipses', (tester) async {
    await tester.runAsync(MorphGlassShadowShader.precache);
    MorphGlassShadowShader.debugEnabled = true;
    const shadows = [MorphGlassDefaults.bodyShadow];
    await _withShadows(() async {
      await tester.pumpWidget(
        _shadowScene(
          const Offset(60, 50),
          const Size(96, 44),
          const LiquidRoundedSuperellipse(borderRadius: 22),
          shadows,
          1,
        ),
      );
      var box = tester.renderObject<RenderBox>(find.byType(GlassShadow));
      if (ui.ImageFilter.isShaderFilterSupported) {
        expect(box, paintsExactlyCountTimes(#clipPath, 0));
        expect(box, paintsExactlyCountTimes(#drawRect, 1));
        // The drawn rect stays inside the paint bounds.
        final bounds = box.paintBounds;
        expect(
          box,
          paints..something((method, arguments) {
            if (method != #drawRect) return false;
            final rect = arguments.first as Rect;
            return bounds.expandToInclude(rect) == bounds;
          }),
        );
      } else {
        expect(
          box,
          paints
            ..clipPath()
            ..rsuperellipse(),
        );
      }
      await tester.pumpWidget(
        _shadowScene(
          const Offset(60, 50),
          const Size(96, 44),
          const LiquidRoundedRectangle(borderRadius: 22),
          shadows,
          1,
        ),
      );
      box = tester.renderObject<RenderBox>(find.byType(GlassShadow));
      expect(
        box,
        paints
          ..clipPath()
          ..rrect(),
      );
    });
  });
}
