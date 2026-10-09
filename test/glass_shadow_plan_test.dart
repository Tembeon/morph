import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/glass_shadow.dart';
import 'package:morph/src/glass/renderer/renderer.dart';

const _shadows = [
  BoxShadow(color: Color(0x40000000), offset: Offset(0, 3), blurRadius: 12),
  BoxShadow(color: Color(0x1F000000), blurRadius: 4, spreadRadius: 1),
];

const _shape = LiquidRoundedSuperellipse(borderRadius: 22);

/// The shadows as GlassShadow painted them before it kept its paths:
/// built at the paint offset every frame, in the layer's coordinates.
class _DirectShadow extends LeafRenderObjectWidget {
  const _DirectShadow(this.visibility);

  final double visibility;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDirectShadow(visibility);
}

class _RenderDirectShadow extends RenderBox {
  _RenderDirectShadow(this.visibility);

  final double visibility;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final rect = offset & size;
    var bounds = rect;
    for (final shadow in _shadows) {
      bounds = bounds.expandToInclude(
        rect
            .shift(shadow.offset)
            .inflate(
              shadow.spreadRadius +
                  glassShadowBlurSupport(shadow.blurRadius * visibility),
            ),
      );
    }
    final outside = Path();
    outside.fillType = PathFillType.evenOdd;
    outside.addRect(bounds.inflate(1));
    outside.addRSuperellipse(
      RSuperellipse.fromRectAndRadius(
        rect.deflate(.5),
        const Radius.circular(22),
      ),
    );
    canvas.save();
    canvas.clipPath(outside);
    for (final shadow in _shadows) {
      final paint = shadow
          .copyWith(
            blurRadius: shadow.blurRadius * visibility,
            blurStyle: BlurStyle.normal,
            color: shadow.color.withValues(alpha: shadow.color.a * visibility),
          )
          .toPaint();
      canvas.drawRSuperellipse(
        RSuperellipse.fromRectAndRadius(
          rect.shift(shadow.offset).inflate(shadow.spreadRadius),
          const Radius.circular(22),
        ),
        paint,
      );
    }
    canvas.restore();
  }
}

const _frame = ValueKey<String>('frame');

Widget _scene(Offset at, double visibility, {required bool direct}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: _frame,
          child: Container(
            width: 200,
            height: 120,
            color: const Color(0xFFFFFFFF),
            child: Stack(
              children: [
                Positioned(
                  left: at.dx,
                  top: at.dy,
                  width: 96,
                  height: 44,
                  child: direct
                      ? _DirectShadow(visibility)
                      : GlassShadow(
                          shape: _shape,
                          shadows: _shadows,
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
    final image = await boundary.toImage(pixelRatio: 3.14);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }))!;
}

void main() {
  testWidgets('kept shadow paths draw what paths built in place drew', (
    tester,
  ) async {
    var worst = 0;
    for (final at in const [
      Offset(40, 30),
      Offset(40.3, 30.7),
      Offset(51.13, 22.41),
      Offset(60.5, 40.25),
    ]) {
      for (final visibility in const [1.0, 0.4]) {
        await tester.pumpWidget(_scene(at, visibility, direct: true));
        final direct = await _shot(tester);
        // Mount at another place and visibility first, so the kept paths
        // are moved and the paints remade.
        await tester.pumpWidget(
          _scene(at + const Offset(7, 3), 1, direct: false),
        );
        await tester.pumpWidget(_scene(at, visibility, direct: false));
        final kept = await _shot(tester);
        var max = 0;
        for (var i = 0; i < direct.length; i++) {
          final d = (direct[i] - kept[i]).abs();
          if (d > max) max = d;
        }
        debugPrint('at $at visibility $visibility: max $max');
        if (max > worst) worst = max;
      }
    }
    // Impeller rasterizes the translated paths identically; Skia rounds
    // blurred edge pixels by up to three channel steps.
    expect(
      worst,
      lessThanOrEqualTo(ui.ImageFilter.isShaderFilterSupported ? 0 : 3),
    );
  });
}
