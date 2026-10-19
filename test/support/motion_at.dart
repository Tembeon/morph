import 'package:morph/src/widgets/alert_motion.dart';
import 'package:morph/src/widgets/date_picker_motion.dart';
import 'package:morph/src/widgets/push_zoom_motion.dart';
import 'package:morph/src/widgets/sheet_motion.dart';
import 'package:morph/src/widgets/zoom_motion.dart';

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

/// See [MorphAlertMotionAt].
extension MorphSheetMotionAt on MorphSheetMotion {
  /// Advances to [t] and returns this motion.
  MorphSheetMotion at(double t) {
    advance(t);
    return this;
  }
}

/// See [MorphAlertMotionAt].
extension MorphZoomMotionAt on MorphZoomMotion {
  /// Advances to [t] and returns this motion.
  MorphZoomMotion at(double t) {
    advance(t);
    return this;
  }
}

/// See [MorphAlertMotionAt].
extension MorphPushZoomMotionAt on MorphPushZoomMotion {
  /// Advances to [t] and returns this motion.
  MorphPushZoomMotion at(double t) {
    advance(t);
    return this;
  }
}

/// See [MorphAlertMotionAt].
extension MorphDatePickerMotionAt on MorphDatePickerMotion {
  /// Advances to [t] and returns this motion.
  MorphDatePickerMotion at(double t) {
    advance(t);
    return this;
  }
}
