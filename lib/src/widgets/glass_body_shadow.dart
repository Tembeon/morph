import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/glass_shadow.dart';
import 'package:morph/src/glass/renderer/internal/glass_live.dart';
import 'package:morph/src/widgets/glass_channel.dart';

/// The exterior shadow of one fused glass body, clipped to outside its
/// outline: no offscreen layer, and no shadow under the translucent body.
@internal
class MorphGlassBodyShadow extends CustomPainter {
  /// Paints [shadows] of [outline] outside [cover] (the outline itself
  /// when null) at [opacity].
  MorphGlassBodyShadow(
    Path outline,
    List<BoxShadow> shadows,
    double opacity, [
    Path? cover,
  ]) : this.live(GlassFixed((outline, shadows, opacity, cover)));

  /// Paints the shadows of [data] outside its cover, repainting when a
  /// live [data] changes.
  MorphGlassBodyShadow.live(this.data)
    : super(
        repaint: morphRepaintOn(
          data,
          () => (
            data.value.$1,
            MorphListKey(data.value.$2),
            data.value.$3,
            data.value.$4,
          ),
        ),
      );

  /// The outline that casts the shadows, the shadows, the body's
  /// visibility and the region the shadows stay out of (the outline when
  /// null): a body whose outline leaves out its necks covers them too.
  final ValueListenable<(Path, List<BoxShadow>, double, Path?)> data;

  /// The shared silhouette in the layer's coordinates.
  Path get outline => data.value.$1;

  /// The region the shadows stay out of, when it is not [outline].
  Path? get cover => data.value.$4;

  /// The material's exterior shadows.
  List<BoxShadow> get shadows => data.value.$2;

  /// The visibility of the body.
  double get opacity => data.value.$3;

  @override
  void paint(Canvas canvas, Size size) {
    final (outline, shadows, opacity, cover) = data.value;
    if (opacity <= 0 || shadows.isEmpty) return;
    final body = outline.getBounds();
    final covered = cover ?? outline;
    var bounds = cover == null ? body : body.expandToInclude(cover.getBounds());
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
    outside.addPath(covered, Offset.zero);
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
      data is! GlassFixed<(Path, List<BoxShadow>, double, Path?)> ||
      oldDelegate.outline != outline ||
      oldDelegate.cover != cover ||
      !listEquals(oldDelegate.shadows, shadows) ||
      oldDelegate.opacity != opacity;
}
