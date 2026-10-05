import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/glass_shadow.dart';
import 'package:morph/src/glass/renderer/internal/glass_live.dart';
import 'package:morph/src/widgets/glass_channel.dart';

/// The exterior shadow of one fused glass body, clipped to outside its
/// outline: no offscreen layer, and no shadow under the translucent body.
@internal
class MorphGlassBodyShadow extends CustomPainter {
  /// Paints [shadows] outside [outline] at [opacity].
  MorphGlassBodyShadow(Path outline, List<BoxShadow> shadows, double opacity)
    : this.live(GlassFixed((outline, shadows, opacity)));

  /// Paints the shadows of [data] outside its outline, repainting when a
  /// live [data] changes.
  MorphGlassBodyShadow.live(this.data)
    : super(
        repaint: morphRepaintOn(
          data,
          () => (data.value.$1, MorphListKey(data.value.$2), data.value.$3),
        ),
      );

  /// The outline, its shadows and the body's visibility.
  final ValueListenable<(Path, List<BoxShadow>, double)> data;

  /// The shared silhouette in the layer's coordinates.
  Path get outline => data.value.$1;

  /// The material's exterior shadows.
  List<BoxShadow> get shadows => data.value.$2;

  /// The visibility of the body.
  double get opacity => data.value.$3;

  @override
  void paint(Canvas canvas, Size size) {
    final (outline, shadows, opacity) = data.value;
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
      data is! GlassFixed<(Path, List<BoxShadow>, double)> ||
      oldDelegate.outline != outline ||
      !listEquals(oldDelegate.shadows, shadows) ||
      oldDelegate.opacity != opacity;
}
