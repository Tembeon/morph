import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The exterior shadow of one fused glass body.
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

  /// The offscreen layers this painter has opened, over all its paints;
  /// debug builds only.
  @visibleForTesting
  static int debugSaveLayerCount = 0;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0 || shadows.isEmpty) return;
    assert(() {
      debugSaveLayerCount++;
      return true;
    }());
    canvas.saveLayer(null, Paint());
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
    final cutout = Paint();
    cutout.blendMode = BlendMode.dstOut;
    canvas.drawPath(outline, cutout);
    canvas.restore();
  }

  @override
  bool shouldRepaint(MorphGlassBodyShadow oldDelegate) =>
      oldDelegate.outline != outline ||
      !listEquals(oldDelegate.shadows, shadows) ||
      oldDelegate.opacity != opacity;
}
