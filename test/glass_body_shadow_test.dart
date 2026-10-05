import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/glass_defaults.dart';
import 'package:morph/src/widgets/glass_body_shadow.dart';

/// The fused-body shadow as it was painted before: one shifted copy of the
/// outline per shadow.
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
    testWidgets('the translated body shadow paints the same pixels: $name', (
      WidgetTester tester,
    ) async {
      final before = await _pixels(tester, _Shifted(outline, shadows, opacity));
      final after = await _pixels(
        tester,
        MorphGlassBodyShadow(outline, shadows, opacity),
      );
      expect(after.length, before.length);
      var differing = 0;
      for (var i = 0; i < before.length; i++) {
        if (before[i] != after[i]) differing++;
      }
      expect(differing, 0);
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
