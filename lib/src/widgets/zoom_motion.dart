import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/spring_state.dart';

/// The measured motion of UIKit's zoom transition (`preferredTransition =
/// .zoom`) into a sheet.
///
/// Read from screen recordings of an iPhone 16 Pro on iOS 27.0.1: a page
/// sheet presented from a 140 x 48 capsule and from a 160 x 100 card, each
/// presented and dismissed programmatically, and dismissed by a tap on the
/// dimming and by drags. The zooming container is not a single
/// interpolation: its center and its size ride springs of their own, and
/// the two springs differ by direction (the center leads on the way in,
/// the size on the way out). The dimming rides the springs UIKit's
/// `_UIZoomTransitionSpec` declares (zoomIn 0.34 / 1.0, zoomOut 0.34 /
/// 0.92), and the content crossfade is a short critically damped spring
/// of its own.
@immutable
class MorphZoomTuning {
  /// UIKit's zoom-in dimming spring from `_UIZoomTransitionSpec`.
  static const zoomInSpring = MorphSpring(0.34, 1);

  /// UIKit's zoom-out spring from `_UIZoomTransitionSpec`.
  static const zoomOutSpring = MorphSpring(0.34, 0.92);

  /// The push zoom's measured dismissal speed, in points per second.
  static const double dismissVelocityThreshold = 1050;

  /// Creates a tuning from explicit values.
  const MorphZoomTuning({
    this.openCenterSpring = const MorphSpring(0.349, 0.833),
    this.openSizeSpring = const MorphSpring(0.472, 0.748),
    this.closeCenterSpring = const MorphSpring(0.442, 0.762),
    this.closeSizeSpring = const MorphSpring(0.203, 1),
    this.fadeSpring = const MorphSpring(0.154, 1),
    this.openFadeDelay = 0.045,
    this.openDimmingSpring = zoomInSpring,
    this.closeDimmingSpring = zoomOutSpring,
    this.scrubSideRate = 0.275,
    this.scrubTopRate = 1.115,
    this.scrubBottomRate = 0.04,
    this.scrubStretch = 17,
    this.scrubReturnSpring = const MorphSpring(0.196, 1),
    this.scrubDismissTravel = 100,
    this.scrubDismissVelocity = dismissVelocityThreshold,
  });

  /// The spring the container's center travels on toward the sheet.
  ///
  /// Fitted with [openSizeSpring] to two device presents: 3.3 points rms
  /// over the container's edges.
  final MorphSpring openCenterSpring;

  /// The spring the container's size grows on toward the sheet.
  final MorphSpring openSizeSpring;

  /// The spring the container's center travels on back to the source.
  ///
  /// Fitted with [closeSizeSpring] to two device dismissals: 5.2 points
  /// rms, worst at the first frames, where the sheet leaves its detent.
  final MorphSpring closeCenterSpring;

  /// The spring the container's size shrinks on back to the source.
  final MorphSpring closeSizeSpring;

  /// The spring of the crossfade from the source's look to the sheet's
  /// content and back (device fits 0.152 - 0.158 s, critically damped).
  final MorphSpring fadeSpring;

  /// Seconds the crossfade waits after the container starts to grow
  /// (device 0.043 - 0.047); on the way back it starts at once.
  final double openFadeDelay;

  /// The spring of the dimming while the sheet zooms in: UIKit's zoomIn
  /// spring (device fit 0.322 - 0.325 s, critically damped).
  final MorphSpring openDimmingSpring;

  /// The spring of the dimming while the sheet zooms out: UIKit's zoomOut
  /// spring (device fit 0.350 - 0.357 / 0.919).
  final MorphSpring closeDimmingSpring;

  /// How far each side of a scrubbed sheet draws in per point the finger
  /// has travelled since the drag began (held device drags: 0.27 - 0.28).
  final double scrubSideRate;

  /// How far a scrubbed sheet's top moves down per point of travel (the
  /// top runs a little ahead of the finger: 1.115 on a slow drag, the
  /// same held after fast ones).
  final double scrubTopRate;

  /// How far a scrubbed sheet's bottom rises per point of travel (0.03 -
  /// 0.05).
  final double scrubBottomRate;

  /// The most a finger back above where the drag began grows a scrubbed
  /// sheet by, in points of travel (the device showed 17).
  final double scrubStretch;

  /// The spring a scrubbed sheet released short of a dismissal returns to
  /// its detent on (device fit 0.196 s, critically damped).
  final MorphSpring scrubReturnSpring;

  /// The travel past which a released scrubbed sheet zooms back into its
  /// source: held drags of 77 points returned, of 126 and more dismissed.
  final double scrubDismissTravel;

  /// The downward release speed, in points per second, past which a
  /// scrubbed sheet zooms back into its source whatever its travel (the
  /// push zoom's measured threshold; a sheet flicked 125 points
  /// dismissed).
  final double scrubDismissVelocity;

  /// The frame of [sheet] scrubbed by a finger that has travelled
  /// [travel] points down since the drag began: the sheet's top follows
  /// the finger a little ahead of it, its sides draw in and its bottom
  /// barely rises; a finger back above where the drag began grows the
  /// sheet the same way, by at most [scrubStretch] of travel.
  Rect scrubFrame(Rect sheet, double travel) {
    final e = math.max(travel, -scrubStretch);
    return Rect.fromLTRB(
      sheet.left + scrubSideRate * e,
      sheet.top + scrubTopRate * e,
      sheet.right - scrubSideRate * e,
      sheet.bottom - scrubBottomRate * e,
    );
  }

  /// The measured tuning.
  static const standard = MorphZoomTuning();
}

/// The zoom of a surface out of its source and back, as a pure function of
/// time.
///
/// Four progress values run from 0 (the source) to 1 (the destination):
/// the container's center, its size, the crossfade of what it shows and
/// the dimming behind it. [open] sends them all to 1 and [close] to 0; a
/// reversal carries each one's velocity, so an interrupted zoom turns
/// around continuously. The container is [rect] between the source's and
/// the destination's frames; the destination's content is laid out at its
/// own size and scaled uniformly to fit the container from its top
/// leading corner, the source's look is stretched over the container, and
/// [fade] crossfades them (UIKit's zoom draws the two that way).
class MorphZoomMotion {
  /// Creates a motion resting at the source.
  MorphZoomMotion({this.tuning = MorphZoomTuning.standard})
    : _center = MorphSpringState(tuning.openCenterSpring, 0),
      _size = MorphSpringState(tuning.openSizeSpring, 0),
      _fade = MorphSpringState(tuning.fadeSpring, 0),
      _dim = MorphSpringState(tuning.openDimmingSpring, 0);

  /// The measured behavior this motion reproduces.
  final MorphZoomTuning tuning;

  final MorphSpringState _center;
  final MorphSpringState _size;
  final MorphSpringState _fade;
  final MorphSpringState _dim;
  double? _fadeAt;
  double _now = 0;
  bool _opening = false;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Whether the motion heads to the destination.
  bool get isOpening => _opening;

  /// Zooms out of the source into the destination from time [t].
  void open(double t) {
    advance(t);
    _opening = true;
    _center.retarget(t, 1, spring: tuning.openCenterSpring);
    _size.retarget(t, 1, spring: tuning.openSizeSpring);
    _dim.retarget(t, 1, spring: tuning.openDimmingSpring);
    _fadeAt = t + tuning.openFadeDelay;
  }

  /// Zooms back into the source from time [t].
  void close(double t) {
    advance(t);
    _opening = false;
    _fadeAt = null;
    _center.retarget(t, 0, spring: tuning.closeCenterSpring);
    _size.retarget(t, 0, spring: tuning.closeSizeSpring);
    _fade.retarget(t, 0);
    _dim.retarget(t, 0, spring: tuning.closeDimmingSpring);
  }

  /// Advances the motion to time [t], applying a pending crossfade.
  void advance(double t) {
    if (t > _now) _now = t;
    final at = _fadeAt;
    if (at != null && at <= _now) {
      _fadeAt = null;
      _fade.retarget(at, 1);
    }
  }

  /// The progress of the container's center at time [t].
  double centerProgress(double t) => _center.value(t);

  /// The progress of the container's size at time [t].
  double sizeProgress(double t) => _size.value(t);

  /// The opacity of the destination's content at time [t]; the source's
  /// look shows at one minus it.
  double fade(double t) => _fade.value(t).clamp(0.0, 1.0);

  /// The fraction of the destination's dimming at time [t].
  double dimming(double t) => _dim.value(t).clamp(0.0, 1.0);

  /// The container's frame at time [t] between [source] and
  /// [destination].
  Rect rect(double t, Rect source, Rect destination) {
    final c = _center.value(t);
    final s = _size.value(t);
    final center = Offset.lerp(source.center, destination.center, c)!;
    return Rect.fromCenter(
      center: center,
      width: lerpDouble(source.width, destination.width, s)!,
      height: lerpDouble(source.height, destination.height, s)!,
    );
  }

  /// The uniform scale the destination's content is drawn at inside
  /// [container], laid out at [destination]'s size.
  static double contentScale(Rect container, Size destination) {
    if (destination.width <= 0 || destination.height <= 0) return 1;
    final sx = container.width / destination.width;
    final sy = container.height / destination.height;
    return sx < sy ? sx : sy;
  }

  /// Whether the motion has come back to the source and rests there.
  bool get isClosed =>
      !_opening &&
      _center.isAtRest(_now, 0.002) &&
      _size.isAtRest(_now, 0.002) &&
      _fade.isAtRest(_now, 0.002) &&
      _dim.isAtRest(_now, 0.002);

  /// Whether nothing moves and nothing is pending.
  bool get isSettled =>
      _fadeAt == null &&
      _center.isAtRest(_now, 0.002) &&
      _size.isAtRest(_now, 0.002) &&
      _fade.isAtRest(_now, 0.002) &&
      _dim.isAtRest(_now, 0.002);
}
