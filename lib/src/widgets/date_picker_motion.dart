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

  /// Whether the picker reduces its motion: the overlay and the pages
  /// still move, only quicker; the label does not dim. An approximation;
  /// it is not measured.
  bool reducedMotion = false;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Whether the overlay is open or opening.
  bool get isOpen => _open;

  /// Whether the overlay has closed and nothing moves.
  bool get isClosed {
    final spring = _spring(_now);
    return !_open && _pendingAt == null && spring.isAtRest(_now, 0.002);
  }

  /// Whether nothing moves.
  bool get isSettled {
    final spring = _spring(_now);
    return _pendingAt == null &&
        spring.isAtRest(_now, 0.001) &&
        _now >= _highlightStart + MorphDatePickerTuning.highlightDuration &&
        _now >= _pageStart + MorphDatePickerTuning.pageDuration &&
        yearPickerSettled(_now);
  }

  /// Advances the motion to time [t].
  void advance(double t) {
    if (t > _now) _now = t;
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
    final spring = _spring(t);
    final opening = _pendingAt != null || !spring.isAtRest(t, 0.002);
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
    if (pending != null && at >= pending) _spring(pending);
    _pendingAt = at;
    _pendingTarget = target;
    _pendingSpring = spring;
  }

  MorphSpringState _spring(double t) {
    final at = _pendingAt;
    if (at != null && t >= at) {
      _pendingAt = null;
      _progress.retarget(at, _pendingTarget, spring: _pendingSpring);
    }
    return _progress;
  }

  /// The overlay's progress at time [t]: 0 hidden, 1 open.
  double progress(double t) => _spring(t).value(t);

  /// The overlay's scale about its anchor at time [t].
  double scale(double t) =>
      MorphDatePickerTuning.hiddenScale +
      (1 - MorphDatePickerTuning.hiddenScale) * progress(t);

  /// The overlay's opacity at time [t].
  double opacity(double t) => progress(t).clamp(0.0, 1.0);

  /// The height of the overlay's box before the scale at time [t], for an
  /// overlay [full] points tall.
  double height(double t, double full) =>
      MorphDatePickerTuning.hiddenHeight +
      (full - MorphDatePickerTuning.hiddenHeight) * progress(t);

  /// The label's text dims under a finger at time [t].
  void press(double t) => _highlight(t, MorphDatePickerTuning.highlightOpacity);

  /// The finger left the label at time [t].
  void release(double t) => _highlight(t, 1);

  void _highlight(double t, double to) {
    advance(t);
    _highlightFrom = highlight(t);
    _highlightTo = reducedMotion ? 1 : to;
    _highlightStart = t;
  }

  /// The opacity of the label's text at time [t].
  double highlight(double t) {
    final k = ((t - _highlightStart) / MorphDatePickerTuning.highlightDuration)
        .clamp(0.0, 1.0);
    return _highlightFrom +
        (_highlightTo - _highlightFrom) *
            MorphDatePickerTuning.highlightCurve.transform(k);
  }

  /// Turns the calendar one month forward ([direction] 1) or back (-1) at
  /// time [t].
  void turnPage(double t, int direction) {
    advance(t);
    _pageStart = t;
    _pageDirection = direction;
  }

  /// How far the current page turn has gone at time [t], from 0 (the old
  /// month in place) to 1 (the new one); 1 when no turn runs.
  double page(double t) {
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

  /// How far the month title's chevron has turned toward pointing down at
  /// time [t]: 0 pointing forward, 1 down.
  ///
  /// UIKit adds each change of the chevron's transform on top of the ones
  /// still running instead of restarting from the current angle (an
  /// iPhone 16 Pro: a second tap 0.12 s into the change carries the
  /// chevron on to 0.82 of the turn before it comes back, while the fades
  /// turn around at once), so the turn is the sum of every change's
  /// remaining part.
  double yearPickerTurn(double t) {
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

  /// How far the calendar has turned to its month and year wheels at time
  /// [t]: 0 the day grid, 1 the wheels.
  double yearPicker(double t) =>
      t >= _years.start ? _years.value(t) : _yearsBefore.value(t);

  /// Whether the change between the day grid and the wheels has finished
  /// at time [t], the chevron's turn included.
  bool yearPickerSettled(double t) =>
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
