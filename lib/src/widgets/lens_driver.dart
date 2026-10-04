import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/clock.dart';

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

/// Drives a [MorphLensMotion] from a [MorphClock] and raw
/// pointer events.
@internal
mixin MorphLensDriver<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T>, MorphClock<T> {
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

  int? _pointer;

  /// Whether [event] belongs to the gesture currently driving this lens.
  bool ownsPointer(PointerEvent event) => event.pointer == _pointer;

  /// Handles a raw pointer down.
  void handleDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton || _pointer != null) return;
    _pointer = event.pointer;
    motion.pointerDown(stamp(event), trackPosition(event.localPosition));
  }

  /// Handles a raw pointer move.
  void handleMove(PointerMoveEvent event) {
    if (!ownsPointer(event)) return;
    motion.pointerMove(stamp(event), trackPosition(event.localPosition));
  }

  /// Handles a raw pointer up.
  void handleUp(PointerUpEvent event) {
    if (!ownsPointer(event)) return;
    _pointer = null;
    motion.pointerUp(stamp(event), trackPosition(event.localPosition));
  }

  /// Handles a cancelled pointer.
  void handleCancel(PointerCancelEvent event) {
    if (!ownsPointer(event)) return;
    _pointer = null;
    motion.pointerCancel(stamp(event));
  }
}
