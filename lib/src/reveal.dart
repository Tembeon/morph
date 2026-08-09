import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/widgets.dart';

import 'package:morph/src/flight.dart';

/// Content choreography: a block unfolds on its own sub-range of the
/// same spring's progress - fade, slide-in, scale, and a vertical
/// "unsquash" from the anchor. Content does not just appear and "be";
/// it unpacks out of the morph's direction of growth.
///
/// The no-overflow guarantee holds by construction: only render
/// transforms are used here (Transform + Opacity). The block's layout is
/// computed once at its final size; no animated constraints,
/// SizeTransition, or heightFactor - the things that throw "RenderFlex
/// overflowed" on every frame.
///
/// Like everything in the system it is a pure symmetric function of the
/// spring value: on close the blocks fold back in reverse order, and
/// interruption stays continuous.
class MorphReveal extends StatelessWidget {
  /// Creates a reveal over [child] on the [from]..[to] progress range.
  const MorphReveal({
    super.key,
    this.from = 0.45,
    this.to = 0.9,
    this.slideOffset = const Offset(0, 14),
    this.scaleFrom = 0.96,
    this.squashFrom = 0.85,
    this.alignment = Alignment.topCenter,
    this.curve = Curves.easeOut,
    required this.child,
  }) : assert(
         0 <= from && from < to && to <= 1,
         'The reveal range must satisfy 0 <= from < to <= 1; '
         'got from: $from, to: $to.',
       );

  /// The progress range `[from, to]` over which the block unfolds.
  /// A cascade is built by offsetting the ranges of adjacent blocks.
  final double from;

  /// Progress at which the block is fully revealed.
  final double to;

  /// Where the block slides in from (logical pixels).
  final Offset slideOffset;

  /// The block's starting overall scale.
  final double scaleFrom;

  /// The starting "squash": extra vertical compression on top of
  /// [scaleFrom]. 1.0 disables it - the block only scales.
  final double squashFrom;

  /// The transform anchor - which edge the block unfolds from. Defaults
  /// to the top: content "unpacks" downward, the same direction the
  /// morph container grows.
  final Alignment alignment;

  /// Shaping curve applied inside the range; a pure function of
  /// progress, so interruption continuity holds.
  final Curve curve;

  /// The content being revealed; laid out once at its final size.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final MorphFlight flight = MorphFlightScope.of(context);
    return ListenableBuilder(
      listenable: flight.controller,
      child: child,
      builder: (BuildContext context, Widget? inner) {
        final double t = Interval(
          from,
          to,
          curve: curve,
        ).transform(flight.controller.progress);
        // The tree structure stays identical for every t: short-
        // circuiting the wrappers at t >= 1 would rebuild the child on
        // each boundary crossing, dropping its state and re-mounting
        // any MorphTag inside. Opacity(1) and an identity transform
        // paint nothing extra.
        final Offset shift = slideOffset * (1 - t);
        final double sx = lerpDouble(scaleFrom, 1, t)!;
        final double sy = lerpDouble(scaleFrom * squashFrom, 1, t)!;
        // An overshooting curve (easeOutBack) may leave [0, 1]: the
        // transform rides it - that is the point - but Opacity asserts
        // on it.
        return Opacity(
          opacity: clampDouble(t, 0, 1),
          child: Transform(
            alignment: alignment,
            transform: Matrix4.identity()
              ..translateByDouble(shift.dx, shift.dy, 0, 1)
              ..scaleByDouble(sx, sy, 1, 1),
            child: inner,
          ),
        );
      },
    );
  }
}
