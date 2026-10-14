import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:morph/src/gesture.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/timeline.dart';

/// A height a sheet rests at, after UISheetPresentationController.Detent.
///
/// A detent's value is the height of the sheet above the bottom safe
/// area; the sheet itself extends under it to the screen's edge. The
/// largest possible value, the "maximum", is the container height minus
/// the top and bottom safe areas, the room UIKit hands a custom detent's
/// resolver.
@immutable
class MorphSheetDetent {
  const MorphSheetDetent._(this._kind, this._value)
    : _resolver = null,
      _identifier = null;

  /// A detent whose value [resolver] computes from the maximum value, as
  /// UIKit's `.custom(identifier:resolver:)`; detents with the same
  /// [identifier] are the same detent (null compares the resolver).
  const MorphSheetDetent.custom(
    double Function(double maximum) resolver, {
    this._identifier,
  }) : _kind = _DetentKind.custom,
       _value = 0,
       _resolver = resolver;

  /// A detent as tall as the sheet's content (SwiftUI
  /// `presentationSizing(.fitted)`), up to the maximum.
  ///
  /// The sheet lays its content out with a loose height and rests it at
  /// the top; content that scrolls fills the maximum instead. Until the
  /// content has laid out once the detent is the maximum.
  static const fitted = MorphSheetDetent._(_DetentKind.fitted, 0);

  /// A detent [value] points tall, clamped to the maximum.
  const MorphSheetDetent.height(double value)
    : this._(_DetentKind.height, value);

  /// A detent at [fraction] of the maximum.
  const MorphSheetDetent.fraction(double fraction)
    : this._(_DetentKind.fraction, fraction);

  /// UIKit's medium detent: [MorphSheetTuning.mediumFraction] of the
  /// maximum.
  static const medium = MorphSheetDetent._(
    _DetentKind.fraction,
    MorphSheetTuning.mediumFraction,
  );

  /// UIKit's large detent: the whole maximum. A sheet at the large detent
  /// docks to the screen edges and turns opaque.
  static const large = MorphSheetDetent._(_DetentKind.large, 1);

  final _DetentKind _kind;
  final double _value;
  final double Function(double maximum)? _resolver;
  final Object? _identifier;

  /// Whether this detent follows the height of the sheet's content.
  bool get isFitted => _kind == _DetentKind.fitted;

  /// Whether this is the full-height detent that docks the sheet.
  bool get isLarge => _kind == _DetentKind.large;

  /// The detent's value for a [maximum] value; a [fitted] detent takes
  /// the content's [fittedHeight], the maximum while it is unknown.
  double resolve(double maximum, {double? fittedHeight}) => switch (_kind) {
    _DetentKind.large => maximum,
    _DetentKind.fraction => maximum * _value.clamp(0.0, 1.0),
    _DetentKind.height => _value.clamp(0.0, maximum),
    _DetentKind.custom => _resolver!(maximum).clamp(0.0, maximum),
    _DetentKind.fitted => (fittedHeight ?? maximum).clamp(0.0, maximum),
  };

  @override
  bool operator ==(Object other) =>
      other is MorphSheetDetent &&
      other._kind == _kind &&
      other._value == _value &&
      (_kind != _DetentKind.custom ||
          (_identifier == null
              ? other._identifier == null && other._resolver == _resolver
              : other._identifier == _identifier));

  @override
  int get hashCode => Object.hash(
    _kind,
    _value,
    _kind == _DetentKind.custom ? (_identifier ?? _resolver) : null,
  );

  @override
  String toString() => switch (_kind) {
    _DetentKind.large => 'MorphSheetDetent.large',
    _DetentKind.fraction => 'MorphSheetDetent.fraction($_value)',
    _DetentKind.height => 'MorphSheetDetent.height($_value)',
    _DetentKind.custom => 'MorphSheetDetent.custom(${_identifier ?? ''})',
    _DetentKind.fitted => 'MorphSheetDetent.fitted',
  };
}

enum _DetentKind { height, fraction, large, custom, fitted }

/// The measured tuning of an iOS 27 sheet (UISheetPresentationController).
abstract final class MorphSheetTuning {
  /// The spring of every sheet animation: presenting, dismissing and
  /// moving between detents. UIKit runs a CASpringAnimation of stiffness
  /// 333.3 and damping 36.5, mass 1: response 0.344 s, critically damped.
  /// The simulator's frames fit it to 0.06 points.
  static const spring = MorphSpring(0.3441, 1);

  /// The medium detent as a fraction of the maximum (435.68 of 778 on a
  /// 402 x 874 screen, read from UIKit's resolution context).
  static const double mediumFraction = 0.56;

  /// The gap around a sheet resting below the large detent, in points:
  /// it floats 8 points from the sides and the bottom of the screen.
  static const double floatingInset = 8;

  /// The radius of the top corners, in the sheet's unscaled points.
  static const double topRadius = 38;

  /// The display corner radius assumed for a floating sheet when the
  /// platform reports none: the iPhone 16 Pro's, where the floating
  /// sheet's bottom corners (62 - 8 = 54 unscaled points) were measured.
  /// The bottom corners grow to the display's radius as the sheet docks,
  /// or flatten to square where the platform reports no radius.
  static const double fallbackDisplayRadius = 62;

  /// The opacity of the black dimming behind a dimmed detent.
  static const double dimmingOpacity = 0.2;

  /// The grabber's size in unscaled points.
  static const Size grabberSize = Size(60, 4);

  /// The distance from the sheet's top edge to the grabber's center.
  static const double grabberOffset = 8;

  /// How far momentum carries a released drag, in seconds of the
  /// release velocity: the sheet settles on the detent nearest to its
  /// height plus the velocity times this. Bracketed by flicks on the
  /// simulator: 680 pt/s up from 544 pt stayed at medium, 680 pt/s down
  /// from 738 pt went to medium (0.143 either way).
  static const double projection = 0.143;

  /// How much faster than the finger the sheet leaves the release: the
  /// settle spring starts at this many times the finger's velocity
  /// (fitted to seven flicks: 2.0 - 2.6, the slowest ones nearest 2).
  static const double releaseVelocityGain = 2;

  /// The release speed, in points per second down, that dismisses a
  /// sheet dragged below its smallest detent however short the drag: a
  /// 680 pt/s flick returned, 900 and 1213 pt/s flicks dismissed.
  static const double dismissVelocity = 1000;

  /// The spring a sheet flicked away leaves on; a sheet released still
  /// leaves on [spring]. Fitted to three flick dismissals (0.12 - 0.5 pt
  /// rms, response 0.349 - 0.354, damping 0.79).
  static const flickDismissSpring = MorphSpring(0.352, 0.79);

  /// The fraction of the finger's velocity a flicked-away sheet leaves
  /// with (0.53 and 0.65 fitted).
  static const double flickDismissVelocityGain = 0.6;

  /// The scale a floating sheet swells by under a touch.
  static const double pressScale = 1.00854;

  /// The spring the swell follows, on touch and on release (0.0001 rms in
  /// scale on a held touch).
  static const pressSpring = MorphSpring(0.2835, 0.70);

  /// Seconds between a touch and the start of the swell.
  static const double pressDelay = 0.028;

  /// How much a drag stretches a sheet that floated when the drag began,
  /// per point the finger travelled since: the ratio of the sheet's
  /// vertical to its horizontal scale is `1 + stretchPerPoint * travel`
  /// plus [stretchLagGain] of the lag, up or down alike. The height grows
  /// and the width shrinks by the square root of that ratio each, so the
  /// area holds, about the sheet's bottom edge. Fitted to three device
  /// drags held still (100 and 320 points down, 140 up: 8.80 - 9.00e-5
  /// per point). A sheet docked when the drag began does not stretch.
  static const double stretchPerPoint = 8.9e-5;

  /// The spring of the lag: a point that follows the finger's travel and
  /// its velocity, so it falls behind only while the finger speeds up and
  /// runs ahead while the finger slows down. A drag that starts or speeds
  /// up stretches the sheet further for a moment, one that stops lets it
  /// dip.
  static const stretchLagSpring = MorphSpring(0.8, 0.5);

  /// How much the lag, in points, adds to the stretch ratio. With
  /// [stretchLagSpring] and [stretchPerPoint] it replays the 18 device
  /// drags and flicks of a floating sheet to 0.0011 - 0.0066 rms in the
  /// ratio (0.0016 - 0.0123 without the lag; a 1300 pt/s flick reaches
  /// 1.043 at 168 points of travel, three times the held stretch).
  static const double stretchLagGain = 2.4e-4;

  /// The spring the stretch returns on when the drag ends: it holds from
  /// the lift and leaves with the settle (0.0005 - 0.0008 rms in the
  /// ratio over three releases held still).
  static const stretchSpring = MorphSpring(0.355, 0.62);

  /// Seconds between the lift of a tap on the grabber and the start of the
  /// detent change it causes (0.045 and 0.065 measured).
  static const double grabberTapDelay = 0.05;

  /// Seconds between the lift of a dragging finger and the start of the
  /// settle; the sheet holds still meanwhile (the median of nine
  /// releases, 0.003 - 0.047).
  static const double releaseDelay = 0.025;

  /// The band at the top of the sheet, in unscaled points, where a tap
  /// cycles the detents as a tap on the grabber does; a tap 25 points
  /// below the top edge cycled them.
  static const double grabberHitHeight = 40;

  /// The limit, in unscaled points, that a sheet which cannot be dismissed
  /// approaches while it is pulled down: the drag is rubber-banded with
  /// this dimension. Not measured on a device.
  static const double refusedPullExtent = 40;

  /// The share of [refusedPullExtent] that a refused pull must exceed when
  /// the finger lifts for the sheet to report a dismiss attempt: UIKit
  /// tests the pull beyond the edge against a quarter of its rubber-band
  /// extent once the drag has ended, then calls
  /// `presentationControllerDidAttemptToDismiss` (read from UIKit, notes
  /// private).
  static const double dismissAttemptShare = 0.25;
}

/// The motion of an iOS 27 sheet: its height between detents, its
/// translation while presenting and dismissing, how far it docks to the
/// screen edges and how much it dims what is behind it.
///
/// Heights are the sheet's unscaled heights in pixels, bottom safe area
/// included; the translation moves the sheet down from its resting place.
/// Every animation rides [MorphSheetTuning.spring] and carries velocity
/// through every retarget. A sheet resting below the large detent floats:
/// it is the full-width sheet scaled down so that it keeps
/// [MorphSheetTuning.floatingInset] from the sides and the bottom. UIKit
/// docks it to the large detent as one transform interpolated by the
/// docking progress, the fraction of the height travelled between where
/// the transition started and the large detent (on the way back, between
/// the large detent and the floating one the sheet heads to); the scale,
/// the bottom corner radius and the opaque background follow the same
/// fraction. A move between two floating detents keeps the sheet
/// floating throughout.
///
/// A touch swells a floating sheet by [MorphSheetTuning.pressScale]. A
/// drag moves the sheet's top edge with the finger: between the smallest
/// and the largest detent the height follows it point for point, above
/// the largest it does not move, and below the smallest the whole sheet
/// slides down. A sheet that floats when the drag begins stretches along
/// the drag with the finger's travel and its changes of speed
/// ([MorphSheetTuning.stretchPerPoint]), keeping its area and its bottom
/// edge, and springs back on release.
/// Releasing above the smallest detent settles on the
/// detent nearest to the height projected by
/// [MorphSheetTuning.projection]; releasing below it dismisses when the
/// projected slide passes half the sheet's visible height or the finger
/// moves faster than [MorphSheetTuning.dismissVelocity], and returns
/// otherwise. The settle carries [MorphSheetTuning.releaseVelocityGain]
/// times the finger's velocity. A tap on the grabber band cycles to the
/// next detent.
class MorphSheetMotion {
  /// Creates a motion with the given detent [heights] (ascending), resting
  /// hidden below the screen until [present].
  MorphSheetMotion({
    required List<double> heights,
    required this.width,
    required int initial,
    this.dockedIndex,
    this.undimmedIndex,
    this.dismissible = true,
    this.inset = MorphSheetTuning.floatingInset,
  }) : _heights = List<double>.of(heights),
       _index = initial,
       _height = MorphSpringState(MorphSheetTuning.spring, heights[initial]),
       _offset = MorphSpringState(MorphSheetTuning.spring, 0) {
    _toDocked = initial == dockedIndex;
    _dockStart = _toDocked ? 1 : 0;
    _heightStart = heights[initial];
    _floating = _toDocked ? _floatingBelowDocked : heights[initial];
    _offset.snap(0, hiddenOffset);
  }

  List<double> _heights;

  /// The width of the container in pixels.
  double width;

  /// The index of the detent that docks the sheet edge to edge, or null
  /// when no detent does.
  final int? dockedIndex;

  /// The index of the largest detent that does not dim, or null when
  /// every detent dims.
  final int? undimmedIndex;

  /// Whether a drag or a tap outside may dismiss the sheet; the host
  /// updates it before a drag (a pop scope that turns dismissal off).
  bool dismissible;

  /// The gap around the floating sheet in pixels.
  final double inset;

  final MorphSpringState _height;
  final MorphSpringState _offset;
  final MorphTimeline _timeline = MorphTimeline(now: 0);
  double? _pressAt;
  final MorphSpringState _press = MorphSpringState(
    MorphSheetTuning.pressSpring,
    1,
  );
  final MorphSpringState _stretch = MorphSpringState(
    MorphSheetTuning.stretchSpring,
    0,
  );
  final MorphSpringState _lag = MorphSpringState(
    MorphSheetTuning.stretchLagSpring,
    0,
  );
  bool _stretching = false;
  double _travel = 0;
  double _travelAt = 0;
  double _travelVelocity = 0;
  int _index;
  bool _dismissing = false;
  double _now = 0;

  bool _toDocked = false;
  double _dockStart = 0;
  double _heightStart = 0;
  double _floating = 0;

  double? _dragFrom;
  double _dragTop = 0;

  /// Called with the detent index whenever a settle picks a new one.
  ValueChanged<int>? onDetentChanged;

  /// Called when a released drag dismisses the sheet.
  VoidCallback? onDismiss;

  /// Called when a released drag would have dismissed a sheet that is not
  /// [dismissible]; the sheet returns to its smallest detent.
  VoidCallback? onDismissAttempt;

  /// The detent heights, ascending.
  List<double> get heights => _heights;

  /// The detent the sheet rests at or heads to.
  int get index => _index;

  /// Whether the sheet is leaving or has left.
  bool get isDismissing => _dismissing;

  /// Whether a drag holds the sheet.
  bool get isDragging => _dragFrom != null && !_released;

  /// The time the motion was last advanced to.
  double get time => _now;

  double get _floatingBelowDocked {
    final docked = dockedIndex;
    if (docked == null) return _heights.first;
    return docked > 0 ? _heights[docked - 1] : _heights[docked];
  }

  /// The translation that hides the sheet below the screen: its visible
  /// height and its gap to the bottom at the selected detent.
  double get hiddenOffset {
    final h = _heights[_index];
    final d = _index == dockedIndex ? 1.0 : 0.0;
    final s = _scaleFor(d);
    return h * s + h * (1 - s) / 2 - _shiftFor(h, d);
  }

  /// Whether the sheet is dismissed and still.
  bool get isDismissed =>
      _dismissing && _offset.isAtRest(_now, 0.5) && _dragFrom == null;

  /// Whether nothing moves.
  bool get isSettled =>
      _dragFrom == null &&
      _height.isAtRest(_now, 0.05) &&
      _offset.isAtRest(_now, 0.05) &&
      _timeline.isEmpty &&
      _pressAt == null &&
      !_released &&
      _press.isAtRest(_now, 1e-4) &&
      !_stretching &&
      _stretch.isAtRest(_now, 1e-5);

  /// The unscaled height at time [t].
  double height(double t) => _height.value(t);

  /// The translation down from the resting place at time [t].
  double offset(double t) => _offset.value(t);

  /// The docking progress at time [t]: 0 floating, 1 edge to edge.
  double dock(double t) => _dockFor(height(t));

  double _dockFor(double h) {
    final docked = dockedIndex;
    if (docked == null) return 0;
    final top = _heights[docked];
    if (_dragFrom != null) {
      final ref = _floatingBelowDocked;
      if (top <= ref) return 1;
      return ((h - ref) / (top - ref)).clamp(0.0, 1.0);
    }
    if (_toDocked) {
      final span = top - _heightStart;
      if (span <= 1e-6) return 1;
      return (_dockStart + (1 - _dockStart) * (h - _heightStart) / span).clamp(
        0.0,
        1.0,
      );
    }
    final span = _heightStart - _heights[_index];
    if (span.abs() <= 1e-6) return 0;
    return (_dockStart * (h - _heights[_index]) / span).clamp(0.0, 1.0);
  }

  double _scaleFor(double dock) => 1 - 2 * inset / width * (1 - dock);

  double _shiftFor(double h, double dock) {
    final reference = dock > 0 ? _floating : h;
    return inset * (reference / width - 1) * (1 - dock);
  }

  /// The uniform scale of the sheet at time [t], the swell of a touch
  /// included.
  double scale(double t) => _scaleFor(dock(t)) * pressScale(t);

  /// The ratio of the sheet's vertical to its horizontal scale at time
  /// [t]: 1 at rest, above 1 while a drag stretches the sheet. The drawn
  /// height is the [scale]d height times its square root, the drawn width
  /// the [scale]d width over it, about the bottom edge. A drag that
  /// catches the sheet while a stretch still returns stretches it on top
  /// of that remainder, which keeps returning on
  /// [MorphSheetTuning.stretchSpring].
  double stretch(double t) =>
      1 +
      _stretch.value(t) +
      (_stretching
          ? MorphSheetTuning.stretchPerPoint * _travel +
                MorphSheetTuning.stretchLagGain * _lag.value(t)
          : 0);

  void _holdStretch(double t) {
    if (!_stretching) return;
    _stretch.snap(t, stretch(t) - 1);
    _stretching = false;
  }

  void _releaseStretch(double t) {
    _holdStretch(t);
    _stretch.retarget(t, 0);
  }

  /// The vertical shift of the scaled sheet's center at time [t], on top
  /// of [offset]: what keeps a floating sheet [inset] off the bottom.
  double shift(double t) => _shiftFor(height(t), dock(t));

  /// How strongly the sheet dims what is behind it at time [t], 0 to 1;
  /// multiply by [MorphSheetTuning.dimmingOpacity].
  double dimming(double t) {
    final hidden = hiddenOffset;
    final shown = hidden <= 0 ? 1.0 : (1 - offset(t) / hidden).clamp(0.0, 1.0);
    final undimmed = undimmedIndex;
    if (undimmed == null) return shown;
    if (undimmed >= _heights.length - 1) return 0;
    final lo = _heights[undimmed];
    final hi = _heights[undimmed + 1];
    final f = hi <= lo ? 1.0 : ((height(t) - lo) / (hi - lo)).clamp(0.0, 1.0);
    return shown * f;
  }

  /// Replaces the detent [heights] and the container [width] after a
  /// layout change, keeping the selected detent.
  void relayout(double t, List<double> heights, double width) {
    advance(t);
    this.width = width;
    _heights = List<double>.of(heights);
    _index = _index.clamp(0, heights.length - 1);
    if (_dragFrom == null) _transition(t, _index);
  }

  /// Slides the sheet in from below the screen to its detent.
  void present(double t) {
    advance(t);
    _dismissing = false;
    _offset.retarget(t, 0, spring: MorphSheetTuning.spring);
  }

  /// Puts the sheet at its detent at time [t] without a slide, for a sheet
  /// whose arrival another motion draws (the zoom out of a source).
  void presentInPlace(double t) {
    advance(t);
    _dismissing = false;
    _offset.snap(t, 0);
  }

  /// Slides the sheet out below the screen.
  void dismiss(double t) {
    advance(t);
    _dragFrom = null;
    _dismissing = true;
    _releaseStretch(t);
    _offset.retarget(t, hiddenOffset, spring: MorphSheetTuning.spring);
  }

  /// Animates to detent [index], as UIKit's animateChanges does.
  void animateTo(double t, int index) {
    advance(t);
    _transition(t, index.clamp(0, _heights.length - 1));
  }

  void _transition(double t, int index, {double? velocity}) {
    final h = height(t);
    final d = _dockFor(h);
    _dragFrom = null;
    _releaseStretch(t);
    final changed = index != _index;
    _index = index;
    _toDocked = index == dockedIndex;
    _dockStart = d;
    _heightStart = h;
    if (!_toDocked) {
      _floating = _heights[index];
    } else if (d <= 0) {
      _floating = h;
    }
    if (velocity != null) _height.setState(t, h, velocity);
    _height.retarget(t, _heights[index]);
    if (changed) onDetentChanged?.call(index);
  }

  double get _top => _height.value(_now) - _offset.value(_now);

  /// A finger touched the sheet: a floating sheet swells.
  void press(double t) {
    advance(t);
    _pressAt = t + MorphSheetTuning.pressDelay;
  }

  /// The touch ended or turned into a drag: the swell goes.
  void unpress(double t) {
    advance(t);
    _pressAt = null;
    _press.retarget(t, 1);
  }

  /// A tap on the grabber band: cycles to the next detent, back to the
  /// smallest after the largest.
  void tapGrabber(double t) {
    advance(t);
    if (_heights.length < 2 || _dismissing) return;
    _timeline.at(t + MorphSheetTuning.grabberTapDelay, (double s) {
      if (_dragFrom == null && !_dismissing) {
        _transition(s, (_index + 1) % _heights.length);
      }
    });
  }

  /// The swell of the sheet under a touch at time [t], as a factor on
  /// [scale]; it fades as the sheet docks.
  double pressScale(double t) => 1 + (_press.value(t) - 1) * (1 - dock(t));

  /// A finger started dragging the sheet at screen position [y].
  void dragStart(double t, double y) {
    advance(t);
    unpress(t);
    _holdStretch(t);
    if (dock(t) < 1) {
      _stretch.retarget(t, 0);
      _stretching = true;
      _travel = 0;
      _travelAt = t;
      _travelVelocity = 0;
      _lag.snap(t, 0);
    }
    _floating = _floatingBelowDocked;
    _dragFrom = y;
    _dragTop = _top;
    _height.snap(t, _height.value(t));
    _offset.snap(t, _offset.value(t));
  }

  /// The finger moved to screen position [y].
  void dragUpdate(double t, double y) {
    advance(t);
    final from = _dragFrom;
    if (from == null || _released) return;
    if (_stretching) _track(t, (y - from).abs());
    final top = math.min(_dragTop - (y - from), _heights.last);
    final lowest = _heights.first;
    if (top >= lowest) {
      _height.snap(t, top);
      _offset.snap(t, 0);
    } else {
      final below = lowest - top;
      _height.snap(t, lowest);
      _offset.snap(
        t,
        dismissible
            ? below
            : morphRubberband(
                below,
                dimension: MorphSheetTuning.refusedPullExtent,
              ),
      );
    }
  }

  void _track(double t, double travel) {
    if (t > _travelAt) {
      final v = (travel - _travel) / (t - _travelAt);
      _lag.setState(t, _lag.value(t), _lag.velocity(t) + v - _travelVelocity);
      _travelVelocity = v;
      _travelAt = t;
    }
    _travel = travel;
  }

  /// The finger let go, moving at [velocity] pixels per second (positive
  /// down).
  void dragEnd(double t, double velocity) {
    advance(t);
    if (_dragFrom == null || _released) return;
    _holdStretch(t);
    _released = true;
    _timeline.at(t + MorphSheetTuning.releaseDelay, (double s) {
      _released = false;
      _settle(s, velocity);
    });
  }

  bool _released = false;

  void _settle(double t, double velocity) {
    if (_dragFrom == null) return;
    _releaseStretch(t);
    const gain = MorphSheetTuning.releaseVelocityGain;
    final below = _offset.value(t);
    if (below > 0) {
      final hidden = hiddenOffset;
      final projected = below + velocity * MorphSheetTuning.projection;
      if (dismissible &&
          (projected > hidden / 2 ||
              velocity > MorphSheetTuning.dismissVelocity)) {
        _dragFrom = null;
        _dismissing = true;
        final flicked = velocity > 0;
        _offset.setState(
          t,
          below,
          flicked ? velocity * MorphSheetTuning.flickDismissVelocityGain : 0,
        );
        _offset.retarget(
          t,
          hidden,
          spring: flicked
              ? MorphSheetTuning.flickDismissSpring
              : MorphSheetTuning.spring,
        );
        onDismiss?.call();
        return;
      }
      if (!dismissible &&
          below >
              MorphSheetTuning.refusedPullExtent *
                  MorphSheetTuning.dismissAttemptShare) {
        onDismissAttempt?.call();
      }
      _offset.setState(t, below, velocity * gain);
      _offset.retarget(t, 0, spring: MorphSheetTuning.spring);
      _transition(t, 0, velocity: 0);
      return;
    }
    final projected = _height.value(t) - velocity * MorphSheetTuning.projection;
    var best = 0;
    for (var i = 1; i < _heights.length; i++) {
      if ((_heights[i] - projected).abs() <
          (_heights[best] - projected).abs()) {
        best = i;
      }
    }
    _offset.retarget(t, 0, spring: MorphSheetTuning.spring);
    _transition(t, best, velocity: -velocity * gain);
  }

  /// The drag was cancelled; the sheet returns to its detent.
  void dragCancel(double t) {
    advance(t);
    if (_dragFrom == null) return;
    _released = false;
    _releaseStretch(t);
    _offset.retarget(t, 0, spring: MorphSheetTuning.spring);
    _transition(t, _index);
  }

  /// Advances the motion to time [t]; a spring within 0.05 pixels of its
  /// target and nearly still comes to rest on it.
  void advance(double t) {
    if (t > _now) _now = t;
    final pressAt = _pressAt;
    if (pressAt != null && pressAt <= _now) {
      _pressAt = null;
      _press.retarget(pressAt, MorphSheetTuning.pressScale);
    }
    _timeline.runDue(_now);
    if (_dragFrom != null) return;
    if (_height.isAtRest(_now, 0.05)) _height.snap(_now, _height.target);
    if (_offset.isAtRest(_now, 0.05)) _offset.snap(_now, _offset.target);
    if (_stretch.isAtRest(_now, 1e-5)) _stretch.snap(_now, _stretch.target);
  }

  /// The sheet's visible rect at time [t] in a container [containerHeight]
  /// pixels tall, transforms applied.
  Rect visibleRect(double t, double containerHeight) {
    final h = height(t);
    final s = scale(t);
    final bottom = containerHeight + (s - 1) * h / 2 + shift(t) + offset(t);
    final k = math.sqrt(math.max(stretch(t), 0.5));
    final w = width * s / k;
    return Rect.fromLTRB(
      (width - w) / 2,
      bottom - h * s * k,
      (width + w) / 2,
      bottom,
    );
  }
}
