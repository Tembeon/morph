import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/lens_motion.dart';

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

  /// Handles a raw pointer down.
  void handleDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;
    motion.pointerDown(stamp(event), trackPosition(event.localPosition));
  }

  /// Handles a raw pointer move.
  void handleMove(PointerMoveEvent event) {
    motion.pointerMove(stamp(event), trackPosition(event.localPosition));
  }

  /// Handles a raw pointer up.
  void handleUp(PointerUpEvent event) {
    motion.pointerUp(stamp(event), trackPosition(event.localPosition));
  }

  /// Handles a cancelled pointer.
  void handleCancel(PointerCancelEvent event) {
    motion.pointerCancel(stamp(event));
  }
}
