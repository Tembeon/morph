import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

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
  bool shouldRepaint(MorphGlassBodyShadow oldDelegate) =>
      oldDelegate.outline != outline ||
      oldDelegate.shadows != shadows ||
      oldDelegate.opacity != opacity;
}
