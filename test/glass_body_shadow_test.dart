import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/glass_shadow.dart';
import 'package:morph/src/glass/renderer/internal/glass_defaults.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/widgets/glass_body_shadow.dart';

/// The fused-body shadow as it was painted before: one shifted copy of the
/// outline per shadow in an offscreen layer, the outline cut out of it.
class _Shifted extends CustomPainter {
  const _Shifted(this.outline, this.shadows, this.opacity);

  final Path outline;
  final List<BoxShadow> shadows;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0 || shadows.isEmpty) return;
    canvas.saveLayer(null, Paint());
    for (final shadow in shadows) {
      final paint = shadow
          .copyWith(
            color: shadow.color.withValues(alpha: shadow.color.a * opacity),
            blurRadius: shadow.blurRadius * opacity,
            blurStyle: BlurStyle.normal,
          )
          .toPaint();
      canvas.drawPath(outline.shift(shadow.offset), paint);
    }
    final cutout = Paint();
    cutout.blendMode = BlendMode.dstOut;
    canvas.drawPath(outline, cutout);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Shifted oldDelegate) => true;
}

Future<Uint8List> _pixels(WidgetTester tester, CustomPainter painter) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: const Color(0xFF8AB4F8),
          child: CustomPaint(painter: painter, size: const Size(360, 520)),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData();
    image.dispose();
    return data!.buffer.asUint8List();
  }))!;
}

Path _rrect(RRect shape) {
  final path = Path();
  path.addRRect(shape);
  return path;
}

void main() {
  final fused = Path.combine(
    PathOperation.union,
    _rrect(const RRect.fromLTRBXY(40, 40, 300, 380, 32, 32)),
    _rrect(const RRect.fromLTRBXY(150, 392, 210, 452, 30, 30)),
  );
  final cases = <String, (Path, List<BoxShadow>, double)>{
    'menu body': (fused, const [MorphGlassDefaults.bodyShadow], 1),
    'fading body': (fused, const [MorphGlassDefaults.bodyShadow], 0.55),
    'two shadows': (
      _rrect(const RRect.fromLTRBXY(20.3, 30.7, 330.1, 120.4, 22, 22)),
      const [
        BoxShadow(
          color: Color(0x33000000),
          offset: Offset(0, 9),
          blurRadius: 28,
        ),
        BoxShadow(color: Color(0x1A000000), blurRadius: 6, spreadRadius: 2),
      ],
      0.8,
    ),
  };

  for (final MapEntry(key: name, value: (outline, shadows, opacity))
      in cases.entries) {
    testWidgets('the clipped body shadow matches the layered one: $name', (
      WidgetTester tester,
    ) async {
      final before = await _pixels(tester, _Shifted(outline, shadows, opacity));
      final after = await _pixels(
        tester,
        MorphGlassBodyShadow(outline, shadows, opacity),
      );
      expect(after.length, before.length);
      const width = 360 * 3;
      var worstOffEdge = 0;
      var worstOnEdge = 0;
      for (var i = 0; i < before.length; i += 4) {
        final x = (i ~/ 4) % width;
        final y = (i ~/ 4) ~/ width;
        var inside = 0;
        for (final (dx, dy) in const [(-1, -1), (2, -1), (-1, 2), (2, 2)]) {
          if (outline.contains(Offset((x + dx) / 3, (y + dy) / 3))) inside++;
        }
        var diff = 0;
        for (var c = 0; c < 4; c++) {
          final d = (before[i + c] - after[i + c]).abs();
          if (d > diff) diff = d;
        }
        if (inside == 4) {
          expect(after.sublist(i, i + 4), [0x8A, 0xB4, 0xF8, 0xFF]);
        }
        if (inside == 0 || inside == 4) {
          if (diff > worstOffEdge) worstOffEdge = diff;
        } else if (diff > worstOnEdge) {
          worstOnEdge = diff;
        }
      }
      expect(worstOffEdge, lessThanOrEqualTo(1));
      expect(worstOnEdge, lessThanOrEqualTo(16));
    });
  }

  for (final (name, shape) in [
    ('rounded superellipse', const LiquidRoundedSuperellipse(borderRadius: 22)),
    ('rounded rectangle', const LiquidRoundedRectangle(borderRadius: 22)),
    ('oval', const LiquidOval()),
  ]) {
    testWidgets('a glass shadow clips instead of a layer: $name', (
      WidgetTester tester,
    ) async {
      const box = Rect.fromLTWH(60.3, 80.7, 180, 96);
      const shadows = [MorphGlassDefaults.bodyShadow];
      final before = await _pixels(tester, _LayeredGlassShadow(shape, box));
      final key = GlobalKey();
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: const Color(0xFF8AB4F8),
              child: SizedBox(
                width: 360,
                height: 520,
                child: Stack(
                  textDirection: TextDirection.ltr,
                  children: [
                    Positioned.fromRect(
                      rect: box,
                      child: GlassShadow(
                        shape: shape,
                        shadows: shadows,
                        settings: const LiquidGlassSettings(),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.renderObject(find.byType(GlassShadow)),
        paintsExactlyCountTimes(#saveLayer, 0),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final after = (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final data = await image.toByteData();
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;
      final inner = _shapePath(shape, box.deflate(.5));
      const width = 360 * 3;
      var worstOffEdge = 0;
      for (var i = 0; i < before.length; i += 4) {
        final x = (i ~/ 4) % width;
        final y = (i ~/ 4) ~/ width;
        var inside = 0;
        for (final (dx, dy) in const [(-1, -1), (2, -1), (-1, 2), (2, 2)]) {
          final p = Offset((x + dx) / 3, (y + dy) / 3);
          if (box.contains(p) && inner.contains(p)) inside++;
        }
        var diff = 0;
        for (var c = 0; c < 4; c++) {
          final d = (before[i + c] - after[i + c]).abs();
          if (d > diff) diff = d;
        }
        if (inside == 4) {
          expect(after.sublist(i, i + 4), [0x8A, 0xB4, 0xF8, 0xFF]);
        }
        if ((inside == 0 || inside == 4) && diff > worstOffEdge) {
          worstOffEdge = diff;
        }
      }
      expect(worstOffEdge, lessThanOrEqualTo(1));
    });
  }

  test('an equal shadow list does not repaint the body shadow', () {
    final outline = _rrect(const RRect.fromLTRBXY(0, 0, 10, 10, 0, 0));
    expect(
      MorphGlassBodyShadow(outline, [
        MorphGlassDefaults.bodyShadow,
      ], 1).shouldRepaint(
        MorphGlassBodyShadow(outline, [MorphGlassDefaults.bodyShadow], 1),
      ),
      isFalse,
    );
  });
}

Path _shapePath(LiquidShape shape, Rect rect) {
  final path = Path();
  switch (shape) {
    case LiquidRoundedSuperellipse(:final borderRadius):
      path.addRSuperellipse(
        RSuperellipse.fromRectAndRadius(rect, Radius.circular(borderRadius)),
      );
    case LiquidOval():
      path.addOval(rect);
    case LiquidRoundedRectangle(:final borderRadius):
      path.addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(borderRadius)),
      );
  }
  return path;
}

/// A glass shadow as it was painted before: the offset shadow in an
/// offscreen layer, the shape less half a pixel cut out of it.
class _LayeredGlassShadow extends CustomPainter {
  const _LayeredGlassShadow(this.shape, this.box);

  final LiquidShape shape;
  final Rect box;

  @override
  void paint(Canvas canvas, Size size) {
    const shadow = MorphGlassDefaults.bodyShadow;
    canvas.saveLayer(null, Paint());
    final paint = shadow.copyWith(blurStyle: BlurStyle.normal).toPaint();
    _draw(canvas, box.shift(shadow.offset).inflate(shadow.spreadRadius), paint);
    final cutout = Paint();
    cutout.blendMode = BlendMode.dstOut;
    _draw(canvas, box.deflate(.5), cutout);
    canvas.restore();
  }

  void _draw(Canvas canvas, Rect rect, Paint paint) {
    switch (shape) {
      case LiquidRoundedSuperellipse(:final borderRadius):
        canvas.drawRSuperellipse(
          RSuperellipse.fromRectAndRadius(rect, Radius.circular(borderRadius)),
          paint,
        );
      case LiquidOval():
        canvas.drawOval(rect, paint);
      case LiquidRoundedRectangle(:final borderRadius):
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(borderRadius)),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_LayeredGlassShadow oldDelegate) => true;
}
