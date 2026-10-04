import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/bar_items.dart';
import 'package:morph/src/widgets/bar_motion.dart';
import 'package:morph/src/widgets/menu.dart';

/// The measured placement of an iOS 27 toolbar on a phone.
abstract final class MorphToolbarMetrics {
  /// The space between the screen's sides and the outer capsules:
  /// `_UIToolbarPaddingSpec` phoneSides, 28 (read from the tuning on
  /// iOS 27, and the capsule frames on the iPhone 16 Pro).
  static const double sideInset = 28;

  /// The space between the bottom of the screen and the capsules:
  /// `_UIToolbarPaddingSpec` phoneBottom, 28.
  static const double bottomInset = 28;

  /// The space between a keyboard and the capsules (not measured; an
  /// engineering default).
  static const double keyboardInset = 8;
}

/// The iOS 27 toolbar: glass capsules floating over the bottom of the
/// screen.
///
/// Each [MorphBarButtonGroup] is one capsule; [leading] groups line up
/// from the leading edge, [trailing] ones from the trailing edge, with the
/// flexible space of a UIKit toolbar between them. Capsules are 48 points
/// tall and sit [sideInset] from the sides and [bottomInset] from the
/// bottom of the screen (UIKit's `_UIToolbarPaddingSpec` phoneSides and
/// phoneBottom, 28), or [keyboardInset] above a keyboard.
///
/// Changing the groups animates like `setToolbarItems(_:animated:)`:
/// capsules move, resize and swell, new ones bud out of their neighbour,
/// buttons grow in and shrink away; see [MorphBarMotion]. Give groups and
/// buttons stable ids so the right glass morphs into the right glass.
///
/// Place it at the bottom of a [Stack] that fills the screen; it is
/// [extent] tall and as wide as it is allowed to be.
class MorphToolbar extends StatelessWidget {
  /// Creates a toolbar.
  const MorphToolbar({
    this.leading = const [],
    this.trailing = const [],
    this.style,
    this.menuStyle,
    this.menuTuning = MorphBarMenuTuning.standard,
    this.menuOverlay,
    this.sideInset = MorphToolbarMetrics.sideInset,
    this.bottomInset = MorphToolbarMetrics.bottomInset,
    this.keyboardInset = MorphToolbarMetrics.keyboardInset,
    super.key,
  });

  /// The groups lined up from the leading edge.
  final List<MorphBarButtonGroup> leading;

  /// The groups lined up from the trailing edge.
  final List<MorphBarButtonGroup> trailing;

  /// The look; null resolves it from the theme.
  final MorphBarStyle? style;

  /// The look of the buttons' menus; null resolves it from the theme.
  final MorphMenuStyle? menuStyle;

  /// The bar buttons' menu recognition, opening delay and menu motion.
  final MorphBarMenuTuning menuTuning;

  /// The overlay the buttons' menus fly in; null uses the nearest one.
  final OverlayState? menuOverlay;

  /// The space between the screen's sides and the outer capsules.
  final double sideInset;

  /// The space between the screen's bottom and the capsules.
  final double bottomInset;

  /// The space between a keyboard and the capsules.
  final double keyboardInset;

  /// The height of the toolbar's capsules.
  static double get capsuleHeight => MorphBarMetrics.toolbar.capsuleHeight;

  /// The height the toolbar takes from the bottom of the screen, its
  /// inset included, above a keyboard [keyboard] tall.
  double extentFor(double keyboard) =>
      capsuleHeight + (keyboard > 0 ? keyboard + keyboardInset : bottomInset);

  /// The height the toolbar takes from the bottom of the screen.
  double get extent => capsuleHeight + bottomInset;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    final below = keyboard > 0 ? keyboard + keyboardInset : bottomInset;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: below),
        child: SizedBox(
          height: capsuleHeight,
          width: double.infinity,
          child: MorphBarItems(
            metrics: MorphBarMetrics.toolbar,
            top: 0,
            leadingInset: sideInset,
            trailingInset: sideInset,
            style: style,
            menuStyle: menuStyle,
            menuTuning: menuTuning,
            menuOverlay: menuOverlay,
            groups: [
              for (final g in leading)
                MorphPlacedGroup(g, MorphBarSide.leading),
              for (final g in trailing)
                MorphPlacedGroup(g, MorphBarSide.trailing),
            ],
          ),
        ),
      ),
    );
  }
}
