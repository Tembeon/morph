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
/// or a drag that starts on the track does nothing. A drag begins after
/// [panSlop] pixels and maps the finger's travel from that point onto
/// the value by the full track width, so the thumb trails the finger and
/// never catches up with it: when the value reaches an end, the finger
/// leads the thumb by the slop plus the thumb width times the travel
/// left, and only past that point does the track stretch. The thumb
/// follows the value directly. On release the value glides on: it keeps
/// the release speed for [glideCoast], then the speed decays
/// exponentially with the time constant [glideDecay], so a release at
/// speed v travels v times their sum further, stopping at the ends. Past
/// either end the whole track stretches toward the finger on a rubber
/// band and gets thinner; on release it springs back.
///
/// Times are seconds and positions pixels from the track's left end.
class MorphSliderMotion {
  /// Creates a slider of track [width] resting at [value] whose thumb
  /// lens filters its motion at [frameRate] frames per second of motion
  /// time.
  MorphSliderMotion({
    required this.width,
    required double value,
    this.frameRate = 120,
  }) : _value = value.clamp(0.0, 1.0),
       _reported = value.clamp(0.0, 1.0),
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

  /// How far the finger moves before a drag begins, fitted to slow drags
  /// recorded on an iPhone and in the simulator.
  static const double panSlop = 11;

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

  /// The length of the track.
  double width;

  double _value;
  double _reported;
  final MorphSpringState _stretch = MorphSpringState(releaseSpring, 0);
  _Glide? _glide;

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

  /// How far the thumb center travels between the ends.
  double get travel => math.max(0, width - thumbSize.width);

  /// The time the motion was last advanced to.
  double get time => _now;

  /// The current value, 0 to 1.
  double get value => _valueAt(_now);

  /// The value last handed to [onChanged], or set from outside.
  double get reportedValue => _reported;

  /// Whether the finger is dragging the thumb.
  bool get isDragging => _press?.dragging ?? false;

  /// How far the stretched track's near end has moved: positive past the
  /// maximum end, negative past the minimum end.
  double get stretch => _stretch.value(_now);

  /// The thumb center along the track, stretch included.
  double get thumbCenter => _thumbAt(_now);

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

  /// Whether every part of the slider is at rest.
  bool get isSettled =>
      _press == null &&
      _glide == null &&
      _timeline.isEmpty &&
      _stretch.isAtRest(_now, 0.01) &&
      lens.isSettled(_now);

  /// Whether a press at [x] grabs the thumb.
  bool hitsThumb(double x) =>
      (x - thumbCenter).abs() <= thumbSize.width / 2 + thumbSlop;

  /// A finger touched the slider at [x]; only the thumb responds.
  void pointerDown(double t, double x) {
    advance(t);
    _timeline.flush(t);
    if (!hitsThumb(x)) return;
    _stopGlide();
    _press = _Press(x);
    lens.lift(t);
  }

  /// The finger moved to [x].
  void pointerMove(double t, double x) {
    advance(t);
    final press = _press;
    if (press == null) return;
    if (!press.dragging) {
      if ((x - press.downX).abs() <= panSlop) return;
      press.dragging = true;
      press.anchor = x;
      press.from = _value;
      press.samples.add((t, x));
      return;
    }
    press.samples.add((t, x));
    final raw = press.from + (x - press.anchor) / width;
    _stretch.snap(t, _stretchFor(raw));
    _set(raw.clamp(0.0, 1.0));
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
      _set(press.from);
    }
    _releaseStretch(t);
    onChangeEnd?.call(_value);
  }

  /// Sets the value without a touch; the thumb jumps there.
  void setValue(double t, double value) {
    advance(t);
    _timeline.clear();
    _glide = null;
    _value = value.clamp(0.0, 1.0);
    _reported = _value;
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

  double _thumbAt(double t) =>
      thumbSize.width / 2 + _valueAt(t) * travel + _stretch.value(t);

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
}
