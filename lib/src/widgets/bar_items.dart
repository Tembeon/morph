import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/flight.dart';
import 'package:morph/src/presentation.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/target.dart';
import 'package:morph/src/widgets/bar_motion.dart';
import 'package:morph/src/widgets/chrome_group.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_button.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/menu_content.dart';
import 'package:morph/src/widgets/menu_entries.dart';
import 'package:morph/src/widgets/menu_host.dart';
import 'package:morph/src/widgets/menu_motion.dart';
import 'package:morph/src/widgets/widgets_theme.dart';
import 'package:morph/src/widgets/typography.dart';

/// One button of a glass bar: a label or an icon.
///
/// Its [id] keeps its identity when the bar's items change: an item with
/// the same id travels to its new place, a new id grows in, a missing one
/// leaves.
@immutable
class MorphBarButton {
  /// Creates a button showing [label] or [icon].
  const MorphBarButton({
    required this.id,
    this.label,
    this.icon,
    this.onPressed,
    this.semanticLabel,
    this.menu,
    this.enabled = true,
  }) : assert(label != null || icon != null, 'a label or an icon'),
       back = false;

  /// Creates the back button of a navigation bar: a chevron followed by
  /// [label], usually the previous screen's title.
  ///
  /// Screen readers announce [semanticLabel], else [label]; a back button
  /// without either has no spoken name, so pass a localized
  /// [semanticLabel] (the navigation stack passes its `backLabel`).
  const MorphBarButton.back({
    this.label,
    this.onPressed,
    this.semanticLabel,
    this.menu,
    this.enabled = true,
    this.id = 'morph.back',
  }) : icon = null,
       back = true;

  /// The identity of the button across item changes.
  final Object id;

  /// The text of the button.
  final String? label;

  /// The icon of the button, drawn [MorphBarMetrics.iconSize] large; used
  /// when there is no [label].
  final Widget? icon;

  /// Called when the button is tapped; null disables the button unless
  /// it has a [menu], which a tap then opens.
  final VoidCallback? onPressed;

  /// The label screen readers announce; defaults to [label].
  final String? semanticLabel;

  /// Whether this is a back button.
  final bool back;

  /// The rows of the button's menu, or null for a button without one.
  ///
  /// Without [onPressed] the menu is the button's primary action, as a
  /// `UIBarButtonItem(menu:)` without a primary action, measured on an
  /// iPhone 16 Pro (iOS 27.0.1): the menu of [MorphMenuButton] with its
  /// triggers - a tap opens it on release after the bar tuning's
  /// [MorphMenuTuning.tapOpenDelay] (see [MorphBarMenuTuning.measuredMenu]),
  /// a held finger opens it after [MorphMenuTuning.holdDuration] and may
  /// slide onto a row and choose it on release, and a release on the
  /// button leaves it open.
  ///
  /// With [onPressed] the menu opens on a long press, UIKit's long press
  /// on a bar button, measured on the back button of an iPhone 16 Pro
  /// (iOS 27.0.1): a touch released before
  /// [MorphBarMenuTuning.recognition] is a tap; held past it the button
  /// no longer fires on release, and its capsule turns into the menu
  /// [MorphBarMenuTuning.open] after the touch - the menu of
  /// [MorphMenuButton], grown out of the capsule. A finger still on the
  /// capsule when it lifts after that fires the button and closes the
  /// menu (UIKit pops one screen); one moved off leaves the menu open,
  /// and a tap on a row selects it. Any [MorphMenuEntry] works here, as
  /// in [MorphMenuButton.items].
  final List<MorphMenuEntry>? menu;

  /// Whether the button may be used, as `UIBarButtonItem.isEnabled`;
  /// false draws the disabled look.
  final bool enabled;

  /// Whether the button accepts taps: it is [enabled] and has an
  /// [onPressed] or a [menu].
  bool get interactive => enabled && (onPressed != null || opensMenuOnTap);

  /// Whether a tap opens the [menu]: the button has rows and no
  /// [onPressed].
  bool get opensMenuOnTap => onPressed == null && (menu?.isNotEmpty ?? false);

  @override
  bool operator ==(Object other) =>
      other is MorphBarButton &&
      other.id == id &&
      other.label == label &&
      other.icon == icon &&
      other.onPressed == onPressed &&
      other.semanticLabel == semanticLabel &&
      other.back == back &&
      other.enabled == enabled &&
      listEquals(other.menu, menu);

  @override
  int get hashCode => Object.hash(
    id,
    label,
    icon,
    onPressed,
    semanticLabel,
    back,
    enabled,
    menu == null ? null : Object.hashAll(menu!),
  );
}

/// The measured timing of a bar button's menu ([MorphBarButton.menu]):
/// the long press of a button with an action, the tap and hold of a
/// button whose menu is its primary action.
@immutable
class MorphBarMenuTuning {
  /// Creates a tuning with the measured bar-menu defaults.
  const MorphBarMenuTuning({
    this.recognition = 0.4,
    this.open = 0.595,
    this.menu = measuredMenu,
  }) : assert(recognition >= 0),
       assert(open >= recognition);

  /// The timing and menu motion measured on the iPhone 16 Pro, iOS 27.0.1.
  static const standard = MorphBarMenuTuning();

  /// The menu of a bar item: [MorphMenuTuning.standard] with the bar
  /// item's later tap opening.
  ///
  /// A `UIBarButtonItem(menu:)` without a primary action opens on a tap's
  /// release 0.013 s after the inline glass menu button does: the first
  /// morph frame follows the release by 0.0610 - 0.0632 s on four repeat
  /// taps against 0.0489 - 0.0495 s inline (iPhone 16 Pro, iOS 27.0.1,
  /// same probe and scene; first taps after a launch differ by 0.000 -
  /// 0.040 s, mean 0.016). Holds open 0.256 s inline and 0.260 - 0.264 s
  /// on the bar, within one display frame, so [MorphMenuTuning.holdDuration]
  /// is shared. Everything else is the inline menu's.
  static const measuredMenu = MorphMenuTuning(tapOpenDelay: 0.102);

  /// Seconds of touch after which a release is no longer a tap: UIKit's
  /// back button popped on releases at 0.25 and 0.35 s and opened its
  /// menu instead at 0.45 s.
  final double recognition;

  /// Seconds from the touch to the opening of the menu: 0.584 - 0.609 s
  /// over seven device holds.
  final double open;

  /// The menu's geometry, springs and content timing after recognition.
  ///
  /// Defaults to [measuredMenu], the measured liquid morph shared with
  /// [MorphMenuButton]. [open] controls when a long press starts it; a
  /// button without an action opens it on its own tap and hold timing.
  final MorphMenuTuning menu;

  @override
  bool operator ==(Object other) =>
      other is MorphBarMenuTuning &&
      other.recognition == recognition &&
      other.open == open &&
      other.menu == menu;

  @override
  int get hashCode => Object.hash(recognition, open, menu);
}

/// Buttons that share one glass capsule.
///
/// UIKit groups adjacent bar items into one piece of glass; separate
/// groups (a fixed space between items) get capsules of their own, 12
/// points apart. A [prominent] group is tinted, like
/// `UIBarButtonItem.Style.prominent`.
@immutable
class MorphBarButtonGroup {
  /// Creates a group of [buttons].
  const MorphBarButtonGroup(this.buttons, {this.id, this.prominent = false});

  /// The buttons, in reading order.
  final List<MorphBarButton> buttons;

  /// The identity of the capsule across item changes; null keeps the
  /// capsule by its position on its side of the bar, counted from the
  /// bar's edge (UIKit morphs the outermost capsule into the outermost
  /// one).
  final Object? id;

  /// Whether the capsule is tinted with the style's prominent color.
  final bool prominent;

  @override
  bool operator ==(Object other) =>
      other is MorphBarButtonGroup &&
      other.id == id &&
      other.prominent == prominent &&
      listEquals(other.buttons, buttons);

  @override
  int get hashCode => Object.hash(id, prominent, Object.hashAll(buttons));
}

/// The measured geometry of the glass buttons of a bar.
///
/// Values read from the view frames UIKit lays out on iOS 27 (iPhone 16
/// Pro, 402 points wide, and the simulator's iPhone 18 Pro Max at 440).
@immutable
class MorphBarMetrics {
  /// Creates metrics from explicit values.
  const MorphBarMetrics({
    required this.capsuleHeight,
    required this.buttonHeight,
    required this.capsulePadding,
    required this.buttonGap,
    required this.labelPadding,
    required this.iconPadding,
    required this.minButtonWidth,
    this.groupGap = 12,
    this.containerSpacing = 12,
    this.iconSize = 24,
    this.fontSize = 17,
    this.backChevronInset = 12,
    this.backChevronWidth = 16.33,
    this.backChevronGap = 6,
    this.backTrailingPadding = 17,
    this.backChevronHeight = 23,
  });

  /// The largest text scale bar labels and titles follow, as the tab bar
  /// labels do (iOS 27 caps bar text at the accessibility sizes).
  static const double maxTextScale = 1.25;

  /// The line height of bar labels and titles, as a multiple of the font
  /// size: the line box UIKit's labels lay out in.
  static const double lineHeight = 1.2;

  /// The height of a capsule.
  final double capsuleHeight;

  /// The height of a button inside its capsule.
  final double buttonHeight;

  /// The space between a capsule's edge and its first and last buttons.
  final double capsulePadding;

  /// The space between two buttons of one capsule.
  final double buttonGap;

  /// The space between two capsules on one side of the bar.
  final double groupGap;

  /// The spacing of the glass container the bar's capsules share: two
  /// capsules closer than this lean toward each other and fuse within
  /// half of it (see [MorphGlassPainter.buildLayer]).
  ///
  /// UIKit renders every capsule of a navigation bar, and every capsule
  /// of a toolbar, as an element of one SDF layer whose smoothness - the
  /// container spacing - is 12 on iOS 27 (read from the layers on the
  /// iPhone 16 Pro and the simulator, constant through item changes).
  /// Resting groups sit [groupGap] apart, as far as the spacing reaches,
  /// so they never touch; a group splitting or two groups passing during
  /// an item change fuse while they are closer.
  final double containerSpacing;

  /// The space on each side of a button's label.
  final double labelPadding;

  /// The space on each side of a button's icon.
  final double iconPadding;

  /// The narrowest a button gets.
  final double minButtonWidth;

  /// The size icons are drawn at.
  final double iconSize;

  /// The size of button labels.
  final double fontSize;

  /// The space between a back button's leading edge and its chevron.
  final double backChevronInset;

  /// The width of the back chevron.
  final double backChevronWidth;

  /// The space between the back chevron and its label.
  final double backChevronGap;

  /// The space after the back button's label.
  final double backTrailingPadding;

  /// The height of the box the back chevron is drawn in.
  final double backChevronHeight;

  @override
  bool operator ==(Object other) =>
      other is MorphBarMetrics &&
      other.capsuleHeight == capsuleHeight &&
      other.buttonHeight == buttonHeight &&
      other.capsulePadding == capsulePadding &&
      other.buttonGap == buttonGap &&
      other.groupGap == groupGap &&
      other.containerSpacing == containerSpacing &&
      other.labelPadding == labelPadding &&
      other.iconPadding == iconPadding &&
      other.minButtonWidth == minButtonWidth &&
      other.iconSize == iconSize &&
      other.fontSize == fontSize &&
      other.backChevronInset == backChevronInset &&
      other.backChevronWidth == backChevronWidth &&
      other.backChevronGap == backChevronGap &&
      other.backTrailingPadding == backTrailingPadding &&
      other.backChevronHeight == backChevronHeight;

  @override
  int get hashCode => Object.hash(
    capsuleHeight,
    buttonHeight,
    capsulePadding,
    buttonGap,
    groupGap,
    containerSpacing,
    labelPadding,
    iconPadding,
    minButtonWidth,
    iconSize,
    fontSize,
    backChevronInset,
    backChevronWidth,
    backChevronGap,
    backTrailingPadding,
    backChevronHeight,
  );

  /// A navigation bar's buttons: capsules 44 tall, buttons 36 tall
  /// inset by 4, 16 between buttons, labels padded by 12, icons by 7.
  static const navigation = MorphBarMetrics(
    capsuleHeight: 44,
    buttonHeight: 36,
    capsulePadding: 4,
    buttonGap: 16,
    labelPadding: 12,
    iconPadding: 7,
    minButtonWidth: 36,
  );

  /// A toolbar's buttons: capsules 48 tall, buttons 38 tall inset by 5,
  /// 14 between buttons, labels padded by 11, icons by 8, never
  /// narrower than 38.
  static const toolbar = MorphBarMetrics(
    capsuleHeight: 48,
    buttonHeight: 38,
    capsulePadding: 5,
    buttonGap: 14,
    labelPadding: 11,
    iconPadding: 8,
    minButtonWidth: 38,
  );
}

/// The look of a glass bar: its capsules, buttons and titles.
@immutable
class MorphBarStyle {
  /// Creates a style; the defaults are the iOS light appearance.
  const MorphBarStyle({
    this.capsuleColor = const Color(0xD9FFFFFF),
    this.rimColor = const Color(0x1F000000),
    this.shadowColor = const Color(0x1A000000),
    this.foregroundColor = const Color(0xFF000000),
    this.prominentColor = const Color(0xFF007AFF),
    this.prominentForegroundColor = const Color(0xFFFFFFFF),
    this.titleColor = const Color(0xFF000000),
    this.disabledIconColor = const Color(0x55000000),
    this.disabledLabelColor = const Color(0x19000000),
    this.disabledProminentColor = const Color(0xFFD1D1D6),
  });

  /// The fill of a clear capsule.
  final Color capsuleColor;

  /// The outline of a capsule.
  final Color rimColor;

  /// The shadow under a capsule.
  final Color shadowColor;

  /// The color of button labels and icons.
  final Color foregroundColor;

  /// The fill of a prominent capsule: systemBlue.
  final Color prominentColor;

  /// The color of labels and icons on a prominent capsule.
  final Color prominentForegroundColor;

  /// The color of the bar's titles.
  final Color titleColor;

  /// The color of a disabled plain button's icon and back chevron.
  ///
  /// UIKit tints a disabled bar item tertiaryLabel and leaves its capsule
  /// glass untouched; through the bar's own color path an icon renders at
  /// about a third of its enabled contrast in light (12 -> 167 on the 245
  /// capsule) and a quarter in dark (249 -> 83 on 32), measured on an
  /// iPhone 16 Pro (iOS 27.0.1). This is that rendered result over the
  /// capsule.
  final Color disabledIconColor;

  /// The color of a disabled plain button's label: text renders far
  /// dimmer than icons through the bar's color path (light 13 -> 221 on
  /// the 245 capsule, dark 249 -> 47 on 32; iPhone 16 Pro, iOS 27.0.1).
  final Color disabledLabelColor;

  /// The fill of a prominent capsule whose buttons are all disabled:
  /// systemGray4. Its glyphs stay [prominentForegroundColor].
  final Color disabledProminentColor;

  /// The light appearance.
  static const light = MorphBarStyle();

  /// The dark appearance.
  static const dark = MorphBarStyle(
    capsuleColor: Color(0xB82C2C2E),
    rimColor: Color(0x33FFFFFF),
    shadowColor: Color(0x40000000),
    foregroundColor: Color(0xFFFFFFFF),
    prominentColor: Color(0xFF0A84FF),
    titleColor: Color(0xFFFFFFFF),
    disabledIconColor: Color(0x3CFFFFFF),
    disabledLabelColor: Color(0x12FFFFFF),
    disabledProminentColor: Color(0xFF3A3A3C),
  );

  @override
  bool operator ==(Object other) =>
      other is MorphBarStyle &&
      other.capsuleColor == capsuleColor &&
      other.rimColor == rimColor &&
      other.shadowColor == shadowColor &&
      other.foregroundColor == foregroundColor &&
      other.prominentColor == prominentColor &&
      other.prominentForegroundColor == prominentForegroundColor &&
      other.titleColor == titleColor &&
      other.disabledIconColor == disabledIconColor &&
      other.disabledLabelColor == disabledLabelColor &&
      other.disabledProminentColor == disabledProminentColor;

  @override
  int get hashCode => Object.hash(
    capsuleColor,
    rimColor,
    shadowColor,
    foregroundColor,
    prominentColor,
    prominentForegroundColor,
    titleColor,
    disabledIconColor,
    disabledLabelColor,
    disabledProminentColor,
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphBarStyle resolve(BuildContext context, MorphBarStyle? explicit) =>
      explicit ??
      MorphWidgetsTheme.maybeOf(context)?.bar ??
      switch (morphBrightnessOf(context)) {
        Brightness.dark => dark,
        Brightness.light => light,
      };
}

/// Where a group of a [MorphBarItems] row sits.
@internal
enum MorphBarSide {
  /// From the leading edge.
  leading,

  /// From the trailing edge.
  trailing,
}

/// A group placed on one side of a [MorphBarItems] row.
@internal
@immutable
class MorphPlacedGroup {
  /// Places [group] on [side].
  const MorphPlacedGroup(this.group, this.side);

  /// The group.
  final MorphBarButtonGroup group;

  /// The side it sits on.
  final MorphBarSide side;
}

/// The label style of bar buttons: [MorphTypography.barButton], or
/// [MorphTypography.barButtonProminent] when [bold], at the metrics' size.
@internal
TextStyle morphBarLabelStyle(MorphBarMetrics metrics, {bool bold = false}) =>
    MorphTypography.resolve(
      (bold ? MorphTypography.barButtonProminent : MorphTypography.barButton)
          .copyWith(
            fontSize: metrics.fontSize,
            height: MorphBarMetrics.lineHeight,
          ),
    );

/// The width of the content of [button].
@internal
double morphBarContentWidth(
  MorphBarButton button,
  MorphBarMetrics metrics,
  TextScaler scaler,
  TextDirection direction, {
  bool bold = false,
}) {
  final label = button.label;
  var width = 0.0;
  if (label != null) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: morphBarLabelStyle(metrics, bold: bold),
      ),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    );
    painter.layout();
    width = painter.width;
    painter.dispose();
  }
  if (button.back) {
    return metrics.backChevronInset +
        metrics.backChevronWidth +
        (label == null || label.isEmpty
            ? metrics.backChevronInset
            : metrics.backChevronGap + width + metrics.backTrailingPadding);
  }
  if (label != null) return width + 2 * metrics.labelPadding;
  return metrics.iconSize + 2 * metrics.iconPadding;
}

/// Lays out [groups] in a row [width] wide: leading groups from
/// [leadingInset], trailing groups from [trailingInset], capsules
/// [MorphBarMetrics.groupGap] apart, [top] the capsules' top edge.
@internal
List<MorphBarCapsuleLayout> morphLayoutBarGroups({
  required List<MorphPlacedGroup> groups,
  required double width,
  required double top,
  required double leadingInset,
  required double trailingInset,
  required MorphBarMetrics metrics,
  required TextScaler scaler,
  required TextDirection direction,
  double Function(MorphBarButton button, {required bool bold})? contentWidth,
}) {
  final rtl = direction == TextDirection.rtl;
  final measure =
      contentWidth ??
      (MorphBarButton b, {required bool bold}) =>
          morphBarContentWidth(b, metrics, scaler, direction, bold: bold);
  final out = <MorphBarCapsuleLayout>[];
  final leading = [
    for (final g in groups)
      if (g.side == MorphBarSide.leading) g.group,
  ];
  final trailing = [
    for (final g in groups)
      if (g.side == MorphBarSide.trailing) g.group,
  ];
  MorphBarCapsuleLayout capsule(
    MorphBarButtonGroup group,
    double start,
    Object? key,
    Object place,
    MorphBarSide side,
  ) {
    final widths = [
      for (final b in group.buttons)
        math.max(metrics.minButtonWidth, measure(b, bold: group.prominent)),
    ];
    final single = group.buttons.length == 1 && group.buttons.first.back;
    final inner =
        widths.fold<double>(0, (a, w) => a + w) +
        metrics.buttonGap * math.max(0, widths.length - 1);
    final total = single ? widths.first : inner + 2 * metrics.capsulePadding;
    final rect = Rect.fromLTWH(start, top, total, metrics.capsuleHeight);
    final items = <MorphBarItemLayout>[];
    var x = single ? start : start + metrics.capsulePadding;
    final buttonTop = top + (metrics.capsuleHeight - metrics.buttonHeight) / 2;
    for (var i = 0; i < widths.length; i++) {
      final itemHeight = single ? metrics.capsuleHeight : metrics.buttonHeight;
      final itemTop = single ? top : buttonTop;
      items.add(
        MorphBarItemLayout(
          group.buttons[i].id,
          Rect.fromLTWH(x, itemTop, widths[i], itemHeight),
        ),
      );
      x += widths[i] + metrics.buttonGap;
    }
    return MorphBarCapsuleLayout(
      key ?? place,
      rect,
      items,
      segment: side,
      anonymous: key == null,
    );
  }

  var x = leadingInset;
  for (var i = 0; i < leading.length; i++) {
    final c = capsule(leading[i], x, leading[i].id, (
      'leading',
      i,
    ), MorphBarSide.leading);
    out.add(c);
    x = c.rect.right + metrics.groupGap;
  }
  var right = width - trailingInset;
  for (var i = 0; i < trailing.length; i++) {
    final g = trailing[trailing.length - 1 - i];
    final c = _shift(
      capsule(g, 0, g.id, ('trailing', i), MorphBarSide.trailing),
      right,
    );
    out.add(c);
    right = c.rect.left - metrics.groupGap;
  }
  if (!rtl) return out;
  return [
    for (final c in out)
      MorphBarCapsuleLayout(
        c.id,
        _mirror(c.rect, width),
        [
          for (final i in c.items)
            MorphBarItemLayout(i.id, _mirror(i.rect, width)),
        ],
        segment: c.segment,
        anonymous: c.anonymous,
      ),
  ];
}

MorphBarCapsuleLayout _shift(MorphBarCapsuleLayout c, double right) {
  final d = Offset(right - c.rect.width, 0);
  return MorphBarCapsuleLayout(
    c.id,
    c.rect.shift(d),
    [for (final i in c.items) MorphBarItemLayout(i.id, i.rect.shift(d))],
    segment: c.segment,
    anonymous: c.anonymous,
  );
}

Rect _mirror(Rect r, double width) =>
    Rect.fromLTRB(width - r.right, r.top, width - r.left, r.bottom);

/// A row of glass bar buttons that animates every change of its groups
/// with [MorphBarMotion].
///
/// A touch on a button lifts its whole capsule like a
/// [MorphGlassButton].
@internal
class MorphBarItems extends StatefulWidget {
  /// Creates the row.
  const MorphBarItems({
    required this.groups,
    required this.metrics,
    required this.top,
    required this.leadingInset,
    required this.trailingInset,
    this.style,
    this.menuStyle,
    this.menuTuning = MorphBarMenuTuning.standard,
    this.menuOverlay,
    this.onLayout,
    this.driftGroups,
    this.driftProgress,
    this.driftFactor = 1,
    this.transition = MorphBarTransitionSpec.standard,
    super.key,
  });

  /// The groups and their sides.
  final List<MorphPlacedGroup> groups;

  /// The geometry of the buttons.
  final MorphBarMetrics metrics;

  /// The top of the capsules in the row.
  final double top;

  /// The space before the first leading capsule.
  final double leadingInset;

  /// The space after the last trailing capsule.
  final double trailingInset;

  /// The look; null resolves it from the theme.
  final MorphBarStyle? style;

  /// The look of the buttons' menus; null resolves it from the theme.
  final MorphMenuStyle? menuStyle;

  /// The buttons' menu recognition, opening delay and menu motion.
  final MorphBarMenuTuning menuTuning;

  /// The overlay the buttons' menus fly in; null uses
  /// [morphPresentationOverlayOf].
  final OverlayState? menuOverlay;

  /// Called with the laid-out capsules whenever the layout changes.
  final ValueChanged<List<MorphBarCapsuleLayout>>? onLayout;

  /// The groups the capsules lean toward while [driftProgress] is set
  /// (see [MorphBarMotion.setDrift]).
  final List<MorphPlacedGroup>? driftGroups;

  /// The progress the lean follows: the capsules lean [driftFactor] times
  /// its value of the way toward [driftGroups]; null ends the lean.
  final ValueListenable<double>? driftProgress;

  /// The share of [driftProgress] the capsules lean by.
  final double driftFactor;

  /// The timing of the row's item transitions: a toolbar's
  /// ([MorphBarTransitionSpec.standard]) or a navigation bar's
  /// ([MorphBarTransitionSpec.navigation]).
  final MorphBarTransitionSpec transition;

  @override
  State<MorphBarItems> createState() => _MorphBarItemsState();
}

class _MorphBarItemsState extends State<MorphBarItems>
    with
        SingleTickerProviderStateMixin<MorphBarItems>,
        MorphClock<MorphBarItems> {
  late final MorphBarMotion _motion = MorphBarMotion(spec: widget.transition);
  final Map<Object, MorphGlassButtonMotion> _presses = {};
  final Map<Object, MorphBarButton> _buttons = {};
  final Map<Object, bool> _prominent = {};
  final Map<Object, bool> _disabled = {};
  final Map<Object, Object> _capsuleOf = {};
  final Object _menuTag = Object();
  _BarMenu? _menu;
  double? _holdStart;
  Object? _holdButton;
  int? _menuFinger;
  BuildContext? _scopeContext;
  List<MorphBarCapsuleLayout> _layout = const [];
  List<MorphBarCapsuleLayout>? _driftLayout;
  bool _hasLayout = false;
  double _laidWidth = 0;
  final Map<(String?, bool, bool), double> _widths = {};
  (TextScaler, TextDirection, MorphBarMetrics)? _widthsFor;
  bool _prune = false;
  final _FlatBodies _flat = _FlatBodies();
  final _FlatBodies _flatApart = _FlatBodies();
  final GlobalKey _contentKey = GlobalKey();
  final Map<Object, (Object, Widget)> _contents = {};
  Object? _pressedCapsule;
  Object? _pressedButton;

  @override
  void advanceMotion(double t) {
    _motion.advance(t);
    for (final p in _presses.values) {
      p.advance(t);
    }
    if (_prune && _motion.isSettled) {
      _prune = false;
      _pruneMaps();
    }
    final start = _holdStart;
    final holding = _holdButton;
    if (start != null &&
        holding != null &&
        t - start >= widget.menuTuning.open) {
      _holdStart = null;
      _openMenu(start + widget.menuTuning.open, holding);
    }
    final menu = _menu;
    if (menu != null) {
      menu.host.advance(t);
      final flight = menu.flight;
      if (!menu.motion.isPresented &&
          !menu.motion.isOpenPending &&
          !menu.host.hasPointer &&
          (flight == null || flight.isFinished)) {
        _menu = null;
        menu.host.dispose();
      }
    }
  }

  @override
  bool get motionSettled =>
      _motion.isSettled &&
      _presses.values.every((p) => p.isSettled) &&
      _holdStart == null &&
      (_menu?.motion.isSettled ?? true);

  @override
  void dispose() {
    final menu = _menu;
    _menu = null;
    menu?.host.dispose();
    super.dispose();
  }

  /// Whether the capsule [id] is drawn by an open menu instead of the bar.
  bool _carried(Object id) {
    final menu = _menu;
    if (menu == null || menu.capsule != id) return false;
    final flight = menu.flight;
    return flight != null && flight.isAirborne;
  }

  /// The menu whose close rings out on the capsule [id]: after the latch
  /// the bar draws both shapes of the menu's motion on the capsule until
  /// they rest, as UIKit keeps its morph container until the kicks ring
  /// out.
  _BarMenu? _landingOn(Object id) {
    final menu = _menu;
    if (menu == null || menu.capsule != id) return null;
    if (!menu.motion.isPresented) return null;
    final flight = menu.flight;
    if (flight != null && flight.isAirborne) return null;
    return menu;
  }

  void _openMenu(double t, Object buttonId) {
    final menu = _prepareMenu(t, buttonId);
    if (menu == null) return;
    menu.motion.open(t, sourceScale: _presses[menu.capsule]?.scale ?? 1);
    wake();
  }

  _BarMenu? _prepareMenu(double t, Object buttonId) {
    final button = _buttons[buttonId];
    final items = button?.menu;
    final capsuleId = _capsuleOf[buttonId];
    final capsule = capsuleId == null ? null : _capsuleLayout(capsuleId);
    final scopeContext = _scopeContext;
    if (button == null ||
        !button.interactive ||
        items == null ||
        items.isEmpty ||
        capsule == null ||
        scopeContext == null ||
        _menu != null) {
      return null;
    }
    final overlay = widget.menuOverlay ?? morphPresentationOverlayOf(context);
    final box = context.findRenderObject();
    final overlayBox = overlay?.context.findRenderObject();
    if (overlay == null || box is! RenderBox || overlayBox is! RenderBox) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: FlutterError(
            'A bar button menu could not open: '
            '${overlay == null ? 'there is no Overlay around the bar' : 'the bar or its overlay is not laid out'}.',
          ),
          library: 'morph',
        ),
      );
      return null;
    }
    morphCheckOverlayAncestor(context, overlay);
    final origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final rect = capsule.rect.shift(origin);
    final tuning = widget.menuTuning.menu;
    final menu = _BarMenu(
      state: this,
      button: button,
      capsule: capsuleId!,
      style: MorphMenuStyle.resolve(context, widget.menuStyle),
      overlay: overlay,
      origin: origin,
    );
    menu.content.entries = items;
    menu.content.rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    menu.content.titleStyle = MorphTypography.resolve(menu.style.textStyle);
    menu.content.textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    menu.content.beginSession();
    final motion = menu.host.prepare(
      button: rect,
      bounds: overlayBox.size,
      padding: morphTargetPaddingOf(
        context,
        overlayBox.size,
        overlayBox: overlayBox,
      ),
      sourceHeight: rect.height,
      tuning: tuning,
      overlay: overlay,
    );
    motion.advance(t);
    _menu = menu;
    return menu;
  }

  double _contentWidth(
    MorphBarButton button,
    TextScaler scaler,
    TextDirection direction, {
    required bool bold,
  }) {
    final metrics = widget.metrics;
    final key = (scaler, direction, metrics);
    if (_widthsFor != key) {
      _widthsFor = key;
      _widths.clear();
    }
    if (button.label == null && !button.back) {
      return morphBarContentWidth(button, metrics, scaler, direction);
    }
    return _widths.putIfAbsent(
      (button.label, button.back, bold),
      () =>
          morphBarContentWidth(button, metrics, scaler, direction, bold: bold),
    );
  }

  bool _sameLayout(double width, List<MorphBarCapsuleLayout> layout) {
    if (!_hasLayout || width != _laidWidth) return false;
    if (layout.length != _layout.length) return false;
    for (var k = 0; k < layout.length; k++) {
      final a = layout[k];
      final b = _layout[k];
      if (a.id != b.id || a.rect != b.rect || a.segment != b.segment) {
        return false;
      }
      if (a.items.length != b.items.length) return false;
      for (var n = 0; n < a.items.length; n++) {
        if (a.items[n].id != b.items[n].id ||
            a.items[n].rect != b.items[n].rect) {
          return false;
        }
      }
    }
    return true;
  }

  void _relayout(double width) {
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final scaler =
        MediaQuery.maybeTextScalerOf(
          context,
        )?.clamp(maxScaleFactor: MorphBarMetrics.maxTextScale) ??
        TextScaler.noScaling;
    List<MorphBarCapsuleLayout> lay(List<MorphPlacedGroup> groups) =>
        morphLayoutBarGroups(
          groups: groups,
          width: width,
          top: widget.top,
          leadingInset: widget.leadingInset,
          trailingInset: widget.trailingInset,
          metrics: widget.metrics,
          scaler: scaler,
          direction: direction,
          contentWidth: (MorphBarButton b, {required bool bold}) =>
              _contentWidth(b, scaler, direction, bold: bold),
        );
    final layout = lay(widget.groups);
    final driftGroups = widget.driftGroups;
    _driftLayout = driftGroups == null || widget.driftProgress == null
        ? null
        : lay(driftGroups);
    for (final g in widget.groups) {
      for (final b in g.group.buttons) {
        _buttons[b.id] = b;
      }
    }
    final prominentBefore = Map.of(_prominent);
    final disabledBefore = Map.of(_disabled);
    for (final c in layout) {
      _prominent[c.id] = widget.groups.any(
        (g) =>
            g.group.prominent &&
            c.items.any((i) => g.group.buttons.any((b) => b.id == i.id)),
      );
      _disabled[c.id] = c.items.every(
        (i) => !(_buttons[i.id]?.interactive ?? true),
      );
      for (final i in c.items) {
        _capsuleOf[i.id] = c.id;
      }
    }
    _refreshMenu();
    if (_sameLayout(width, layout)) return;
    final first = !_hasLayout;
    _hasLayout = true;
    _laidWidth = width;
    _layout = layout;
    _motion.reducedMotion = morphReducedMotionOf(context);
    _motion.setLayout(clock, layout, animated: !first);
    for (final c in _motion.capsules) {
      if (c.id case final MorphBarDepartedId departed
          when !_prominent.containsKey(departed)) {
        _prominent[departed] = prominentBefore[departed.id] ?? false;
        _disabled[departed] = disabledBefore[departed.id] ?? false;
      }
    }
    _prune = true;
    if (!first) wake();
    widget.onLayout?.call(layout);
  }

  void _refreshMenu() {
    final menu = _menu;
    if (menu == null) return;
    final button = _buttons[menu.button.id];
    final entries = button?.menu;
    if (button == null ||
        !button.interactive ||
        entries == null ||
        entries.isEmpty) {
      menu.host.close();
      return;
    }
    menu.button = button;
    menu.host.updateEntries(entries);
  }

  /// Forgets the buttons and capsules that are no longer drawn.
  void _pruneMaps() {
    final items = {for (final f in _motion.items) f.id};
    final capsules = {for (final c in _motion.capsules) c.id};
    _buttons.removeWhere((Object id, MorphBarButton _) => !items.contains(id));
    _capsuleOf.removeWhere((Object id, Object _) => !items.contains(id));
    _contents.removeWhere(
      (Object id, (Object, Widget) _) => !items.contains(id),
    );
    _prominent.removeWhere((Object id, bool _) => !capsules.contains(id));
    _disabled.removeWhere((Object id, bool _) => !capsules.contains(id));
    _presses.removeWhere(
      (Object id, MorphGlassButtonMotion press) =>
          !capsules.contains(id) && id != _pressedCapsule && press.isSettled,
    );
  }

  MorphGlassButtonMotion _press(Object capsule, Size size) {
    final motion = _presses.putIfAbsent(
      capsule,
      () => MorphGlassButtonMotion(size: size),
    );
    motion.size = size;
    motion.reducedMotion = morphReducedMotionOf(context);
    return motion;
  }

  MorphBarCapsuleLayout? _capsuleLayout(Object id) {
    for (final c in _layout) {
      if (c.id == id) return c;
    }
    return null;
  }

  void _down(MorphBarButton button, PointerDownEvent event) {
    if (!button.interactive || event.buttons != kPrimaryButton) return;
    final capsuleId = _capsuleOf[button.id];
    final capsule = capsuleId == null ? null : _capsuleLayout(capsuleId);
    if (capsule == null) return;
    _pressedCapsule = capsuleId;
    _pressedButton = button.id;
    final press = _press(capsuleId!, capsule.rect.size);
    final t = stamp(event);
    press.pointerDown(t, event.localPosition - capsule.rect.topLeft);
    if (button.opensMenuOnTap) {
      final current = _menu;
      final menu = current == null
          ? _prepareMenu(t, button.id)
          : current.button.id == button.id
          ? current
          : null;
      if (menu == null || menu.host.hasPointer) return;
      _menuFinger = event.pointer;
      menu.host.menuPointerDown(event);
      wake();
      return;
    }
    final items = button.menu;
    if (items != null && items.isNotEmpty && _menu == null) {
      _holdStart = t;
      _holdButton = button.id;
      wake();
    }
  }

  Offset _local(Object capsuleId, Offset global) {
    final box = context.findRenderObject();
    final capsule = _capsuleLayout(capsuleId);
    if (box is! RenderBox || capsule == null) return Offset.zero;
    return box.globalToLocal(global) - capsule.rect.topLeft;
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer == _menuFinger) _menu?.host.menuPointerMove(event);
    final id = _pressedCapsule;
    if (id == null) return;
    _presses[id]?.pointerMove(stamp(event), _local(id, event.position));
  }

  void _up(PointerUpEvent event) {
    final id = _pressedCapsule;
    final buttonId = _pressedButton;
    if (id == null) return;
    _pressedCapsule = null;
    _pressedButton = null;
    final t = stamp(event);
    final activated =
        _presses[id]?.pointerUp(t, _local(id, event.position)) ?? false;
    if (event.pointer == _menuFinger) {
      _menuFinger = null;
      _menu?.host.menuPointerUp(event);
      wake();
      return;
    }
    final start = _holdStart;
    final held = _holdButton != null && start != null;
    final recognized = held && t - start >= widget.menuTuning.recognition;
    if (held && !recognized) {
      _holdStart = null;
      _holdButton = null;
    }
    final menu = _menu;
    if (menu != null && menu.button.id == buttonId) {
      _holdButton = null;
      if (activated && menu.motion.isOpen) {
        _buttons[buttonId]?.onPressed?.call();
        menu.motion.close(t);
        wake();
      }
      return;
    }
    if (recognized) return;
    if (activated && buttonId != null) _buttons[buttonId]?.onPressed?.call();
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer == _menuFinger) {
      _menuFinger = null;
      _menu?.host.menuPointerCancel(event);
    }
    final id = _pressedCapsule;
    if (id == null) return;
    _pressedCapsule = null;
    _pressedButton = null;
    _holdStart = null;
    _holdButton = null;
    _presses[id]?.pointerCancel(stamp(event));
  }

  @override
  Widget build(BuildContext context) {
    final style = MorphBarStyle.resolve(context, widget.style);
    final glass = MorphGlass.maybeOf(context);
    final brightness = morphBrightnessOf(context);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final items = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _relayout(constraints.maxWidth);
        final progress = widget.driftProgress;
        if (progress == null && _motion.isDrifting) {
          _motion.endDrift(clock);
          wake();
        }
        return ListenableBuilder(
          listenable: progress == null
              ? frames
              : Listenable.merge([frames, progress]),
          builder: (BuildContext context, Widget? _) {
            if (progress != null) {
              _motion.setDrift(
                _driftLayout,
                widget.driftFactor * progress.value.clamp(0.0, 1.0),
              );
            }
            final capsules = _motion.capsules;
            final items = _motion.items;
            Rect lifted(Object id, Rect rect) {
              final press = _presses[id];
              if (press == null) return rect;
              final lean = press.lean;
              return Rect.fromCenter(
                center: rect.center + lean,
                width: rect.width * press.scaleX,
                height: rect.height * press.scaleY,
              );
            }

            final apart = [
              for (final c in capsules)
                if (c.apart)
                  MorphGlassSurface(
                    kind: MorphGlassKind.button,
                    shape: RRect.fromRectAndRadius(
                      c.rect,
                      Radius.circular(
                        math.min(c.rect.width, c.rect.height) / 2,
                      ),
                    ),
                    color: _capsuleColor(c.id, style),
                    brightness: brightness,
                    opacity: c.opacity,
                  ),
            ];
            final joined = [
              for (final c in capsules)
                if (c.apart)
                  ...const <MorphGlassSurface>[]
                else if (_landingOn(c.id) case final landing?) ...[
                  MorphGlassSurface(
                    kind: MorphGlassKind.button,
                    shape: landing.motion.buttonBlob.rrect.shift(
                      -landing.origin,
                    ),
                    color: _capsuleColor(c.id, style),
                    brightness: brightness,
                  ),
                  MorphGlassSurface(
                    kind: MorphGlassKind.menu,
                    shape: landing.motion.menuBlob.rrect.shift(-landing.origin),
                    color: style.capsuleColor,
                    brightness: brightness,
                  ),
                ] else if (!_carried(c.id))
                  MorphGlassSurface(
                    kind: MorphGlassKind.button,
                    shape: RRect.fromRectAndRadius(
                      lifted(c.id, c.rect),
                      Radius.circular(
                        math.min(c.rect.width, c.rect.height) / 2,
                      ),
                    ),
                    color: _capsuleColor(c.id, style),
                    brightness: brightness,
                  ),
            ];
            final menuCapsule = _menuCapsule();
            final content = Stack(
              key: _contentKey,
              clipBehavior: Clip.none,
              children: [
                Positioned.fromRect(
                  rect: menuCapsule ?? Rect.zero,
                  child: IgnorePointer(
                    child: Builder(
                      builder: (BuildContext context) {
                        _scopeContext = context;
                        return MorphTag(
                          id: _menuTag,
                          shape: const StadiumBorder(),
                          child: const SizedBox.expand(),
                        );
                      },
                    ),
                  ),
                ),
                for (final f in items)
                  if (_buttons[f.id] case final button?)
                    if (!_carried(_capsuleOf[f.id] ?? f.id))
                      _buildItem(
                        button,
                        f,
                        style,
                        direction,
                        capsuleId: _capsuleOf[f.id],
                      ),
              ],
            );
            final spacing = widget.metrics.containerSpacing;
            final bar = SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: glass == null
                  ? CustomPaint(
                      painter: _CapsulePainter([
                        ..._flat.of(joined, spacing),
                        ..._flatApart.of(apart, spacing),
                      ], style),
                      child: content,
                    )
                  : MorphGlassHost(
                      painter: glass,
                      mode: MorphGlassMode.layer,
                      frame: () => MorphGlassFrame(
                        joined,
                        spacing: spacing,
                        still: progress == null && motionSettled,
                        contentSlots: [
                          for (final f in items)
                            Rect.fromCenter(
                              center: f.center,
                              width: f.size.width,
                              height: f.size.height,
                            ),
                        ],
                      ),
                      content: apart.isEmpty
                          ? content
                          : Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: MorphGlassHost(
                                      painter: glass,
                                      mode: MorphGlassMode.layer,
                                      frame: () => MorphGlassFrame(
                                        apart,
                                        spacing: spacing,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned.fill(child: content),
                              ],
                            ),
                    ),
            );
            return bar;
          },
        );
      },
    );
    final grouped = MorphChromeBackdrop(child: items);
    if (MorphScope.maybeOf(context) != null) return grouped;
    return MorphScope(child: grouped);
  }

  Color _capsuleColor(Object id, MorphBarStyle style) {
    if (!(_prominent[id] ?? false)) return style.capsuleColor;
    return (_disabled[id] ?? false)
        ? style.disabledProminentColor
        : style.prominentColor;
  }

  Rect? _menuCapsule() {
    final id =
        _menu?.capsule ??
        (_holdButton == null ? null : _capsuleOf[_holdButton]);
    if (id == null) return null;
    return _capsuleLayout(id)?.rect;
  }

  Widget _buildItem(
    MorphBarButton button,
    MorphBarItemFrame frame,
    MorphBarStyle style,
    TextDirection direction, {
    required Object? capsuleId,
  }) {
    final prominent = capsuleId != null && (_prominent[capsuleId] ?? false);
    final color = prominent
        ? style.prominentForegroundColor
        : button.interactive
        ? style.foregroundColor
        : style.disabledLabelColor;
    final iconColor = prominent || button.interactive
        ? color
        : style.disabledIconColor;
    final press = capsuleId == null ? null : _presses[capsuleId];
    final capsule = capsuleId == null ? null : _capsuleLayout(capsuleId);
    final landing = capsuleId == null ? null : _landingOn(capsuleId);
    var center = frame.center;
    var scale = frame.scale;
    if (landing != null && capsule != null) {
      final blob = landing.motion.buttonBlob;
      center =
          blob.rect.center -
          landing.origin +
          (center - capsule.rect.center) * blob.scale;
      scale *= blob.scale;
    } else if (press != null && capsule != null) {
      final c = capsule.rect.center;
      center = c + (center - c) * press.scaleX + press.lean;
      scale *= press.scale;
    }
    final metrics = widget.metrics;
    final inputs = (button, color, iconColor, prominent, direction, metrics);
    final cached = _contents[button.id];
    Widget content;
    if (cached != null && cached.$1 == inputs) {
      content = cached.$2;
    } else {
      content = _ButtonContent(
        button: button,
        metrics: metrics,
        color: color,
        iconColor: iconColor,
        bold: prominent,
        direction: direction,
      );
      _contents[button.id] = (inputs, content);
    }
    if (frame.blur > 0.05) {
      content = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: frame.blur,
          sigmaY: frame.blur,
          tileMode: TileMode.decal,
        ),
        child: content,
      );
    }
    content = Opacity(
      opacity: frame.presence.clamp(0.0, 1.0),
      child: Transform.scale(scale: scale, child: content),
    );
    if (!frame.leaving) {
      content = Semantics(
        button: true,
        enabled: button.interactive,
        label: button.semanticLabel ?? button.label,
        expanded: (button.menu?.isNotEmpty ?? false)
            ? _menu?.button.id == button.id && (_menu?.motion.isOpen ?? false)
            : null,
        onTap: button.opensMenuOnTap
            ? (_menu == null ? () => _openMenu(clock, button.id) : null)
            : button.onPressed,
        onLongPress:
            button.interactive &&
                !button.opensMenuOnTap &&
                (button.menu?.isNotEmpty ?? false) &&
                _menu == null
            ? () => _openMenu(clock, button.id)
            : null,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (PointerDownEvent e) => _down(button, e),
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _cancel,
          child: ExcludeSemantics(child: content),
        ),
      );
    } else {
      content = IgnorePointer(child: ExcludeSemantics(child: content));
    }
    return Positioned(
      key: ValueKey<Object>(button.id),
      left: center.dx - frame.size.width / 2,
      top: center.dy - frame.size.height / 2,
      width: frame.size.width,
      height: frame.size.height,
      child: content,
    );
  }
}

/// The long-press menu of one bar button: the measured menu of
/// [MorphMenuButton] grown out of the button's capsule, carried by an
/// engine flight from the bar's own tag.
class _BarMenu {
  _BarMenu({
    required this.state,
    required this.button,
    required this.capsule,
    required this.style,
    required this.overlay,
    required this.origin,
  });

  final _MorphBarItemsState state;
  MorphBarButton button;
  final Object capsule;
  final MorphMenuStyle style;
  final OverlayState overlay;
  final Offset origin;
  late final MorphMenuController host = MorphMenuController(
    tagId: state._menuTag,
    scopeContext: () => state._scopeContext,
    clock: () => state.clock,
    stamp: state.stamp,
    wake: state.wake,
    style: () => style,
    glyph: () => glyph,
    semanticLabel: () => button.semanticLabel ?? button.label,
  );
  MorphMenuContent get content => host.menuContent;
  MorphMenuMotion get motion => host.menuMotion!;
  MorphFlight? get flight => host.flight;

  Widget get glyph {
    final frame = state._capsuleLayout(capsule);
    return SizedBox.fromSize(
      size: frame?.rect.size ?? Size.zero,
      child: Center(
        child: _ButtonContent(
          button: button,
          metrics: state.widget.metrics,
          color: MorphBarStyle.resolve(
            state.context,
            state.widget.style,
          ).foregroundColor,
          bold: false,
          direction: Directionality.maybeOf(state.context) ?? TextDirection.ltr,
        ),
      ),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.button,
    required this.metrics,
    required this.color,
    required this.bold,
    required this.direction,
    Color? iconColor,
  }) : iconColor = iconColor ?? color;

  final MorphBarButton button;
  final MorphBarMetrics metrics;
  final Color color;
  final Color iconColor;
  final bool bold;
  final TextDirection direction;

  @override
  Widget build(BuildContext context) {
    final label = button.label;
    final text = label == null
        ? null
        : Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: morphBarLabelStyle(
              metrics,
              bold: bold,
            ).copyWith(color: color),
          );
    if (button.back) {
      return Padding(
        padding: EdgeInsetsDirectional.only(start: metrics.backChevronInset),
        child: Row(
          children: [
            SizedBox(
              width: metrics.backChevronWidth,
              height: metrics.backChevronHeight,
              child: CustomPaint(
                painter: MorphBackChevronPainter(
                  color: iconColor,
                  mirrored: direction == TextDirection.rtl,
                ),
              ),
            ),
            if (text != null) ...[
              SizedBox(width: metrics.backChevronGap),
              Flexible(child: text),
            ],
          ],
        ),
      );
    }
    return Center(
      child:
          text ??
          IconTheme.merge(
            data: IconThemeData(color: iconColor, size: metrics.iconSize),
            child: SizedBox.square(
              dimension: metrics.iconSize,
              child: Center(child: button.icon),
            ),
          ),
    );
  }
}

/// Paints the back chevron of a navigation bar, pointing to the leading
/// edge; [mirrored] flips it for right-to-left text.
@internal
class MorphBackChevronPainter extends CustomPainter {
  /// Creates the painter.
  const MorphBackChevronPainter({required this.color, this.mirrored = false});

  /// The stroke color.
  final Color color;

  /// Whether the chevron points right.
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.19;
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = stroke;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    final left = stroke / 2 + size.width * 0.12;
    final right = size.width - stroke / 2 - size.width * 0.12;
    final path = Path();
    if (mirrored) {
      path.moveTo(left, stroke / 2);
      path.lineTo(right, size.height / 2);
      path.lineTo(left, size.height - stroke / 2);
    } else {
      path.moveTo(right, stroke / 2);
      path.lineTo(left, size.height / 2);
      path.lineTo(right, size.height - stroke / 2);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(MorphBackChevronPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.mirrored != mirrored;
}

/// The bodies the flat capsules draw, traced once per change of their
/// shapes.
///
/// The grouping rule is the glass renderer's (`MorphGlassLayerParts.of`):
/// capsules group by geometry alone - the container fuses any two within
/// its spacing, whatever their colors - and a fused body takes the color
/// of its first capsule in drawing order, as the renderer's bodies take
/// the tint of their first surface, faded by its opacity. Capsules under
/// half a point either way are not drawn.
class _FlatBodies {
  List<RRect> _shapes = const [];
  List<Color> _colors = const [];
  List<double> _opacities = const [];
  double _spacing = double.nan;
  List<(Color, Object, double)> _bodies = const [];

  List<(Color, Object, double)> of(
    List<MorphGlassSurface> surfaces,
    double spacing,
  ) {
    final visible = [
      for (final s in surfaces)
        if (s.bounds.width >= 0.5 && s.bounds.height >= 0.5) s,
    ];
    final shapes = [for (final s in visible) s.shape];
    final colors = [for (final s in visible) s.color];
    final opacities = [for (final s in visible) s.opacity.clamp(0.0, 1.0)];
    if (spacing == _spacing &&
        listEquals(shapes, _shapes) &&
        listEquals(colors, _colors) &&
        listEquals(opacities, _opacities)) {
      return _bodies;
    }
    _shapes = shapes;
    _colors = colors;
    _opacities = opacities;
    _spacing = spacing;
    _bodies = [
      for (final group in morphGlassContainerGroups(shapes, spacing))
        (
          colors[group.first],
          group.length == 1
              ? shapes[group.single]
              : morphGlassContainerOutline([
                  for (final i in group) shapes[i],
                ], spacing).path,
          opacities[group.first],
        ),
    ];
    return _bodies;
  }
}

/// The flat capsules (no [MorphGlass] installed): each one an RRect,
/// except capsules the glass container fuses ([spacing]; see
/// [_FlatBodies] for the rule every glass tier shares), which are drawn
/// as their fused outline.
class _CapsulePainter extends CustomPainter {
  _CapsulePainter(this.bodies, this.style);

  /// The blur of the drop shadow under a flat capsule (an engineering
  /// default of the fallback, not measured).
  static const double shadowBlur = 6;

  /// How far the drop shadow sits below a flat capsule (not measured).
  static const double shadowOffset = 2;

  /// The width of a flat capsule's rim (not measured).
  static const double rimWidth = 0.5;

  final List<(Color, Object, double)> bodies;
  final MorphBarStyle style;

  static Color _faded(Color color, double opacity) =>
      color.withValues(alpha: color.a * opacity);

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint();
    shadow.maskFilter = const MaskFilter.blur(BlurStyle.normal, shadowBlur);
    const down = Offset(0, shadowOffset);
    for (final (_, body, opacity) in bodies) {
      shadow.color = _faded(style.shadowColor, opacity);
      switch (body) {
        case final RRect shape:
          canvas.drawRRect(shape.shift(down), shadow);
        case final Path path:
          canvas.drawPath(path.shift(down), shadow);
      }
    }
    final fill = Paint();
    final rim = Paint();
    rim.style = PaintingStyle.stroke;
    rim.strokeWidth = rimWidth;
    for (final (color, body, opacity) in bodies) {
      fill.color = _faded(color, opacity);
      rim.color = _faded(style.rimColor, opacity);
      switch (body) {
        case final RRect shape:
          canvas.drawRRect(shape, fill);
          canvas.drawRRect(shape.deflate(rimWidth / 2), rim);
        case final Path path:
          canvas.drawPath(path, fill);
          canvas.drawPath(path, rim);
      }
    }
  }

  @override
  bool shouldRepaint(_CapsulePainter oldDelegate) =>
      !listEquals(oldDelegate.bodies, bodies) || oldDelegate.style != style;
}
