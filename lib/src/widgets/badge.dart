import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/typography.dart';

/// A badge on a bar button or a tab: a count, a short text or a dot
/// (UIKit `UIBarButtonItem.Badge`, `UITabBarItem.badgeValue`, SwiftUI
/// `badge(_:)`).
///
/// It draws at the top trailing corner of the item's icon, in systemRed
/// with white text unless its colors are given. Its size, font and offset
/// are not yet measured on a device: they follow the iOS 26 badge by eye
/// (a 17 point tall capsule with 12 point semibold text, a 10 point dot).
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

  /// The fill of the badge; null is systemRed.
  final Color? backgroundColor;

  /// Whether the badge draws anything.
  bool get visible => switch ((count, text)) {
    (final int n, _) => n > 0,
    (_, final String t) => t.isNotEmpty,
    _ => true,
  };

  /// The label of the badge, or null for a dot.
  String? get label => count?.toString() ?? text;

  /// The default fill: systemRed.
  static const Color defaultBackgroundColor = Color(0xFFFF3B30);

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

/// Places [badge] over the top trailing corner of [child].
@internal
class MorphBadged extends StatelessWidget {
  /// Creates the badged child.
  const MorphBadged({required this.badge, required this.child, super.key});

  /// The badge, or null for none.
  final MorphBadge? badge;

  /// The badged widget, usually an icon.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final badge = this.badge;
    if (badge == null || !badge.visible) return child;
    final label = badge.label;
    final fill = badge.backgroundColor ?? MorphBadge.defaultBackgroundColor;
    final Widget mark = label == null
        ? Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          )
        : Container(
            constraints: const BoxConstraints(minWidth: 17),
            height: 17,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: ShapeDecoration(
              color: fill,
              shape: const StadiumBorder(),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              textScaler: TextScaler.noScaling,
              style:
                  MorphTypography.resolve(
                    const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ).copyWith(
                    color:
                        badge.foregroundColor ??
                        MorphBadge.defaultForegroundColor,
                  ),
            ),
          );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        PositionedDirectional(
          top: label == null ? -2 : -6,
          end: label == null ? -2 : -8,
          child: Semantics(label: label, child: mark),
        ),
      ],
    );
  }
}
