import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/glass_shadow.dart';

/// The exterior shadow of one fused glass body, clipped to outside its
/// outline: no offscreen layer, and no shadow under the translucent body.
@internal
class MorphGlassBodyShadow extends CustomPainter {
  /// Paints [shadows] outside [outline] at [opacity].
  const MorphGlassBodyShadow(this.outline, this.shadows, this.opacity);

  /// The shared silhouette in the layer's coordinates.
  final Path outline;

  /// The material's exterior shadows.
  final List<BoxShadow> shadows;

  /// The visibility of the body.
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0 || shadows.isEmpty) return;
    final body = outline.getBounds();
    var bounds = body;
    for (final shadow in shadows) {
      bounds = bounds.expandToInclude(
        body
            .shift(shadow.offset)
            .inflate(
              shadow.spreadRadius +
                  glassShadowBlurSupport(shadow.blurRadius * opacity),
            ),
      );
    }
    final outside = Path();
    outside.fillType = PathFillType.evenOdd;
    outside.addRect(bounds.inflate(1));
    outside.addPath(outline, Offset.zero);
    canvas.save();
    canvas.clipPath(outside);
    for (final shadow in shadows) {
      final paint = shadow
          .copyWith(
            color: shadow.color.withValues(alpha: shadow.color.a * opacity),
            blurRadius: shadow.blurRadius * opacity,
            blurStyle: BlurStyle.normal,
          )
          .toPaint();
      if (shadow.offset == Offset.zero) {
        canvas.drawPath(outline, paint);
      } else {
        canvas.save();
        canvas.translate(shadow.offset.dx, shadow.offset.dy);
        canvas.drawPath(outline, paint);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MorphGlassBodyShadow oldDelegate) =>
      oldDelegate.outline != outline ||
      !listEquals(oldDelegate.shadows, shadows) ||
      oldDelegate.opacity != opacity;
}
