import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/spring_state.dart';

/// The measured tuning and geometry of the iOS 27 compact date picker
/// (UIDatePicker with the compact style) and the overlay it opens.
abstract final class MorphDatePickerTuning {
  /// The spring the overlay opens on, fitted to the simulator's frames of
  /// `_UIDatePickerOverlayPlatterView` (0.27 percent rms of the travel; no
  /// tuning value was found to read).
  static const openSpring = MorphSpring(0.32, 0.8);

  /// The spring the overlay closes on, fitted the same way (0.18 percent
  /// rms).
  static const closeSpring = MorphSpring(0.348, 0.86);

  /// The spring an open overlay changes picker on when the other label
  /// of a date-and-time picker is tapped: the platter's frame moves from
  /// the calendar's placement to the wheels' (or back) while the two
  /// contents cross-fade, both pinned to the anchored corner. Fitted to
  /// the platter's frames on an iPhone 16 Pro (critically damped, response
  /// 0.25 s: 0.04 percent rms of the travel; a screen recording of the same
  /// switch reads 0.245), starting [switchDelay] after the lift of the tap.
  /// The outgoing content's opacity is one minus the progress, the
  /// incoming one's the progress.
  static const switchSpring = MorphSpring(0.25, 1);

  /// The time from the lift of the tap that opens the overlay to the
  /// start of its spring (an iPhone 16 Pro: 0.143 and 0.125 s from the
  /// platter's frames; the simulator 0.14 - 0.15 s).
  static const double openDelay = 0.14;

  /// The time from the lift of the tap outside to the start of the
  /// closing spring (an iPhone 16 Pro: 0.052 and 0.062 s).
  static const double closeDelay = 0.055;

  /// The time from the lift of the tap outside to the start of the
  /// closing spring while the overlay is still opening: the close turns
  /// the opening around from its value and velocity (an iPhone 16 Pro,
  /// taps 0.05 - 0.3 s after the opening tap: 0.030, 0.042 and 0.038 s,
  /// 0.003 rms of the scale with the springs unchanged).
  static const double closeDelayWhileOpening = 0.037;

  /// The time from the lift of a tap on the label to the start of the
  /// open while the previous overlay is still closing: UIKit opens a new
  /// overlay from its hidden state and lets the old one finish its close
  /// (an iPhone 16 Pro, taps 0.05 - 0.3 s into the close: 0.072 s).
  static const double reopenDelay = 0.072;

  /// The time from the lift of the tap on the other label to the start of
  /// the [switchSpring] (an iPhone 16 Pro: 0.088 s).
  static const double switchDelay = 0.088;

  /// The scale of the hidden overlay about its anchor.
  static const double hiddenScale = 0.2;

  /// The seconds the overlay fades in or out for under Reduce Motion, at
  /// its full size, on [reducedMotionCurve]. Read from UIKit, notes
  /// private: UIDatePicker's overlay presentation replaces its spring by
  /// this fade under Reduce Motion (and switches pickers with it too,
  /// which morph does not follow yet).
  static const double reducedMotionDuration = 0.3;

  /// The easing of the Reduce Motion fade: UIView's default curve.
  static const Curve reducedMotionCurve = Curves.easeInOut;

  /// The height of the hidden overlay's box before the scale: the overlay
  /// grows its box from this height to its own while it scales, so its
  /// content is revealed from the anchored edge.
  static const double hiddenHeight = 50;

  /// The distance from the label's center to the overlay's facing edge,
  /// across and along: the overlay's top sits this far below the label's
  /// center (or its bottom this far above), and its trailing edge this far
  /// before the center before it is moved inside the margins.
  static const double anchorOffset = 6;

  /// The space the overlay keeps from the screen's sides on a wide phone
  /// (the iOS 27 simulator's 440 point iPhone 18 Pro Max): UIKit's layout
  /// margin there.
  static const double margin = 20;

  /// The space the overlay keeps from the screen's sides on a phone
  /// narrower than [wideScreenWidth] (an iPhone 16 Pro, 402 points: the
  /// calendar's left edge at 16 in a screen recording).
  static const double compactMargin = 16;

  /// The screen width from which the overlay keeps [margin] rather than
  /// [compactMargin] from the sides: UIKit's system layout margins grow
  /// from 16 to 20 points on the 414 point and wider phones.
  static const double wideScreenWidth = 414;

  /// The space the overlay keeps from the sides of a screen [width]
  /// points wide.
  static double marginFor(double width) =>
      width >= wideScreenWidth ? margin : compactMargin;

  /// The corner radius of the overlay.
  static const double cornerRadius = 28;

  /// The size of the date overlay: a month calendar, five weeks or six
  /// (see [sixWeekRowHeight]), or the month and year wheels in its place.
  static const Size calendarSize = Size(320, 332);

  /// The height of a calendar row in a month of six weeks: UIKit keeps the
  /// calendar [calendarSize] and packs the six rows into the five rows'
  /// space (an iPhone 16 Pro, August 2026: cells 42.67 x 38, the chosen
  /// day's disc 38 across).
  static const double sixWeekRowHeight = 38;

  /// The duration of the change between the calendar's day grid and its
  /// month and year wheels, in seconds: a tap on the month title fades the
  /// grid, the weekday initials and the month chevrons out and the wheels
  /// in, and turns the title's chevron a quarter turn to point down, all on
  /// CABasicAnimations of this duration with [yearPickerCurve] (an iPhone
  /// 16 Pro: the layers' opacity and the chevron's frame follow it to
  /// 0.0001 with the start fitted).
  static const double yearPickerDuration = 0.25;

  /// The timing curve of the change between the day grid and the month and
  /// year wheels: UIKit's ease in and out.
  static const yearPickerCurve = Cubic(0.42, 0, 0.58, 1);

  /// The time from the lift of the tap on the month title to the start of
  /// the wheels fading in (an iPhone 16 Pro, eight taps: 0.061 - 0.077 s,
  /// mean 0.069; UIKit builds the wheels first).
  static const double yearPickerShowDelay = 0.069;

  /// The time from the lift of the tap on the month title to the start of
  /// the day grid fading back in (an iPhone 16 Pro, six taps: 0.018 -
  /// 0.022 s, mean 0.019).
  static const double yearPickerHideDelay = 0.019;

  /// The time from the lift of a second tap on the month title to the
  /// start of the day grid fading back in while the wheels still fade in
  /// (an iPhone 16 Pro, four taps 0.03 and 0.12 s after the first: 0.013
  /// s, 0.006 - 0.016 rms of the opacity against 0.019 - 0.038 with
  /// [yearPickerHideDelay]).
  static const double yearPickerHideDelayWhileShowing = 0.013;

  /// The size of the time overlay: the hour and minute wheels.
  static const Size timeSize = Size(232, 204);

  /// The duration of the label's highlight fading in and out, in seconds:
  /// a CABasicAnimation of its opacity with the timing curve
  /// [highlightCurve].
  static const double highlightDuration = 0.47;

  /// The timing curve of the label's highlight.
  static const highlightCurve = Cubic(0.25, 0.1, 0.25, 1);

  /// The opacity the label's text fades toward under a touch (inferred
  /// from the start of the animation; about one half).
  static const double highlightOpacity = 0.5;

  /// The duration of a month page turn, in seconds: the grid slides one
  /// page on a sine ease in and out.
  static const double pageDuration = 0.3;

  /// The height of the compact date label.
  static const double dateLabelHeight = 34.33;

  /// The height of the compact time label.
  static const double timeLabelHeight = 36;

  /// The horizontal space inside a compact label.
  static const double labelPadding = 12;

  /// The space between the date label and the time label.
  static const double labelGap = 4;
}

/// Where the overlay of a compact date picker sits.
@immutable
class MorphDatePickerPlacement {
  /// Creates a placement.
  const MorphDatePickerPlacement({required this.rect, required this.anchor});

  /// The overlay's box.
  final Rect rect;

  /// The point the overlay grows out of and shrinks into: the label's
  /// center across (kept on the overlay's edge when the label's center is
  /// past it), the overlay's facing edge along.
  final Offset anchor;

  /// Whether the overlay sits below its label.
  bool get below => anchor.dy <= rect.top + 0.5;

  @override
  bool operator ==(Object other) =>
      other is MorphDatePickerPlacement &&
      other.rect == rect &&
      other.anchor == anchor;

  @override
  int get hashCode => Object.hash(rect, anchor);
}

/// Places the overlay of a compact date picker of [size] for a [label] in
/// [screen], as UIKit does on iOS 27.
///
/// The overlay hangs below the label, its top
/// [MorphDatePickerTuning.anchorOffset] below the label's center, or above
/// it when there is no room below inside [padding]. Across, it extends
/// toward the leading side: its trailing edge sits the offset before the
/// label's center, then it moves as little as it must to stay
/// [MorphDatePickerTuning.marginFor] the screen's width from its sides.
/// Checked against six placements on the iOS 27 simulator and one on an
/// iPhone 16 Pro.
MorphDatePickerPlacement morphPlaceDatePicker({
  required Size size,
  required Rect label,
  required Size screen,
  EdgeInsets padding = EdgeInsets.zero,
  TextDirection textDirection = TextDirection.ltr,
}) {
  const offset = MorphDatePickerTuning.anchorOffset;
  final margin = MorphDatePickerTuning.marginFor(screen.width);
  final c = label.center;
  final belowTop = c.dy + offset;
  final roomBelow = screen.height - padding.bottom - belowTop;
  final below = roomBelow >= size.height || c.dy > screen.height;
  final top = below
      ? belowTop
      : math.max(padding.top, c.dy - offset - size.height);
  final ideal = textDirection == TextDirection.ltr
      ? c.dx - offset - size.width
      : c.dx + offset;
  final low = margin + padding.left;
  final high = math.max(
    low,
    screen.width - margin - padding.right - size.width,
  );
  final left = ideal.clamp(low, high);
  final rect = Rect.fromLTWH(left, top, size.width, size.height);
  return MorphDatePickerPlacement(
    rect: rect,
    anchor: Offset(
      c.dx.clamp(rect.left, rect.right),
      below ? rect.top : rect.bottom,
    ),
  );
}

/// The motion of a compact date picker: the overlay opening out of its
/// label and closing back, the label's highlight, the calendar's page
/// turns, and the calendar's change between its day grid and its month
/// and year wheels.
///
/// One progress drives the overlay: it scales about its anchor from
/// [MorphDatePickerTuning.hiddenScale], fades in, and grows its box from
/// [MorphDatePickerTuning.hiddenHeight] to its own height, on
/// [MorphDatePickerTuning.openSpring]; closing reverses it on
/// [MorphDatePickerTuning.closeSpring], velocity included.
///
/// Times are seconds on the caller's clock.
class MorphDatePickerMotion {
  /// Creates the motion of a closed picker.
  MorphDatePickerMotion();

  final MorphSpringState _progress = MorphSpringState(
    MorphDatePickerTuning.openSpring,
    0,
  );
  double _now = 0;
  bool _open = false;
  double _highlightStart = double.negativeInfinity;
  double _highlightFrom = 1;
  double _highlightTo = 1;
  double _pageStart = double.negativeInfinity;
  int _pageDirection = 0;

  /// Whether the motion follows Reduce Motion: the overlay fades in and
  /// out at its full size over [MorphDatePickerTuning.reducedMotionDuration]
  /// (read from UIKit, notes private), and the label skips its press
  /// dimming and page turns keep their timing (approximations, not
  /// recorded on the device).
  bool reducedMotion = false;

  double _fadeStart = double.negativeInfinity;
  double _fadeFrom = 0;
  double _fadeTo = 0;

  double _fade(double t) {
    final k = ((t - _fadeStart) / MorphDatePickerTuning.reducedMotionDuration)
        .clamp(0.0, 1.0);
    return _fadeFrom +
        (_fadeTo - _fadeFrom) *
            MorphDatePickerTuning.reducedMotionCurve.transform(k);
  }

  bool _fadeDone(double t) =>
      t >= _fadeStart + MorphDatePickerTuning.reducedMotionDuration;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Whether the overlay is open or opening.
  bool get isOpen => _open;

  /// Whether the overlay has closed and nothing moves.
  bool get isClosed {
    if (reducedMotion) return !_open && _pendingAt == null && _fadeDone(_now);
    final spring = _spring(_now);
    return !_open && _pendingAt == null && spring.isWithin(_now, _closedRest);
  }

  // The overlay settles on the rule its raster-to-live glyph handover was
  // tuned with: within [overlayRest] of open and slower than ten times
  // that per second. The reach bound moves the handover by a frame and
  // strikes one more glyph atlas frame per open (glyph_strikes
  // date-picker 2 to 3), each 6 - 9 ms of raster on the Pixel 6a.
  bool get _overlaySettled {
    if (reducedMotion) return _fadeDone(_now);
    final spring = _spring(_now);
    return (spring.value(_now) - spring.target).abs() < overlayRest &&
        spring.velocity(_now).abs() < overlayRest * 10;
  }

  /// The swing of the overlay's progress, and of a switch between the
  /// pickers, at which they rest. NEAR: the calendar's edge lands by up to
  /// 0.27 pt, looser than [MorphRest.length]; resting at 0.1 pt costs 20
  /// more frames in the date-picker perf scene (172 to 192).
  static const double overlayRest = 1e-3;

  /// The swing at which a closing overlay counts as gone, and an opening
  /// one as open enough that a close waits the full delay. NEAR: 0.53 pt
  /// on the calendar's edge, behind an overlay that has faded out.
  static const double _closedRest = 2e-3;

  /// Whether nothing moves.
  bool get isSettled {
    return _pendingAt == null &&
        _overlaySettled &&
        _now >= _highlightStart + MorphDatePickerTuning.highlightDuration &&
        _now >= _pageStart + MorphDatePickerTuning.pageDuration &&
        _yearPickerSettledAt(_now);
  }

  /// Advances the motion to time [t].
  void advance(double t) {
    if (t < _now) return;
    _applyPending(t);
    _now = t;
  }

  /// Opens the overlay at time [t]: the spring starts [delay] seconds
  /// later ([MorphDatePickerTuning.openDelay] by default, UIKit's latency
  /// from the lift of the tap); until then whatever motion runs goes on.
  void open(double t, {double delay = MorphDatePickerTuning.openDelay}) {
    advance(t);
    _open = true;
    _schedule(t + delay, 1, MorphDatePickerTuning.openSpring);
  }

  /// Closes the overlay at time [t], the spring starting [delay] seconds
  /// later: by default [MorphDatePickerTuning.closeDelay] from rest and
  /// [MorphDatePickerTuning.closeDelayWhileOpening] while the overlay
  /// still opens.
  void close(double t, {double? delay}) {
    advance(t);
    final opening =
        _pendingAt != null ||
        (reducedMotion ? !_fadeDone(t) : !_spring(t).isWithin(t, _closedRest));
    _open = false;
    _schedule(
      t +
          (delay ??
              (opening
                  ? MorphDatePickerTuning.closeDelayWhileOpening
                  : MorphDatePickerTuning.closeDelay)),
      0,
      MorphDatePickerTuning.closeSpring,
    );
  }

  double? _pendingAt;
  double _pendingTarget = 0;
  MorphSpring _pendingSpring = MorphDatePickerTuning.openSpring;

  void _schedule(double at, double target, MorphSpring spring) {
    final pending = _pendingAt;
    if (pending != null && at >= pending) _applyPending(pending);
    _pendingAt = at;
    _pendingTarget = target;
    _pendingSpring = spring;
  }

  void _applyPending(double t) {
    final at = _pendingAt;
    if (at == null || t < at) return;
    _pendingAt = null;
    if (reducedMotion) {
      _fadeFrom = _fade(at);
      _fadeTo = _pendingTarget;
      _fadeStart = at;
      _progress.snap(at, _pendingTarget);
      return;
    }
    _progress.retarget(at, _pendingTarget, spring: _pendingSpring);
  }

  MorphSpringState _spring(double t) {
    final at = _pendingAt;
    if (at == null || t < at) return _progress;
    final projected = MorphSpringState(_pendingSpring, _progress.value(at));
    projected.setState(at, _progress.value(at), _progress.velocity(at));
    projected.retarget(at, _pendingTarget);
    return projected;
  }

  /// The overlay's progress: 0 hidden, 1 open.
  double get progress => _progressAt(_now);

  double _progressAt(double t) {
    if (!reducedMotion) return _spring(t).value(t);
    final at = _pendingAt;
    if (at == null || t < at) return _fade(t);
    final from = _fade(at);
    final k = ((t - at) / MorphDatePickerTuning.reducedMotionDuration).clamp(
      0.0,
      1.0,
    );
    return from +
        (_pendingTarget - from) *
            MorphDatePickerTuning.reducedMotionCurve.transform(k);
  }

  /// The overlay's scale about its anchor.
  double get scale => _scaleAt(_now);

  double _scaleAt(double t) => reducedMotion
      ? 1
      : MorphDatePickerTuning.hiddenScale +
            (1 - MorphDatePickerTuning.hiddenScale) * _progressAt(t);

  /// The overlay's opacity.
  double get opacity => _opacityAt(_now);

  double _opacityAt(double t) => _progressAt(t).clamp(0.0, 1.0);

  /// The height of the overlay's box before the scale, for an
  /// overlay [full] points tall.
  double height(double full) => _heightAt(_now, full);

  double _heightAt(double t, double full) => reducedMotion
      ? full
      : MorphDatePickerTuning.hiddenHeight +
            (full - MorphDatePickerTuning.hiddenHeight) * _progressAt(t);

  /// The label's text dims under a finger at time [t].
  void press(double t) => _highlight(t, MorphDatePickerTuning.highlightOpacity);

  /// The finger left the label at time [t].
  void release(double t) => _highlight(t, 1);

  void _highlight(double t, double to) {
    advance(t);
    _highlightFrom = _highlightAt(t);
    _highlightTo = reducedMotion ? 1 : to;
    _highlightStart = t;
  }

  /// The opacity of the label's text.
  double get highlight => _highlightAt(_now);

  double _highlightAt(double t) {
    final k = ((t - _highlightStart) / MorphDatePickerTuning.highlightDuration)
        .clamp(0.0, 1.0);
    return _highlightFrom +
        (_highlightTo - _highlightFrom) *
            MorphDatePickerTuning.highlightCurve.transform(k);
  }

  /// Turns the calendar one month forward ([direction] 1) or back (-1) at
  /// time [t]. A running turn completes before another can start.
  void turnPage(double t, int direction) {
    advance(t);
    if (_pageAt(t) < 1) return;
    _pageStart = t;
    _pageDirection = direction;
  }

  /// How far the current page turn has gone, from 0 (the old
  /// month in place) to 1 (the new one); 1 when no turn runs.
  double get page => _pageAt(_now);

  double _pageAt(double t) {
    final k = (t - _pageStart) / MorphDatePickerTuning.pageDuration;
    if (k >= 1) return 1;
    if (k <= 0) return 0;
    return (1 - math.cos(math.pi * k)) / 2;
  }

  /// The direction of the latest page turn: 1 forward, -1 back, 0 none.
  int get pageDirection => _pageDirection;

  _Tween _years = const _Tween(start: double.negativeInfinity, from: 0, to: 0);
  _Tween _yearsBefore = const _Tween(
    start: double.negativeInfinity,
    from: 0,
    to: 0,
  );

  /// Whether the calendar shows, or turns to, its month and year wheels.
  bool get showsYearPicker => _years.to == 1;

  /// Turns the calendar to its month and year wheels ([show] true) or back
  /// to its day grid at time [t], the tap's lift.
  ///
  /// The change starts [MorphDatePickerTuning.yearPickerShowDelay] or
  /// [MorphDatePickerTuning.yearPickerHideDelay] later
  /// ([MorphDatePickerTuning.yearPickerHideDelayWhileShowing] when the
  /// wheels still fade in) and runs
  /// [MorphDatePickerTuning.yearPickerDuration] seconds on
  /// [MorphDatePickerTuning.yearPickerCurve] from wherever the previous
  /// change stands then, as UIKit restarts its animations from the
  /// presentation value; until then the previous change goes on.
  void showYearPicker(double t, {required bool show}) {
    advance(t);
    final target = show ? 1.0 : 0.0;
    final moving = t < _years.start + MorphDatePickerTuning.yearPickerDuration;
    final start =
        t +
        (show
            ? MorphDatePickerTuning.yearPickerShowDelay
            : moving
            ? MorphDatePickerTuning.yearPickerHideDelayWhileShowing
            : MorphDatePickerTuning.yearPickerHideDelay);
    final running = start >= _years.start ? _years : _yearsBefore;
    _yearsBefore = running;
    _years = _Tween(start: start, from: running.value(start), to: target);
    if (target != _turnTarget) {
      _turns.removeWhere(
        (_Turn turn) =>
            turn.start + MorphDatePickerTuning.yearPickerDuration <= t,
      );
      _turns.add((start: start, delta: _turnTarget - target));
      _turnTarget = target;
    }
  }

  final List<_Turn> _turns = [];
  double _turnTarget = 0;

  /// How far the month title's chevron has turned toward pointing down: 0
  /// pointing forward, 1 down.
  ///
  /// UIKit adds each change of the chevron's transform on top of the ones
  /// still running instead of restarting from the current angle (an
  /// iPhone 16 Pro: a second tap 0.12 s into the change carries the
  /// chevron on to 0.82 of the turn before it comes back, while the fades
  /// turn around at once), so the turn is the sum of every change's
  /// remaining part.
  double get yearPickerTurn => _yearPickerTurnAt(_now);

  double _yearPickerTurnAt(double t) {
    var value = _turnTarget;
    for (final turn in _turns) {
      final k = (t - turn.start) / MorphDatePickerTuning.yearPickerDuration;
      if (k >= 1) continue;
      value +=
          turn.delta *
          (1 -
              (k <= 0
                  ? 0
                  : MorphDatePickerTuning.yearPickerCurve.transform(k)));
    }
    return value;
  }

  /// How far the calendar has turned to its month and year wheels: 0 the
  /// day grid, 1 the wheels.
  double get yearPicker => _yearPickerAt(_now);

  double _yearPickerAt(double t) =>
      t >= _years.start ? _years.value(t) : _yearsBefore.value(t);

  /// Whether the change between the day grid and the wheels has finished
  ///, the chevron's turn included.
  bool get yearPickerSettled => _yearPickerSettledAt(_now);

  bool _yearPickerSettledAt(double t) =>
      t >= _years.start + MorphDatePickerTuning.yearPickerDuration &&
      _turns.every(
        (_Turn turn) =>
            t >= turn.start + MorphDatePickerTuning.yearPickerDuration,
      );
}

typedef _Turn = ({double start, double delta});

@immutable
class _Tween {
  const _Tween({required this.start, required this.from, required this.to});

  final double start;
  final double from;
  final double to;

  double value(double t) {
    final k = (t - start) / MorphDatePickerTuning.yearPickerDuration;
    if (k <= 0) return from;
    if (k >= 1) return to;
    return from +
        (to - from) * MorphDatePickerTuning.yearPickerCurve.transform(k);
  }
}
