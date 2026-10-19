import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/spring_state.dart';

/// The measured tuning and geometry of an iOS 27 alert
/// (UIAlertController with the alert style).
abstract final class MorphAlertTuning {
  /// The spring of every alert animation: the dimming, the alert's opacity
  /// and its scale, presenting and dismissing. UIKit runs a
  /// CASpringAnimation of stiffness 522.35 and damping 45.71, mass 1:
  /// response 0.275 s, critically damped.
  static const spring = MorphSpring(0.2749, 1);

  /// The scale an alert presents from: it shrinks from this size to its
  /// own while it fades in (fitted 1.199 on an iPhone 16 Pro, 0.02
  /// percent rms; 1.196 on the simulator). A dismissing alert only fades.
  static const double presentScale = 1.199;

  /// The opacity of the black dimming behind an alert.
  static const double dimmingOpacity = 0.2;

  /// The alert text size in points, from the UIKit layout captures.
  static const double textFontSize = 17;

  /// The 17-point text line height in the UIKit layout captures.
  static const double textLineHeight = 20.33;

  /// The line-height multiplier of 17-point alert text.
  static const double textHeight = textLineHeight / textFontSize;

  /// The message line-height multiplier from the UIKit layout captures.
  static const double messageHeight = 1.2;

  /// The preferred action's semibold weight from the UIKit layout captures.
  static const FontWeight preferredWeight = FontWeight.w600;

  /// The single header's regular weight from the UIKit layout captures.
  static const FontWeight singleHeaderWeight = FontWeight.w400;

  /// The button's horizontal text inset from the UIKit layout captures.
  static const double buttonTextInset = 12;

  /// The screen-side alert margin, an engineering layout default.
  static const double screenMargin = 20;

  /// The text scale cap, an engineering layout default.
  static const double maxTextScale = 2;

  /// The flat fallback shadow sigma, an engineering rendering default.
  static const double flatShadowSigma = 24;

  /// The flat fallback shadow offset, an engineering rendering default.
  static const double flatShadowOffset = 8;

  /// The width of an alert.
  static const double width = 320;

  /// The corner radius of an alert's platter.
  static const double cornerRadius = 34;

  /// The space between the top of an alert and its first text label.
  ///
  /// UIKit's view dumps of iOS 27 alerts on the device (scene x4disalert,
  /// tool/ios_reference/references/disabled/dumps): the title `UILabel`
  /// rests 22 points under the platter's top in a column alert (313 in a
  /// platter at 291) and in a row alert with a text field (218 in 196).
  static const double headerTop = 22;

  /// The horizontal space between an alert's edge and its text.
  static const double textInset = 30;

  /// The space between the title and the message labels.
  ///
  /// UIKit's view dumps (see [headerTop]): the message `UILabel` starts at
  /// 340.67 under a title label of 20.33 points ending at 333.33 (22
  /// pixels at 3x; 245.67 under 238.33 in the row alert). The labels are
  /// as tall as UIKit makes them (`MorphLabelHeight`).
  static const double titleGap = 22 / 3;

  /// The space below the header text when both a title and a message
  /// show.
  ///
  /// UIKit's view dumps (see [headerTop]): the header scroll view ends at
  /// 363 under a message label ending at 358.67 (13 pixels at 3x), so a
  /// title and a one-line message make a 72 point header, as the
  /// recorded platters (264 points with three actions) and the action
  /// sheet popover's header (floored to 72 in the device tree of scene
  /// w2alert) hold.
  static const double headerBottom = 13 / 3;

  /// The space below the header text when only one line of text shows.
  ///
  /// Carried from the first port (11 pixels at 3x): no committed capture
  /// holds an alert with a title or a message alone, so the 46 point
  /// header it gives under a 20.33 point label is not replayed.
  static const double singleHeaderBottom = 11 / 3;

  /// The space around the stack of buttons.
  static const double buttonInset = 16;

  /// The height of a button.
  static const double buttonHeight = 48;

  /// The space between two buttons.
  static const double buttonGap = 8;

  /// The space between the header and a text field.
  ///
  /// UIKit's view dumps (see [headerTop]): the row alert's text field
  /// cell starts at 280 under a message label ending at 263.67 (49 pixels
  /// at 3x).
  static const double fieldTop = 49 / 3;

  /// The horizontal space between an alert's edge and a text field.
  static const double fieldInset = 15;

  /// The space between a text field and the buttons.
  static const double fieldBottom = 4;

  /// The opacity of a pressed button's fill, relative to its normal fill.
  static const double pressedFillOpacity = 0.4;

  /// The width of an action sheet's content when it presents as a popover
  /// from its source.
  static const double popoverWidth = 240;
}

/// The motion of an iOS 27 alert: the dimming, the alert's opacity and its
/// scale.
///
/// Presenting, the alert fades in with the dimming while it shrinks from
/// [MorphAlertTuning.presentScale] to its size; dismissing, it fades out
/// with the dimming at its size. Both run on [MorphAlertTuning.spring],
/// and a dismissal in the middle of the presentation reverses from where
/// the alert stands, velocity included.
///
/// For Reduce Motion ([reducedMotion]) the alert does not shrink: it
/// fades in at its size on the same spring. Read from UIKit, notes
/// private: UIAlertController starts the presentation at scale 1 instead
/// of 1.2 under Reduce Motion and keeps the timing.
///
/// Times are seconds on the caller's clock.
class MorphAlertMotion {
  /// Creates the motion of an alert that is not shown yet.
  MorphAlertMotion({
    this.spring = MorphAlertTuning.spring,
    this.presentScale = MorphAlertTuning.presentScale,
  }) : _progress = MorphSpringState(spring, 0),
       _scale = MorphSpringState(spring, presentScale);

  /// The spring of the progress and the scale.
  final MorphSpring spring;

  /// The scale the alert presents from.
  final double presentScale;

  final MorphSpringState _progress;
  final MorphSpringState _scale;
  double _now = 0;
  bool _dismissing = false;

  /// Whether the alert presents for Reduce Motion, at its size.
  bool reducedMotion = false;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Whether the alert is on its way out.
  bool get isDismissing => _dismissing;

  /// Whether the alert has left and nothing moves any more.
  bool get isDismissed =>
      _dismissing && _progress.isWithin(_now, MorphRest.opacity);

  /// Whether nothing moves visibly any more: the fade and the dimming
  /// swing less than [MorphRest.opacity] and the scale less than
  /// [MorphRest.scale] of the alert's width ([settle] lands them).
  bool get isSettled =>
      _progress.isWithin(_now, MorphRest.opacity) &&
      _scale.isWithin(_now, MorphRest.scale(MorphAlertTuning.width));

  /// Lands every spring on its target at the motion's time: at a visible
  /// rest ([isSettled]) nothing that shows moves (NEAR, invisible).
  void settle() {
    _progress.settle(_now);
    _scale.settle(_now);
  }

  /// Starts presenting the alert at time [t].
  void present(double t) {
    advance(t);
    _dismissing = false;
    if (_progress.value(t) <= 0 && _progress.velocity(t) == 0) {
      _scale.snap(t, presentScale);
    }
    _progress.retarget(t, 1);
    _scale.retarget(t, 1);
  }

  /// Starts dismissing the alert at time [t].
  void dismiss(double t) {
    advance(t);
    _dismissing = true;
    _progress.retarget(t, 0);
  }

  /// Advances the motion to time [t].
  void advance(double t) {
    if (t > _now) _now = t;
  }

  /// The presentation progress: 0 hidden, 1 shown.
  double get progress => _progress.value(_now);

  /// The opacity of the alert.
  double get opacity => progress.clamp(0.0, 1.0);

  /// The opacity of the dimming, as a fraction of
  /// [MorphAlertTuning.dimmingOpacity].
  double get dimming => progress.clamp(0.0, 1.0);

  /// The scale of the alert.
  double get scale => reducedMotion ? 1 : _scale.value(_now);
}

/// The edge of a popover that points at its source.
enum MorphPopoverArrowDirection {
  /// The popover sits above its source; the arrow points down.
  down,

  /// The popover sits below its source; the arrow points up.
  up,

  /// The popover sits to the right of its source; the arrow points left.
  left,

  /// The popover sits to the left of its source; the arrow points right.
  right,
}

/// Where a popover sits relative to its source, as UIKit places an action
/// sheet presented from a source view on iOS 27.
@immutable
class MorphPopoverPlacement {
  /// Creates a placement.
  const MorphPopoverPlacement({
    required this.content,
    required this.arrowDirection,
    required this.arrowCenter,
  });

  /// The popover's content box, without the arrow.
  final Rect content;

  /// The content edge the arrow sits on.
  final MorphPopoverArrowDirection arrowDirection;

  /// The arrow's center along [arrowDirection], in the same coordinates as
  /// [content].
  final double arrowCenter;

  /// The tip of the arrow: the point the popover grows out of and shrinks
  /// back into.
  Offset get anchor => switch (arrowDirection) {
    MorphPopoverArrowDirection.down => Offset(
      arrowCenter,
      content.bottom + MorphPopoverTuning.arrowLength,
    ),
    MorphPopoverArrowDirection.up => Offset(
      arrowCenter,
      content.top - MorphPopoverTuning.arrowLength,
    ),
    MorphPopoverArrowDirection.left => Offset(
      content.left - MorphPopoverTuning.arrowLength,
      arrowCenter,
    ),
    MorphPopoverArrowDirection.right => Offset(
      content.right + MorphPopoverTuning.arrowLength,
      arrowCenter,
    ),
  };

  /// The popover's whole box, arrow included.
  Rect get bounds => content.expandToInclude(
    Rect.fromCenter(center: anchor, width: 0, height: 0),
  );

  @override
  bool operator ==(Object other) =>
      other is MorphPopoverPlacement &&
      other.content == content &&
      other.arrowDirection == arrowDirection &&
      other.arrowCenter == arrowCenter;

  @override
  int get hashCode => Object.hash(content, arrowDirection, arrowCenter);

  @override
  String toString() =>
      'MorphPopoverPlacement($content, ${arrowDirection.name}, $arrowCenter)';
}

/// The measured tuning of an iOS 27 popover: an action sheet presented
/// from a source view.
abstract final class MorphPopoverTuning {
  /// The spring a popover presents on: a CASpringAnimation of stiffness
  /// 331.9 and damping 29.15 (response 0.345 s, damping ratio 0.80),
  /// scaling the popover and fading it in together.
  static const presentSpring = MorphSpring(0.3449, 0.8);

  /// The spring a popover dismisses on: stiffness 283.97, damping 28.65
  /// (response 0.373 s, damping ratio 0.85).
  static const dismissSpring = MorphSpring(0.3729, 0.85);

  /// The scale a popover grows from and shrinks to, about its arrow tip.
  static const double hiddenScale = 0.01;

  /// The length of the arrow from the content's edge to its tip.
  static const double arrowLength = 13;

  /// The width of the arrow's base.
  static const double arrowWidth = 28;

  /// The corner radius of a popover's content.
  static const double cornerRadius = 34;

  /// The space a popover keeps from the screen's sides.
  static const double margin = 10;

  /// The nearest the arrow's center comes to a corner of the content: the
  /// corner radius plus half the arrow. A placement that would push the
  /// arrow closer is not taken.
  static const double arrowCornerClearance = cornerRadius + arrowWidth / 2;
}

/// The motion of an iOS 27 popover: one progress that scales the popover
/// about its arrow tip from [MorphPopoverTuning.hiddenScale] and fades it
/// in on [MorphPopoverTuning.presentSpring], and shrinks and fades it back
/// on [MorphPopoverTuning.dismissSpring].
///
/// For Reduce Motion ([reducedMotion]) the popover keeps its size and only
/// fades, on the same springs. Read from UIKit, notes private: UIKit's
/// popover animation uses the identity transform instead of its shrink
/// under Reduce Motion.
class MorphPopoverMotion {
  /// Creates the motion of a popover that is not shown yet.
  MorphPopoverMotion({
    this.presentSpring = MorphPopoverTuning.presentSpring,
    this.dismissSpring = MorphPopoverTuning.dismissSpring,
    this.hiddenScale = MorphPopoverTuning.hiddenScale,
  }) : _progress = MorphSpringState(presentSpring, 0);

  /// The spring the popover presents on.
  final MorphSpring presentSpring;

  /// The spring the popover dismisses on.
  final MorphSpring dismissSpring;

  /// The scale of the hidden popover.
  final double hiddenScale;

  final MorphSpringState _progress;
  double _now = 0;
  bool _dismissing = false;

  /// Whether the popover moves for Reduce Motion, at its size.
  bool reducedMotion = false;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Whether the popover is on its way out.
  bool get isDismissing => _dismissing;

  /// Whether the popover has left and nothing moves any more.
  bool get isDismissed => _dismissing && _rests;

  /// Whether nothing moves visibly. NEAR: the progress rests within 1e-3,
  /// which lands the far edge of a 300 pt popover by up to 0.3 pt, looser
  /// than [MorphRest.length]; resting at 0.1 pt keeps an action sheet's
  /// dismissal 64 ms longer.
  bool get isSettled => _rests;

  bool get _rests => _progress.isWithin(_now, 1e-3);

  /// Starts presenting the popover at time [t].
  void present(double t) {
    advance(t);
    _dismissing = false;
    _progress.retarget(t, 1, spring: presentSpring);
  }

  /// Starts dismissing the popover at time [t].
  void dismiss(double t) {
    advance(t);
    _dismissing = true;
    _progress.retarget(t, 0, spring: dismissSpring);
  }

  /// Advances the motion to time [t].
  void advance(double t) {
    if (t > _now) _now = t;
  }

  /// The presentation progress: 0 hidden, 1 shown.
  double get progress => _progress.value(_now);

  /// The scale of the popover about its arrow tip.
  double get scale => reducedMotion
      ? 1
      : math.max(0, hiddenScale + (1 - hiddenScale) * progress);

  /// The opacity of the popover.
  double get opacity => progress.clamp(0.0, 1.0);
}

/// Places a popover of [size] next to [source] inside [screen], the way
/// UIKit places an iOS 27 popover with any arrow direction.
///
/// Each side of the source is a candidate in the order above, below, then
/// the trailing and the leading side: the popover centers on the source
/// along that side, then slides as little as it must to stay
/// [MorphPopoverTuning.margin] from the screen's sides and inside
/// [padding] (the safe area, keyboard included). Toward the source it may
/// slide by up to the arrow's length, so the arrow tip overlaps the
/// source a little rather than the popover changing sides. A side where
/// that is not enough is skipped, and so is one where the slide would
/// bring the arrow, which stays on the source's center, within
/// [MorphPopoverTuning.arrowCornerClearance] of a corner. Of the rest the
/// one that slides least in total wins, earlier candidates on ties. When
/// no side works the popover goes above or below, where there is more
/// room.
///
/// Checked against 15 placements on the iOS 27 simulator.
MorphPopoverPlacement morphPlacePopover({
  required Size size,
  required Rect source,
  required Size screen,
  EdgeInsets padding = EdgeInsets.zero,
  TextDirection textDirection = TextDirection.ltr,
}) {
  const arrow = MorphPopoverTuning.arrowLength;
  const margin = MorphPopoverTuning.margin;
  const clearance = MorphPopoverTuning.arrowCornerClearance;
  final left = margin + padding.left;
  final right = screen.width - margin - padding.right;
  final top = padding.top;
  final bottom = screen.height - padding.bottom;
  final candidates = textDirection == TextDirection.ltr
      ? const [
          MorphPopoverArrowDirection.down,
          MorphPopoverArrowDirection.up,
          MorphPopoverArrowDirection.left,
          MorphPopoverArrowDirection.right,
        ]
      : const [
          MorphPopoverArrowDirection.down,
          MorphPopoverArrowDirection.up,
          MorphPopoverArrowDirection.right,
          MorphPopoverArrowDirection.left,
        ];
  MorphPopoverPlacement? best;
  var bestShift = double.infinity;
  for (final edge in candidates) {
    final vertical =
        edge == MorphPopoverArrowDirection.down ||
        edge == MorphPopoverArrowDirection.up;
    final double ideal;
    final double low;
    final double high;
    final double center;
    final double start;
    final double end;
    final double length;
    final double crossLength;
    if (vertical) {
      ideal = edge == MorphPopoverArrowDirection.down
          ? source.top - arrow - size.height
          : source.bottom + arrow;
      low = top;
      high = bottom;
      length = size.height;
      start = left;
      end = right;
      center = source.center.dx;
      crossLength = size.width;
    } else {
      ideal = edge == MorphPopoverArrowDirection.right
          ? source.left - arrow - size.width
          : source.right + arrow;
      low = left;
      high = right;
      length = size.width;
      start = top;
      end = bottom;
      center = source.center.dy;
      crossLength = size.height;
    }
    if (high - low < length || end - start < crossLength) continue;
    final along = ideal.clamp(low, high - length);
    final slide = (along - ideal).abs();
    if (slide > arrow) continue;
    final crossIdeal = center - crossLength / 2;
    final placed = crossIdeal.clamp(start, end - crossLength);
    if (center - placed < clearance ||
        placed + crossLength - center < clearance) {
      continue;
    }
    final shift = slide + (placed - crossIdeal).abs();
    if (shift < bestShift) {
      bestShift = shift;
      best = _placement(edge, size, along, placed, center);
    }
  }
  if (best != null) return best;
  final above = source.top - top;
  final below = bottom - source.bottom;
  final edge = above >= below
      ? MorphPopoverArrowDirection.down
      : MorphPopoverArrowDirection.up;
  final x = (source.center.dx - size.width / 2)
      .clamp(left, math.max(left, right - size.width))
      .toDouble();
  final y = edge == MorphPopoverArrowDirection.down
      ? math.max(top, source.top - arrow - size.height)
      : math.min(bottom - size.height, source.bottom + arrow);
  final inset = math.min(clearance, size.width / 2);
  final center = source.center.dx.clamp(x + inset, x + size.width - inset);
  return _placement(
    edge,
    size,
    y.clamp(top, math.max(top, bottom - size.height)),
    x,
    center,
  );
}

MorphPopoverPlacement _placement(
  MorphPopoverArrowDirection edge,
  Size size,
  double along,
  double placed,
  double center,
) {
  final vertical =
      edge == MorphPopoverArrowDirection.down ||
      edge == MorphPopoverArrowDirection.up;
  final content = vertical
      ? Rect.fromLTWH(placed, along, size.width, size.height)
      : Rect.fromLTWH(along, placed, size.width, size.height);
  return MorphPopoverPlacement(
    content: content,
    arrowDirection: edge,
    arrowCenter: center,
  );
}
