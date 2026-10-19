import 'package:morph/src/widgets/alert_motion.dart';

/// Replays read a motion at their rows' time stamps: [at] advances the
/// motion to [t] and returns it for the read.
extension MorphAlertMotionAt on MorphAlertMotion {
  /// Advances to [t] and returns this motion.
  MorphAlertMotion at(double t) {
    advance(t);
    return this;
  }
}

/// See [MorphAlertMotionAt].
extension MorphPopoverMotionAt on MorphPopoverMotion {
  /// Advances to [t] and returns this motion.
  MorphPopoverMotion at(double t) {
    advance(t);
    return this;
  }
}
