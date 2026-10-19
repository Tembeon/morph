import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:morph/src/gesture.dart';
import 'package:morph/src/widgets/small_lens.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/timeline.dart';

/// The motion of an iOS 27 slider: value, thumb lens and track stretch.
///
/// Only the thumb is a handle: a press on it lifts the thumb lens, a tap
/// or a drag that starts on the track does nothing. A drag begins once
/// the finger has moved [panSlop] pixels and maps its travel beyond that
/// distance onto the value by the full track width, as UIKit's pan
/// removes its hysteresis from the translation (a drag whose start had to
/// wait counts from where it begins, see [pointerMove]). So the thumb
/// trails the finger and never catches up with it: when the value reaches
/// an end, the finger leads the thumb by the slop plus the thumb width
/// times the travel left, and only past that point does the track
/// stretch. The thumb
/// follows the value directly. On release the value glides on: it keeps
/// the release speed for [glideCoast], then the speed decays
/// exponentially with the time constant [glideDecay], so a release at
/// speed v travels v times their sum further, stopping at the ends. Past
/// either end the whole track stretches toward the finger on a rubber
/// band and gets thinner; on release it springs back.
///
/// The fill ends under the thumb center, except within [fillRamp] of
/// either end, where it runs linearly to the track end, so a full slider
/// is filled to its end and an empty one shows no fill.
///
/// With [ticks] (two or more) the value snaps to evenly spaced stops: the
/// reported value is the stop nearest to where the finger maps, and the
/// thumb and fill show that place through a detent curve: at a fraction u
/// of the way from the stop to the midpoint between two stops they have
/// left the stop by u to the power [tickExponent] of that way, so the
/// thumb sits near a stop and moves over to the next one only close to the
/// midpoint, with no smoothing and no dependence on the finger's speed. A
/// fast finger crosses that band within a frame or two and the thumb seems
/// to jump stop to stop; a slow one shows it between. After a release the
/// place springs ([tickReleaseSpring], from the release speed) onto the
/// stop nearest to where the release speed projects it ([tickProjection],
/// when that is at least [tickProjectionThreshold]), seen through the same
/// curve, without a glide.
///
/// Times are seconds and positions pixels from the track's left end.
class MorphSliderMotion {
  /// Creates a slider of track [width] resting at [value] whose thumb
  /// lens filters its motion at [frameRate] frames per second of motion
  /// time.
  MorphSliderMotion({
    required this._width,
    required double value,
    this.frameRate = 120,
    this._ticks = 0,
  }) : _value = value.clamp(0.0, 1.0),
       _reported = value.clamp(0.0, 1.0),
       _settle = MorphSpringState(tickReleaseSpring, value.clamp(0.0, 1.0)),
       lens = MorphSmallLens(
         restSize: thumbSize,
         liftedSize: liftedThumbSize,
         frameRate: frameRate,
       );

  /// The frames per second of motion time the thumb lens filters at: 120
  /// for a ProMotion display, 60 for a 60 Hz one.
  final double frameRate;

  /// The size of the resting thumb.
  static const Size thumbSize = Size(37, 24);

  /// The size of the lifted thumb.
  static const Size liftedThumbSize = Size(57.35, 37.2);

  /// The height of the resting track.
  static const double trackHeight = 6;

  /// How far the finger moves before a drag begins; the value counts only
  /// the travel past it. UIKit's pan hysteresis, read from UIKit, notes
  /// private; every device recording whose drag began at once counts from
  /// exactly this distance.
  static const double panSlop = 10;

  /// How far outside the resting thumb a press still grabs it.
  static const double thumbSlop = 8;

  /// Seconds the value keeps the release speed after the release.
  static const double glideCoast = 0.04;

  /// The time constant, in seconds, of the release speed's exponential
  /// decay after [glideCoast].
  static const double glideDecay = 0.083;

  /// The window, in seconds before the last move, the release speed is
  /// measured over.
  static const double velocityWindow = 0.05;

  /// The rubber band of the near track end as (limit, stiffness).
  static const (double, double) rubberBand = (13, 0.74);

  /// How far the far track end moves, as a fraction of the near end.
  static const double farEdgeRatio = 0.357;

  /// How much thinner the track gets per pixel of stretch.
  static const double squish = 0.2936;

  /// The spring the stretched track returns on.
  static const releaseSpring = MorphSpring(0.63, 0.85);

  /// Seconds between the release and the return of the stretched track.
  static const double releaseDelay = 0.07;

  /// The span of value at either end over which the fill runs from the
  /// thumb center to the track end.
  static const double fillRamp = 0.0198;

  /// The exponent of the stepped slider's detent curve: at a fraction u of
  /// the way from a stop to the midpoint between two stops, the thumb has
  /// left the stop by u to this power of that way. Read from UIKit, notes
  /// private.
  static const double tickExponent = 5;

  /// The spring a released stepped slider moves onto its stop on,
  /// starting from the release speed. Read from UIKit, notes private.
  static const tickReleaseSpring = MorphSpring(0.4, 1);

  /// Seconds of release speed a released stepped slider projects ahead to
  /// pick its stop. Read from UIKit, notes private.
  static const double tickProjection = 0.099;

  /// The shortest projection, in pixels, that picks a stop other than the
  /// one the finger left the thumb at. Read from UIKit, notes private.
  static const double tickProjectionThreshold = 10;

  /// The spring an animated [setValue] moves the thumb and fill on: UIKit's
  /// programmatic-update spring, response 0.4, damping 0.8, read from UIKit (notes private) on the iOS 27.0 simulator; the
  /// glass slider's fill replays it within 0.16 pt on a 300 pt track for
  /// jumps of 0.01 to 0.8. The duration does not depend on the distance
  /// (the header's "fixed velocity" does not describe iOS 27).
  static const programmaticSpring = MorphSpring(0.4, 0.8);

  /// The diameter of a tick mark.
  static const double tickSize = 3;

  /// The distance of the first tick center from the track's left end;
  /// the ticks are spaced by the thumb travel, half a point left of the
  /// thumb centers at the stops.
  static const double tickInset = 18;

  /// How far below the track center the tick centers sit.
  static const double tickOffset = 8.5;

  /// The number of tick marks the value snaps to; below two the slider is
  /// continuous.
  ///
  /// A slider made stepped shows its thumb at the current value until the
  /// next touch snaps it to a stop.
  int get ticks => _ticks;
  int _ticks;

  set ticks(int value) {
    if (_ticks == value) return;
    final wasStepped = _stepped;
    _ticks = value;
    if (wasStepped || !_stepped) return;
    _programmatic = false;
    _settle.snap(_now, this.value);
    _detented = false;
    lens.resetFlex(_now, _thumbAt(_now));
  }

  bool get _stepped => ticks >= 2;

  /// The length of the track.
  double get width => _width;
  double _width;

  /// Changes the track width without feeding the relayout into flex.
  set width(double value) {
    if (_width == value) return;
    _width = value;
    lens.resetFlex(_now, _thumbAt(_now));
  }

  double _value;
  double _reported;
  bool _programmatic = false;
  final MorphSpringState _stretch = MorphSpringState(releaseSpring, 0);
  _Glide? _glide;
  final MorphSpringState _settle;

  /// Whether a stepped slider shows its place through the detent curve:
  /// from a drag on, until the value is set from outside.
  bool _detented = false;

  /// The thumb's lens.
  final MorphSmallLens lens;

  final MorphTimeline _timeline = MorphTimeline(now: 0);
  bool _started = false;
  _Press? _press;

  double get _now => _timeline.now;

  /// Called with the new value whenever the user changes it.
  ValueChanged<double>? onChanged;

  /// Called with the final value when a drag and its fling end.
  ValueChanged<double>? onChangeEnd;

  /// Called when a dragging finger takes the value onto either end, and,
  /// on a stepped slider, with true when it takes the value onto another
  /// inner stop: the moments UIKit's slider plays its end and detent
  /// haptics (read from UIKit, notes private). A fling gliding into an
  /// end does not call it.
  ValueChanged<bool>? onFeel;

  /// How far the thumb center travels between the ends.
  double get travel => math.max(0, width - thumbSize.width);

  /// The value's visible rest ([MorphRest], NEAR): a swing that moves the
  /// thumb less than [MorphRest.length] along [travel].
  double get _valueRest => MorphRest.scale(travel);

  /// The time the motion was last advanced to.
  double get time => _now;

  /// The current value, 0 to 1.
  double get value => _valueAt(_now);

  /// The value last handed to [onChanged], or set from outside.
  double get reportedValue => _reported;

  /// Whether the finger is dragging the thumb.
  bool get isDragging => _press?.dragging ?? false;

  /// Whether the value glides on after a release.
  bool get isGliding => _glide != null;

  /// Whether an animated [setValue] is moving the thumb.
  bool get isAnimatingValueChange =>
      _programmatic && !_settle.isWithin(_now, _valueRest);

  /// How far the stretched track's near end has moved: positive past the
  /// maximum end, negative past the minimum end.
  double get stretch => _stretch.value(_now);

  /// The thumb center along the track, stretch included.
  double get thumbCenter => _thumbAt(_now);

  /// Where the thumb shows the value, 0 to 1: the value itself, or for a
  /// stepped slider its place seen through the detent curve.
  double get position => _positionAt(_now);

  /// The right end of the fill, stretch included: under the thumb center,
  /// running out to the track end within [fillRamp] of either end.
  double get fillEnd {
    final u = position;
    final half = thumbSize.width / 2;
    final slope = half / fillRamp + travel;
    final center = half + u * travel;
    final end = u < 0.5
        ? math.min(center, slope * u)
        : width - math.min(width - center, slope * (1 - u));
    final ends = trackEnds;
    if (width <= 0) return ends.left;
    return ends.left + end * (ends.right - ends.left) / width;
  }

  /// The tick centers along the unstretched track, empty when continuous.
  List<double> get tickCenters => [
    if (_stepped)
      for (var i = 0; i < ticks; i++) tickInset + i * travel / (ticks - 1),
  ];

  /// The track ends, stretch included.
  ({double left, double right}) get trackEnds {
    final n = stretch;
    final far = farEdgeRatio * n;
    return n >= 0
        ? (left: far, right: width + n)
        : (left: n, right: width + far);
  }

  /// The track height, thinner while stretched.
  double get currentTrackHeight => trackHeight - squish * stretch.abs();

  /// Whether every part of the slider is at rest. A finger held still
  /// counts: the lifted thumb rests until the finger moves or lifts.
  bool get isSettled =>
      _glide == null &&
      _timeline.isEmpty &&
      _stretch.isWithin(_now, MorphRest.length) &&
      _settleAtRest &&
      lens.isSettled(_now) &&
      lens.hasSampled(_now, _thumbAt(_now));

  /// Puts a settled thumb lens onto its targets.
  void settle() {
    if (_stepped && _press == null) _settle.settle(_now);
    lens.settle(_now, _thumbAt(_now));
  }

  /// Whether a press at [x] grabs the thumb.
  bool hitsThumb(double x) =>
      (x - thumbCenter).abs() <= thumbSize.width / 2 + thumbSlop;

  /// A finger touched the slider at [x]; only the thumb responds.
  void pointerDown(double t, double x) {
    advance(t);
    _timeline.flush(t);
    if (!hitsThumb(x)) return;
    _stopGlide();
    _stopProgrammatic(t);
    _press = _Press(x);
    lens.lift(t);
  }

  /// The finger moved to [x].
  ///
  /// With [begin], a drag that has not begun yet begins here and counts
  /// the travel from [x], as UIKit's pan does when its start waited on
  /// another gesture: it resets its translation instead of removing the
  /// hysteresis.
  void pointerMove(double t, double x, {bool begin = false}) {
    advance(t);
    final press = _press;
    if (press == null) return;
    if (!press.dragging) {
      final travel = x - press.downX;
      if (!begin && travel.abs() < panSlop) return;
      press.dragging = true;
      press.anchor = begin ? x : press.downX + travel.sign * panSlop;
      press.from = _stepped ? _positionAt(t) : _value;
      press.sample(t, x);
      return;
    }
    press.sample(t, x);
    final raw = press.from + (x - press.anchor) / width;
    _stretch.snap(t, _stretchFor(raw));
    final clamped = raw.clamp(0.0, 1.0);
    if (!_stepped) {
      if (clamped != _value && (clamped == 0 || clamped == 1)) {
        onFeel?.call(false);
      }
      _set(clamped);
      return;
    }
    _detented = true;
    _settle.snap(t, clamped);
    final stop = _stopNear(clamped);
    if (stop != _value) onFeel?.call(stop > 0 && stop < 1);
    _set(stop);
  }

  /// The finger left the slider at [x].
  ///
  /// [velocity], in pixels per second, overrides the release speed,
  /// which is otherwise the speed of the last moves however long ago
  /// they were, as UIKit's pan recognizer reports it: a device slider
  /// released after the finger stopped still glides on that speed.
  void pointerUp(double t, double x, {double? velocity}) {
    advance(t);
    final press = _press;
    if (press == null) return;
    _press = null;
    lens.unlift(t);
    if (!press.dragging) return;
    final stretched = _stretch.target != 0;
    _releaseStretch(t);
    final speed = velocity ?? _velocity(press.samples);
    if (_stepped) {
      _settleOnStop(t, speed);
      onChangeEnd?.call(_value);
      return;
    }
    if (speed == 0 || stretched) {
      onChangeEnd?.call(_value);
      return;
    }
    _glide = _Glide(start: t, from: _value, speed: speed / width);
  }

  /// The touch was cancelled; the value stays where it is, or, with
  /// [revert], returns to where the drag picked it up - for a touch
  /// another gesture took over before the slider owned it.
  void pointerCancel(double t, {bool revert = false}) {
    advance(t);
    final press = _press;
    if (press == null) return;
    _press = null;
    lens.unlift(t);
    if (!press.dragging) return;
    if (revert) {
      _stretch.snap(t, 0);
      _set(_stepped ? _stopNear(press.from) : press.from);
      _settle.snap(t, press.from);
    }
    _releaseStretch(t);
    if (_stepped && !revert) _settleOnStop(t, _velocity(press.samples));
    onChangeEnd?.call(_value);
  }

  /// Sends a released stepped slider's place, moving at [speed] pixels per
  /// second, to the stop its projection picks.
  void _settleOnStop(double t, double speed) {
    final from = _settle.value(t);
    final v = width > 0 ? speed / width : 0.0;
    final ahead = tickProjection * v;
    final far = (ahead * width).abs() >= tickProjectionThreshold;
    final stop = _stopNear(far ? from + ahead : from);
    _settle.setState(t, from, v);
    _settle.retarget(t, stop, spring: tickReleaseSpring);
    _set(stop);
  }

  /// The index of the stop nearest to [x]; a tie goes to the lower one.
  int _stopIndex(double x) {
    final steps = ticks - 1;
    return (x.clamp(0.0, 1.0) * steps - 0.5).ceil().clamp(0, steps);
  }

  double _stopNear(double x) => _stopIndex(x) / (ticks - 1);

  /// Where a stepped slider shows place [p]: the nearest stop plus the
  /// way to the midpoint on that side times its fraction to the power
  /// [tickExponent]. Beyond the outer stops the place shows as it is, held
  /// on the track (UIKit rubber-bands a release overshoot there).
  double _detent(double p) {
    final steps = ticks - 1;
    final i = _stopIndex(p);
    final stop = i / steps;
    final half = 0.5 / steps;
    final low = i == 0 ? stop : stop - half;
    final high = i == steps ? stop : stop + half;
    final edge = p <= stop ? low : high;
    if (edge == stop) return p.clamp(0.0, 1.0);
    final u = (p.clamp(low, high) - stop) / half;
    return stop + half * u * u * u * u * u;
  }

  /// Whether the stepped slider's settle no longer shows: its remaining
  /// swing, seen through the detent curve, moves the thumb less than
  /// [MorphRest.length].
  bool get _settleAtRest {
    if (!_stepped || !_detented) return _settle.isWithin(_now, _valueRest);
    if (_press != null) return false;
    final half = 0.5 / (ticks - 1);
    final reach = _settle.reach(_now);
    final shown = reach >= half
        ? reach
        : half * math.pow(reach / half, tickExponent);
    return shown * travel < MorphRest.length;
  }

  /// Sets the value without a touch: the thumb jumps there, or with
  /// [animated] travels there on [programmaticSpring] from where it shows,
  /// as UIKit's `setValue(_:animated: true)` does.
  ///
  /// The animated thumb stays between the ends; on iOS the spring's
  /// overshoot at an end stretches the track instead (not reproduced). A
  /// stepped slider jumps.
  void setValue(double t, double value, {bool animated = false}) {
    advance(t);
    final shown = _positionAt(t);
    _timeline.clear();
    _glide = null;
    _value = value.clamp(0.0, 1.0);
    _reported = _value;
    _detented = false;
    _stretch.snap(t, 0);
    if (animated && !_stepped && shown != _value) {
      if (!_programmatic) _settle.snap(t, shown);
      _programmatic = true;
      _settle.retarget(t, _value, spring: programmaticSpring);
      return;
    }
    _programmatic = false;
    _settle.snap(t, _value);
    lens.resetFlex(t, _thumbAt(t));
  }

  void _stopProgrammatic(double t) {
    if (!_programmatic) return;
    _programmatic = false;
    _value = _settle.value(t).clamp(0.0, 1.0);
    _settle.snap(t, _value);
  }

  /// Advances the motion to time [t].
  void advance(double t) {
    if (!_started) {
      _started = true;
      _timeline.runDue(t);
      lens.advance(t, _thumbAt);
      return;
    }
    if (t < _now) return;
    final glideFrom = _now;
    lens.advance(t, (double s) {
      _timeline.runDue(s);
      return _thumbAt(s);
    });
    _timeline.runDue(t);
    if (t > glideFrom) _tickGlide(t);
  }

  void _tickGlide(double t) {
    final glide = _glide;
    if (glide == null) return;
    if (glide.remaining(t) * travel < 0.05) {
      _glide = null;
      _set(glide.end.clamp(0.0, 1.0));
      onChangeEnd?.call(_value);
      return;
    }
    _set(glide.value(t).clamp(0.0, 1.0));
  }

  double _stretchFor(double raw) {
    final excess = raw > 1
        ? (raw - 1) * width
        : raw < 0
        ? raw * width
        : 0.0;
    return excess.sign * _band(excess.abs());
  }

  void _stopGlide() {
    if (_glide == null) return;
    _value = _valueAt(_now);
    _glide = null;
    _stretch.snap(_now, 0);
  }

  void _releaseStretch(double t) {
    if (_stretch.target == 0 && _stretch.value(t) == 0) return;
    _timeline.at(t + releaseDelay, (s) => _stretch.retarget(s, 0));
  }

  void _set(double value) {
    _value = value;
    _report(value);
  }

  void _report(double value) {
    if (value == _reported) return;
    _reported = value;
    onChanged?.call(value);
  }

  double _valueAt(double t) => _glide?.value(t).clamp(0.0, 1.0) ?? _value;

  double _positionAt(double t) {
    if (_programmatic) return _settle.value(t).clamp(0.0, 1.0);
    if (!_stepped) return _valueAt(t);
    final p = _settle.value(t);
    return _detented ? _detent(p) : p;
  }

  double _thumbAt(double t) =>
      thumbSize.width / 2 + _positionAt(t) * travel + _stretch.value(t);

  static double _velocity(List<(double, double)> samples) {
    if (samples.isEmpty) return 0;
    final last = samples.last;
    for (final (st, sx) in samples) {
      if (st >= last.$1 - velocityWindow) {
        final dt = last.$1 - st;
        return dt > 0 ? (last.$2 - sx) / dt : 0;
      }
    }
    return 0;
  }

  static double _band(double over) {
    final (limit, stiffness) = rubberBand;
    return morphRubberband(over, dimension: limit, coefficient: stiffness);
  }
}

/// The value's glide after a release: the release speed held for
/// [MorphSliderMotion.glideCoast], then decaying exponentially.
class _Glide {
  _Glide({required this.start, required this.from, required this.speed});

  final double start;
  final double from;
  final double speed;

  static const double _coast = MorphSliderMotion.glideCoast;
  static const double _decay = MorphSliderMotion.glideDecay;

  double get end => from + speed * (_coast + _decay);

  double value(double t) {
    final dt = math.max(0.0, t - start);
    if (dt <= _coast) return from + speed * dt;
    return end - speed * _decay * math.exp(-(dt - _coast) / _decay);
  }

  double remaining(double t) => (end - value(t)).abs();
}

class _Press {
  _Press(this.downX);

  final double downX;
  bool dragging = false;
  double anchor = 0;
  double from = 0;
  final List<(double, double)> samples = [];

  void sample(double t, double x) {
    var stale = 0;
    final from = t - MorphSliderMotion.velocityWindow;
    while (stale < samples.length && samples[stale].$1 < from) {
      stale++;
    }
    samples.removeRange(0, stale);
    samples.add((t, x));
  }
}
