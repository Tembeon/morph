import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/control_host.dart';

import 'package:morph/src/widgets/lens_motion.dart';
import 'package:morph/src/widgets/typography.dart';

/// The deformed lens outline in [size], mirrored for [rtl].
@internal
RRect morphLensShape(MorphLensMotion motion, Size size, {required bool rtl}) {
  final lensSize = motion.size;
  final width = lensSize.width * motion.scaleX;
  final height = lensSize.height * motion.scaleY;
  final center = rtl ? size.width - motion.center : motion.center;
  return RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: Offset(center, size.height / 2),
      width: width,
      height: height,
    ),
    Radius.circular(math.min(width, height) / 2),
  );
}

/// Measures a resolved control label at [scaler], disposing its painter.
@internal
double morphLensLabelWidth(String text, TextStyle style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: MorphTypography.resolve(style)),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  );
  painter.layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Drives a [MorphLensMotion] from a [MorphControlHost].
@internal
mixin MorphLensDriver<T extends StatefulWidget> on MorphControlHost<T> {
  /// The motion this state drives; created by the host.
  MorphLensMotion get motion;

  /// Converts a pointer's local position to a coordinate along the track.
  double trackPosition(Offset local);

  @override
  void advanceMotion(double t) => motion.advance(t);

  @override
  bool get motionSettled => motion.isSettled;

  bool _reconcilePending = false;

  /// Reconciles a user selection with the parent's current [selected]
  /// after callbacks and the resulting rebuild have finished.
  void reconcileSelection(int Function() selected) {
    if (_reconcilePending) return;
    _reconcilePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reconcilePending = false;
      if (!mounted) return;
      final index = selected();
      if (motion.selected == index) return;
      motion.select(clock, index, notify: false);
      setState(() {});
      wake();
    });
  }

  @override
  void onControlDown(double t, PointerDownEvent event) =>
      motion.pointerDown(t, trackPosition(event.localPosition));

  @override
  void onControlMove(double t, PointerMoveEvent event) =>
      motion.pointerMove(t, trackPosition(event.localPosition));

  @override
  void onControlUp(double t, PointerUpEvent event) =>
      motion.pointerUp(t, trackPosition(event.localPosition));

  @override
  void onControlCancel(double t) => motion.pointerCancel(t);
}
