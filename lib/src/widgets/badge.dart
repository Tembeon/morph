import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/theme/theme.dart';
import 'package:morph/src/widgets/typography.dart';

/// A badge on a bar button or a tab: a count, a short text or a dot
/// (UIKit `UIBarButtonItem.Badge`, `UITabBarItem.badgeValue`, SwiftUI
/// `badge(_:)`).
///
/// It draws in systemRed with white text unless its colors are given: a
/// capsule as tall as its 12 point medium text line plus 2 points above and
/// below, 4 points of side padding, at least as wide as it is tall and at
/// most 64 points wide; the dot is an 18 point circle. On a bar button it
/// centers on the 45 degree point of its capsule's top trailing corner; on a
/// tab its leading edge sits 5 points inside the glyph's trailing edge.
/// These metrics are read from UIKit (notes private); how a badge appears,
/// changes and leaves (UIKit fades it with the bar's update animation) is
/// not reproduced, and the tab badge's height above the glyph is not
/// measured.
@immutable
class MorphBadge {
  /// A badge showing [count]; a count of zero or less shows no badge.
  const MorphBadge.count(
    int this.count, {
    this.foregroundColor,
    this.backgroundColor,
  }) : text = null;

  /// A badge showing [text]; an empty text shows no badge.
  const MorphBadge.string(
    String this.text, {
    this.foregroundColor,
    this.backgroundColor,
  }) : count = null;

  /// A dot without text (UIKit `Badge.indicator()`).
  const MorphBadge.indicator({this.backgroundColor})
    : count = null,
      text = null,
      foregroundColor = null;

  /// The number shown, or null.
  final int? count;

  /// The text shown, or null.
  final String? text;

  /// The color of the text; null is white.
  final Color? foregroundColor;

  /// The fill of the badge; null is systemRed in the brightness and
  /// contrast the badge draws in.
  final Color? backgroundColor;

  /// Whether the badge draws anything.
  bool get visible => switch ((count, text)) {
    (final int n, _) => n > 0,
    (_, final String t) => t.isNotEmpty,
    _ => true,
  };

  /// The label of the badge, or null for a dot.
  String? get label => count?.toString() ?? text;

  /// The default text color.
  static const Color defaultForegroundColor = Color(0xFFFFFFFF);

  @override
  bool operator ==(Object other) =>
      other is MorphBadge &&
      other.count == count &&
      other.text == text &&
      other.foregroundColor == foregroundColor &&
      other.backgroundColor == backgroundColor;

  @override
  int get hashCode =>
      Object.hash(count, text, foregroundColor, backgroundColor);
}

/// The metrics of a [MorphBadge], read from UIKit's bar badge metrics
/// and its badge placement (notes private).
@internal
abstract final class MorphBadgeMetrics {
  /// The text size: caption 1.
  static const double fontSize = 12;

  /// The text weight: medium.
  static const FontWeight fontWeight = FontWeight.w500;

  /// The space above and below the text.
  static const double verticalPadding = 2;

  /// The space before and after the text.
  static const double horizontalPadding = 4;

  /// The widest a badge gets.
  static const double maxWidth = 64;

  /// The size of a badge without text.
  static const double dotSize = 18;

  /// How far past its capsule's corner point a bar badge's trailing edge
  /// may reach before the badge moves toward the item.
  static const double cornerReach = 10;

  /// How far inside the glyph's trailing edge a tab badge's leading edge
  /// sits.
  static const double tabInset = 5;

  /// The tab badge's top above the glyph's top: by eye, not measured
  /// (UIKit places it 2 points below the tab button's top).
  static const double tabRise = 6;

  /// The text style of a badge label in [color].
  static TextStyle textStyle(Color color, {BuildContext? context}) =>
      MorphTypography.resolve(
        const TextStyle(fontSize: fontSize, fontWeight: fontWeight),
        context: context,
      ).copyWith(color: color);

  /// The size of a badge showing [label] (null for the dot).
  static Size sizeOf(String? label, {BuildContext? context}) {
    if (label == null || label.isEmpty) return const Size.square(dotSize);
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: textStyle(const Color(0xFF000000), context: context),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    painter.layout();
    final text = painter.size;
    painter.dispose();
    final height = text.height + 2 * verticalPadding;
    final width = math.max(
      height,
      math.min(text.width + 2 * horizontalPadding, maxWidth),
    );
    return Size(width, height);
  }
}

/// Places [badge] over [child], at the corner of a bar button's capsule
/// ([MorphBadged.corner]) or beside a tab's glyph ([MorphBadged.glyph]).
@internal
class MorphBadged extends StatelessWidget {
  /// A bar button's badge: [child] fills the item's box of [itemSize], and
  /// [capsule] is the rounded rectangle, in the box's coordinates, whose top
  /// trailing corner the badge centers on (its 45 degree point on a corner
  /// of [radius]).
  const MorphBadged.corner({
    required this.badge,
    required this.child,
    required Size this.itemSize,
    required Rect this.capsule,
    required double this.radius,
    super.key,
  }) : glyphSize = null;

  /// A tab's badge: [child] is the glyph of [glyphSize].
  const MorphBadged.glyph({
    required this.badge,
    required this.child,
    required Size this.glyphSize,
    super.key,
  }) : itemSize = null,
       capsule = null,
       radius = null;

  /// The badge, or null for none.
  final MorphBadge? badge;

  /// The badged widget.
  final Widget child;

  /// The size of a bar button's box.
  final Size? itemSize;

  /// The capsule a bar button's badge sits on, in the box's coordinates.
  final Rect? capsule;

  /// The capsule's corner radius.
  final double? radius;

  /// The size of a tab's glyph.
  final Size? glyphSize;

  /// The top left corner of a badge of [size] on a bar button.
  @visibleForTesting
  static Offset cornerOrigin({
    required Size size,
    required Size itemSize,
    required Rect capsule,
    required double radius,
    required bool rtl,
  }) {
    final inset = radius * (1 - math.sqrt1_2);
    final cy = capsule.top + inset;
    final half = size.width / 2;
    double cx;
    if (rtl) {
      final corner = capsule.left + inset;
      final hi = itemSize.width - half;
      final lo = math.min(hi, corner - MorphBadgeMetrics.cornerReach + half);
      cx = corner.clamp(lo, hi);
    } else {
      final corner = capsule.right - inset;
      final hi = corner + MorphBadgeMetrics.cornerReach - half;
      final lo = math.min(hi, half);
      cx = corner.clamp(lo, hi);
    }
    return Offset(cx - half, cy - size.height / 2);
  }

  @override
  Widget build(BuildContext context) {
    final badge = this.badge;
    if (badge == null || !badge.visible) return child;
    final label = badge.label;
    final size = MorphBadgeMetrics.sizeOf(label, context: context);
    final fill =
        badge.backgroundColor ??
        _systemRed(
          morphBrightnessOf(context),
          highContrast: morphHighContrastOf(context),
        );
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final Widget mark = Container(
      width: size.width,
      height: size.height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(
        horizontal: MorphBadgeMetrics.horizontalPadding,
      ),
      decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
      child: label == null
          ? null
          : Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
              style: MorphBadgeMetrics.textStyle(
                badge.foregroundColor ?? MorphBadge.defaultForegroundColor,
                context: context,
              ),
            ),
    );
    final Offset origin;
    if (glyphSize case final glyph?) {
      final start = glyph.width - MorphBadgeMetrics.tabInset;
      origin = Offset(
        rtl ? glyph.width - start - size.width : start,
        -MorphBadgeMetrics.tabRise,
      );
    } else {
      origin = cornerOrigin(
        size: size,
        itemSize: itemSize!,
        capsule: capsule!,
        radius: radius!,
        rtl: rtl,
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          left: origin.dx,
          top: origin.dy,
          width: size.width,
          height: size.height,
          child: Semantics(label: label, child: mark),
        ),
      ],
    );
  }
}

// iOS 27 systemRed and its Increase Contrast values, read from UIKit's
// color tables (states.md).
Color _systemRed(Brightness brightness, {required bool highContrast}) =>
    switch ((brightness, highContrast)) {
      (Brightness.light, false) => const Color(0xFFFF383C),
      (Brightness.light, true) => const Color(0xFFE9152D),
      (Brightness.dark, false) => const Color(0xFFFF4245),
      (Brightness.dark, true) => const Color(0xFFFF6165),
    };
