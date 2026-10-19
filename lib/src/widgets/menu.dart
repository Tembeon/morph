import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/flight.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/presentation.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/target.dart';
import 'package:morph/src/widgets/activity_indicator.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/glyph_scale.dart';
import 'package:morph/src/widgets/menu_content.dart';
import 'package:morph/src/widgets/menu_entries.dart';
import 'package:morph/src/widgets/menu_host.dart';
import 'package:morph/src/widgets/menu_layout.dart';
import 'package:morph/src/widgets/menu_motion.dart';
import 'package:morph/src/widgets/press.dart';
import 'package:morph/src/widgets/touch_listener.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/theme/theme.dart';
import 'package:morph/src/widgets/glass_glow.dart';

/// The look of a [MorphMenuButton] and its menu.
class MorphMenuAppearance implements MorphAppearance {
  /// Creates an appearance; the defaults are the iOS 27 light appearance.
  const MorphMenuAppearance({
    this.glassColor = const Color(0xF2F9F9FF),
    this.shadowColor = const Color(0x33000000),
    this.shadowElevation = 12,
    this.textStyle = const TextStyle(fontSize: 17, color: Color(0xF5000000)),
    this.iconColor = const Color(0xF5000000),
    this.disabledIconColor = const Color(0x4C3C3C43),
    this.iconSize = MorphMenuTuning.rowIconSize,
    this.destructiveColor = const Color(0xFFFF383C),
    this.highlightColor = const Color(0x1F000000),
    this.secondaryColor = const Color(0x993C3C43),
    this.disabledColor = const Color(0x4C3C3C43),
    this.separatorColor = const Color(0x14000000),
    this.submenuColor = const Color(0x66FFFFFF),
    this.glassTint = const Color(0x00000000),
    this.submenuRimColor = const Color(0xFFFFFFFF),
    this.submenuShadowColor = const Color(0x1E000000),
    this.paletteSelectionColor = const Color(0x10000000),
  });

  /// The fallback fill of the button and menu without a glass painter.
  /// The installed renderer uses [glassTint].
  final Color glassColor;

  /// The color of the shadow under the button and the menu.
  final Color shadowColor;

  /// The elevation of the shadow under the button and the menu.
  final double shadowElevation;

  /// The style of row titles.
  ///
  /// The menu shows in an overlay, outside the text style of the screen
  /// the button sits on, so this is the whole style of its titles: it
  /// replaces the overlay's ambient text style instead of merging into it.
  final TextStyle textStyle;

  /// The color of the button's default glyph and of row glyphs.
  final Color iconColor;

  /// The color of a disabled button's glyph: tertiaryLabel. UIKit leaves
  /// the glass of a disabled menu button untouched (iPhone 16 Pro, iOS
  /// 27.0.1, light and dark).
  final Color disabledIconColor;

  /// The size of row glyphs.
  final double iconSize;

  /// The color of destructive rows.
  final Color destructiveColor;

  /// The fill of the pill under the highlighted row.
  final Color highlightColor;

  /// The color of subtitles and section headers: secondaryLabel.
  final Color secondaryColor;

  /// The color of disabled rows and of the loading row: tertiaryLabel.
  final Color disabledColor;

  /// The color of the hairline between groups of rows (rendered 229 on
  /// the 249 light platter, 50 on the 32 dark one).
  final Color separatorColor;

  /// The fallback tint a submenu card lays over the list under it.
  ///
  /// A card is a translucent platter that blurs what lies under it by
  /// [MorphMenuTuning.cardBlur]: where it covers the list it opened from
  /// it reads 252 on the 249 light menu and 57 on the 32 dark one; past
  /// that list's edge only the blur shows (device screenshots, iPhone 16
  /// Pro). Each further card under it adds half as much.
  final Color submenuColor;

  /// The tint of the button and menu cards in the installed renderer.
  /// Untinted regular glass reads 252 over a 249.5 light list and 57 over
  /// a 32 dark list on the iPhone 16 Pro; its transfer supplies the lift.
  final Color glassTint;

  /// The fallback highlight along a submenu card's top edge, fading over
  /// its first points (device: a one-pixel line at 251 - 255 over the 248
  /// light card, 65 - 83 over the 57 dark one).
  final Color submenuRimColor;

  /// The shadow color around a submenu card, on the liquid tier and in
  /// the fallback. Light: alpha 0.1188 (30 / 255) from a Gaussian fit of
  /// native straight side and bottom profiles over 242 gray, 0.273 gray
  /// RMS; dark is unmeasured.
  final Color submenuShadowColor;

  /// The platter under the selected palette cell (sampled: 233 on 249
  /// light, 53 on 32 dark).
  final Color paletteSelectionColor;

  /// The light appearance.
  static const light = MorphMenuAppearance();

  /// The dark appearance, sampled from the iOS 27 dark menu.
  static const dark = MorphMenuAppearance(
    glassColor: Color(0xF2222222),
    shadowColor: Color(0x66000000),
    textStyle: TextStyle(fontSize: 17, color: Color(0xF5FFFFFF)),
    iconColor: Color(0xF5FFFFFF),
    disabledIconColor: Color(0x4CEBEBF5),
    destructiveColor: Color(0xFFFF4245),
    highlightColor: Color(0x29FFFFFF),
    secondaryColor: Color(0x99EBEBF5),
    disabledColor: Color(0x4CEBEBF5),
    separatorColor: Color(0x14FFFFFF),
    submenuColor: Color(0x1DFFFFFF),
    submenuRimColor: Color(0x33FFFFFF),
    submenuShadowColor: Color(0x33000000),
    paletteSelectionColor: Color(0x18FFFFFF),
  );

  /// Resolves [explicit], then the ambient [MorphTheme], then the
  /// table for the ambient brightness.
  static MorphMenuAppearance resolve(
    BuildContext context,
    MorphMenuAppearance? explicit,
  ) =>
      explicit ??
      MorphThemeScope.maybeOf(context)?.appearance<MorphMenuAppearance>() ??
      switch (morphBrightnessOf(context)) {
        Brightness.dark => dark,
        Brightness.light => light,
      };

  /// A copy of this appearance with the given fields replaced.
  MorphMenuAppearance copyWith({
    Color? glassColor,
    Color? shadowColor,
    double? shadowElevation,
    TextStyle? textStyle,
    Color? iconColor,
    Color? disabledIconColor,
    double? iconSize,
    Color? destructiveColor,
    Color? highlightColor,
    Color? secondaryColor,
    Color? disabledColor,
    Color? separatorColor,
    Color? submenuColor,
    Color? glassTint,
    Color? submenuRimColor,
    Color? submenuShadowColor,
    Color? paletteSelectionColor,
  }) => MorphMenuAppearance(
    glassColor: glassColor ?? this.glassColor,
    shadowColor: shadowColor ?? this.shadowColor,
    shadowElevation: shadowElevation ?? this.shadowElevation,
    textStyle: textStyle ?? this.textStyle,
    iconColor: iconColor ?? this.iconColor,
    disabledIconColor: disabledIconColor ?? this.disabledIconColor,
    iconSize: iconSize ?? this.iconSize,
    destructiveColor: destructiveColor ?? this.destructiveColor,
    highlightColor: highlightColor ?? this.highlightColor,
    secondaryColor: secondaryColor ?? this.secondaryColor,
    disabledColor: disabledColor ?? this.disabledColor,
    separatorColor: separatorColor ?? this.separatorColor,
    submenuColor: submenuColor ?? this.submenuColor,
    glassTint: glassTint ?? this.glassTint,
    submenuRimColor: submenuRimColor ?? this.submenuRimColor,
    submenuShadowColor: submenuShadowColor ?? this.submenuShadowColor,
    paletteSelectionColor: paletteSelectionColor ?? this.paletteSelectionColor,
  );

  @override
  bool operator ==(Object other) =>
      other is MorphMenuAppearance &&
      other.glassColor == glassColor &&
      other.shadowColor == shadowColor &&
      other.shadowElevation == shadowElevation &&
      other.textStyle == textStyle &&
      other.iconColor == iconColor &&
      other.disabledIconColor == disabledIconColor &&
      other.iconSize == iconSize &&
      other.destructiveColor == destructiveColor &&
      other.highlightColor == highlightColor &&
      other.secondaryColor == secondaryColor &&
      other.disabledColor == disabledColor &&
      other.separatorColor == separatorColor &&
      other.submenuColor == submenuColor &&
      other.glassTint == glassTint &&
      other.submenuRimColor == submenuRimColor &&
      other.submenuShadowColor == submenuShadowColor &&
      other.paletteSelectionColor == paletteSelectionColor;

  @override
  int get hashCode => Object.hash(
    glassColor,
    shadowColor,
    shadowElevation,
    textStyle,
    iconColor,
    disabledIconColor,
    iconSize,
    destructiveColor,
    highlightColor,
    secondaryColor,
    disabledColor,
    separatorColor,
    submenuColor,
    glassTint,
    submenuRimColor,
    submenuShadowColor,
    paletteSelectionColor,
  );
}

/// What makes a [MorphMenuSource] open its menu.
enum MorphMenuTrigger {
  /// The menu is the source's primary action, as a `UIButton` whose
  /// `showsMenuAsPrimaryAction` is on or a `UIBarButtonItem(menu:)`
  /// without a primary action: a tap released on the source, or within
  /// [MorphMenuTuning.tapSlop] of it, opens it after
  /// [MorphMenuTuning.tapOpenDelay] (a release farther off opens
  /// nothing), a finger held within that slop opens it after
  /// [MorphMenuTuning.holdDuration] and may then slide onto a row and
  /// choose it on release.
  tap,

  /// The menu opens only by holding, after
  /// [MorphMenuTuning.holdDuration], as a `UIButton` with a primary
  /// action and a menu; a tap released on the source calls
  /// [MorphMenuSource.onTap] instead.
  hold,
}

/// The configuration shared by [MorphMenuSource] and [MorphMenuButton].
abstract class _MorphMenuSourceWidget extends StatefulWidget {
  const _MorphMenuSourceWidget({
    required this.menu,
    required this.appearance,
    required this.tuning,
    required this.overlay,
    required this.semanticLabel,
    required this.onOpen,
    required this.enabled,
    required this.order,
    required this.dismissOnSelect,
    super.key,
  });

  /// Whether the source opens its menu.
  ///
  /// A disabled source ignores touches, and an open menu closes when the
  /// source turns disabled.
  final bool enabled;

  /// The entries of the menu, top to bottom when it opens downward.
  final List<MorphMenuEntry> menu;

  /// The look of the menu; null resolves it through
  /// [MorphMenuAppearance.resolve].
  final MorphMenuAppearance? appearance;

  /// The measured motion.
  @internal
  final MorphMenuTuning tuning;

  /// The overlay the menu shows in, or null for
  /// [morphPresentationOverlayOf]: above the bars of a navigation stack
  /// the source sits in, as UIKit shows its menus.
  ///
  /// It must be an ancestor of the source.
  final OverlayState? overlay;

  /// The localized accessibility label supplied by the caller; null leaves
  /// the label to the source's child.
  final String? semanticLabel;

  /// Called with the flight of the menu each time a new one launches;
  /// its [MorphFlight.events] are the seam for haptics.
  @internal
  final ValueChanged<MorphFlight>? onOpen;

  /// The order of the entries relative to the source.
  final MorphMenuOrder order;

  /// Whether choosing a row closes the menu: null leaves it to each
  /// row's [MorphMenuItem.keepsMenuOpen], true closes after every row,
  /// false keeps the menu open after every row (SwiftUI's
  /// `menuActionDismissBehavior`).
  final bool? dismissOnSelect;

  /// The source drawn at rest, or null for the round glass button of
  /// [MorphMenuButton].
  Widget? get _source;

  /// The diameter of the round glass button of [MorphMenuButton].
  double get _size => MorphMenuTuning.buttonDiameter;

  /// What the menu carries inside the shrinking source shape; for the
  /// glass button its glyph, null for the ellipsis.
  Widget? get _look;

  ShapeBorder get _shape;

  MorphMenuTrigger get _trigger;

  VoidCallback? get _onTap;

  ({Color color, Color? rim})? get _surface;

  bool get _focusable => true;

  @override
  State<_MorphMenuSourceWidget> createState() => _MorphMenuSourceState();
}

/// Turns [child] into its own morphing menu, as iOS 27 does for any
/// `UIButton` with a menu, a `UIBarButtonItem.menu` or a control's
/// context menu interaction.
///
/// The [child] is drawn as it is. A touch on it lifts it by the measured
/// press of a menu button and, on the [trigger], the child's box
/// grows into the menu of [MorphMenuButton]: the same motion, content,
/// glass and flight, with the child's box and [shape] as the source the
/// menu grows out of and shrinks back into. While the menu is up the
/// [look] (the [child] when null) shrinks inside the source shape on the
/// menu's glass, so a child that draws its own surface, such as a glass
/// button, passes its content without that surface as the [look]. After
/// the close hands the source back, the source shape and the menu draw
/// the rest of the close over the child's box until the kicks ring out,
/// and the child shows again.
///
/// The [child] should not handle the touches itself: this widget takes
/// them, lifts the child and opens the menu; with [MorphMenuTrigger.hold]
/// it calls [onTap] for a tap. The source also takes keyboard focus, draws
/// the focus ring around the child's box, and Enter or Space do what a
/// tap does. A [child] that takes keyboard focus itself, such as its own
/// [FocusableActionDetector], sets [focusable] to false so that the
/// keyboard stops on it once, and calls [open] on Enter or Space.
///
/// The [shape] is the outline of the child at rest: [StadiumBorder] and
/// [CircleBorder] are capsules, a [RoundedRectangleBorder],
/// [RoundedSuperellipseBorder] or [ContinuousRectangleBorder] gives its
/// top-left corner radius to the source shape.
///
/// A source removed while its menu is up takes the menu with it at once.
class MorphMenuSource extends _MorphMenuSourceWidget {
  /// Creates a source that opens [menu] from [child].
  const MorphMenuSource({
    required super.menu,
    required this.child,
    this.look,
    this.shape = const StadiumBorder(),
    this.trigger = MorphMenuTrigger.tap,
    this.onTap,
    this.color,
    this.rimColor,
    this.focusable = true,
    super.appearance,
    @internal super.tuning = MorphMenuTuning.standard,
    super.overlay,
    super.semanticLabel,
    @internal super.onOpen,
    super.enabled = true,
    super.order = MorphMenuOrder.automatic,
    super.dismissOnSelect,
    super.key,
  });

  /// The source at rest; its box is where the menu grows from.
  final Widget child;

  /// What the menu carries inside the shrinking source shape, centered in
  /// the source's box; null carries [child], so a [child] holding a
  /// [GlobalKey] needs a look of its own.
  final Widget? look;

  /// The outline of [child] at rest.
  final ShapeBorder shape;

  /// What opens the menu.
  final MorphMenuTrigger trigger;

  /// Called for a tap released on the source, or within
  /// [MorphMenuTuning.tapSlop] of it, when [trigger] is
  /// [MorphMenuTrigger.hold].
  final VoidCallback? onTap;

  /// The fill of [child]'s own surface at rest, such as a glass button's
  /// fill or tint, or null for a [child] drawn on the menu's glass.
  ///
  /// The source shape the menu grows out of starts in this color, and the
  /// one it lands back into ends in it, so the hand-offs to and from
  /// [child] show no jump; in between it crosses into the menu's glass
  /// as the [look] fades out ([MorphMenuTuning.lookFadeStart] to
  /// [MorphMenuTuning.lookFadeEnd] of the morph). A glass painter tints
  /// the source's glass with it.
  final Color? color;

  /// The rim of [child]'s surface without a glass painter, drawn around
  /// the source shape at the [color]'s share; null draws none.
  final Color? rimColor;

  /// Whether the source takes keyboard focus and draws the focus ring;
  /// false leaves both to a [child] that takes the focus itself.
  final bool focusable;

  /// Opens the menu of the [MorphMenuSource] or [MorphMenuButton] above
  /// [context], as a tap on it does; nothing happens when there is none,
  /// it is disabled or its menu is already open.
  ///
  /// The source takes keyboard focus itself, draws the focus ring around
  /// its box and answers Enter or Space as a tap; this opens the menu from
  /// anywhere else below it, such as a focusable [child] of a source
  /// whose [focusable] is false.
  static void open(BuildContext context) {
    final state = context.findAncestorStateOfType<_MorphMenuSourceState>();
    if (state == null || !state.widget.enabled) return;
    if (state._motion?.isOpen ?? false) return;
    state._openFromSemantics();
  }

  @override
  ({Color color, Color? rim})? get _surface {
    final color = this.color;
    return color == null ? null : (color: color, rim: rimColor);
  }

  @override
  Widget? get _source => child;

  @override
  Widget? get _look => look ?? child;

  @override
  ShapeBorder get _shape => shape;

  @override
  MorphMenuTrigger get _trigger => trigger;

  @override
  VoidCallback? get _onTap => onTap;

  @override
  bool get _focusable => focusable;
}

/// A round glass button that turns into its menu exactly like an iOS 27
/// `UIButton` whose menu is its primary action: the glass ellipsis
/// configuration of [MorphMenuSource].
///
/// A tap opens the menu on release; holding opens it after
/// [MorphMenuTuning.holdDuration] and lets the finger slide onto a
/// row and select it on release. A release outside the menu, Esc or the
/// system back gesture closes it. The menu shows in the nearest [Overlay]
/// unless [overlay] names another one, below the button when the button
/// sits in the upper half of the safe area and above it, with its entries
/// reversed (unless [order] is [MorphMenuOrder.fixed]), otherwise; the
/// keyboard counts as an obstructed edge.
///
/// The [menu] are [MorphMenuEntry] values: rows, sections (with headers,
/// single selection, palettes and small or medium cells), submenus that
/// open as cards stacked over the menu, dividers, deferred groups and
/// free-form [MorphMenuWidget] rows. The open menu follows the widget: a
/// rebuild with other entries updates it in place and resizes it on the
/// measured springs, as a SwiftUI menu follows its state. The button
/// takes keyboard focus and opens on Enter or Space; in the menu, arrow
/// keys move the highlight, Enter or Space choose, Esc goes back out of a
/// submenu and then closes the menu.
///
/// The menu opens and closes on UIKit's measured progress spring; once it
/// has closed, the button draws the rest of the close itself until its
/// kicks have rung out, as UIKit keeps its morph on screen until then.
/// The open menu is modal: a barrier without dimming takes the touches
/// outside it, focus stays in it, and a pop or Escape closes it. A button
/// removed while its menu is up takes the menu with it at once.
///
/// A disabled menu button keeps its glass and draws its glyph in
/// [MorphMenuAppearance.disabledIconColor], as UIKit's does.
class MorphMenuButton extends _MorphMenuSourceWidget {
  /// Creates a menu button.
  const MorphMenuButton({
    required super.menu,
    this.child,
    this.size = MorphMenuTuning.buttonDiameter,
    super.appearance,
    @internal super.tuning = MorphMenuTuning.standard,
    super.overlay,
    super.semanticLabel,
    @internal super.onOpen,
    super.enabled = true,
    super.order = MorphMenuOrder.automatic,
    super.dismissOnSelect,
    super.key,
  });

  /// The button's glyph; an ellipsis when null.
  final Widget? child;

  /// The diameter of the button.
  final double size;

  @override
  double get _size => size;

  @override
  Widget? get _source => null;

  @override
  Widget? get _look => child;

  @override
  ShapeBorder get _shape => const CircleBorder();

  @override
  MorphMenuTrigger get _trigger => MorphMenuTrigger.tap;

  @override
  VoidCallback? get _onTap => null;

  @override
  ({Color color, Color? rim})? get _surface => null;
}

/// The progress of a menu that flies on the engine: the measured spring
/// in motion time, the clock the kicks run on, with the flight that
/// carries the menu sent the same way through [onOpen] and [onClose].
@internal
class MorphMenuFlightProgress extends MorphMenuProgress {
  /// Creates the progress of [tuning]'s spring.
  MorphMenuFlightProgress(
    MorphMenuTuning tuning, {
    required this.onOpen,
    required this.onClose,
  }) : _spring = MorphMenuProgress.spring(tuning);

  /// Called when the menu opens: launches or retargets its flight.
  final VoidCallback onOpen;

  /// Called when the menu closes: closes its flight.
  final VoidCallback onClose;

  final MorphMenuProgress _spring;

  @override
  double valueAt(double t) => _spring.valueAt(t);

  @override
  bool restsWithin(double t, double rest) => _spring.restsWithin(t, rest);

  @override
  void open(double t) {
    _spring.open(t);
    onOpen();
  }

  @override
  void close(double t) {
    _spring.close(t);
    onClose();
  }
}

/// Wires [content]'s submenu layouts into [motion]; its actions and
/// highlights reach the content through the motion's events
/// ([MorphMenuController]).
@internal
void morphConnectMenu(
  MorphMenuMotion motion,
  MorphMenuContent content, {
  bool? dismissOnSelect,
}) {
  motion.submenuLayout = content.submenu;
  motion.dismissOnSelect = dismissOnSelect;
}

/// Checks that [overlay] is an ancestor of [context], which every
/// coordinate of a menu is measured against.
@internal
void morphCheckOverlayAncestor(BuildContext context, OverlayState overlay) {
  final overlayElement = overlay.context;
  var found = false;
  context.visitAncestorElements((Element element) {
    if (identical(element, overlayElement)) {
      found = true;
      return false;
    }
    return true;
  });
  if (!found) {
    throw FlutterError.fromParts([
      ErrorSummary('The overlay of a menu is not an ancestor of its button.'),
      ErrorDescription(
        'The menu measures its button in the coordinates of the overlay it '
        'shows in, which needs the overlay above the button.',
      ),
    ]);
  }
}

/// What [MorphMenuLayer] draws a menu from: the motion, the content and
/// the look of the source, and where the touches on the open menu go.
@internal
abstract interface class MorphMenuHost {
  /// The look of the menu.
  MorphMenuAppearance get menuStyle;

  /// The fill and flat rim of the source's own surface, which the source
  /// shape starts and ends in, or null for a source on the menu's glass.
  ({Color color, Color? rim})? get menuSourceSurface;

  /// The look of the source, shown inside the shrinking source shape.
  Widget get menuGlyph;

  /// A value equal between two frames whose [menuGlyph] looks the same,
  /// or null when the glyph changes only with [menuStyle].
  Object? get menuGlyphKey;

  /// The content of the menu.
  MorphMenuContent get menuContent;

  /// The glass painter installed above the menu's source, or null when the
  /// source has none.
  ///
  /// The menu is the source's own glass carried into an overlay, which may
  /// sit above the source's [MorphGlassScope]; the menu draws with this painter.
  MorphGlassPainter? get menuGlass;

  /// Notifies when the motion has advanced.
  Listenable get menuRepaint;

  /// The key of the root card's rows, which move into the open menu from
  /// wherever they were built ahead of it.
  GlobalKey get menuRowsKey;

  /// The blur drawn over the root card's rows (the content blur), which
  /// their glyph drawing reads as its cover ([MorphGlyphs]).
  ValueNotifier<double> get menuRowsBlur;

  /// The motion, or null before the menu first opens.
  MorphMenuMotion? get menuMotion;

  /// The time of the motion's clock.
  double get menuClock;

  /// Wakes the motion's clock after a change made through [menuMotion].
  void menuWake();

  /// Runs [command] on the motion at time [at], [menuClock] when null.
  ///
  /// The motion is advanced to that time first, each close it requests on
  /// the way answered at its own time, and the events the command raises
  /// are delivered before this returns.
  void menuCommand(
    void Function(MorphMenuMotion motion, double t) command, {
    double? at,
  });

  /// A finger touched the open menu.
  void menuPointerDown(PointerDownEvent event);

  /// A finger on the menu moved.
  void menuPointerMove(PointerMoveEvent event);

  /// A finger on the menu lifted.
  void menuPointerUp(PointerUpEvent event);

  /// A touch on the menu was cancelled.
  void menuPointerCancel(PointerCancelEvent event);
}

class _MorphMenuSourceState extends State<_MorphMenuSourceWidget>
    with
        SingleTickerProviderStateMixin<_MorphMenuSourceWidget>,
        MorphClock<_MorphMenuSourceWidget>
    implements MorphPressTarget {
  final Object _tagId = Object();
  BuildContext? _scopeContext;
  MorphMenuAppearance _style = MorphMenuAppearance.light;
  late final MorphMenuController _host = MorphMenuController(
    tagId: _tagId,
    scopeContext: () => _scopeContext,
    clock: () => clock,
    stamp: stamp,
    wake: wake,
    style: () => _style,
    surface: () => widget._surface,
    glyph: () => _glyphFor(_style, true),
    glyphKey: () => widget._source == null ? null : widget._look,
    semanticLabel: () => _semanticLabel,
    onOpen: (MorphFlight flight) => widget.onOpen?.call(flight),
    onTap: _tapped,
  );

  String? get _semanticLabel => widget.semanticLabel;
  MorphMenuContent get _content => _host.menuContent;
  MorphMenuMotion? get _motion => _host.menuMotion;

  MorphGlassOutline? _silhouette;
  Offset _silhouetteOrigin = Offset.zero;
  MorphGlassOutline? _shiftedSilhouette;

  MorphGlassOutline? _silhouetteAt(MorphGlassOutline? outline, Offset origin) {
    if (outline == null) return null;
    if (!identical(outline, _silhouette) || origin != _silhouetteOrigin) {
      _silhouette = outline;
      _silhouetteOrigin = origin;
      _shiftedSilhouette = outline.shift(origin);
    }
    return _shiftedSilhouette;
  }

  MorphFlight? get _flight => _host.flight;

  // The button's tree is built from this; every other frame only pushes
  // the press scale and the landing shapes into its render objects.
  final ValueNotifier<_ButtonStructure> _structure =
      ValueNotifier<_ButtonStructure>((landing: false, still: true));
  final ValueNotifier<bool> _expanded = ValueNotifier<bool>(false);
  // Synced as a build would read them: the flight hands the source back
  // on its own ticker. The press scale sits outside the structure's
  // subtree, so it hears the rebuilding frames too.
  late final MorphFrameSync<_ButtonStructure> _ticks =
      MorphFrameSync<_ButtonStructure>(
        structure: _syncValues,
        rebuild: (_ButtonStructure structure) => _structure.value = structure,
        notifiesOnRebuild: true,
      );
  double _pressScale = 1;
  _Shapes? _landingShapes;
  bool _faceWithField = false;

  _ButtonStructure _syncValues() {
    final motion = _motion;
    final landing = motion != null && _landing;
    final still = _still();
    _expanded.value = motion?.isOpen ?? false;
    _pressScale = landing || still ? 1 : motion?.pressScale ?? 1;
    if (landing) _landingShapes = _landingNow(motion);
    return (landing: landing, still: still);
  }

  _Shapes _landingNow(MorphMenuMotion motion) {
    final origin = -motion.button.topLeft;
    final source = motion.buttonBlob;
    return (
      menu: motion.menuBlob.rrect.shift(origin),
      source: source.rrect.shift(origin),
      sourceRect: source.rect.shift(origin),
      sourceScale: source.scale,
      lookStretch: 1,
      look: (opacity: 1, blur: 0),
      outline: _silhouetteAt(
        motion.silhouetteFor(withField: _faceWithField),
        origin,
      ),
      glow: null,
    );
  }

  @override
  void initState() {
    super.initState();
    _content.entries = widget.menu;
    _content.order = widget.order;
    _ticks.follow(frames);
  }

  @override
  void didUpdateWidget(_MorphMenuSourceWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _host.updateEntries(
      widget.menu,
      order: widget.order,
      dismissOnSelect: widget.dismissOnSelect,
    );
    if (oldWidget.enabled && !widget.enabled) _host.close();
  }

  @override
  void deactivate() {
    _host.sourceActive = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _host.sourceActive = true;
  }

  @override
  void dispose() {
    _host.dispose();
    _structure.dispose();
    _expanded.dispose();
    _ticks.dispose();
    super.dispose();
  }

  MorphMenuMotion _prepare() {
    final current = _motion;
    if (current != null && current.isPresented) {
      if (current.isClosing) _host.beginReopenSession();
      return current;
    }
    final overlay =
        widget.overlay ??
        morphPresentationOverlayOf(context) ??
        Overlay.of(context);
    if (widget.overlay != null) morphCheckOverlayAncestor(context, overlay);
    final box = context.findRenderObject()! as RenderBox;
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final button = origin & box.size;
    final padding = morphTargetPaddingOf(
      context,
      overlayBox.size,
      overlayBox: overlayBox,
    );
    _content.rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    _content.titleStyle = MorphTypography.resolve(_style.textStyle);
    _content.textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    _content.beginSession();
    final motion = _host.prepare(
      button: button,
      bounds: overlayBox.size,
      padding: padding,
      sourceRadius: _sourceRadius(Directionality.maybeOf(context)),
      tuning: widget.tuning,
      overlay: overlay,
      dismissOnSelect: widget.dismissOnSelect,
    );
    motion.opensOnTap = widget._trigger == MorphMenuTrigger.tap;
    return motion;
  }

  void _tapped() {
    if (widget.enabled) widget._onTap?.call();
  }

  double? _sourceRadius(TextDirection? direction) {
    final BorderRadiusGeometry? radius = switch (widget._shape) {
      RoundedRectangleBorder(:final borderRadius) => borderRadius,
      RoundedSuperellipseBorder(:final borderRadius) => borderRadius,
      ContinuousRectangleBorder(:final borderRadius) => borderRadius,
      _ => null,
    };
    return radius?.resolve(direction).topLeft.x;
  }

  @override
  void advanceMotion(double t) => _host.advance(t, framePeriod: framePeriod);

  @override
  bool get motionSettled => _motion?.isSettled ?? true;

  @override
  void settleMotion() => _motion?.settle();

  @override
  double? get motionWakeTime => _host.wakeTime;

  void _buttonDown(PointerDownEvent event) {
    if (!widget.enabled ||
        event.buttons != kPrimaryButton ||
        _host.hasPointer ||
        (_motion?.isOpen ?? false)) {
      return;
    }
    _prepare();
    _host.menuPointerDown(event);
  }

  @override
  void pressDown(PointerDownEvent event) => _buttonDown(event);

  @override
  void pressMove(PointerMoveEvent event) => _host.menuPointerMove(event);

  @override
  void pressUp(PointerUpEvent event) => _host.menuPointerUp(event);

  @override
  void pressCancel(PointerCancelEvent event) => _host.menuPointerCancel(event);

  @override
  void pressLost(PointerCancelEvent event) => _host.menuPointerCancel(event);

  void _activate() {
    if (_motion?.isOpen ?? false) return;
    _openFromSemantics();
  }

  void _openFromSemantics() {
    _prepare();
    _host.open();
  }

  bool get _landing => _host.isLanding;

  bool _still() {
    final motion = _motion;
    return motion == null ||
        (!motion.isPresented && !_landing && motion.isSettled);
  }

  ({
    MorphMenuAppearance style,
    double size,
    Widget glyph,
    bool still,
    Widget face,
  })?
  _resting;

  Widget _face(
    BuildContext context,
    MorphMenuAppearance style,
    Widget glyph,
    _ButtonStructure structure,
  ) {
    final motion = _motion;
    final source = widget._source;
    if (source != null) {
      final landing = motion != null && structure.landing;
      return Stack(
        fit: .passthrough,
        clipBehavior: .none,
        children: [
          Visibility.maintain(visible: !landing, child: source),
          if (landing)
            Positioned.fill(child: _landingFace(context, style, glyph, motion)),
        ],
      );
    }
    if (motion == null || !structure.landing) {
      final resting = _resting;
      final still = structure.still;
      if (resting != null &&
          identical(resting.style, style) &&
          resting.size == widget._size &&
          identical(resting.glyph, glyph) &&
          resting.still == still) {
        return resting.face;
      }
      final box = Offset.zero & Size.square(widget._size);
      final _Shapes shapes = (
        menu: null,
        source: RRect.fromRectAndRadius(box, Radius.circular(box.width / 2)),
        sourceRect: box,
        sourceScale: 1,
        lookStretch: 1,
        look: (opacity: 1, blur: 0),
        outline: null,
        glow: null,
      );
      final face = _MenuShapes(
        style: style,
        glyph: glyph,
        shapes: () => shapes,
        still: still,
      );
      _resting = (
        style: style,
        size: widget._size,
        glyph: glyph,
        still: still,
        face: face,
      );
      return face;
    }
    return _landingFace(context, style, glyph, motion);
  }

  Widget _landingFace(
    BuildContext context,
    MorphMenuAppearance style,
    Widget glyph,
    MorphMenuMotion motion,
  ) {
    final withField = morphGlassShadesOutlines(
      MorphGlassScope.maybeOf(context),
    );
    if (withField != _faceWithField || _landingShapes == null) {
      _faceWithField = withField;
      _landingShapes = _landingNow(motion);
    }
    return _MenuShapes(
      style: style,
      glyph: glyph,
      frames: _ticks,
      shapes: () => _landingShapes!,
      surface: widget._surface,
      menu: true,
    );
  }

  ({Widget? child, Color color, bool enabled, Widget glyph})? _glyph;

  // The same glyph instance across parent rebuilds keeps the resting face
  // cached in _face.
  Widget _glyphFor(MorphMenuAppearance style, bool enabled) {
    final custom = widget._look;
    if (widget._source != null) return custom!;
    final color = enabled ? style.iconColor : style.disabledIconColor;
    final last = _glyph;
    if (last != null &&
        identical(last.child, custom) &&
        last.color == color &&
        last.enabled == enabled) {
      return last.glyph;
    }
    final glyph = custom == null
        ? _Ellipsis(color: color)
        : enabled
        ? custom
        : IconTheme.merge(
            data: IconThemeData(color: color),
            child: custom,
          );
    _glyph = (child: custom, color: color, enabled: enabled, glyph: glyph);
    return glyph;
  }

  @override
  Widget build(BuildContext context) {
    final style = MorphMenuAppearance.resolve(context, widget.appearance);
    _style = style;
    final flight = _flight;
    if (flight != null && !flight.isFinished) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (!flight.isFinished) flight.markNeedsBuild();
      });
    }
    _structure.value = _ticks.read();
    final enabled = widget.enabled;
    final glyph = _glyphFor(style, enabled);
    final hold = widget._trigger == MorphMenuTrigger.hold;
    final Widget face = MorphLiveTemplate(
      live: _ticks,
      template: () => Transform.scale(scale: _pressScale),
      child: Builder(
        builder: (BuildContext context) {
          _scopeContext = context;
          return MorphTag(
            id: _tagId,
            shape: widget._shape,
            surfaceColor: widget._surface?.color ?? style.glassColor,
            child: ValueListenableBuilder<_ButtonStructure>(
              valueListenable: _structure,
              builder:
                  (
                    BuildContext context,
                    _ButtonStructure structure,
                    Widget? _,
                  ) => _face(context, style, glyph, structure),
            ),
          );
        },
      ),
    );
    final Widget button = MorphLiveSemantics(
      live: _expanded,
      propertiesOf: () => SemanticsProperties(
        button: true,
        enabled: enabled,
        expanded: _expanded.value,
        label: _semanticLabel,
        onTap: !enabled
            ? null
            : hold
            ? _tapped
            : _openFromSemantics,
        onLongPress: enabled && hold ? _openFromSemantics : null,
      ),
      child: MorphPress(
        target: this,
        enabled: enabled,
        focusable: widget._focusable,
        behavior: .opaque,
        focusRing: true,
        onActivate: !enabled
            ? null
            : hold
            ? _tapped
            : _activate,
        child: widget._source == null
            ? SizedBox.square(dimension: widget._size, child: face)
            : face,
      ),
    );
    if (MorphScope.maybeOf(context) != null) return button;
    return MorphScope(child: button);
  }
}

/// What a menu button's tree is built from; it rebuilds only when this
/// changes.
typedef _ButtonStructure = ({bool landing, bool still});

/// The opacity and blur of the button's look inside the shrinking source.
typedef _Look = ({double opacity, double blur});

/// Both shapes of the morph at one frame, in the coordinates of the box
/// they are drawn in; [menu] is null for the resting button, [source] for
/// a menu without a source shape (a context menu).
typedef _Shapes = ({
  RRect? menu,
  RRect? source,
  Rect sourceRect,
  double sourceScale,
  double lookStretch,
  _Look look,
  MorphGlassOutline? outline,
  MorphGlassGlow? glow,
});

/// Both shapes of the morph and the button's look inside the shrinking
/// one, in the coordinates of the box this is laid out in; without a
/// [menu] it is the resting button. A silhouette in the [shapes] is the
/// outline the two shapes fuse into; without one they are drawn as their
/// union.
///
/// The [shapes] are read again on every notification of [frames]
/// without a build; the tree changes only with the widget.
///
/// The look fades only with a [look]: on the button (resting, or after
/// the latch, where the progress is at or under zero) it is drawn
/// without a layer, which keeps the glass of every resting button in its
/// backdrop group.
class _MenuShapes extends StatelessWidget {
  const _MenuShapes({
    required this.style,
    required this.glyph,
    required this.shapes,
    this.surface,
    this.frames,
    this.menu = false,
    this.look = false,
    this.content,
    this.menuBlur,
    this.still = false,
    this.sourced = true,
  });

  final MorphMenuAppearance style;
  final Widget glyph;
  final _Shapes Function() shapes;
  final ({Color color, Color? rim})? surface;
  final Listenable? frames;
  final bool menu;
  final bool look;
  final Widget? content;
  final double? menuBlur;
  final bool still;

  /// Whether the morph has a source shape whose look is drawn inside it;
  /// a context menu grows out of a blob without one.
  final bool sourced;

  @override
  Widget build(BuildContext context) {
    final glass = MorphGlassScope.maybeOf(context);
    final content = this.content;
    final frames = this.frames;
    final Widget glyph = MorphLiveTemplate(
      live: frames,
      template: () {
        final now = shapes();
        return Transform.scale(
          scaleX: now.sourceScale * now.lookStretch,
          scaleY: now.sourceScale,
        );
      },
      child: MorphGlyphs(child: this.glyph),
    );
    final Widget surfaces;
    if (glass == null) {
      surfaces = MorphLiveTemplate(
        live: frames,
        template: () {
          final now = shapes();
          return CustomPaint(
            painter: _GlassPainter(
              style: style,
              menu: now.menu,
              source: now.source,
              outline: now.outline,
              surface: surface,
              glassShare: surface == null ? 1 : 1 - now.look.opacity,
              glow: now.glow,
            ),
          );
        },
      );
    } else {
      final brightness = morphBrightnessOf(context);
      surfaces = MorphGlassHost(
        painter: glass,
        mode: MorphGlassMode.layer,
        frames: frames,
        frame: () {
          final now = shapes();
          final menu = now.menu;
          final own = surface?.color;
          final share = 1 - now.look.opacity;
          final source = now.source;
          return MorphGlassFrame(
            [
              if (source != null)
                MorphGlassSurface(
                  kind: MorphGlassKind.button,
                  shape: source,
                  color: own == null
                      ? style.glassColor
                      : Color.lerp(own, style.glassColor, share)!,
                  tint: own == null
                      ? style.glassTint
                      : Color.lerp(own, style.glassTint, share),
                  blurRadius: menu == null ? null : menuBlur,
                  brightness: brightness,
                ),
              if (menu != null)
                MorphGlassSurface(
                  kind: MorphGlassKind.menu,
                  shape: menu,
                  color: style.glassColor,
                  tint: style.glassTint,
                  blurRadius: menuBlur,
                  brightness: brightness,
                  glow: now.glow,
                ),
            ],
            outline: menu == null ? null : now.outline,
            still: still,
          );
        },
      );
    }
    return Stack(
      clipBehavior: .none,
      children: [
        Positioned.fill(child: surfaces),
        ?content,
        if (sourced)
          Positioned.fill(
            child: MorphLiveCenter(
              live: frames,
              rectOf: () => shapes().sourceRect,
              // The glyph is laid out in the source's box of the frame,
              // centered, but again only when that can change it; the
              // ellipsis is the same box in any box as large.
              fixedSize: this.glyph is _Ellipsis
                  ? const Size.square(MorphMenuTuning.ellipsisSize)
                  : null,
              hiddenOf: look ? () => shapes().look.opacity <= 0 : null,
              ignoring: true,
              child: look
                  ? _Faded(
                      frames: frames,
                      look: () => shapes().look,
                      child: glyph,
                    )
                  : glyph,
            ),
          ),
      ],
    );
  }
}

/// [child] at the opacity of [look] and blurred by its blur, drawn
/// through one layer, both read again on every notification of [frames].
class _Faded extends StatelessWidget {
  const _Faded({required this.frames, required this.look, required this.child});

  final Listenable? frames;
  final _Look Function() look;
  final Widget child;

  static final ui.ImageFilter _none = ui.ImageFilter.blur(
    tileMode: TileMode.decal,
  );

  static bool _blurred(_Look look) =>
      look.blur > MorphMenuTuning.blurThreshold && look.opacity > 0;

  @override
  Widget build(BuildContext context) {
    return MorphLiveTemplate(
      live: frames,
      template: () {
        final now = look();
        return Opacity(
          alwaysIncludeSemantics: true,
          opacity: _blurred(now) ? 1 : now.opacity,
        );
      },
      child: MorphLiveTemplate(
        live: frames,
        template: () {
          final now = look();
          final blurred = _blurred(now);
          return ImageFiltered(
            enabled: blurred,
            imageFilter: blurred
                ? ui.ImageFilter.compose(
                    outer: ui.ColorFilter.matrix(<double>[
                      1, 0, 0, 0, 0, //
                      0, 1, 0, 0, 0, //
                      0, 0, 1, 0, 0, //
                      0, 0, 0, now.opacity, 0,
                    ]),
                    inner: ui.ImageFilter.blur(
                      sigmaX: now.blur,
                      sigmaY: now.blur,
                      tileMode: TileMode.decal,
                    ),
                  )
                : _none,
          );
        },
        child: child,
      ),
    );
  }
}

/// The menu inside the vessel: both shapes, the content and the button's
/// look, laid out over the whole overlay and drawn from the motion. The
/// rows of each card are built once per layout of that card, and the
/// layer builds only when what it shows changes (cards, highlight, glow,
/// whether the menu takes touches); every other frame pushes the motion's
/// geometry into the render objects around them.
@internal
class MorphMenuLayer extends StatefulWidget {
  /// Creates the layer of [host]'s menu carried by [flight].
  const MorphMenuLayer({required this.host, required this.flight, super.key});

  /// The menu drawn.
  final MorphMenuHost host;

  /// The flight that carries the menu.
  final MorphFlight flight;

  @override
  State<MorphMenuLayer> createState() => _MorphMenuLayerState();
}

class _MorphMenuLayerState extends State<MorphMenuLayer> {
  final ScrollController _scroll = ScrollController();
  bool _parentScrollLocked = false;
  Expando<Widget> _rows = Expando<Widget>();
  final Map<MorphMenuLayout, ValueNotifier<int?>> _hidden = Map.identity();
  MorphMenuAppearance? _rowsStyle;
  // Synced where a build would read the motion: a frame that changes the
  // structure builds, every other one only pushes its geometry.
  late final MorphFrameSync<_LayerStructure?> _ticks =
      MorphFrameSync<_LayerStructure?>(
        structure: _update,
        rebuild: (_LayerStructure? _) => setState(() {}),
      );
  _LayerFrame? _frame;
  _LayerStructure? _built;
  bool _withField = false;
  Brightness _brightness = Brightness.light;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrolled);
    _listen();
  }

  @override
  void didUpdateWidget(MorphMenuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.host, widget.host) ||
        !identical(oldWidget.flight, widget.flight)) {
      _listen();
    }
  }

  @override
  void dispose() {
    _ticks.dispose();
    _scroll.dispose();
    for (final hidden in _hidden.values) {
      hidden.dispose();
    }
    super.dispose();
  }

  void _listen() {
    _ticks.follow(
      Listenable.merge([widget.host.menuRepaint, widget.flight.frameTicks]),
    );
  }

  /// Reads the motion's frame and returns the structure it shows.
  _LayerStructure? _update() {
    final host = widget.host;
    final motion = host.menuMotion;
    if (motion == null) {
      _frame = null;
      return null;
    }
    final style = host.menuStyle;
    final frame = _LayerFrame(
      motion,
      style: style,
      brightness: _brightness,
      withField: _withField,
    );
    _frame = frame;
    host.menuRowsBlur.value = motion.contentBlur;
    final cards = frame.cards;
    for (var i = 0; i < cards.length; i++) {
      _hiddenOf(cards[i].layout).value = i + 1 < cards.length
          ? cards[i + 1].source
          : null;
    }
    final visible = frame.visible;
    return _LayerStructure(
      motion: motion,
      painter: host.menuGlass,
      style: style,
      surface: host.menuSourceSurface,
      glyph: host.menuGlyphKey,
      open: motion.isOpen,
      layouts: [for (final card in cards) card.layout],
      faces: [for (var i = 1; i < cards.length; i++) frame.cardAt(i).faces],
      highlighted: motion.highlighted,
      highlightedCard: motion.highlightedCard,
      sliding: motion.isSliding,
      scrolls: cards.isNotEmpty && cards[0].layout.height > visible + 0.5,
    );
  }

  void _scrolled() {
    final motion = widget.host.menuMotion;
    if (motion == null || !_scroll.hasClients) return;
    motion.scrollOffset = _scroll.offset;
  }

  bool _scrollStarted(ScrollNotification notification) {
    if (morphScrollDragged(notification)) _scrollGesture();
    return false;
  }

  void _scrollGesture() {
    final host = widget.host;
    host.menuCommand((motion, t) => motion.pointerScrolled(t));
    host.menuWake();
  }

  Widget _rowsOf(
    MorphMenuLayout layout,
    MorphMenuAppearance style, {
    ValueListenable<double>? cover,
  }) {
    if (!identical(style, _rowsStyle)) {
      _rows = Expando<Widget>();
      _rowsStyle = style;
    }
    return _rows[layout] ??= _menuRows(
      layout: layout,
      style: style,
      hidden: _hiddenOf(layout),
      content: widget.host.menuContent,
      onSelect: (int target) => _select(layout, target),
      cover: cover,
    );
  }

  ValueNotifier<int?> _hiddenOf(MorphMenuLayout layout) =>
      _hidden.putIfAbsent(layout, () => ValueNotifier<int?>(null));

  void _select(MorphMenuLayout layout, int target) {
    final host = widget.host;
    final motion = host.menuMotion;
    if (motion == null || !motion.isOpen) return;
    if (!identical(motion.cards[motion.topCard].layout, layout)) return;
    host.menuCommand((motion, t) => motion.select(t, target));
    host.menuWake();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final host = widget.host;
    final motion = host.menuMotion;
    if (motion == null || !motion.isOpen) return KeyEventResult.ignored;
    final top = motion.topCard;
    final layout = motion.cards[top].layout;
    final order = [for (var i = 0; i < layout.targets.length; i++) i];
    order.sort((int a, int b) {
      final ra = layout.targets[a].rect;
      final rb = layout.targets[b].rect;
      final dy = ra.top.compareTo(rb.top);
      return dy != 0 ? dy : ra.left.compareTo(rb.left);
    });
    final current = motion.highlightedCard == top ? motion.highlighted : null;
    final rtl = host.menuContent.rtl;
    final key = event.logicalKey;
    void move(int step) {
      if (order.isEmpty) return;
      final at = current == null ? -1 : order.indexOf(current);
      final next = at < 0
          ? (step > 0 ? 0 : order.length - 1)
          : (at + step).clamp(0, order.length - 1);
      host.menuCommand((motion, t) => motion.highlight(t, order[next]));
    }

    final KeyEventResult result;
    if (key == LogicalKeyboardKey.arrowDown) {
      move(1);
      result = KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      move(-1);
      result = KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (current == null) return KeyEventResult.ignored;
      host.menuCommand((motion, t) => motion.select(t, current));
      result = KeyEventResult.handled;
    } else if (key ==
        (rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight)) {
      if (current == null ||
          layout.targets[current].kind != MorphMenuTargetKind.submenu) {
        return KeyEventResult.ignored;
      }
      host.menuCommand((motion, t) => motion.select(t, current));
      result = KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape ||
        key ==
            (rtl
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowLeft)) {
      var back = false;
      host.menuCommand((motion, t) => back = motion.back(t));
      if (!back) return KeyEventResult.ignored;
      result = KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    host.menuWake();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final glyph = host.menuGlyph;
    final painter = host.menuGlass;
    _withField = morphGlassShadesOutlines(
      painter ?? MorphGlassScope.maybeOf(context),
    );
    _brightness = morphBrightnessOf(context);
    final structure = _built = _ticks.read();
    final frame = _frame;
    final Widget body;
    if (structure == null || frame == null) {
      body = const SizedBox.shrink();
    } else {
      final motion = structure.motion;
      final style = structure.style;
      final cards = frame.cards;
      final layer = IgnorePointer(
        ignoring: !structure.open,
        child: Listener(
          behavior: .opaque,
          onPointerDown: host.menuPointerDown,
          onPointerMove: host.menuPointerMove,
          onPointerUp: host.menuPointerUp,
          onPointerCancel: host.menuPointerCancel,
          child: _MenuShapes(
            style: style,
            glyph: glyph,
            frames: _ticks,
            shapes: () => _frame!.shapes,
            surface: structure.surface,
            menu: true,
            look: true,
            sourced: motion.drawsSource,
            menuBlur: motion.tuning.cardBlur,
            content: Positioned.fill(
              child: MorphLiveWindow(
                live: _ticks,
                windowOf: () => _frame!.menu.rrect,
                clipsOf: () => _frame!.cards.length < 2,
                child: Stack(
                  clipBehavior: .none,
                  children: [
                    // The content moves inside the window by its
                    // transform, so a frame that moves it lays nothing out.
                    MorphLivePositionedTemplate(
                      live: _ticks,
                      template: () {
                        final now = _frame!;
                        return Positioned(
                          left: now.at.dx,
                          top: now.at.dy,
                          width: now.size.width,
                          height: now.size.height,
                          child: morphLiveSlot,
                        );
                      },
                      child: MorphLiveTemplate(
                        live: _ticks,
                        template: () {
                          final now = _frame!;
                          final transform = Matrix4.identity();
                          transform.scaleByDouble(
                            now.scale * now.stretch.dx,
                            now.scale * now.stretch.dy,
                            1,
                            1,
                          );
                          return Transform(transform: transform);
                        },
                        child: Stack(
                          clipBehavior: .none,
                          children: [
                            _Faded(
                              frames: _ticks,
                              look: () => _frame!.faded,
                              child: Stack(
                                clipBehavior: .none,
                                children: [
                                  ..._cards(motion, style, cards, top: false),
                                ],
                              ),
                            ),
                            ..._cards(motion, style, cards, top: true),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      body = painter == null
          ? layer
          : MorphGlassScope(painter: painter, child: layer);
    }
    final Widget menu = Semantics(
      container: true,
      explicitChildNodes: true,
      role: ui.SemanticsRole.menu,
      child: Focus(autofocus: true, onKeyEvent: _key, child: body),
    );
    // In a build scope and a repaint boundary of the menu's own, a frame
    // that changes the structure lays out and repaints the menu, not the
    // overlay it shows in.
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) => menu,
      ),
    );
  }

  List<Widget> _cards(
    MorphMenuMotion motion,
    MorphMenuAppearance style,
    List<MorphMenuCard> cards, {
    required bool top,
  }) {
    final width = motion.tuning.menuWidth;
    final radius = motion.tuning.cornerRadius;
    if (top) {
      if (cards.length < 2) return const [];
      final last = cards.length - 1;
      return [_card(motion, style, cards, last, width, radius)];
    }
    final count = cards.length < 2 ? cards.length : cards.length - 1;
    return [
      for (var i = 0; i < count; i++)
        _card(motion, style, cards, i, width, radius),
    ];
  }

  /// The frame card [index] shows at in the content, scale included, with
  /// the root list [visible] high.
  static Rect _shown(
    List<MorphMenuCard> cards,
    int index,
    double width,
    double visible,
  ) {
    final card = cards[index];
    final s = card.scale;
    final rect = index == 0 ? Rect.fromLTWH(0, 0, width, visible) : card.rect;
    return Rect.fromLTWH(
      width / 2 + (rect.left - width / 2) * s,
      rect.top * s,
      rect.width * s,
      rect.height * s,
    );
  }

  static Rect _local(Rect rect, Offset origin, double k) => Rect.fromLTWH(
    (rect.left - origin.dx) * k,
    (rect.top - origin.dy) * k,
    rect.width * k,
    rect.height * k,
  );

  _RootKey? _rootKey;
  Widget? _rootWidget;

  Widget? _rootFor(_RootKey key) {
    final last = _rootKey;
    if (last != null &&
        identical(last.layout, key.layout) &&
        identical(last.style, key.style) &&
        identical(last.tuning, key.tuning) &&
        last.locked == key.locked &&
        last.scrolls == key.scrolls &&
        last.width == key.width &&
        last.radius == key.radius &&
        last.highlighted == key.highlighted &&
        last.highlightedCard == key.highlightedCard &&
        last.sliding == key.sliding) {
      return _rootWidget;
    }
    _rootKey = key;
    return _rootWidget = null;
  }

  Widget _remember(Widget root) => _rootWidget = root;

  /// The root card's list below its moving frame: the same widget while
  /// nothing it shows changes, so a frame of the motion rebuilds none of
  /// it.
  Widget _root(
    MorphMenuMotion motion,
    MorphMenuAppearance style,
    MorphMenuLayout layout, {
    required bool locked,
    required bool scrolls,
    required double width,
    required double radius,
  }) {
    final content = SizedBox(
      width: width,
      height: layout.height,
      child: Stack(
        clipBehavior: .none,
        children: [
          ?_highlight(motion, style, layout, 0),
          KeyedSubtree(
            key: widget.host.menuRowsKey,
            child: _rowsOf(layout, style, cover: widget.host.menuRowsBlur),
          ),
        ],
      ),
    );
    final Widget body = scrolls
        ? NotificationListener<ScrollNotification>(
            onNotification: _scrollStarted,
            child: RawScrollbar(
              controller: _scroll,
              thumbColor: style.secondaryColor,
              thickness: MorphMenuTuning.scrollThickness,
              radius: const Radius.circular(
                MorphMenuTuning.scrollThickness / 2,
              ),
              mainAxisMargin: radius / 2,
              crossAxisMargin: MorphMenuTuning.scrollInset,
              child: CustomScrollView(
                controller: _scroll,
                physics: locked ? const NeverScrollableScrollPhysics() : null,
                slivers: [SliverToBoxAdapter(child: content)],
              ),
            ),
          )
        : OverflowBox(
            alignment: .topLeft,
            minHeight: layout.height,
            maxHeight: layout.height,
            child: content,
          );
    return ClipRRect(
      borderRadius: .circular(locked ? radius : 0),
      child: GestureDetector(
        behavior: .opaque,
        onPanUpdate: locked
            ? (DragUpdateDetails details) => _scrollGesture()
            : null,
        child: IgnorePointer(ignoring: locked, child: body),
      ),
    );
  }

  Widget _card(
    MorphMenuMotion motion,
    MorphMenuAppearance style,
    List<MorphMenuCard> cards,
    int index,
    double width,
    double radius,
  ) {
    final card = cards[index];
    final layout = card.layout;
    if (index == 0) {
      final locked = cards.length > 1;
      if (locked && !_parentScrollLocked && _scroll.hasClients) {
        (_scroll.position as ScrollPositionWithSingleContext).goIdle();
      }
      _parentScrollLocked = locked;
      final scrolls = _built!.scrolls;
      final rootKey = (
        layout: layout,
        style: style,
        tuning: motion.tuning,
        locked: locked,
        scrolls: scrolls,
        width: width,
        radius: radius,
        highlighted: motion.highlighted,
        highlightedCard: motion.highlightedCard,
        sliding: motion.isSliding,
      );
      final root =
          _rootFor(rootKey) ??
          _remember(
            _root(
              motion,
              style,
              layout,
              locked: locked,
              scrolls: scrolls,
              width: width,
              radius: radius,
            ),
          );
      return MorphLivePositionedTemplate(
        key: const ValueKey<int>(0),
        live: _ticks,
        template: () {
          final now = _frame!;
          return Positioned(
            left: width / 2 * (1 - now.cards[0].scale),
            top: 0,
            width: width,
            height: now.visible,
            child: morphLiveSlot,
          );
        },
        child: MorphLiveTemplate(
          live: _ticks,
          template: () => Transform.scale(
            scale: _frame!.cards[0].scale,
            alignment: .topLeft,
          ),
          child: MorphLiveTemplate(
            live: _ticks,
            template: () => Opacity(opacity: _frame!.cards[0].rowOpacity),
            child: root,
          ),
        ),
      );
    }
    MorphMenuPlaced? header;
    for (final element in layout.elements) {
      if (element.kind == MorphMenuPlacedKind.cardHeader) header = element;
    }
    final glass = widget.host.menuGlass ?? MorphGlassScope.maybeOf(context);
    _CardFrame now() => _frame!.cardAt(index);
    final shadowColor = style.submenuShadowColor;
    final cardBlur = motion.tuning.cardBlur;
    return MorphLivePositionedTemplate(
      key: ValueKey<int>(index),
      live: _ticks,
      template: () {
        final card = now();
        return Positioned(
          left: card.shown.left,
          top: card.shown.top,
          width: card.size.width,
          height: card.size.height,
          child: morphLiveSlot,
        );
      },
      child: MorphLiveTemplate(
        live: _ticks,
        template: () =>
            Transform.scale(scale: now().scale, alignment: .topLeft),
        child: Stack(
          clipBehavior: .none,
          children: [
            if (glass != null)
              Positioned.fill(
                child: BackdropGroup(
                  child: MorphGlassHost(
                    painter: glass,
                    mode: MorphGlassMode.body,
                    frames: _ticks,
                    frame: () {
                      final surface = now().surface;
                      return MorphGlassFrame(
                        [surface],
                        outline: morphGlassContainerOutline([surface.shape], 0),
                      );
                    },
                  ),
                ),
              ),
            if (glass == null)
              Positioned.fill(
                child: MorphLiveTemplate(
                  live: _ticks,
                  template: () {
                    final card = now();
                    return CustomPaint(
                      painter: _CardShadowPainter(
                        radius: card.radius,
                        color: shadowColor,
                        opacity: card.platter,
                      ),
                    );
                  },
                ),
              ),
            if (glass == null)
              Positioned.fill(
                child: MorphLiveTemplate(
                  live: _ticks,
                  template: () => ClipRRect(
                    borderRadius: BorderRadius.circular(now().radius),
                  ),
                  child: MorphLiveTemplate(
                    live: _ticks,
                    template: () {
                      final blur = now().blur;
                      return BackdropFilter(
                        enabled: blur > MorphMenuTuning.blurThreshold,
                        filter: ui.ImageFilter.blur(
                          sigmaX: blur,
                          sigmaY: blur,
                          tileMode: TileMode.clamp,
                        ),
                      );
                    },
                    child: Stack(
                      clipBehavior: .none,
                      children: [
                        Positioned.fill(
                          child: MorphLiveTemplate(
                            live: _ticks,
                            template: () => ClipPath(
                              clipper: _CardBackdropClipper(now().under),
                            ),
                            child: MorphLiveTemplate(
                              live: _ticks,
                              template: () => CustomPaint(
                                painter: _CardBasePainter(now().surface),
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: MorphLiveTemplate(
                            live: _ticks,
                            template: () {
                              final card = now();
                              return CustomPaint(
                                painter: _CardPlatterPainter(
                                  radius: card.radius,
                                  under: card.under,
                                  tint: style.submenuColor,
                                  rim: style.submenuRimColor,
                                  blur: cardBlur,
                                  opacity: card.platter,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: MorphLiveTemplate(
                live: _ticks,
                template: () => ClipRRect(
                  borderRadius: BorderRadius.circular(now().radius),
                ),
                child: OverflowBox(
                  alignment: .topLeft,
                  minWidth: width,
                  maxWidth: width,
                  minHeight: layout.height,
                  maxHeight: layout.height,
                  child: MorphLiveTemplate(
                    live: _ticks,
                    template: () =>
                        Transform.translate(offset: now().contentOffset),
                    child: SizedBox(
                      width: width,
                      height: layout.height,
                      child: Stack(
                        clipBehavior: .none,
                        children: [
                          ?_highlight(motion, style, layout, index),
                          MorphLiveTemplate(
                            live: _ticks,
                            template: () => Opacity(opacity: now().rowsOpacity),
                            child: _rowsOf(layout, style),
                          ),
                          if (header != null)
                            Positioned.fill(
                              child: MorphLiveTemplate(
                                live: _ticks,
                                template: () =>
                                    Opacity(opacity: now().rowsAlpha),
                                child: Stack(
                                  clipBehavior: .none,
                                  children: [
                                    DefaultTextStyle(
                                      style: MorphTypography.resolve(
                                        style.textStyle,
                                      ),
                                      child: _CardHeader(
                                        frames: _ticks,
                                        header: header,
                                        placed: () => now().header!,
                                        values: () => now().headerValues,
                                        faces: _built!.faces[index - 1],
                                        style: style,
                                        width: layout.width,
                                        content: widget.host.menuContent,
                                        onSelect: (int target) =>
                                            _select(layout, target),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static MorphMenuPlaced _headerAt(
    List<MorphMenuCard> cards,
    int index,
    MorphMenuPlaced header,
  ) {
    final card = cards[index];
    final parent = cards[index - 1];
    final source = card.source;
    if (source == null || source >= parent.layout.targets.length) return header;
    final target = parent.layout.targets[source];
    if (target.element < 0) return header;
    final row = parent.layout.elements[target.element];
    final ratio = parent.scale / card.scale;
    final center = card.layout.width / 2;
    final q = card.progress.clamp(0.0, 1.0);
    double column(double source) {
      final from = center + (source - center) * ratio;
      return from + (source - from) * q;
    }

    final image = row.imageCenter;
    return MorphMenuPlaced(
      kind: header.kind,
      rect: header.rect,
      entry: header.entry,
      title: header.title,
      imageCenter: image == null || header.imageCenter == null
          ? header.imageCenter
          : column(image),
      titleStart: column(row.titleStart),
      titleEnd: column(row.titleEnd),
      target: header.target,
    );
  }

  Widget? _highlight(
    MorphMenuMotion motion,
    MorphMenuAppearance style,
    MorphMenuLayout layout,
    int card,
  ) {
    final index = motion.highlighted;
    if (index == null || motion.highlightedCard != card) return null;
    if (index >= layout.targets.length) return null;
    final target = layout.targets[index];
    if (target.kind == MorphMenuTargetKind.back) return null;
    if (target.kind == MorphMenuTargetKind.submenu && !motion.isSliding) {
      return null;
    }
    final element = target.element < 0 ? null : layout.elements[target.element];
    final cell = switch (element?.kind) {
      MorphMenuPlacedKind.palette ||
      MorphMenuPlacedKind.small ||
      MorphMenuPlacedKind.medium => true,
      _ => false,
    };
    final rect = cell
        ? target.rect
        : target.rect
              .deflate(0)
              .inflateHorizontal(-motion.tuning.highlightInset);
    return Positioned.fromRect(
      rect: rect,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: style.highlightColor,
          borderRadius: .circular(
            cell
                ? MorphMenuTuning.cellHighlightRadius
                : math.min(rect.height / 2, motion.tuning.rowHeight / 2),
          ),
        ),
      ),
    );
  }
}

typedef _RootKey = ({
  MorphMenuLayout layout,
  MorphMenuAppearance style,
  MorphMenuTuning tuning,
  bool locked,
  bool scrolls,
  double width,
  double radius,
  int? highlighted,
  int highlightedCard,
  bool sliding,
});

extension on Rect {
  Rect inflateHorizontal(double delta) =>
      Rect.fromLTRB(left - delta, top, right + delta, bottom);
}

/// What a menu layer's tree is built from; the layer builds only when
/// this changes.
class _LayerStructure {
  _LayerStructure({
    required this.motion,
    required this.painter,
    required this.style,
    required this.surface,
    required this.glyph,
    required this.open,
    required this.layouts,
    required this.faces,
    required this.highlighted,
    required this.highlightedCard,
    required this.sliding,
    required this.scrolls,
  });

  final MorphMenuMotion motion;
  final MorphGlassPainter? painter;
  final MorphMenuAppearance style;
  final ({Color color, Color? rim})? surface;
  final Object? glyph;
  final bool open;
  final List<MorphMenuLayout> layouts;
  final List<_HeaderFaces> faces;
  final int? highlighted;
  final int highlightedCard;
  final bool sliding;
  final bool scrolls;

  static bool _same<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i]) && a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is _LayerStructure &&
      identical(other.motion, motion) &&
      identical(other.painter, painter) &&
      identical(other.style, style) &&
      other.surface == surface &&
      other.glyph == glyph &&
      other.open == open &&
      _same(other.layouts, layouts) &&
      _same(other.faces, faces) &&
      other.highlighted == highlighted &&
      other.highlightedCard == highlightedCard &&
      other.sliding == sliding &&
      other.scrolls == scrolls;

  @override
  int get hashCode => Object.hash(
    motion,
    painter,
    style,
    open,
    layouts.length,
    highlighted,
    highlightedCard,
    sliding,
    scrolls,
  );
}

/// Which titles a card header draws: the row's weight while it is not
/// fully bold, the header's while it is at all.
typedef _HeaderFaces = ({bool regular, bool bold});

/// A menu layer's geometry at one frame of its motion.
class _LayerFrame {
  _LayerFrame(
    MorphMenuMotion motion, {
    required MorphMenuAppearance style,
    required Brightness brightness,
    required bool withField,
  }) : menu = motion.menuBlob,
       cards = motion.cards,
       visible = motion.visibleRootHeight {
    final source = motion.buttonBlob;
    final scale = motion.contentScale;
    final content = motion.contentRect;
    this.scale = scale;
    stretch = motion.contentStretch;
    at = content.topLeft - menu.rect.topLeft;
    size = motion.menuRect.size;
    shapes = (
      menu: motion.rootBlob.rrect,
      source: motion.drawsSource ? source.rrect : null,
      sourceRect: source.rect,
      sourceScale: source.scale,
      lookStretch: motion.buttonLookStretch,
      look: (opacity: motion.buttonLookOpacity, blur: motion.buttonLookBlur),
      outline: motion.silhouetteFor(withField: withField),
      glow: motion.glowAt(brightness),
    );
    faded = (
      opacity: motion.cardGlassTransferred ? 0 : motion.contentOpacity,
      blur: motion.contentBlur / scale,
    );
    _cards = [
      for (var i = 1; i < cards.length; i++)
        _CardFrame(
          motion,
          cards,
          i,
          visible: visible,
          style: style,
          brightness: brightness,
        ),
    ];
  }

  /// The blob of the menu's content.
  final MorphMenuBlob menu;

  /// The cards shown, the root list first.
  final List<MorphMenuCard> cards;

  /// The visible height of the root list.
  final double visible;

  /// The button's and the menu's shapes.
  late final _Shapes shapes;

  /// The content's top-left in the menu's frame.
  late final Offset at;

  /// The size the content is laid out at.
  late final Size size;

  /// The content's scale.
  late final double scale;

  /// The flex's stretch of the content along each axis, on top of
  /// [scale].
  late final Offset stretch;

  /// The fade of everything under the top card.
  late final _Look faded;

  late final List<_CardFrame> _cards;

  /// The geometry of card [index], one or above.
  _CardFrame cardAt(int index) => _cards[index - 1];
}

/// The geometry of a card over the root list at one frame.
class _CardFrame {
  _CardFrame(
    MorphMenuMotion motion,
    List<MorphMenuCard> cards,
    int index, {
    required double visible,
    required MorphMenuAppearance style,
    required Brightness brightness,
  }) {
    final tuning = motion.tuning;
    final width = tuning.menuWidth;
    final cornerRadius = tuning.cornerRadius;
    final card = cards[index];
    final s = card.scale;
    final rect = card.rect;
    scale = s;
    size = rect.size;
    shown = _MorphMenuLayerState._shown(cards, index, width, visible);
    final k = s == 0 ? 1.0 : 1 / s;
    under = [
      for (var j = index - 1; j >= 0; j--)
        RRect.fromRectAndRadius(
          _MorphMenuLayerState._local(
            _MorphMenuLayerState._shown(cards, j, width, visible),
            shown.topLeft,
            k,
          ),
          Radius.circular(cornerRadius * cards[j].scale * k),
        ),
    ];
    radius = math.min(cornerRadius, rect.height / 2);
    platter = card.platterOpacity * motion.cardMaterialOpacity;
    rowsAlpha = card.rowOpacity * card.closeOpacity;
    rowsOpacity = card.rowsOpacity * rowsAlpha;
    blur = tuning.cardBlur * platter;
    contentOffset = Offset(-rect.left, card.contentTop);
    surface = MorphGlassSurface(
      kind: MorphGlassKind.menu,
      shape: RRect.fromRectAndRadius(
        Offset.zero & rect.size,
        Radius.circular(radius),
      ),
      color: style.glassColor,
      tint: style.glassTint,
      transmissionGamma: tuning.cardTransmissionGamma,
      blurRadius: tuning.cardBlur,
      optics: MorphGlassOptics(unliftedDisplacement: tuning.cardDisplacement),
      brightness: brightness,
      opacity: platter,
      shadows: [
        BoxShadow(
          color: style.submenuShadowColor,
          offset: const Offset(0, MorphMenuTuning.cardShadowOffset),
          blurRadius: MorphMenuTuning.cardShadowRadius,
        ),
      ],
    );
    MorphMenuPlaced? header;
    for (final element in card.layout.elements) {
      if (element.kind == MorphMenuPlacedKind.cardHeader) header = element;
    }
    this.header = header == null
        ? null
        : _MorphMenuLayerState._headerAt(cards, index, header);
    final bold = card.headerBold.clamp(0.0, 1.0);
    headerValues = (
      bold: bold,
      turn: card.chevronTurn.clamp(0.0, 1.0),
      separator: card.platterOpacity.clamp(0.0, 1.0),
    );
    faces = (regular: bold < 1, bold: bold > 0);
  }

  late final double scale;
  late final Size size;
  late final Rect shown;
  late final List<RRect> under;
  late final double radius;
  late final double platter;
  late final double rowsAlpha;
  late final double rowsOpacity;
  late final double blur;
  late final Offset contentOffset;
  late final MorphGlassSurface surface;
  late final MorphMenuPlaced? header;
  late final _HeaderValues headerValues;
  late final _HeaderFaces faces;
}

/// How bold a card header's title is, how far its chevron has turned and
/// the opacity of its separator, each from 0 to 1.
typedef _HeaderValues = ({double bold, double turn, double separator});

/// The header of a submenu card: the row it grew out of, its title
/// turning bold and its chevron turning down as the card opens.
///
/// Its columns and the turn are read again on every notification of
/// [frames] without a build; which titles it draws ([faces]) is part of
/// the widget.
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.frames,
    required this.header,
    required this.placed,
    required this.values,
    required this.faces,
    required this.style,
    required this.width,
    required this.content,
    required this.onSelect,
  });

  final Listenable frames;
  final MorphMenuPlaced header;
  final MorphMenuPlaced Function() placed;
  final _HeaderValues Function() values;
  final _HeaderFaces faces;
  final MorphMenuAppearance style;
  final double width;
  final MorphMenuContent content;
  final ValueChanged<int> onSelect;

  Color get _title => style.textStyle.color ?? style.iconColor;

  Widget _text(TextStyle base) => Text(
    header.title ?? '',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: MorphTypography.resolve(base).copyWith(color: _title),
  );

  @override
  Widget build(BuildContext context) {
    final header = this.header;
    final entry = header.entry;
    final icon = entry is MorphSubmenu ? entry.icon : null;
    final target = header.target;
    final direction = Directionality.of(context);
    final metrics = content.metrics;
    return Positioned.fromRect(
      rect: header.rect,
      child: Semantics(
        button: true,
        role: ui.SemanticsRole.menuItem,
        expanded: true,
        label: header.title,
        onTap: target < 0 ? null : () => onSelect(target),
        excludeSemantics: true,
        child: Stack(
          children: [
            if (header.imageCenter != null && icon != null)
              MorphLivePositionedTemplate(
                live: frames,
                template: () => Positioned.directional(
                  textDirection: direction,
                  start: placed().imageCenter! - MorphMenuTuning.imageSlot / 2,
                  width: MorphMenuTuning.imageSlot,
                  top: 0,
                  bottom: 0,
                  child: morphLiveSlot,
                ),
                child: Center(
                  child: IconTheme.merge(
                    data: IconThemeData(size: style.iconSize, color: _title),
                    child: icon,
                  ),
                ),
              ),
            MorphLivePositionedTemplate(
              live: frames,
              template: () {
                final now = placed();
                return Positioned.directional(
                  textDirection: direction,
                  start: now.titleStart,
                  end: width - now.titleEnd,
                  top: 0,
                  bottom: 0,
                  child: morphLiveSlot,
                );
              },
              child: Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [
                  if (faces.regular)
                    MorphLiveTemplate(
                      live: frames,
                      template: () => Opacity(opacity: 1 - values().bold),
                      child: _text(style.textStyle),
                    ),
                  if (faces.bold)
                    MorphLiveTemplate(
                      live: frames,
                      template: () => Opacity(opacity: values().bold),
                      child: _text(
                        style.textStyle.merge(MorphTypography.title),
                      ),
                    ),
                ],
              ),
            ),
            PositionedDirectional(
              start: metrics.chevronCenter - MorphMenuTuning.markSlot / 2,
              width: MorphMenuTuning.markSlot,
              top: 0,
              bottom: 0,
              child: Center(
                child: Transform.flip(
                  flipX: content.rtl,
                  child: MorphLiveTemplate(
                    live: frames,
                    template: () =>
                        Transform.rotate(angle: values().turn * math.pi / 2),
                    child: CustomPaint(
                      size: MorphMenuTuning.chevronSize,
                      painter: _ChevronPainter(color: _title, down: false),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: metrics.separatorInset,
              right: metrics.separatorInset,
              bottom: 0,
              height: 1,
              child: MorphLiveTemplate(
                live: frames,
                template: () => Opacity(opacity: values().separator),
                child: ColoredBox(color: style.separatorColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rows of one card: [layout]'s elements in [style], drawn through
/// their own layer. With a [limit] only the first [limit] elements are
/// built, leaving out loading rows and free-form widgets.
Widget _menuRows({
  required MorphMenuLayout layout,
  required MorphMenuAppearance style,
  required ValueListenable<int?> hidden,
  required MorphMenuContent content,
  required ValueChanged<int> onSelect,
  ValueListenable<double>? cover,
  int? limit,
}) {
  final Widget rows = DefaultTextStyle(
    style: MorphTypography.resolve(style.textStyle),
    child: _MenuRows(
      layout: layout,
      style: style,
      hidden: hidden,
      content: content,
      onSelect: onSelect,
      limit: limit,
    ),
  );
  final Widget layer = RepaintBoundary(child: rows);
  // The rows draw as a card: a snap about the layer's center would move
  // the far rows against the card's edges by up to a few points, and the
  // spring's tail flipping between grid scales and the exact one shook
  // them at the end of the open.
  return cover == null
      ? layer
      : MorphGlyphs(cover: cover, snaps: false, child: layer);
}

/// The root rows of [host]'s menu built ahead of its opening, out of
/// sight: the first [count] elements of the root card, under the key the
/// open menu draws them with, so the opening moves them into the menu
/// instead of building them in its first frame.
@internal
Widget morphMenuPrebuiltRows(MorphMenuController host, int count) {
  final motion = host.menuMotion!;
  final layout = motion.layout;
  return ExcludeFocus(
    child: Offstage(
      child: Align(
        alignment: .topLeft,
        child: SizedBox(
          width: motion.tuning.menuWidth,
          height: layout.height,
          child: Stack(
            clipBehavior: .none,
            children: [
              KeyedSubtree(
                key: host.menuRowsKey,
                child: _menuRows(
                  layout: layout,
                  style: host.menuStyle,
                  hidden: host.prebuildHidden,
                  content: host.menuContent,
                  onSelect: _ignoreSelect,
                  cover: host.menuRowsBlur,
                  limit: count,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _ignoreSelect(int target) {}

/// The identity of the element at [index] of a card's layout.
class _RowKey extends LocalKey {
  const _RowKey(this.index);

  final int index;

  @override
  bool operator ==(Object other) => other is _RowKey && other.index == index;

  @override
  int get hashCode => index.hashCode;
}

/// The elements of one card, each at its frame in the card's content.
///
/// The element widgets are made once per layout and style, so building
/// the rows again with the same layout rebuilds none of them.
class _MenuRows extends StatefulWidget {
  const _MenuRows({
    required this.layout,
    required this.style,
    required this.hidden,
    required this.content,
    required this.onSelect,
    this.limit,
  });

  final MorphMenuLayout layout;
  final ValueListenable<int?> hidden;
  final MorphMenuAppearance style;
  final MorphMenuContent content;
  final ValueChanged<int> onSelect;
  final int? limit;

  @override
  State<_MenuRows> createState() => _MenuRowsState();
}

class _MenuRowsState extends State<_MenuRows> {
  final ValueNotifier<int?> _hidden = ValueNotifier<int?>(null);
  List<Widget>? _children;
  List<bool> _late = const [];

  @override
  void initState() {
    super.initState();
    widget.hidden.addListener(_hiddenChanged);
    _hidden.value = widget.hidden.value;
  }

  @override
  void didUpdateWidget(_MenuRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hidden, widget.hidden)) {
      oldWidget.hidden.removeListener(_hiddenChanged);
      widget.hidden.addListener(_hiddenChanged);
      _hidden.value = widget.hidden.value;
    }
    if (!identical(oldWidget.layout, widget.layout) ||
        !identical(oldWidget.style, widget.style) ||
        !identical(oldWidget.content, widget.content)) {
      _children = null;
    }
  }

  @override
  void dispose() {
    widget.hidden.removeListener(_hiddenChanged);
    _hidden.dispose();
    super.dispose();
  }

  void _hiddenChanged() => _hidden.value = widget.hidden.value;

  void _select(int target) => widget.onSelect(target);

  List<Widget> _build() {
    final layout = widget.layout;
    final children = <Widget>[];
    final late = <bool>[];
    for (var i = 0; i < layout.elements.length; i++) {
      final element = layout.elements[i];
      if (element.kind == MorphMenuPlacedKind.cardHeader) continue;
      late.add(
        element.kind == MorphMenuPlacedKind.loading ||
            element.kind == MorphMenuPlacedKind.widget,
      );
      children.add(
        element.entry is MorphSubmenu && element.kind == MorphMenuPlacedKind.row
            ? ValueListenableBuilder<int?>(
                key: _RowKey(i),
                valueListenable: _hidden,
                builder: (BuildContext context, int? hidden, Widget? _) =>
                    _MenuElement(
                      element: element,
                      style: widget.style,
                      width: layout.width,
                      content: widget.content,
                      onSelect: _select,
                      hidden: hidden == element.target,
                    ),
              )
            : _MenuElement(
                key: _RowKey(i),
                element: element,
                style: widget.style,
                width: layout.width,
                content: widget.content,
                onSelect: _select,
              ),
      );
    }
    _late = late;
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final all = _children ??= _build();
    final limit = widget.limit;
    return SizedBox(
      width: layout.width,
      height: layout.height,
      child: Stack(
        clipBehavior: .none,
        children: limit == null
            ? all
            : [
                for (var i = 0; i < all.length && i < limit; i++)
                  if (!_late[i]) all[i],
              ],
      ),
    );
  }
}

class _MenuElement extends StatelessWidget {
  const _MenuElement({
    required this.element,
    required this.style,
    required this.width,
    required this.content,
    required this.onSelect,
    this.hidden = false,
    super.key,
  });

  final bool hidden;

  final MorphMenuPlaced element;
  final MorphMenuAppearance style;
  final double width;
  final MorphMenuContent content;
  final ValueChanged<int> onSelect;

  Color get _title => style.textStyle.color ?? style.iconColor;

  VoidCallback? get _tap {
    final target = element.target;
    return target < 0 ? null : () => onSelect(target);
  }

  Widget _at(double center, double extent, Widget child) =>
      PositionedDirectional(
        start: center - extent / 2,
        width: extent,
        top: 0,
        bottom: 0,
        child: Center(child: child),
      );

  Widget _text(
    String text,
    TextStyle base,
    Color color, {
    int maxLines = 1,
    TextAlign? align,
  }) => Text(
    text,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    textAlign: align,
    style: MorphTypography.resolve(base).copyWith(color: color),
  );

  @override
  Widget build(BuildContext context) {
    final element = this.element;
    final rect = element.rect;
    return Positioned.fromRect(
      rect: rect,
      child: switch (element.kind) {
        MorphMenuPlacedKind.row when hidden => Opacity(
          opacity: 0,
          child: _row(),
        ),
        MorphMenuPlacedKind.row => _row(),
        MorphMenuPlacedKind.header => _header(),
        MorphMenuPlacedKind.separator => ColoredBox(
          color: style.separatorColor,
        ),
        MorphMenuPlacedKind.palette ||
        MorphMenuPlacedKind.small ||
        MorphMenuPlacedKind.medium => _cell(),
        MorphMenuPlacedKind.loading => _loading(),
        MorphMenuPlacedKind.widget => _widget(),
        MorphMenuPlacedKind.cardHeader => const SizedBox.shrink(),
      },
    );
  }

  Widget _row() {
    final entry = element.entry;
    final String title;
    final String? subtitle;
    final Widget? icon;
    final bool enabled;
    final bool destructive;
    var state = MorphMenuState.off;
    var submenu = false;
    Color? iconColor;
    switch (entry) {
      case MorphMenuItem():
        title = entry.title;
        subtitle = entry.subtitle;
        state = entry.state;
        icon = entry.iconVisibility == MorphMenuIconVisibility.hidden
            ? null
            : state != MorphMenuState.off && entry.selectedIcon != null
            ? entry.selectedIcon
            : entry.icon;
        enabled = entry.enabled;
        destructive = entry.destructive;
        iconColor = entry.iconColor;
      case MorphSubmenu():
        title = entry.title;
        subtitle = entry.subtitle;
        icon = entry.icon;
        enabled = entry.enabled;
        destructive = entry.destructive;
        submenu = true;
      default:
        return const SizedBox.shrink();
    }
    final color = !enabled
        ? style.disabledColor
        : destructive
        ? style.destructiveColor
        : _title;
    final check = element.checkCenter;
    final image = element.imageCenter;
    return Semantics(
      button: true,
      role: ui.SemanticsRole.menuItem,
      enabled: enabled,
      checked: state == MorphMenuState.off || submenu
          ? null
          : state == MorphMenuState.on,
      mixed: state == MorphMenuState.mixed ? true : null,
      expanded: submenu ? false : null,
      label: title,
      value: subtitle,
      onTap: enabled ? _tap : null,
      excludeSemantics: true,
      child: Stack(
        children: [
          if (check != null && state != MorphMenuState.off)
            _at(
              check,
              MorphMenuTuning.markSlot,
              CustomPaint(
                size: state == MorphMenuState.on
                    ? MorphMenuTuning.checkSize
                    : MorphMenuTuning.mixedSize,
                painter: _MarkPainter(
                  color: color,
                  mixed: state == MorphMenuState.mixed,
                ),
              ),
            ),
          if (image != null && icon != null)
            _at(
              image,
              MorphMenuTuning.imageSlot,
              IconTheme.merge(
                data: IconThemeData(
                  size: style.iconSize,
                  color: iconColor ?? color,
                ),
                child: icon,
              ),
            ),
          PositionedDirectional(
            start: element.titleStart,
            end: width - element.titleEnd,
            top: 0,
            bottom: 0,
            child: Column(
              mainAxisAlignment: .center,
              crossAxisAlignment: .start,
              children: [
                _text(
                  title,
                  style.textStyle,
                  color,
                  maxLines: element.maxLines,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: MorphMenuTuning.subtitleGap),
                  _text(subtitle, _subtitleStyle, style.secondaryColor),
                ],
              ],
            ),
          ),
          if (submenu)
            _at(
              _metrics.chevronCenter,
              MorphMenuTuning.markSlot,
              Transform.flip(
                flipX: content.rtl,
                child: CustomPaint(
                  size: MorphMenuTuning.chevronSize,
                  painter: _ChevronPainter(color: color, down: false),
                ),
              ),
            ),
        ],
      ),
    );
  }

  MorphMenuMetrics get _metrics => content.metrics;

  static const _subtitleStyle = TextStyle(fontSize: 13);

  Widget _header() {
    return Semantics(
      header: true,
      label: element.title,
      excludeSemantics: true,
      child: Stack(
        children: [
          PositionedDirectional(
            start: element.titleStart,
            end: width - element.titleEnd,
            top: _metrics.headerLabelTop,
            child: _text(
              element.title ?? '',
              _subtitleStyle,
              style.secondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell() {
    final entry = element.entry;
    final String title;
    final Widget? icon;
    final bool enabled;
    final bool destructive;
    var selected = false;
    Color? iconColor;
    switch (entry) {
      case MorphMenuItem():
        title = entry.title;
        selected = entry.state != MorphMenuState.off;
        icon = selected && entry.selectedIcon != null
            ? entry.selectedIcon
            : entry.icon;
        enabled = entry.enabled;
        destructive = entry.destructive;
        iconColor = entry.iconColor;
      case MorphSubmenu():
        title = entry.title;
        icon = entry.icon;
        enabled = entry.enabled;
        destructive = entry.destructive;
      default:
        return const SizedBox.shrink();
    }
    final color = !enabled
        ? style.disabledColor
        : destructive
        ? style.destructiveColor
        : _title;
    final kind = element.kind;
    final metrics = _metrics;
    final Widget body;
    if (kind == MorphMenuPlacedKind.medium) {
      body = Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: metrics.mediumLabelTop,
            child: Center(
              child: icon == null
                  ? null
                  : IconTheme.merge(
                      data: IconThemeData(
                        size: style.iconSize,
                        color: iconColor ?? color,
                      ),
                      child: icon,
                    ),
            ),
          ),
          Positioned(
            left: 2,
            right: 2,
            top: metrics.mediumLabelTop,
            child: _text(
              title,
              const TextStyle(fontSize: 12),
              color,
              align: TextAlign.center,
            ),
          ),
        ],
      );
    } else {
      final palette = kind == MorphMenuPlacedKind.palette;
      body = Stack(
        alignment: Alignment.center,
        children: [
          if (palette && selected)
            SizedBox.square(
              dimension: metrics.palettePlatter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: style.paletteSelectionColor,
                  borderRadius: .circular(metrics.palettePlatterRadius),
                ),
              ),
            ),
          if (icon != null)
            IconTheme.merge(
              data: IconThemeData(
                size: palette ? metrics.paletteImageSize : style.iconSize,
                color: iconColor ?? color,
              ),
              child: icon,
            ),
        ],
      );
    }
    return Semantics(
      button: true,
      role: ui.SemanticsRole.menuItem,
      enabled: enabled,
      selected: selected,
      label: title,
      onTap: enabled ? _tap : null,
      excludeSemantics: true,
      child: body,
    );
  }

  Widget _loading() {
    final check = element.imageCenter ?? _metrics.imageCenter;
    return Semantics(
      label: element.title,
      liveRegion: true,
      excludeSemantics: true,
      child: Stack(
        children: [
          _at(
            check,
            MorphMenuTuning.imageSlot,
            MorphActivityIndicator(color: style.disabledColor),
          ),
          PositionedDirectional(
            start: element.titleStart,
            end: width - element.titleEnd,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _text(
                element.title ?? '',
                style.textStyle,
                style.disabledColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _widget() {
    final entry = element.entry;
    if (entry is! MorphMenuWidget) return const SizedBox.shrink();
    final key = element.key;
    final Widget child = Builder(builder: entry.builder);
    return OverflowBox(
      alignment: .topCenter,
      minHeight: 0,
      maxHeight: double.infinity,
      child: Padding(
        padding: .symmetric(horizontal: _metrics.widgetInset),
        child: entry.height != null || key == null
            ? child
            : _HeightReporter(
                onHeight: (double height) => content.reportHeight(key, height),
                child: child,
              ),
      ),
    );
  }
}

/// Reports the height [child] lays out at, after the frame.
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightReporter renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (_reported == height) return;
    _reported = height;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (attached) onHeight(height);
    });
  }
}

/// The checkmark or the dash of a row's selection mark.
class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.color, required this.mixed});

  final Color color;
  final bool mixed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    if (mixed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.height / 2),
        ),
        paint,
      );
      return;
    }
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2.1;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    final path = Path();
    path.moveTo(size.width * 0.06, size.height * 0.55);
    path.lineTo(size.width * 0.36, size.height * 0.92);
    path.lineTo(size.width * 0.94, size.height * 0.08);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.mixed != mixed;
}

/// A chevron pointing forward (mirrored in right-to-left text) or down.
/// The shadow a submenu card casts around itself, kept off its face: the
/// card is translucent.
class _CardShadowPainter extends CustomPainter {
  const _CardShadowPainter({
    required this.radius,
    required this.color,
    required this.opacity,
  });

  final double radius;
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0 || color.a <= 0) return;
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.save();
    final outside = Path();
    outside.fillType = PathFillType.evenOdd;
    outside.addRect(shape.outerRect.inflate(MorphMenuTuning.shadowReach));
    outside.addRRect(shape);
    canvas.clipPath(outside);
    final paint = Paint();
    paint.color = color.withValues(alpha: color.a * opacity);
    paint.maskFilter = const MaskFilter.blur(
      BlurStyle.normal,
      MorphMenuTuning.shadowBlur,
    );
    canvas.drawRRect(shape, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CardShadowPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.color != color ||
      oldDelegate.opacity != opacity;
}

class _CardBackdropClipper extends CustomClipper<Path> {
  const _CardBackdropClipper(this.under);

  final List<RRect> under;

  @override
  Path getClip(Size size) {
    var path = Path();
    path.addRect(Offset.zero & size);
    for (final list in under) {
      final cut = Path();
      cut.addRRect(list);
      path = Path.combine(PathOperation.difference, path, cut);
    }
    return path;
  }

  @override
  bool shouldReclip(_CardBackdropClipper oldClipper) =>
      !listEquals(oldClipper.under, under);
}

class _CardBasePainter extends CustomPainter {
  const _CardBasePainter(this.surface);

  final MorphGlassSurface surface;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = surface.color.withValues(
      alpha: surface.color.a * surface.opacity,
    );
    canvas.drawRRect(surface.shape, paint);
  }

  @override
  bool shouldRepaint(_CardBasePainter oldPainter) =>
      oldPainter.surface != surface;
}

/// The face of a submenu card over its blurred backdrop: [tint] over the
/// lists [under] it, each spread by [blur] the way the card's blur
/// spreads their edges, every further one at half the tint, and [rim]
/// along the top edge.
class _CardPlatterPainter extends CustomPainter {
  const _CardPlatterPainter({
    required this.radius,
    required this.under,
    required this.tint,
    required this.rim,
    required this.blur,
    required this.opacity,
  });

  final double radius;
  final List<RRect> under;
  final Color tint;
  final Color rim;
  final double blur;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final paint = Paint();
    paint.maskFilter = blur > 0
        ? MaskFilter.blur(BlurStyle.normal, blur)
        : null;
    var strength = 1.0;
    for (final list in under) {
      paint.color = tint.withValues(alpha: tint.a * opacity * strength);
      canvas.drawRRect(list, paint);
      strength /= 2;
    }
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final edge = Paint();
    edge.style = PaintingStyle.stroke;
    edge.strokeWidth = MorphMenuTuning.cardRimWidth;
    final reach = math.min(radius, size.height / 2);
    edge.shader = ui.Gradient.linear(Offset.zero, Offset(0, reach), [
      rim.withValues(alpha: rim.a * opacity),
      rim.withValues(alpha: 0),
    ]);
    canvas.drawRRect(shape, edge);
  }

  @override
  bool shouldRepaint(_CardPlatterPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.tint != tint ||
      oldDelegate.rim != rim ||
      oldDelegate.blur != blur ||
      oldDelegate.opacity != opacity ||
      !listEquals(oldDelegate.under, under);
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color, required this.down});

  final Color color;
  final bool down;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    final path = Path();
    final w = size.width;
    final h = size.height;
    if (down) {
      path.moveTo(w * 0.08, h * 0.12);
      path.lineTo(w * 0.5, h * 0.88);
      path.lineTo(w * 0.92, h * 0.12);
    } else {
      path.moveTo(w * 0.12, h * 0.08);
      path.lineTo(w * 0.88, h * 0.5);
      path.lineTo(w * 0.12, h * 0.92);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.down != down;
}

/// The glass of both shapes as one body - their fused [outline], or their
/// union without one - or the resting button when there is no [menu].
class _GlassPainter extends CustomPainter {
  const _GlassPainter({
    required this.style,
    required this.source,
    this.menu,
    this.outline,
    this.surface,
    this.glassShare = 1,
    this.glow,
  });

  final MorphMenuAppearance style;
  final RRect? source;
  final RRect? menu;
  final MorphGlassOutline? outline;
  final ({Color color, Color? rim})? surface;
  final double glassShare;
  final MorphGlassGlow? glow;

  @override
  void paint(Canvas canvas, Size size) {
    final menu = this.menu;
    final outline = this.outline;
    final Path shape;
    if (menu != null && outline != null) {
      shape = outline.path;
    } else {
      shape = Path();
      final source = this.source;
      if (source != null) shape.addRRect(source);
      if (menu != null) shape.addRRect(menu);
    }
    canvas.drawShadow(shape, style.shadowColor, style.shadowElevation, true);
    final surface = this.surface;
    final fill = Paint();
    fill.color = surface == null
        ? style.glassColor
        : Color.lerp(surface.color, style.glassColor, glassShare)!;
    canvas.drawPath(shape, fill);
    final glow = this.glow;
    if (menu != null && glow != null) morphPaintGlassGlow(canvas, menu, glow);
    final rim = surface?.rim;
    if (rim == null || glassShare >= 1) return;
    final stroke = Paint();
    stroke.style = PaintingStyle.stroke;
    stroke.strokeWidth = 0.5;
    stroke.color = rim.withValues(alpha: rim.a * (1 - glassShare));
    canvas.drawPath(shape, stroke);
  }

  @override
  bool shouldRepaint(_GlassPainter oldDelegate) =>
      oldDelegate.menu != menu ||
      oldDelegate.source != source ||
      oldDelegate.outline != outline ||
      oldDelegate.style != style ||
      oldDelegate.surface != surface ||
      oldDelegate.glassShare != glassShare ||
      oldDelegate.glow != glow;
}

class _Ellipsis extends StatelessWidget {
  const _Ellipsis({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: MorphMenuTuning.ellipsisSize,
      child: CustomPaint(painter: _EllipsisPainter(color)),
    );
  }
}

class _EllipsisPainter extends CustomPainter {
  const _EllipsisPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    final center = size.center(Offset.zero);
    for (final dx in const [
      -MorphMenuTuning.ellipsisPitch,
      0.0,
      MorphMenuTuning.ellipsisPitch,
    ]) {
      canvas.drawCircle(
        center + Offset(dx, 0),
        MorphMenuTuning.ellipsisRadius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EllipsisPainter oldDelegate) =>
      oldDelegate.color != color;
}
