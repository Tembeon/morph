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

  /// The space the overlay keeps from the screen's sides.
  static const double margin = 20;

  /// The corner radius of the overlay.
  static const double cornerRadius = 28;

  /// The size of the date overlay: a month calendar of five weeks.
  static const Size calendarSize = Size(320, 332);

  /// The height one more week adds to the calendar.
  static const double weekHeight = 45.67;

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
/// [MorphDatePickerTuning.margin] from the screen's sides. Checked against
/// six placements on the iOS 27 simulator.
MorphDatePickerPlacement morphPlaceDatePicker({
  required Size size,
  required Rect label,
  required Size screen,
  EdgeInsets padding = EdgeInsets.zero,
  TextDirection textDirection = TextDirection.ltr,
}) {
  const offset = MorphDatePickerTuning.anchorOffset;
  const margin = MorphDatePickerTuning.margin;
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
/// label and closing back, the label's highlight, and the calendar's page
/// turns.
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
  bool get isClosed => !_open && _progress.isAtRest(_now, 0.002);

  /// Whether nothing moves.
  bool get isSettled =>
      _progress.isAtRest(_now, 0.001) &&
      _now >= _highlightStart + MorphDatePickerTuning.highlightDuration &&
      _now >= _pageStart + MorphDatePickerTuning.pageDuration;

  /// Advances the motion to time [t].
  void advance(double t) {
    if (t > _now) _now = t;
  }

  /// Opens the overlay at time [t].
  void open(double t) {
    advance(t);
    _open = true;
    _progress.retarget(t, 1, spring: MorphDatePickerTuning.openSpring);
  }

  /// Closes the overlay at time [t].
  void close(double t) {
    advance(t);
    _open = false;
    _progress.retarget(t, 0, spring: MorphDatePickerTuning.closeSpring);
  }

  /// The overlay's progress at time [t]: 0 hidden, 1 open.
  double progress(double t) => _progress.value(t);

  /// The overlay's scale about its anchor at time [t].
  double scale(double t) =>
      MorphDatePickerTuning.hiddenScale +
      (1 - MorphDatePickerTuning.hiddenScale) * _progress.value(t);

  /// The overlay's opacity at time [t].
  double opacity(double t) => _progress.value(t).clamp(0.0, 1.0);

  /// The height of the overlay's box before the scale at time [t], for an
  /// overlay [full] points tall.
  double height(double t, double full) =>
      MorphDatePickerTuning.hiddenHeight +
      (full - MorphDatePickerTuning.hiddenHeight) * _progress.value(t);

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
}
