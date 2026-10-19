import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_button.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/theme/theme.dart';

/// Liquid Glass behind app content, in a shape: SwiftUI's
/// `glassEffect(_:in:)` and UIKit's `UIVisualEffectView` with a
/// `UIGlassEffect`.
///
/// The glass fills the box [child] lays out in, under [child], in
/// [shape]. It is the material of a glass button at rest: the installed
/// [MorphGlassPainter] draws it ([GlassBuiltInPainter] as liquid, fake or
/// flat glass), and without one it is a flat fill from the
/// [MorphGlassButtonAppearance]. Resting glass effects inside a
/// [MorphGlassContainer] are shaded in the container's one layer, as
/// glass buttons are.
///
/// [style] picks the regular or the clear material ([MorphGlassStyle]),
/// [tint] fills the glass with a color (`UIGlassEffect.tintColor`,
/// `Glass.tint(_:)`), as a prominent glass button is filled.
///
/// With [interactive] (`UIGlassEffect.isInteractive`,
/// `Glass.interactive()`) the glass and its content lift, stretch toward
/// a dragging finger and glow under it by the flex interaction of a glass
/// button of the same size ([MorphGlassButtonMotion]). It watches the
/// finger without taking it: buttons and gestures in [child] still
/// receive their touches. Interactive glass is assumed to move as a
/// `.glass()` button's; it is not yet measured on its own. With the
/// platform's reduced motion on, it glows but never lifts or leans.
///
/// The shape is one of [StadiumBorder] (the default, SwiftUI's capsule),
/// [CircleBorder], [RoundedRectangleBorder] or
/// [RoundedSuperellipseBorder] with one radius for every corner. Liquid
/// glass draws rounded corners as continuous ones (a superellipse), as
/// iOS draws its glass; flat glass draws them circular.
class MorphGlassEffect extends StatefulWidget {
  /// Puts glass of [style] in [shape] behind [child].
  const MorphGlassEffect({
    required this.child,
    this.shape = const StadiumBorder(),
    this.style = MorphGlassStyle.regular,
    this.tint,
    this.interactive = false,
    this.appearance,
    super.key,
  });

  /// The content drawn over the glass; the glass takes its size.
  final Widget child;

  /// The outline of the glass.
  final ShapeBorder shape;

  /// The material of the glass.
  final MorphGlassStyle style;

  /// The color the glass is filled with, or null for untinted glass.
  final Color? tint;

  /// Whether the glass responds to touch as a glass button does.
  final bool interactive;

  /// The flat colors of the glass without a painter or on the flat tier;
  /// null resolves them from the theme.
  final MorphGlassButtonAppearance? appearance;

  @override
  State<MorphGlassEffect> createState() => _MorphGlassEffectState();
}

final Listenable _resting = Listenable.merge(const <Listenable>[]);

RRect Function(Size size) _outline(ShapeBorder shape, TextDirection? dir) {
  switch (shape) {
    case StadiumBorder():
      return morphCapsuleShape;
    case CircleBorder(eccentricity: 0):
      return (Size size) {
        final side = math.min(size.width, size.height);
        return RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: size.center(Offset.zero),
            width: side,
            height: side,
          ),
          Radius.circular(side / 2),
        );
      };
    case RoundedRectangleBorder(:final borderRadius) ||
        RoundedSuperellipseBorder(:final borderRadius):
      final radius = borderRadius.resolve(dir).topLeft;
      assert(
        borderRadius.resolve(dir) == BorderRadius.all(radius) &&
            radius.x == radius.y,
        'MorphGlassEffect takes one circular radius for every corner.',
      );
      return (Size size) => RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(
          math.min(radius.x, math.min(size.width, size.height) / 2),
        ),
      );
    default:
      assert(false, 'MorphGlassEffect does not draw ${shape.runtimeType}.');
      return morphCapsuleShape;
  }
}

class _MorphGlassEffectState extends State<MorphGlassEffect>
    with SingleTickerProviderStateMixin, MorphClock {
  final MorphGlassButtonMotion _motion = MorphGlassButtonMotion(
    size: Size.zero,
  );
  int? _pointer;
  (ShapeBorder, TextDirection?)? _shapeKey;
  RRect Function(Size size) _shape = morphCapsuleShape;

  @override
  void advanceMotion(double t) => _motion.advance(t);

  @override
  bool get motionSettled => _motion.isSettled;

  @override
  void settleMotion() => _motion.settle();

  double get _lift {
    final lifted = _motion.liftedScale - 1;
    if (lifted <= 0) return 0;
    return ((_motion.scale - 1) / lifted).clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(MorphGlassEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.interactive && _pointer != null) {
      _pointer = null;
      _motion.pointerCancel(clock);
      wake();
    }
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    _pointer = event.pointer;
    _motion.size = box.size;
    _motion.pointerDown(stamp(event), event.localPosition);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _motion.pointerMove(stamp(event), event.localPosition);
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _motion.pointerUp(stamp(event), event.localPosition);
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _motion.pointerCancel(stamp(event));
  }

  @override
  Widget build(BuildContext context) {
    final appearance = MorphGlassButtonAppearance.resolve(
      context,
      widget.appearance,
    );
    final brightness = morphBrightnessOf(context);
    final painter = MorphGlassScope.maybeOf(context);
    final key = (widget.shape, Directionality.maybeOf(context));
    if (key != _shapeKey) {
      _shapeKey = key;
      _shape = _outline(key.$1, key.$2);
    }
    final tint = widget.tint;
    final clear = widget.style == MorphGlassStyle.clear;
    final interactive = widget.interactive;
    _motion.reducedMotion = morphReducedMotionOf(context);
    final Widget capsule = MorphControlCapsule(
      painter: painter,
      frames: interactive ? frames : _resting,
      color: tint ?? (clear ? appearance.clearFillColor : appearance.fillColor),
      tint: tint == null && clear ? const Color(0x00000000) : null,
      style: clear ? MorphGlassStyle.clear : null,
      rim: tint == null ? appearance.rimColor : appearance.prominentRimColor,
      shadow: appearance.shadowColor,
      brightness: brightness,
      enabled: true,
      shape: _shape,
      lift: interactive ? () => _lift : null,
      glow: interactive
          ? () => _motion.glowAt(brightness, tint: tint, clear: clear)
          : null,
      still: interactive ? () => _motion.isSettled : () => true,
      child: widget.child,
    );
    return Listener(
      onPointerDown: interactive ? _down : null,
      onPointerMove: interactive ? _move : null,
      onPointerUp: interactive ? _up : null,
      onPointerCancel: interactive ? _cancel : null,
      child: MorphLiveTransform(
        live: frames,
        writeInto: (Matrix4 into) {
          if (_motion.isAtRest) return;
          final lean = _motion.lean;
          into.translateByDouble(lean.dx, lean.dy, 0, 1);
          into.scaleByDouble(_motion.scaleX, _motion.scaleY, 1, 1);
        },
        child: capsule,
      ),
    );
  }
}
