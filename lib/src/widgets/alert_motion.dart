import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/glass_button.dart';
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

  /// How strongly a dragging finger pulls the lifted platter, relative to
  /// a glass button ([MorphGlassButtonMotion.pull]): an iPhone 16 Pro
  /// leans the 320 x 264 platter 0.4 points for a 120 point drag (0.06 pt
  /// rms; the button's pull leaves 0.7 - 1.3).
  static const double platterPull = 0.25;

  /// How much the platter stretches along a drag per point of lean,
  /// relative to a glass button ([MorphGlassButtonMotion.stretch]; 0.1 -
  /// 0.2 pt rms in size on the device, the button's leaves 1 - 4).
  static const double platterStretch = 0.6;

  /// The corner radius of an alert's platter.
  static const double cornerRadius = 34;

  /// The space between the top of an alert and its first text line.
  static const double headerTop = 22;

  /// The horizontal space between an alert's edge and its text.
  static const double textInset = 30;

  /// The space between the title and the message.
  static const double titleGap = 7.33;

  /// The space below the header text when both a title and a message
  /// show.
  static const double headerBottom = 4.33;

  /// The space below the header text when only one line of text shows.
  static const double singleHeaderBottom = 3.67;

  /// The space around the stack of buttons.
  static const double buttonInset = 16;

  /// The height of a button.
  static const double buttonHeight = 48;

  /// The space between two buttons.
  static const double buttonGap = 8;

  /// The space between the header and a text field.
  static const double fieldTop = 16.33;

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

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Whether the alert is on its way out.
  bool get isDismissing => _dismissing;

  /// Whether the alert has left and nothing moves any more.
  bool get isDismissed => _dismissing && _progress.isAtRest(_now, 0.002);

  /// Whether nothing moves.
  bool get isSettled =>
      _progress.isAtRest(_now, 0.001) && _scale.isAtRest(_now, 1e-4);

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

  /// The presentation progress at time [t]: 0 hidden, 1 shown.
  double progress(double t) => _progress.value(t);

  /// The opacity of the alert at time [t].
  double opacity(double t) => _progress.value(t).clamp(0.0, 1.0);

  /// The opacity of the dimming at time [t], as a fraction of
  /// [MorphAlertTuning.dimmingOpacity].
  double dimming(double t) => _progress.value(t).clamp(0.0, 1.0);

  /// The scale of the alert at time [t].
  double scale(double t) => _scale.value(t);
}

/// The edge of a popover that points at its source.
enum MorphPopoverArrowEdge {
  /// The popover sits above its source; the arrow points down.
  bottom,

  /// The popover sits below its source; the arrow points up.
  top,

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
    required this.edge,
    required this.arrowCenter,
  });

  /// The popover's content box, without the arrow.
  final Rect content;

  /// The content edge the arrow sits on.
  final MorphPopoverArrowEdge edge;

  /// The arrow's center along [edge], in the same coordinates as
  /// [content].
  final double arrowCenter;

  /// The tip of the arrow: the point the popover grows out of and shrinks
  /// back into.
  Offset get anchor => switch (edge) {
    MorphPopoverArrowEdge.bottom => Offset(
      arrowCenter,
      content.bottom + MorphPopoverTuning.arrowLength,
    ),
    MorphPopoverArrowEdge.top => Offset(
      arrowCenter,
      content.top - MorphPopoverTuning.arrowLength,
    ),
    MorphPopoverArrowEdge.left => Offset(
      content.left - MorphPopoverTuning.arrowLength,
      arrowCenter,
    ),
    MorphPopoverArrowEdge.right => Offset(
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
      other.edge == edge &&
      other.arrowCenter == arrowCenter;

  @override
  int get hashCode => Object.hash(content, edge, arrowCenter);

  @override
  String toString() =>
      'MorphPopoverPlacement($content, ${edge.name}, $arrowCenter)';
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

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Whether the popover is on its way out.
  bool get isDismissing => _dismissing;

  /// Whether the popover has left and nothing moves any more.
  bool get isDismissed => _dismissing && _progress.isAtRest(_now, 0.002);

  /// Whether nothing moves.
  bool get isSettled => _progress.isAtRest(_now, 0.001);

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

  /// The presentation progress at time [t]: 0 hidden, 1 shown.
  double progress(double t) => _progress.value(t);

  /// The scale of the popover about its arrow tip at time [t].
  double scale(double t) =>
      math.max(0, hiddenScale + (1 - hiddenScale) * _progress.value(t));

  /// The opacity of the popover at time [t].
  double opacity(double t) => _progress.value(t).clamp(0.0, 1.0);
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
/// Checked against 16 placements on the iOS 27 simulator.
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
          MorphPopoverArrowEdge.bottom,
          MorphPopoverArrowEdge.top,
          MorphPopoverArrowEdge.left,
          MorphPopoverArrowEdge.right,
        ]
      : const [
          MorphPopoverArrowEdge.bottom,
          MorphPopoverArrowEdge.top,
          MorphPopoverArrowEdge.right,
          MorphPopoverArrowEdge.left,
        ];
  MorphPopoverPlacement? best;
  var bestShift = double.infinity;
  for (final edge in candidates) {
    final vertical =
        edge == MorphPopoverArrowEdge.bottom ||
        edge == MorphPopoverArrowEdge.top;
    final double ideal;
    final double low;
    final double high;
    final double center;
    final double start;
    final double end;
    final double length;
    final double crossLength;
    if (vertical) {
      ideal = edge == MorphPopoverArrowEdge.bottom
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
      ideal = edge == MorphPopoverArrowEdge.right
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
      ? MorphPopoverArrowEdge.bottom
      : MorphPopoverArrowEdge.top;
  final x = (source.center.dx - size.width / 2)
      .clamp(left, math.max(left, right - size.width))
      .toDouble();
  final y = edge == MorphPopoverArrowEdge.bottom
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
  MorphPopoverArrowEdge edge,
  Size size,
  double along,
  double placed,
  double center,
) {
  final vertical =
      edge == MorphPopoverArrowEdge.bottom || edge == MorphPopoverArrowEdge.top;
  final content = vertical
      ? Rect.fromLTWH(placed, along, size.width, size.height)
      : Rect.fromLTWH(along, placed, size.width, size.height);
  return MorphPopoverPlacement(
    content: content,
    edge: edge,
    arrowCenter: center,
  );
}
