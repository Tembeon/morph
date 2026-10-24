import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/theme/glass.dart';
import 'package:morph/src/theme/surface_borders.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_outline.dart';

/// Paints app contours from the same live frame that draws the glass.
/// No input, layout, backdrop capture or widget rebuild belongs to this layer.
@internal
class MorphSurfaceBorderPainter extends CustomPainter {
  /// Follows [source] at [tier] for one painter entry [mode].
  MorphSurfaceBorderPainter({
    required this.source,
    required this.borders,
    required this.tier,
    required this.mode,
  }) : super(repaint: source.live);

  /// The control's existing frame stream.
  final MorphGlassSource source;

  /// App-authored per-role contours.
  final MorphSurfaceBorders borders;

  /// The tier whose fused geometry the glass uses.
  final MorphGlassTier tier;

  /// Whether coordinates are local to one surface or to the whole layer.
  final MorphGlassMode mode;

  BorderSide _side(MorphGlassSurface surface) => switch (surface.kind) {
    .bar => borders.bar,
    .track => borders.track,
    .menu => borders.menu,
    .button => borders.button,
    .lens => borders.lens,
    .knob => borders.knob,
    .thumb => borders.thumb,
  };

  bool _visible(MorphGlassSurface surface, BorderSide side) =>
      surface.opacity > 0 &&
      !surface.bounds.isEmpty &&
      side.style != BorderStyle.none &&
      side.color.a > 0;

  Paint _paint(BorderSide side, double opacity) {
    final paint = Paint();
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = side.width;
    paint.color = side.color.withValues(
      alpha: side.color.a * opacity.clamp(0, 1),
    );
    return paint;
  }

  void _surface(
    Canvas canvas,
    MorphGlassSurface surface, {
    bool local = false,
  }) {
    final side = _side(surface);
    if (!_visible(surface, side)) return;
    final shape = local ? surface.localShape : surface.shape;
    canvas.drawRRect(
      shape.inflate(side.width * side.strokeAlign / 2),
      _paint(side, surface.opacity),
    );
  }

  void _body(
    Canvas canvas,
    List<MorphGlassSurface> surfaces,
    MorphGlassOutline outline,
  ) {
    if (surfaces.isEmpty || surfaces.first.opacity <= 0) return;
    BorderSide? border;
    for (final surface in surfaces) {
      final side = _side(surface);
      if (!_visible(surface, side)) continue;
      border = side;
      break;
    }
    final side = border;
    if (side == null) return;
    final path = outline.path;
    final paint = _paint(side, surfaces.first.opacity);
    if (side.strokeAlign == 0 || side.width == 0) {
      canvas.drawPath(path, paint);
      return;
    }
    // Clip the two stroke halves rather than inventing an inset fused path.
    final inside = side.width * (1 - side.strokeAlign);
    final outside = side.width * (1 + side.strokeAlign);
    if (inside > 0) {
      canvas.save();
      canvas.clipPath(path);
      paint.strokeWidth = inside;
      canvas.drawPath(path, paint);
      canvas.restore();
    }
    if (outside > 0) {
      canvas.save();
      final outsideClip = Path();
      outsideClip.fillType = PathFillType.evenOdd;
      outsideClip.addRect(path.getBounds().inflate(side.width + 1));
      outsideClip.addPath(path, Offset.zero);
      canvas.clipPath(outsideClip);
      paint.strokeWidth = outside;
      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final frame = source.frame;
    switch (mode) {
      case MorphGlassMode.surface || MorphGlassMode.fill:
        _surface(canvas, frame.surfaces.single, local: true);
      case MorphGlassMode.body:
        _body(canvas, frame.surfaces, frame.outline!);
      case MorphGlassMode.layer:
        final parts = frame.partsFor(tier);
        for (final surfaces in [parts.fills, parts.separate, parts.floating]) {
          for (final surface in surfaces) {
            _surface(canvas, surface);
          }
        }
        for (final (surfaces, outline) in parts.fused) {
          _body(canvas, surfaces, outline);
        }
    }
  }

  @override
  bool shouldRepaint(MorphSurfaceBorderPainter oldDelegate) =>
      source != oldDelegate.source ||
      borders != oldDelegate.borders ||
      tier != oldDelegate.tier ||
      mode != oldDelegate.mode;
}
