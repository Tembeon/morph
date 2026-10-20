import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:morph/src/motion/spring.dart';
import 'package:morph/src/motion/spring_state.dart';
import 'package:morph/src/widgets/menu_motion.dart'
    show MorphFusionTurns, MorphMenuTuning;

/// A zoom of a surface out of its source and back, as a pure function of
/// time: the classic zoom ([MorphZoomMotion]) or the liquid one out of a
/// glass source ([MorphLiquidZoomMotion]).
@internal
abstract interface class MorphZoom {
  /// The farthest, in pixels, a progress of 1 moves an edge of the
  /// zooming surface; the host updates it from the frames it zooms
  /// between.
  abstract double travel;

  /// The time the motion was last advanced to.
  double get time;

  /// Whether the motion heads to the destination.
  bool get isOpening;

  /// Whether the motion has come back to the source and rests there.
  bool get isClosed;

  /// Whether nothing moves and nothing is pending.
  bool get isSettled;

  /// Zooms out of the source from time [t].
  void open(double t);

  /// Zooms back into the source from time [t].
  void close(double t);

  /// Advances the motion to time [t].
  void advance(double t);

  /// The zooming surface's frame between [source] and [destination].
  Rect rect(Rect source, Rect destination);

  /// The progress of the surface's size.
  double get sizeProgress;

  /// The opacity of the destination's content.
  double get fade;

  /// The fraction of the destination's dimming.
  double get dimming;
}

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
class MorphZoomMotion implements MorphZoom {
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

  /// The farthest, in pixels, a progress of 1 moves an edge of the
  /// container ([MorphRest.travel] between its two frames); the host
  /// updates it from the frames it zooms between.
  @override
  double travel = MorphRest.screen;

  /// The time the motion was last advanced to.
  @override
  double get time => _now;

  /// Whether the motion heads to the destination.
  @override
  bool get isOpening => _opening;

  /// Zooms out of the source into the destination from time [t].
  @override
  void open(double t) {
    advance(t);
    _opening = true;
    _center.retarget(t, 1, spring: tuning.openCenterSpring);
    _size.retarget(t, 1, spring: tuning.openSizeSpring);
    _dim.retarget(t, 1, spring: tuning.openDimmingSpring);
    _fadeAt = t + tuning.openFadeDelay;
  }

  /// Zooms back into the source from time [t].
  @override
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
  @override
  void advance(double t) {
    if (t > _now) _now = t;
    final at = _fadeAt;
    if (at != null && at <= _now) {
      _fadeAt = null;
      _fade.retarget(at, 1);
    }
  }

  /// The progress of the container's center.
  double get centerProgress => _centerProgressAt(_now);

  double _centerProgressAt(double t) => _center.value(t);

  /// The progress of the container's size.
  @override
  double get sizeProgress => _sizeProgressAt(_now);

  double _sizeProgressAt(double t) => _size.value(t);

  /// The opacity of the destination's content; the source's
  /// look shows at one minus it.
  @override
  double get fade => _fade.value(_now).clamp(0.0, 1.0);

  /// The fraction of the destination's dimming.
  @override
  double get dimming => _dimmingAt(_now);

  double _dimmingAt(double t) => _dim.value(t).clamp(0.0, 1.0);

  /// The container's frame between [source] and
  /// [destination].
  @override
  Rect rect(Rect source, Rect destination) =>
      _rectAt(_now, source, destination);

  Rect _rectAt(double t, Rect source, Rect destination) {
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
  @override
  bool get isClosed => !_opening && _rests;

  /// Whether nothing moves and nothing is pending.
  @override
  bool get isSettled => _fadeAt == null && _rests;

  /// Whether what remains of the motion is invisible ([MorphRest], NEAR):
  /// the center and the size move an edge less than [MorphRest.length] over
  /// [travel], the crossfade and the dimming change less than
  /// [MorphRest.opacity].
  bool get _rests {
    final progress = MorphRest.scale(travel);
    return _center.isWithin(_now, progress) &&
        _size.isWithin(_now, progress) &&
        _fade.isWithin(_now, MorphRest.opacity) &&
        _dim.isWithin(_now, MorphRest.opacity);
  }
}

/// The measured motion of UIKit's zoom out of a glass source: the liquid
/// morph (`_UIZoomLiquidMorphAnimator`, read from UIKit, notes private),
/// the same two-blob morph a glass button grows its menu with.
///
/// Read from an iPhone 16 Pro on iOS 27.0.1 (probe scene `snzoom` with a
/// glass `UIButton` source 140 x 48, page sheet at medium and large): the
/// presentation frames of the two glass elements the morph fuses, sampled
/// on every display frame (test/fixtures/ios27-device/zoom/liquid.json).
/// The sheet's glass grows out of a [seedDiameter] circle at the source's
/// center while the source's glass shrinks to [sourceRestSize] on its way
/// into the sheet; closing, the sheet shrinks back into that circle while
/// the source's glass grows back where it rests. Each edge rides a spring
/// of its own, fitted to those frames within 0.1 - 2.1 points rms.
@immutable
class MorphLiquidZoomTuning {
  /// Creates a tuning from explicit values.
  const MorphLiquidZoomTuning({
    this.openCenterSpring = const MorphSpring(0.295, 0.68),
    this.openSizeSpring = const MorphSpring(0.36, 0.74),
    this.openSourceTravelSpring = const MorphSpring(0.355, 0.74),
    this.openSourceWidthSpring = const MorphSpring(0.205, 0.97),
    this.openSourceHeightSpring = const MorphSpring(0.355, 0.74),
    this.openCornerSpring = const MorphSpring(0.4, 0.8),
    this.openCornerDelay = 0.028,
    this.openCornerFrom = 500,
    this.closeCenterSpring = const MorphSpring(0.42, 0.82),
    this.closeCenterDelay = 0.033,
    this.closeSizeSpring = const MorphSpring(0.49, 0.8),
    this.closeSourceTravelSpring = const MorphSpring(0.42, 0.69),
    this.closeSourceTravelDelay = 0.006,
    this.closeSourceWidthSpring = const MorphSpring(0.54, 0.74),
    this.closeSourceWidthDelay = 0.017,
    this.closeSourceHeightSpring = const MorphSpring(0.49, 0.8),
    this.closeCornerSpring = const MorphSpring(0.48, 0.82),
    this.closeCornerTo = 201,
    this.lookSpring = const MorphSpring(0.207, 0.98),
    this.openDimmingSpring = MorphZoomTuning.zoomInSpring,
    this.closeDimmingSpring = MorphZoomTuning.zoomOutSpring,
    this.seedDiameter = 20.5,
    this.sourceRestSize = 12,
    this.sourceTravel = 0.33,
  });

  /// The spring the sheet's center travels on out of the source (device
  /// fits 0.29 - 0.30 / 0.68).
  final MorphSpring openCenterSpring;

  /// The spring the sheet's width and height grow on out of the seed
  /// (0.35 - 0.37 / 0.72 - 0.74).
  final MorphSpring openSizeSpring;

  /// The spring the source's glass travels on into the sheet.
  final MorphSpring openSourceTravelSpring;

  /// The spring the source's glass narrows on (0.20 - 0.21, nearly
  /// critically damped): it narrows ahead of its height.
  final MorphSpring openSourceWidthSpring;

  /// The spring the source's glass flattens on.
  final MorphSpring openSourceHeightSpring;

  /// The spring the sheet's corners round down on, from [openCornerFrom]
  /// toward the sheet's own radii.
  final MorphSpring openCornerSpring;

  /// Seconds the corners wait after the sheet starts to grow.
  final double openCornerDelay;

  /// The radius the opening corners start from: far past half the short
  /// side, so the growing sheet stays a capsule until the corners round
  /// down below it (the device's corners hold at 201 for 0.15 s).
  final double openCornerFrom;

  /// The spring the sheet's center travels on back to the source (0.42 -
  /// 0.43 / 0.82).
  final MorphSpring closeCenterSpring;

  /// Seconds the closing sheet's center waits after its size starts to
  /// shrink (0.031 - 0.035): its top first comes down toward the source.
  final double closeCenterDelay;

  /// The spring the sheet's width and height shrink on into the seed.
  final MorphSpring closeSizeSpring;

  /// The spring the source's glass travels on back to its place.
  final MorphSpring closeSourceTravelSpring;

  /// Seconds the source's glass waits before it travels back.
  final double closeSourceTravelDelay;

  /// The spring the source's glass widens on: it lands a few points wide
  /// and settles (0.54 / 0.74).
  final MorphSpring closeSourceWidthSpring;

  /// Seconds the source's glass waits before it widens.
  final double closeSourceWidthDelay;

  /// The spring the source's glass grows back to its height on.
  final MorphSpring closeSourceHeightSpring;

  /// The spring the closing corners round up on, toward [closeCornerTo].
  final MorphSpring closeCornerSpring;

  /// The radius the closing corners head for: a capsule once the sheet
  /// is small.
  final double closeCornerTo;

  /// The crossfade of the source's look and the sheet's content, both
  /// ways (0.204 - 0.208 / 0.98 - 1.0, within 0.003 of the device's
  /// portal opacities).
  final MorphSpring lookSpring;

  /// The dimming spring while the sheet grows: UIKit's zoomIn spring.
  final MorphSpring openDimmingSpring;

  /// The dimming spring while the sheet shrinks: UIKit's zoomOut spring.
  final MorphSpring closeDimmingSpring;

  /// The diameter of the circle the sheet grows out of and shrinks into,
  /// at the source's center.
  final double seedDiameter;

  /// The side of the square the source's glass shrinks to inside the
  /// sheet.
  final double sourceRestSize;

  /// How far toward the sheet's center the source's glass travels, as a
  /// fraction of the way (0.33 at the medium detent; it rests inside the
  /// sheet, where it fuses unseen).
  final double sourceTravel;

  /// The measured tuning.
  static const standard = MorphLiquidZoomTuning();
}

/// A channel's spring start that waits for its delay.
typedef _Pending = ({
  double at,
  MorphSpringState state,
  double target,
  MorphSpring spring,
});

/// The liquid zoom of a sheet out of a glass source and back, as a pure
/// function of time.
///
/// Progress values run from 0 (at the source) to 1 (the sheet), each on
/// its own spring: the sheet's center and size, the source glass's travel,
/// width and height, the corners, the crossfade of the source's look into
/// the sheet's content, and the dimming. [open] sends them to 1 and
/// [close] to 0; a reversal carries each one's velocity.
class MorphLiquidZoomMotion implements MorphZoom {
  /// Creates a motion resting at the source.
  MorphLiquidZoomMotion({this.tuning = MorphLiquidZoomTuning.standard})
    : _center = MorphSpringState(tuning.openCenterSpring, 0),
      _size = MorphSpringState(tuning.openSizeSpring, 0),
      _travel = MorphSpringState(tuning.openSourceTravelSpring, 0),
      _width = MorphSpringState(tuning.openSourceWidthSpring, 0),
      _height = MorphSpringState(tuning.openSourceHeightSpring, 0),
      _corner = MorphSpringState(tuning.openCornerSpring, 0),
      _look = MorphSpringState(tuning.lookSpring, 0),
      _dim = MorphSpringState(tuning.openDimmingSpring, 0);

  /// The measured behavior this motion reproduces.
  final MorphLiquidZoomTuning tuning;

  final MorphSpringState _center;
  final MorphSpringState _size;
  final MorphSpringState _travel;
  final MorphSpringState _width;
  final MorphSpringState _height;
  final MorphSpringState _corner;
  final MorphSpringState _look;
  final MorphSpringState _dim;
  final List<_Pending> _pending = [];
  double _cornerFar = 0;
  double _now = 0;
  bool _opening = false;
  final MorphFusionTurns _fusions = MorphFusionTurns(MorphMenuTuning.standard);

  /// The farthest, in pixels, a progress of 1 moves an edge of the sheet
  /// ([MorphRest.travel] between the source and the sheet); the host
  /// updates it from the frames it zooms between.
  @override
  double travel = MorphRest.screen;

  /// The time the motion was last advanced to.
  @override
  double get time => _now;

  /// Whether the motion heads to the sheet.
  @override
  bool get isOpening => _opening;

  /// Grows the sheet out of the source from time [t].
  @override
  void open(double t) {
    advance(t);
    _opening = true;
    _fusions.start(t, opening: true);
    _cornerFar = tuning.openCornerFrom;
    _center.retarget(t, 1, spring: tuning.openCenterSpring);
    _size.retarget(t, 1, spring: tuning.openSizeSpring);
    _travel.retarget(t, 1, spring: tuning.openSourceTravelSpring);
    _width.retarget(t, 1, spring: tuning.openSourceWidthSpring);
    _height.retarget(t, 1, spring: tuning.openSourceHeightSpring);
    _look.retarget(t, 1);
    _dim.retarget(t, 1, spring: tuning.openDimmingSpring);
    _pending.clear();
    _pending.add((
      at: t + tuning.openCornerDelay,
      state: _corner,
      target: 1,
      spring: tuning.openCornerSpring,
    ));
  }

  /// Shrinks the sheet back into the source from time [t].
  @override
  void close(double t) {
    advance(t);
    _opening = false;
    _fusions.start(t, opening: false);
    _pending.clear();
    _cornerFar = tuning.closeCornerTo;
    _size.retarget(t, 0, spring: tuning.closeSizeSpring);
    _height.retarget(t, 0, spring: tuning.closeSourceHeightSpring);
    _pending.addAll([
      (
        at: t + tuning.closeCenterDelay,
        state: _center,
        target: 0,
        spring: tuning.closeCenterSpring,
      ),
      (
        at: t + tuning.closeSourceTravelDelay,
        state: _travel,
        target: 0,
        spring: tuning.closeSourceTravelSpring,
      ),
      (
        at: t + tuning.closeSourceWidthDelay,
        state: _width,
        target: 0,
        spring: tuning.closeSourceWidthSpring,
      ),
    ]);
    _corner.retarget(t, 0, spring: tuning.closeCornerSpring);
    _look.retarget(t, 0);
    _dim.retarget(t, 0, spring: tuning.closeDimmingSpring);
  }

  /// Advances the motion to time [t], starting the channels that wait
  /// when they are due.
  @override
  void advance(double t) {
    if (t > _now) _now = t;
    _pending.removeWhere((pending) {
      if (pending.at > _now) return false;
      pending.state.retarget(
        pending.at,
        pending.target,
        spring: pending.spring,
      );
      return true;
    });
  }

  /// The sheet's frame between [source] and [sheet]: out of a circle at
  /// the source's center.
  Rect container(Rect source, Rect sheet) {
    final seed = Rect.fromCenter(
      center: source.center,
      width: tuning.seedDiameter,
      height: tuning.seedDiameter,
    );
    final c = _center.value(_now);
    final s = _size.value(_now);
    return Rect.fromCenter(
      center: Offset.lerp(seed.center, sheet.center, c)!,
      width: math.max(0, lerpDouble(seed.width, sheet.width, s)!),
      height: math.max(0, lerpDouble(seed.height, sheet.height, s)!),
    );
  }

  @override
  Rect rect(Rect source, Rect destination) => container(source, destination);

  /// The source glass's frame: at [source] at rest, a small square inside
  /// [sheet] while the sheet shows.
  Rect sourceGlass(Rect source, Rect sheet) {
    final rest = Offset.lerp(source.center, sheet.center, tuning.sourceTravel)!;
    final size = tuning.sourceRestSize;
    return Rect.fromCenter(
      center: Offset.lerp(source.center, rest, _travel.value(_now))!,
      width: math.max(0, lerpDouble(source.width, size, _width.value(_now))!),
      height: math.max(
        0,
        lerpDouble(source.height, size, _height.value(_now))!,
      ),
    );
  }

  /// The radius a sheet corner of resting radius [rest] shows now; a
  /// radius past half the sheet's short side draws a capsule.
  double corner(double rest) =>
      rest + (_cornerFar - rest) * (1 - _corner.value(_now));

  /// The radius, in points, of the blur that fuses the sheet's glass and
  /// the source's: the envelope of the menu's liquid morph
  /// ([MorphMenuTuning.fusionEnvelope]), started by every [open] and
  /// [close]. UIKit draws both with the same liquid morph; the zoom's own
  /// radius is not measured (NEAR, assumed the menu's).
  double get fusionRadius => _fusions.radiusAt(_now);

  /// Whether the sheet's glass and the source's still fuse: from every
  /// [open] or [close] until its fusion envelope ends.
  bool get fusing => !_fusions.endedAt(_now);

  /// The opacity of the sheet's content; the source's look shows at one
  /// minus it.
  @override
  double get fade => _look.value(_now).clamp(0.0, 1.0);

  /// The fraction of the sheet's dimming.
  @override
  double get dimming => _dim.value(_now).clamp(0.0, 1.0);

  /// The progress of the sheet's size, the measure a caller fades or
  /// dissolves by.
  @override
  double get sizeProgress => _size.value(_now);

  /// Whether the motion has come back to the source and rests there.
  @override
  bool get isClosed => !_opening && _rests;

  /// Whether nothing moves and nothing is pending.
  @override
  bool get isSettled => _pending.isEmpty && _rests && !fusing;

  bool get _rests {
    final progress = MorphRest.scale(travel);
    return _center.isWithin(_now, progress) &&
        _size.isWithin(_now, progress) &&
        _travel.isWithin(_now, progress) &&
        _width.isWithin(_now, progress) &&
        _height.isWithin(_now, progress) &&
        _corner.isWithin(_now, MorphRest.scale(tuning.openCornerFrom)) &&
        _look.isWithin(_now, MorphRest.opacity) &&
        _dim.isWithin(_now, MorphRest.opacity);
  }
}
