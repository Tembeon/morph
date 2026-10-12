import 'package:flutter/rendering.dart';
import 'package:morph/src/glass/renderer/internal/glass_composition_probe.dart';
import 'package:meta/meta.dart';

/// Transform from [owner]'s local coordinates to the logical coordinates of
/// the render pass whose fragment coordinates its image filters see.
///
/// Filter coordinates are local to the enclosing render pass. A seeded
/// fractional-opacity pass uses its clipped origin; otherwise the root
/// screen coordinates apply. [translation] is retained compositor motion.
@internal
Matrix4 filterPassTransform(
  RenderObject owner, {
  required bool seeding,
  required double devicePixelRatio,
  Offset translation = Offset.zero,
  Matrix4? screen,
}) {
  final Matrix4 transform;
  if (seeding) {
    final origin = GlassCompositionProbe.seededPassOrigin(
      owner,
      devicePixelRatio,
    );
    transform = screen ?? owner.getTransformTo(null);
    transform.leftTranslateByDouble(-origin.dx, -origin.dy, 0, 1);
  } else {
    transform = screen ?? owner.getTransformTo(null);
  }
  if (translation != Offset.zero) {
    transform.multiply(
      Matrix4.translationValues(translation.dx, translation.dy, 0),
    );
  }
  return transform;
}
