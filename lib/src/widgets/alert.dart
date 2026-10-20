import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/themes.dart';
import 'package:morph/src/widgets/edit_menu.dart';
import 'package:morph/src/widgets/alert_motion.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_button.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/glyph_scale.dart';
import 'package:morph/src/widgets/haptics.dart';
import 'package:morph/src/widgets/motion_route.dart';
import 'package:morph/src/widgets/popover_shape.dart';
import 'package:morph/src/widgets/touch_listener.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/theme/theme.dart';

/// The role of a [MorphAlertAction], after UIAlertAction.Style.
enum MorphAlertActionStyle {
  /// An ordinary action.
  normal,

  /// The action that cancels: it goes first in a row of two buttons and
  /// last in a column, and an action sheet presented from a source leaves
  /// it out (a tap outside the popover runs it).
  cancel,

  /// An action that destroys data: its title is red.
  destructive,
}

/// One button of an alert or an action sheet.
@immutable
class MorphAlertAction {
  /// Creates an action titled [title].
  const MorphAlertAction({
    required this.title,
    this.style = MorphAlertActionStyle.normal,
    this.onPressed,
    this.isPreferred = false,
    this.enabled = true,
    this.enabledListenable,
  });

  /// The button's title.
  final String title;

  /// The button's role.
  final MorphAlertActionStyle style;

  /// Called once the alert has left after the user chose this action, as
  /// UIKit calls an action's handler after the dismissal.
  final VoidCallback? onPressed;

  /// Whether this is the preferred action: its button is filled with the
  /// accent color and Return chooses it.
  final bool isPreferred;

  /// Whether the button accepts taps.
  ///
  /// A disabled button keeps its fill and draws its title in
  /// [MorphAlertAppearance.disabledLabelColor]; a disabled preferred button
  /// shows the plain fill instead of the accent and keeps its semibold
  /// title.
  final bool enabled;

  /// Whether the button accepts taps, live (UIKit's settable
  /// `UIAlertAction.isEnabled`): the alert follows each change, so an OK
  /// button can wait for a text field to be filled. Null uses [enabled].
  final ValueListenable<bool>? enabledListenable;

  /// Whether the button accepts taps now: [enabledListenable]'s value, or
  /// [enabled].
  bool get isEnabled => enabledListenable?.value ?? enabled;
}

/// A text field of an alert.
@immutable
class MorphAlertTextField {
  /// Creates a field.
  const MorphAlertTextField({
    this.placeholder,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
    this.autofocus,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.semanticLabel,
  });

  /// Called with the text after each change the user makes.
  final ValueChanged<String>? onChanged;

  /// Whether the field takes the keyboard focus when the alert shows;
  /// null focuses the first field, as UIKit does.
  final bool? autofocus;

  /// Whether the keyboard corrects what is typed (UIKit
  /// `autocorrectionType`).
  final bool autocorrect;

  /// Whether the keyboard suggests words (UIKit `spellCheckingType` and
  /// the predictive bar).
  final bool enableSuggestions;

  /// How the keyboard capitalizes (UIKit `autocapitalizationType`).
  final TextCapitalization textCapitalization;

  /// Formatters that check and shape what is typed.
  final List<TextInputFormatter>? inputFormatters;

  /// The label screen readers announce for the field; null announces the
  /// [placeholder].
  final String? semanticLabel;

  /// The text shown while the field is empty.
  final String? placeholder;

  /// The controller of the field's text; null keeps one inside the alert.
  final TextEditingController? controller;

  /// Whether the field hides what is typed.
  final bool obscureText;

  /// The kind of keyboard the field asks for.
  final TextInputType? keyboardType;
}

/// The look of an alert or an action sheet.
@immutable
class MorphAlertAppearance implements MorphAppearance {
  /// Creates an appearance; the defaults are the iOS light appearance.
  const MorphAlertAppearance({
    this.platterColor = const Color(0xA1FDFDFF),
    this.dimmingColor = const Color(0xFF000000),
    this.shadowColor = const Color(0x24000000),
    this.titleColor = const Color(0xFF000000),
    this.messageColor = const Color(0x993C3C43),
    this.buttonColor = const Color(0x1F767680),
    this.labelColor = const Color(0xFF000000),
    this.destructiveColor = const Color(0xFFFF383C),
    this.preferredColor = const Color(0xFF0088FF),
    this.preferredLabelColor = const Color(0xFFFFFFFF),
    this.placeholderColor = const Color(0x4C3C3C43),
    this.disabledLabelColor = const Color(0x4C3C3C43),
  });

  /// The flat stand-in for the glass platter when no [MorphGlassPainter]
  /// is installed (fitted to the simulator's pixels over the grouped
  /// background); a painter receives it as the tint.
  final Color platterColor;

  /// The hue of the dimming behind an alert; its opacity is
  /// [MorphAlertTuning.dimmingOpacity] times this color's own.
  final Color dimmingColor;

  /// The shadow of the flat platter.
  final Color shadowColor;

  /// The color of the title.
  final Color titleColor;

  /// The color of the message: secondaryLabel.
  final Color messageColor;

  /// The fill of a button and of a text field: tertiarySystemFill.
  final Color buttonColor;

  /// The color of a button's title.
  final Color labelColor;

  /// The color of a destructive button's title: systemRed.
  final Color destructiveColor;

  /// The fill of the preferred button: the accent color.
  final Color preferredColor;

  /// The color of the preferred button's title.
  final Color preferredLabelColor;

  /// The color of a text field's placeholder.
  final Color placeholderColor;

  /// The color of a disabled button's title: tertiaryLabel, destructive
  /// or not. UIKit keeps a disabled action's fill and draws its title in
  /// tertiaryLabel; a disabled preferred action loses the accent fill for
  /// the plain one and keeps its semibold title (iPhone 16 Pro, iOS
  /// 27.0.1, light and dark).
  final Color disabledLabelColor;

  /// The light appearance, as UIKit renders it.
  static const light = MorphAlertAppearance();

  /// The dark appearance, as UIKit renders it.
  static const dark = MorphAlertAppearance(
    platterColor: Color(0xCC282828),
    titleColor: Color(0xFFFFFFFF),
    messageColor: Color(0x99EBEBF5),
    buttonColor: Color(0x3D767680),
    labelColor: Color(0xFFFFFFFF),
    destructiveColor: Color(0xFFFF4245),
    preferredColor: Color(0xFF0091FF),
    shadowColor: Color(0x4D000000),
    placeholderColor: Color(0x4CEBEBF5),
    disabledLabelColor: Color(0x4CEBEBF5),
  );

  /// The light appearance under Increase Contrast: the button fill
  /// (tertiarySystemFill) turns from 12 to 20 percent and the destructive
  /// and preferred accents take systemRed's and systemBlue's
  /// increased-contrast variants (read from UIKit's color tables, notes
  /// private). UIKit also darkens the title and message under it; those
  /// keep their standard colors here until the device records them.
  static const lightHighContrast = MorphAlertAppearance(
    buttonColor: Color(0x33767680),
    destructiveColor: Color(0xFFE9152D),
    preferredColor: Color(0xFF1E6EF4),
  );

  /// The dark appearance under Increase Contrast: the button fill turns
  /// from 24 to 32 percent, the accents take their increased-contrast
  /// variants (read from UIKit's color tables, notes private).
  static const darkHighContrast = MorphAlertAppearance(
    platterColor: Color(0xCC282828),
    titleColor: Color(0xFFFFFFFF),
    messageColor: Color(0x99EBEBF5),
    buttonColor: Color(0x52767680),
    labelColor: Color(0xFFFFFFFF),
    destructiveColor: Color(0xFFFF6165),
    preferredColor: Color(0xFF5CB8FF),
    shadowColor: Color(0x4D000000),
    placeholderColor: Color(0x4CEBEBF5),
    disabledLabelColor: Color(0x4CEBEBF5),
  );

  /// Copies this appearance with the given fields replaced.
  MorphAlertAppearance copyWith({
    Color? platterColor,
    Color? dimmingColor,
    Color? shadowColor,
    Color? titleColor,
    Color? messageColor,
    Color? buttonColor,
    Color? labelColor,
    Color? destructiveColor,
    Color? preferredColor,
    Color? preferredLabelColor,
    Color? placeholderColor,
    Color? disabledLabelColor,
  }) => MorphAlertAppearance(
    platterColor: platterColor ?? this.platterColor,
    dimmingColor: dimmingColor ?? this.dimmingColor,
    shadowColor: shadowColor ?? this.shadowColor,
    titleColor: titleColor ?? this.titleColor,
    messageColor: messageColor ?? this.messageColor,
    buttonColor: buttonColor ?? this.buttonColor,
    labelColor: labelColor ?? this.labelColor,
    destructiveColor: destructiveColor ?? this.destructiveColor,
    preferredColor: preferredColor ?? this.preferredColor,
    preferredLabelColor: preferredLabelColor ?? this.preferredLabelColor,
    placeholderColor: placeholderColor ?? this.placeholderColor,
    disabledLabelColor: disabledLabelColor ?? this.disabledLabelColor,
  );

  /// Resolves [explicit], then the ambient [MorphTheme], then the
  /// table for the ambient brightness and contrast with
  /// [MorphThemeData.tint] as its [preferredColor].
  static MorphAlertAppearance resolve(
    BuildContext context,
    MorphAlertAppearance? explicit,
  ) => morphResolveAppearance(
    context,
    explicit,
    light: light,
    dark: dark,
    lightHighContrast: lightHighContrast,
    darkHighContrast: darkHighContrast,
    tinted: (table, tint) => table.copyWith(preferredColor: tint),
  );

  @override
  bool operator ==(Object other) =>
      other is MorphAlertAppearance &&
      other.platterColor == platterColor &&
      other.dimmingColor == dimmingColor &&
      other.shadowColor == shadowColor &&
      other.titleColor == titleColor &&
      other.messageColor == messageColor &&
      other.buttonColor == buttonColor &&
      other.labelColor == labelColor &&
      other.destructiveColor == destructiveColor &&
      other.preferredColor == preferredColor &&
      other.preferredLabelColor == preferredLabelColor &&
      other.placeholderColor == placeholderColor &&
      other.disabledLabelColor == disabledLabelColor;

  @override
  int get hashCode => Object.hash(
    platterColor,
    dimmingColor,
    shadowColor,
    titleColor,
    messageColor,
    buttonColor,
    labelColor,
    destructiveColor,
    preferredColor,
    preferredLabelColor,
    placeholderColor,
    disabledLabelColor,
  );
}

/// Shows an alert that moves like an iOS 27 UIAlertController, and
/// completes with the action the user chose.
///
/// The alert fades in over a dimming while it shrinks into place, and
/// fades out when it leaves; see [MorphAlertMotion]. It is 320 points
/// wide and centered in the room the safe area and the keyboard leave.
/// Two actions sit side by side, the cancel action first; more stack,
/// the cancel action last. A touch anywhere on the alert lifts the whole
/// platter like a glass button of its size (a dragging finger stretches
/// it and pulls it along by the platter's flex), the button under the finger
/// highlights, and the finger may slide to another button before it
/// lifts. A finger that scrolls an alert taller than the screen chooses
/// nothing: the highlight goes and the platter settles. The
/// future completes when the alert starts to leave; the chosen action's
/// [MorphAlertAction.onPressed] runs once it is gone. A tap outside does
/// nothing, as in UIKit; Escape chooses the cancel action and Return the
/// preferred one.
///
/// While the alert's scale moves (presenting, under a touch) its text and
/// buttons are drawn from one raster of them, mipmapped, so the glyph
/// atlas is not filled again at every scale of the sweep: NEAR
/// (resampled, at most 9 percent magnified). At rest they are drawn
/// exactly (IDENTICAL). A fading raster is drawn with the fade in its
/// paint, without an offscreen pass: NEAR (at most 1 of 255 per channel).
///
/// The alert is pushed on the root navigator when [useRootNavigator] is
/// null or true, as UIKit presents an alert above everything; false
/// pushes it on the nearest one.
Future<MorphAlertAction?> showMorphAlert(
  BuildContext context, {
  String? title,
  String? message,
  List<MorphAlertAction> actions = const [],
  List<MorphAlertTextField> textFields = const [],
  MorphAlertAppearance? appearance,
  bool? useRootNavigator,
}) {
  final route = MorphAlertRoute(
    title: title,
    message: message,
    actions: actions,
    textFields: textFields,
    appearance: appearance,
  );
  final navigator = Navigator.of(
    context,
    rootNavigator: useRootNavigator ?? true,
  );
  route._themes = MorphThemeCarrier(context, to: navigator.context);
  return navigator.push(route);
}

/// Shows an action sheet the way iOS 27 presents one, and completes with
/// the action the user chose.
///
/// With an [anchor] (a context inside the control that summoned the
/// sheet) or an [anchorRect] (in global coordinates), the sheet is a
/// glass popover next to its source: it grows out of its arrow tip on a
/// spring and shrinks back into it, placed by [morphPlacePopover]; see
/// [MorphPopoverMotion]. An [anchor] must be mounted and laid out;
/// otherwise this function throws a descriptive [FlutterError].
/// The popover does not lift under a touch. The
/// cancel action does not show there; a tap outside runs it. Without a source, iOS 27 presents an action sheet on
/// an iPhone as an alert, and so does this function, the cancel action at
/// the bottom. Otherwise it behaves like [showMorphAlert].
Future<MorphAlertAction?> showMorphActionSheet(
  BuildContext context, {
  String? title,
  String? message,
  List<MorphAlertAction> actions = const [],
  BuildContext? anchor,
  Rect? anchorRect,
  MorphAlertAppearance? appearance,
  bool? useRootNavigator,
}) {
  Rect? source = anchorRect;
  if (source == null && anchor != null) {
    if (!anchor.mounted) {
      throw FlutterError('showMorphActionSheet anchor is no longer mounted.');
    }
    final box = anchor.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      throw FlutterError('showMorphActionSheet anchor must be laid out.');
    }
    source = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
  }
  final route = MorphAlertRoute(
    title: title,
    message: message,
    actions: actions,
    appearance: appearance,
    actionSheet: true,
    source: source,
  );
  final navigator = Navigator.of(
    context,
    rootNavigator: useRootNavigator ?? true,
  );
  route._themes = MorphThemeCarrier(anchor ?? context, to: navigator.context);
  return navigator.push(route);
}

/// The route [showMorphAlert] and [showMorphActionSheet] push: the alert
/// as a real navigator route, so the back button, `Navigator.pop` and pop
/// scopes work as on any route.
class MorphAlertRoute extends PopupRoute<MorphAlertAction>
    with
        MorphMotionRouteMixin<MorphAlertAction>,
        GlassBackdropCacheRoute<MorphAlertAction> {
  /// Creates the route.
  MorphAlertRoute({
    this.title,
    this.message,
    this.actions = const [],
    this.textFields = const [],
    this.appearance,
    this.actionSheet = false,
    this.source,
    super.settings,
  });

  /// The bold line at the top.
  final String? title;

  /// The text below the title.
  final String? message;

  /// The buttons.
  final List<MorphAlertAction> actions;

  /// The text fields between the text and the buttons.
  final List<MorphAlertTextField> textFields;

  /// The look; null resolves it from the theme.
  final MorphAlertAppearance? appearance;

  /// Whether this is an action sheet: a tap outside cancels it.
  final bool actionSheet;

  /// The global rect of the control an action sheet was summoned from;
  /// null presents it as an alert.
  final Rect? source;

  _AlertViewState? _view;
  MorphAlertAction? _chosen;
  MorphThemeCarrier? _themes;

  /// Whether the route presents as a popover next to [source].
  bool get isPopover => actionSheet && source != null;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => const Duration(seconds: 1);

  @override
  Widget buildModalBarrier() => const IgnorePointer(child: SizedBox.expand());

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final view = GlassPlaneScope.backdrop(
      backdrop: GlassBackdrop.cached(backdropCache),
      child: _AlertView(route: this),
    );
    return _themes?.install(view) ?? view;
  }

  @override
  MorphAlertAction? motionRouteResult(MorphAlertAction? result) =>
      result ?? _cancel;

  @override
  void motionRouteDidPop(MorphAlertAction? result) => _chosen = result;

  @override
  bool get projectsMotion => true;

  @override
  bool leaveMotionRoute() {
    final view = _view;
    if (view == null || !view.mounted) return false;
    view._leave();
    return true;
  }

  bool _ran = false;

  @override
  void motionRouteDidFinish() {
    final chosen = _chosen;
    if (chosen != null && !_ran) {
      _ran = true;
      chosen.onPressed?.call();
    }
  }

  MorphAlertAction? get _cancel {
    for (final a in actions) {
      if (a.style == MorphAlertActionStyle.cancel) return a;
    }
    return null;
  }
}

/// The indices of the actions in the order they show: the cancel action
/// first in a row, last in a column, and left out of a popover.
List<int> _ordered(
  List<MorphAlertAction> actions, {
  required bool row,
  required bool popover,
}) {
  final cancel = [
    for (var i = 0; i < actions.length; i++)
      if (actions[i].style == MorphAlertActionStyle.cancel) i,
  ];
  final rest = [
    for (var i = 0; i < actions.length; i++)
      if (actions[i].style != MorphAlertActionStyle.cancel) i,
  ];
  if (popover) return rest;
  return row ? [...cancel, ...rest] : [...rest, ...cancel];
}

TextStyle _buttonText(MorphAlertAction action, MorphAlertAppearance style) =>
    MorphTypography.resolve(
      MorphTypography.alertAction.copyWith(
        height: MorphAlertTuning.textHeight,
        fontWeight: action.isPreferred
            ? MorphAlertTuning.preferredWeight
            : null,
        color: !action.isEnabled
            ? style.disabledLabelColor
            : action.isPreferred
            ? style.preferredLabelColor
            : action.style == MorphAlertActionStyle.destructive
            ? style.destructiveColor
            : style.labelColor,
      ),
    );

class _AlertView extends StatefulWidget {
  const _AlertView({required this.route});

  final MorphAlertRoute route;

  @override
  State<_AlertView> createState() => _AlertViewState();
}

class _AlertViewState extends State<_AlertView>
    with SingleTickerProviderStateMixin<_AlertView>, MorphClock<_AlertView> {
  late final MorphAlertMotion? _alert = widget.route.isPopover
      ? null
      : MorphAlertMotion();
  late final MorphPopoverMotion? _popover = widget.route.isPopover
      ? MorphPopoverMotion()
      : null;
  final MorphGlassButtonMotion _press = MorphGlassButtonMotion(size: Size.zero);
  final GlobalKey _card = GlobalKey();
  // One key per action, not per slot: when the row turns into a column the
  // cancel action moves, and its button state and focus move with it.
  late final List<GlobalKey> _actionKeys = [
    for (final _ in widget.route.actions) GlobalKey(),
  ];
  List<GlobalKey> _buttonKeys = const [];
  late final List<TextEditingController> _ownControllers = [
    for (final f in widget.route.textFields)
      if (f.controller == null) TextEditingController(),
  ];
  late final List<TextEditingController> _controllers = () {
    var own = 0;
    return [
      for (final f in widget.route.textFields)
        f.controller ?? _ownControllers[own++],
    ];
  }();
  bool _leaving = false;
  int? _pointer;
  // The tracked finger scrolled the card's content: it chooses nothing
  // and moves nothing until it lifts.
  bool _scrolled = false;
  // The highlighted action repaints its own fill; the card does not rebuild
  // as the finger slides from action to action.
  final ValueNotifier<int?> _highlighted = ValueNotifier<int?>(null);
  List<MorphAlertAction> _shown = const [];

  MorphAlertRoute get _route => widget.route;

  @override
  void initState() {
    super.initState();
    _route._view = this;
    _alert?.present(clock);
    _popover?.present(clock);
    wake();
  }

  @override
  void dispose() {
    if (_route._view == this) _route._view = null;
    for (final c in _ownControllers) {
      c.dispose();
    }
    _highlighted.dispose();
    super.dispose();
  }

  @override
  void advanceMotion(double t) {
    _alert?.advance(t);
    _popover?.advance(t);
    _press.advance(t);
    _syncOverlay();
    final gone = _alert?.isDismissed ?? _popover?.isDismissed ?? false;
    if (_leaving && gone) {
      _route.finishMotionRoute();
    } else if (!_leaving &&
        (_alert?.isSettled ?? true) &&
        (_popover?.isSettled ?? true)) {
      _route.reportMotionOpened();
    }
  }

  @override
  bool get motionSettled =>
      (_alert?.isSettled ?? true) &&
      (_popover?.isSettled ?? true) &&
      _press.isSettled;

  @override
  void settleMotion() {
    _alert?.settle();
    final gone = _alert?.isDismissed ?? _popover?.isDismissed ?? false;
    if (_leaving && gone) _route.finishMotionRoute();
  }

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    _alert?.dismiss(clock);
    _popover?.dismiss(clock);
    if (_press.isPressed) _press.pointerCancel(clock);
    _pointer = null;
    _highlighted.value = null;
    setState(() {});
    wake();
  }

  void _choose(MorphAlertAction action) {
    if (_leaving || !action.isEnabled) return;
    _route.popMotionRoute(action);
  }

  void _cancelOutside() {
    if (_leaving || !_route.actionSheet) return;
    final cancel = _route._cancel;
    if (cancel != null) {
      _route._ran = true;
      cancel.onPressed?.call();
    }
    _route.popMotionRoute(cancel);
  }

  void _escape() {
    final cancel = _route._cancel;
    if (cancel != null) {
      _choose(cancel);
    } else if (_route.actionSheet) {
      _route.popMotionRoute(null);
    }
  }

  void _return() {
    for (final a in _shown) {
      if (a.isPreferred) {
        _choose(a);
        return;
      }
    }
  }

  int? _buttonAt(Offset global) {
    for (var i = 0; i < _buttonKeys.length && i < _shown.length; i++) {
      final box = _buttonKeys[i].currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final local = box.globalToLocal(global);
      if ((Offset.zero & box.size).contains(local)) {
        return _shown[i].isEnabled ? i : null;
      }
    }
    return null;
  }

  Offset? _cardLocal(Offset global) {
    final box = _card.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    _press.size = box.size;
    return box.globalToLocal(global);
  }

  void _down(PointerDownEvent event) {
    if (_leaving || _pointer != null || event.buttons != kPrimaryButton) {
      return;
    }
    final local = _cardLocal(event.position);
    if (local == null) return;
    _pointer = event.pointer;
    _scrolled = false;
    _press.reducedMotion = morphReducedMotionOf(context);
    if (!_route.isPopover) _press.pointerDown(stamp(event), local);
    _highlighted.value = _buttonAt(event.position);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer || _scrolled) return;
    final local = _cardLocal(event.position);
    if (local == null) return;
    if (!_route.isPopover) _press.pointerMove(stamp(event), local);
    final over = _buttonAt(event.position);
    if (over == _highlighted.value) return;
    if (over != null) morphPlayHaptic(context, MorphHaptic.selection);
    _highlighted.value = over;
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (_scrolled) return;
    if (!_route.isPopover) {
      final local = _cardLocal(event.position) ?? Offset.zero;
      _press.pointerUp(stamp(event), local);
    }
    final chosen = _buttonAt(event.position);
    _highlighted.value = null;
    if (chosen != null) _choose(_shown[chosen]);
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (_scrolled) return;
    if (!_route.isPopover) _press.pointerCancel(stamp(event));
    _highlighted.value = null;
  }

  bool _contentScrolled(ScrollNotification notification) {
    if (_pointer == null ||
        _scrolled ||
        notification.depth != 0 ||
        !morphScrollDragged(notification)) {
      return false;
    }
    _scrolled = true;
    if (!_route.isPopover) _press.pointerCancel(clock);
    _highlighted.value = null;
    wake();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final reduced = morphReducedMotionOf(context);
    _alert?.reducedMotion = reduced;
    _popover?.reducedMotion = reduced;
    final style = MorphAlertAppearance.resolve(context, _route.appearance);
    final popover = _route.isPopover;
    final rowCandidate =
        !popover && _route.actions.length == 2 && !_route.actionSheet;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final width = popover
        ? MorphAlertTuning.popoverWidth
        : math.min(
            MorphAlertTuning.width,
            MediaQuery.sizeOf(context).width -
                2 * MorphAlertTuning.screenMargin,
          );
    final row = rowCandidate && _fitsInRow(width, style, scaler, direction);
    final order = _ordered(_route.actions, row: row, popover: popover);
    final shown = [for (final i in order) _route.actions[i]];
    final kept = _keptCard;
    // A build that changes nothing the card draws (the dismissal's, which
    // only stops the card taking touches) hands back the card built
    // before, so it does not rebuild.
    final card =
        kept != null &&
            kept.row == row &&
            kept.width == width &&
            kept.style == style &&
            listEquals(kept.actions, shown)
        ? kept
        : _keptCard = _buildCard(shown, order, row, width, style, popover);
    final interactive = Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: MorphLiveTransform.matrix(
        live: frames,
        matrixOf: _pressTransform,
        child: NotificationListener<ScrollNotification>(
          onNotification: _contentScrolled,
          child: card,
        ),
      ),
    );
    final semantic = Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: _route.title ?? _route.message,
      child: interactive,
    );
    final keyed = CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
        const SingleActivator(LogicalKeyboardKey.enter): _return,
      },
      child: FocusScope(autofocus: true, child: semantic),
    );
    // Only the layout reads the safe area and the keyboard, so a keyboard
    // animating in rebuilds the layout and leaves the card alone.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: MorphAlertTuning.maxTextScale,
      child: DefaultTextStyle(
        style: MorphTypography.resolve(
          TextStyle(
            fontSize: MorphAlertTuning.textFontSize,
            color: style.labelColor,
          ),
        ),
        child: Builder(
          builder: (BuildContext context) {
            final safe = MediaQuery.paddingOf(context);
            final padding = EdgeInsets.fromLTRB(
              safe.left,
              safe.top,
              safe.right,
              math.max(safe.bottom, MediaQuery.viewInsetsOf(context).bottom),
            );
            return popover
                ? _popoverLayout(context, keyed, style, padding, direction)
                : _alertLayout(context, keyed, style, padding);
          },
        ),
      ),
    );
  }

  _AlertCard? _keptCard;

  _AlertCard _buildCard(
    List<MorphAlertAction> shown,
    List<int> order,
    bool row,
    double width,
    MorphAlertAppearance style,
    bool popover,
  ) {
    _shown = shown;
    _buttonKeys = [for (final i in order) _actionKeys[i]];
    return _AlertCard(
      key: _card,
      title: _route.title,
      message: _route.message,
      actions: _shown,
      buttonKeys: _buttonKeys,
      fields: _route.textFields,
      controllers: _controllers,
      row: row,
      width: width,
      highlighted: _highlighted,
      style: style,
      radius: popover
          ? MorphPopoverTuning.cornerRadius
          : MorphAlertTuning.cornerRadius,
      platter: !popover,
      onChoose: _choose,
      onSubmit: _return,
      frames: frames,
      opacity: _opacity,
    );
  }

  Matrix4 _pressTransform() {
    final lean = _press.lean;
    final transform = Matrix4.translationValues(lean.dx, lean.dy, 0);
    transform.multiply(
      Matrix4.diagonal3Values(_press.scaleX, _press.scaleY, 1),
    );
    return transform;
  }

  MorphAlertAppearance? _style;

  double _dimming(MorphAlertAppearance style) {
    return style.dimmingColor.a *
        MorphAlertTuning.dimmingOpacity *
        _alert!.dimming;
  }

  // The glass reads the dimming from the backdrop cache, so the cache
  // follows the motion on every frame, not only on a build.
  void _syncOverlay() {
    final style = _style;
    if (_alert == null || style == null) return;
    _route.backdropCache.overlay = style.dimmingColor.withValues(
      alpha: _dimming(style),
    );
  }

  double _opacity() =>
      (_alert?.opacity ?? _popover?.opacity ?? 1).clamp(0.0, 1.0);

  (double, MorphAlertAppearance, TextScaler, TextDirection, bool)? _rowKey;
  bool _rowFits = false;

  bool _fitsInRow(
    double width,
    MorphAlertAppearance style,
    TextScaler scaler,
    TextDirection direction,
  ) {
    final key = (
      width,
      style,
      scaler,
      direction,
      MorphTypography.usesAppleSystemFont,
    );
    if (key == _rowKey) return _rowFits;
    _rowKey = key;
    return _rowFits = _measureRow(width, style, scaler, direction);
  }

  bool _measureRow(
    double width,
    MorphAlertAppearance style,
    TextScaler scaler,
    TextDirection direction,
  ) {
    final each =
        (width -
            2 * MorphAlertTuning.buttonInset -
            MorphAlertTuning.buttonGap) /
        2;
    for (final a in _route.actions) {
      final painter = TextPainter(
        text: TextSpan(text: a.title, style: _buttonText(a, style)),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      );
      painter.layout();
      final fits = painter.width + 2 * MorphAlertTuning.buttonTextInset <= each;
      painter.dispose();
      if (!fits) return false;
    }
    return true;
  }

  Widget _alertLayout(
    BuildContext context,
    Widget card,
    MorphAlertAppearance style,
    EdgeInsets padding,
  ) {
    final motion = _alert!;
    _style = style;
    _syncOverlay();
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _cancelOutside,
            child: MorphLiveColoredBox(
              live: frames,
              colorOf: () =>
                  style.dimmingColor.withValues(alpha: _dimming(style)),
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: padding,
            child: Center(
              child: MorphLiveTransform.matrix(
                live: frames,
                matrixOf: () {
                  final s = motion.scale;
                  return Matrix4.diagonal3Values(s, s, 1);
                },
                child: IgnorePointer(
                  // Flips only in dismiss, which _leave follows with a build.
                  ignoring: motion.isDismissing,
                  child: card,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _popoverLayout(
    BuildContext context,
    Widget card,
    MorphAlertAppearance style,
    EdgeInsets padding,
    TextDirection direction,
  ) {
    final motion = _popover!;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _cancelOutside,
          ),
        ),
        Positioned.fill(
          child: _PopoverLayout(
            motion: motion,
            frames: frames,
            source: _route.source!,
            origin: () => _overlayOrigin(context),
            padding: padding,
            direction: direction,
            children: [
              _platterFor(style),
              IgnorePointer(ignoring: motion.isDismissing, child: card),
            ],
          ),
        ),
      ],
    );
  }

  (MorphAlertAppearance, Widget)? _platter;

  // The platter takes the shape the layout places, built at layout, so its
  // arrow and the card move as one. A build that keeps the style hands
  // back the same widget, so the dismissal does not build it again.
  Widget _platterFor(MorphAlertAppearance style) {
    if (_platter case (final kept, final platter) when kept == style) {
      return platter;
    }
    final platter = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) => _PopoverPlatter(
        shape: (box as _PopoverConstraints).shape,
        style: style,
        frames: frames,
        opacity: _opacity,
      ),
    );
    _platter = (style, platter);
    return platter;
  }

  Offset _overlayOrigin(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) return box.localToGlobal(Offset.zero);
    return Offset.zero;
  }
}

/// The constraints a popover's platter is laid out with: tight to the
/// box of its [shape], which they carry, so the platter builds again
/// whenever the shape changes.
class _PopoverConstraints extends BoxConstraints {
  _PopoverConstraints(this.shape) : super.tight(shape.bounds.size);

  /// The popover's shape in the platter's coordinates.
  final MorphPopoverShape shape;

  @override
  bool operator ==(Object other) =>
      other is _PopoverConstraints && other.shape == shape;

  @override
  int get hashCode => shape.hashCode;
}

/// Lays out a popover's platter and card: the card at its own size, the
/// placement from it ([morphPlacePopover]), and the platter at the
/// placement's shape; both paint scaled by the motion about the arrow's
/// tip.
class _PopoverLayout extends MultiChildRenderObjectWidget {
  const _PopoverLayout({
    required this.motion,
    required this.frames,
    required this.source,
    required this.origin,
    required this.padding,
    required this.direction,
    required super.children,
  });

  final MorphPopoverMotion motion;
  final Listenable frames;
  final Rect source;
  final Offset Function() origin;
  final EdgeInsets padding;
  final TextDirection direction;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPopover(
    motion: motion,
    frames: frames,
    source: source,
    origin: origin,
    padding: padding,
    direction: direction,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderPopover renderObject) =>
      renderObject.update(
        motion: motion,
        frames: frames,
        source: source,
        origin: origin,
        padding: padding,
        direction: direction,
      );
}

class _PopoverParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderPopover extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PopoverParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PopoverParentData> {
  _RenderPopover({
    required this._motion,
    required this._frames,
    required this._source,
    required this._origin,
    required this._padding,
    required this._direction,
  });

  MorphPopoverMotion _motion;
  Listenable _frames;
  Rect _source;
  Offset Function() _origin;
  EdgeInsets _padding;
  TextDirection _direction;

  /// Takes the configuration of a new [_PopoverLayout].
  void update({
    required MorphPopoverMotion motion,
    required Listenable frames,
    required Rect source,
    required Offset Function() origin,
    required EdgeInsets padding,
    required TextDirection direction,
  }) {
    if (!identical(frames, _frames) && attached) {
      _frames.removeListener(markNeedsPaint);
      frames.addListener(markNeedsPaint);
    }
    _frames = frames;
    _origin = origin;
    if (!identical(motion, _motion)) markNeedsPaint();
    _motion = motion;
    if (source != _source || padding != _padding || direction != _direction) {
      markNeedsLayout();
    }
    _source = source;
    _padding = padding;
    _direction = direction;
  }

  MorphPopoverPlacement? _placement;

  // The overlay's position the last paint found, which layout places the
  // popover by: no box's position can be read during layout.
  Offset _seen = Offset.zero;
  Offset _laidOutAt = Offset.zero;
  bool _painted = false;
  final LayerHandle<TransformLayer> _platterLayer = LayerHandle();
  final LayerHandle<TransformLayer> _cardLayer = LayerHandle();

  RenderBox get _platter => firstChild!;
  RenderBox get _card => lastChild!;

  // Every frame of the motion repaints the popover alone.
  @override
  bool get isRepaintBoundary => true;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PopoverParentData) {
      child.parentData = _PopoverParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frames.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _frames.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _platterLayer.layer = null;
    _cardLayer.layer = null;
    super.dispose();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    _card.layout(
      BoxConstraints(
        maxWidth: MorphAlertTuning.popoverWidth,
        maxHeight: math.max(0, size.height - _padding.vertical),
      ),
      parentUsesSize: true,
    );
    _laidOutAt = _seen;
    final placement = _placement = morphPlacePopover(
      size: _card.size,
      source: _source.shift(-_laidOutAt),
      screen: size,
      padding: _padding,
      textDirection: _direction,
    );
    final bounds = placement.bounds;
    final vertical =
        placement.arrowDirection == MorphPopoverArrowDirection.down ||
        placement.arrowDirection == MorphPopoverArrowDirection.up;
    _platter.layout(
      _PopoverConstraints(
        MorphPopoverShape(
          content: placement.content.shift(-bounds.topLeft),
          direction: placement.arrowDirection,
          arrowCenter:
              placement.arrowCenter - (vertical ? bounds.left : bounds.top),
        ),
      ),
    );
  }

  Matrix4 _around(Offset at) {
    final anchor = _placement!.anchor;
    final s = _motion.scale;
    final m = Matrix4.translationValues(anchor.dx, anchor.dy, 0);
    m.multiply(Matrix4.diagonal3Values(s, s, 1));
    m.multiply(
      Matrix4.translationValues(at.dx - anchor.dx, at.dy - anchor.dy, 0),
    );
    return m;
  }

  Matrix4 _transformOf(RenderBox child) => _around(
    identical(child, _platter)
        ? _placement!.bounds.topLeft
        : _placement!.content.topLeft,
  );

  @override
  void paint(PaintingContext context, Offset offset) {
    // Laid out for another position of the overlay (the first frame of a
    // popover in a nested navigator, an overlay moved since), the popover
    // is placed again in the next frame. A popover's first frame shows
    // nothing (its opacity starts at 0).
    _seen = _origin();
    if (_seen != _laidOutAt) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (attached) markNeedsLayout();
      });
    }
    _painted = _motion.opacity > 0;
    if (!_painted) {
      _platterLayer.layer = null;
      _cardLayer.layer = null;
      return;
    }
    _platterLayer.layer = context.pushTransform(
      needsCompositing,
      offset,
      _transformOf(_platter),
      (PaintingContext context, Offset offset) =>
          context.paintChild(_platter, offset),
      oldLayer: _platterLayer.layer,
    );
    _cardLayer.layer = context.pushTransform(
      needsCompositing,
      offset,
      _transformOf(_card),
      (PaintingContext context, Offset offset) =>
          context.paintChild(_card, offset),
      oldLayer: _cardLayer.layer,
    );
  }

  // The popover takes taps across its frame, the arrow's strip included,
  // as UIKit's popover view does; the card takes its own first.
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!_painted) return false;
    final hit = result.addWithPaintTransform(
      transform: _transformOf(_card),
      position: position,
      hitTest: (BoxHitTestResult result, Offset position) =>
          _card.hitTest(result, position: position),
    );
    if (hit) return true;
    final toPlatter = Matrix4.tryInvert(_transformOf(_platter));
    if (toPlatter == null) return false;
    return (Offset.zero & _platter.size).contains(
      MatrixUtils.transformPoint(toPlatter, position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (_placement == null) return;
    transform.multiply(_transformOf(child));
  }
}

/// The glass of a popover: its content box and arrow as one [shape],
/// shaded as one body on the liquid tier and filled on the flat ones.
class _PopoverPlatter extends StatelessWidget {
  const _PopoverPlatter({
    required this.shape,
    required this.style,
    required this.frames,
    required this.opacity,
  });

  final MorphPopoverShape shape;
  final MorphAlertAppearance style;
  final Listenable frames;
  final double Function() opacity;

  @override
  Widget build(BuildContext context) {
    final glass = MorphGlassScope.maybeOf(context);
    if (glass == null) {
      return CustomPaint(
        painter: _PlatterPainter(
          style: style,
          shape: shape.path,
          opacity: opacity,
          frames: frames,
        ),
      );
    }
    final brightness = morphBrightnessOf(context);
    final outline = shape.outline(shaded: morphGlassShadesOutlines(glass));
    final body = shape.body;
    final arrow = RRect.fromRectAndRadius(shape.arrowBox, Radius.zero);
    MorphGlassSurface surface(RRect part, double opacity) => MorphGlassSurface(
      kind: MorphGlassKind.menu,
      shape: part,
      color: style.platterColor,
      brightness: brightness,
      opacity: opacity,
    );
    return MorphGlassHost(
      painter: glass,
      mode: MorphGlassMode.body,
      frames: frames,
      frame: () {
        final shown = opacity();
        return MorphGlassFrame([
          surface(body, shown),
          surface(arrow, shown),
        ], outline: outline);
      },
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.title,
    required this.message,
    required this.actions,
    required this.buttonKeys,
    required this.fields,
    required this.controllers,
    required this.row,
    required this.width,
    required this.highlighted,
    required this.style,
    required this.radius,
    required this.platter,
    required this.onChoose,
    required this.onSubmit,
    required this.frames,
    required this.opacity,
    super.key,
  });

  final String? title;
  final String? message;
  final List<MorphAlertAction> actions;
  final List<GlobalKey> buttonKeys;
  final List<MorphAlertTextField> fields;
  final List<TextEditingController> controllers;
  final bool row;
  final double width;
  final ValueListenable<int?> highlighted;
  final MorphAlertAppearance style;
  final double radius;

  /// Whether the card draws its own platter; a popover's platter is the
  /// popover's, arrow and all.
  final bool platter;
  final ValueChanged<MorphAlertAction> onChoose;
  final VoidCallback onSubmit;
  final Listenable frames;
  final double Function() opacity;

  @override
  Widget build(BuildContext context) {
    final glass = MorphGlassScope.maybeOf(context);
    final brightness = morphBrightnessOf(context);
    final title = this.title;
    final message = this.message;
    final both = title != null && message != null;
    final single = (title ?? message) != null && !both;
    final textWidth = width - 2 * MorphAlertTuning.textInset;
    final header = <Widget>[
      if (title != null)
        MorphLabelHeight(
          child: Text(
            title,
            textAlign: TextAlign.start,
            style: MorphTypography.resolve(
              MorphTypography.alertTitle.copyWith(
                height: MorphAlertTuning.textHeight,
                fontWeight: both ? null : MorphAlertTuning.singleHeaderWeight,
                color: style.titleColor,
              ),
            ),
          ),
        ),
      if (both) const SizedBox(height: MorphAlertTuning.titleGap),
      if (message != null)
        MorphLabelHeight(
          child: Text(
            message,
            textAlign: TextAlign.start,
            style: MorphTypography.resolve(
              single
                  ? TextStyle(
                      fontSize: MorphAlertTuning.textFontSize,
                      height: MorphAlertTuning.textHeight,
                      color: style.titleColor,
                    )
                  : MorphTypography.alertMessage.copyWith(
                      height: MorphAlertTuning.messageHeight,
                      color: style.messageColor,
                    ),
            ),
          ),
        ),
    ];
    final fieldWidgets = <Widget>[
      for (var i = 0; i < fields.length; i++) ...[
        if (i > 0) const SizedBox(height: MorphAlertTuning.fieldGap),
        _AlertField(
          field: fields[i],
          controller: controllers[i],
          style: style,
          autofocus: fields[i].autofocus ?? i == 0,
          onSubmit: onSubmit,
        ),
      ],
    ];
    final buttons = [
      for (var i = 0; i < actions.length; i++)
        _AlertButton(
          key: buttonKeys[i],
          action: actions[i],
          index: i,
          highlighted: highlighted,
          style: style,
          onChoose: onChoose,
        ),
    ];
    final Widget buttonBlock = row
        ? Row(
            children: [
              Expanded(child: buttons[0]),
              const SizedBox(width: MorphAlertTuning.buttonGap),
              Expanded(child: buttons[1]),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(height: MorphAlertTuning.buttonGap),
                buttons[i],
              ],
            ],
          );
    final hasHeader = header.isNotEmpty;
    final content = Padding(
      padding: EdgeInsets.only(
        top: hasHeader ? MorphAlertTuning.headerTop : 0,
        bottom: MorphAlertTuning.buttonInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasHeader)
            Padding(
              padding: EdgeInsets.only(
                left: MorphAlertTuning.textInset,
                right: MorphAlertTuning.textInset,
                bottom: both
                    ? MorphAlertTuning.headerBottom
                    : MorphAlertTuning.singleHeaderBottom,
              ),
              child: SizedBox(
                width: textWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: header,
                ),
              ),
            ),
          if (fieldWidgets.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                top: hasHeader
                    ? MorphAlertTuning.fieldTop - MorphAlertTuning.headerBottom
                    : MorphAlertTuning.buttonInset,
                left: MorphAlertTuning.fieldInset,
                right: MorphAlertTuning.fieldInset,
                bottom: MorphAlertTuning.fieldBottom,
              ),
              child: Column(children: fieldWidgets),
            ),
          if (buttons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                top: MorphAlertTuning.buttonInset,
                left: MorphAlertTuning.buttonInset,
                right: MorphAlertTuning.buttonInset,
              ),
              child: buttonBlock,
            ),
        ],
      ),
    );
    final scroll = ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      children: [content],
    );
    // The text scales and fades with the card: drawn through the glyph
    // policy, it strikes no new glyphs on every frame of the sweep. In a
    // repaint boundary of its own below the policy, a frame that only
    // fades or moves it keeps its pictures.
    final clipped = MorphGlyphs.faded(
      live: frames,
      opacityOf: opacity,
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: scroll,
        ),
      ),
    );
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          if (platter)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) {
                  final shape = RRect.fromRectAndRadius(
                    Offset.zero & box.biggest,
                    Radius.circular(radius),
                  );
                  if (glass == null) {
                    final outline = Path();
                    outline.addRRect(shape);
                    return CustomPaint(
                      painter: _PlatterPainter(
                        style: style,
                        shape: outline,
                        opacity: opacity,
                        frames: frames,
                      ),
                    );
                  }
                  return MorphGlassHost(
                    painter: glass,
                    mode: MorphGlassMode.surface,
                    frames: frames,
                    frame: () => MorphGlassFrame([
                      MorphGlassSurface(
                        kind: MorphGlassKind.menu,
                        shape: shape,
                        color: style.platterColor,
                        brightness: brightness,
                        opacity: opacity(),
                      ),
                    ]),
                  );
                },
              ),
            ),
          clipped,
        ],
      ),
    );
  }
}

class _PlatterPainter extends CustomPainter {
  _PlatterPainter({
    required this.style,
    required this.shape,
    required this.opacity,
    required Listenable frames,
  }) : super(repaint: frames);

  final MorphAlertAppearance style;
  final Path shape;
  final double Function() opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = this.opacity();
    Color faded(Color c) => c.withValues(alpha: c.a * opacity);
    final shadow = Paint();
    shadow.color = faded(style.shadowColor);
    shadow.maskFilter = const MaskFilter.blur(
      BlurStyle.normal,
      MorphAlertTuning.flatShadowSigma,
    );
    canvas.drawPath(
      shape.shift(const Offset(0, MorphAlertTuning.flatShadowOffset)),
      shadow,
    );
    final fill = Paint();
    fill.color = faded(style.platterColor);
    canvas.drawPath(shape, fill);
  }

  @override
  bool shouldRepaint(_PlatterPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.shape != shape ||
      oldDelegate.opacity != opacity;
}

class _AlertButton extends StatefulWidget {
  const _AlertButton({
    required this.action,
    required this.index,
    required this.highlighted,
    required this.style,
    required this.onChoose,
    super.key,
  });

  final MorphAlertAction action;

  /// The button's place among the card's actions.
  final int index;

  /// The index of the highlighted action, if any.
  final ValueListenable<int?> highlighted;
  final MorphAlertAppearance style;
  final ValueChanged<MorphAlertAction> onChoose;

  @override
  State<_AlertButton> createState() => _AlertButtonState();
}

class _AlertButtonState extends State<_AlertButton> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.action.enabledListenable?.addListener(_enabledChanged);
  }

  @override
  void didUpdateWidget(_AlertButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.action.enabledListenable;
    final now = widget.action.enabledListenable;
    if (!identical(before, now)) {
      before?.removeListener(_enabledChanged);
      now?.addListener(_enabledChanged);
    }
  }

  @override
  void dispose() {
    widget.action.enabledListenable?.removeListener(_enabledChanged);
    super.dispose();
  }

  void _enabledChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final style = widget.style;
    final base = action.isPreferred && action.isEnabled
        ? style.preferredColor
        : style.buttonColor;
    void activate() => widget.onChoose(action);
    return MorphControlFocus(
      enabled: action.isEnabled,
      onHighlight: (bool focused) => setState(() => _focused = focused),
      onActivate: activate,
      child: Semantics(
        container: true,
        button: true,
        enabled: action.isEnabled,
        label: action.title,
        onTap: action.isEnabled ? activate : null,
        child: ExcludeSemantics(
          child: MorphFocusRing(
            visible: _focused,
            // A boundary of its own: a highlight change repaints this
            // button's fill and title, not the card.
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _ButtonFillPainter(
                  color: base,
                  index: widget.index,
                  highlighted: widget.highlighted,
                ),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: MorphAlertTuning.buttonHeight,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: MorphAlertTuning.buttonTextInset,
                  ),
                  child: Text(
                    action.title,
                    textAlign: TextAlign.center,
                    style: _buttonText(action, style),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An action's stadium fill, dimmed while the finger is on it.
class _ButtonFillPainter extends CustomPainter {
  _ButtonFillPainter({
    required this.color,
    required this.index,
    required this.highlighted,
  }) : super(repaint: highlighted);

  final Color color;
  final int index;
  final ValueListenable<int?> highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    fill.color = highlighted.value == index
        ? color.withValues(alpha: color.a * MorphAlertTuning.pressedFillOpacity)
        : color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.shortestSide / 2),
      ),
      fill,
    );
  }

  @override
  bool shouldRepaint(_ButtonFillPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.index != index ||
      oldDelegate.highlighted != highlighted;
}

class _AlertField extends StatefulWidget {
  const _AlertField({
    required this.field,
    required this.controller,
    required this.style,
    required this.autofocus,
    required this.onSubmit,
  });

  final MorphAlertTextField field;
  final TextEditingController controller;
  final MorphAlertAppearance style;
  final bool autofocus;
  final VoidCallback onSubmit;

  @override
  State<_AlertField> createState() => _AlertFieldState();
}

class _AlertFieldState extends State<_AlertField>
    implements TextSelectionGestureDetectorBuilderDelegate {
  final FocusNode _focus = FocusNode(debugLabel: 'MorphAlertTextField');
  final GlobalKey<EditableTextState> _editable = GlobalKey<EditableTextState>();
  late final TextSelectionGestureDetectorBuilder _gestures =
      TextSelectionGestureDetectorBuilder(delegate: this);

  @override
  GlobalKey<EditableTextState> get editableTextKey => _editable;

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  // The placeholder builds again only when the field turns empty or stops
  // being empty, not on every keystroke, caret move or composing change.
  late MorphChanges<bool> _emptiness = _emptinessOf(widget.controller);

  static MorphChanges<bool> _emptinessOf(TextEditingController controller) =>
      MorphChanges(controller, () => controller.text.isEmpty);

  @override
  void didUpdateWidget(_AlertField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _emptiness = _emptinessOf(widget.controller);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final controller = widget.controller;
    final text = MorphTypography.resolve(
      TextStyle(
        fontSize: MorphAlertTuning.textFontSize,
        height: MorphAlertTuning.textHeight,
        color: style.titleColor,
      ),
    );
    final placeholder = widget.field.placeholder;
    return Container(
      height: MorphAlertTuning.buttonHeight,
      padding: const EdgeInsets.symmetric(
        horizontal: MorphAlertTuning.fieldInset,
      ),
      decoration: ShapeDecoration(
        color: style.buttonColor,
        shape: const StadiumBorder(),
      ),
      alignment: AlignmentDirectional.centerStart,
      child: Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          if (placeholder != null)
            ListenableBuilder(
              listenable: _emptiness,
              builder: (BuildContext context, Widget? child) =>
                  controller.text.isEmpty ? child! : const SizedBox.shrink(),
              child: ExcludeSemantics(
                child: Text(
                  placeholder,
                  maxLines: 1,
                  style: text.copyWith(color: style.placeholderColor),
                ),
              ),
            ),
          Semantics(
            label: widget.field.semanticLabel ?? placeholder,
            child: _gestures.buildGestureDetector(
              behavior: HitTestBehavior.translucent,
              child: EditableText(
                key: _editable,
                controller: controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                obscureText: widget.field.obscureText,
                keyboardType: widget.field.keyboardType,
                onChanged: widget.field.onChanged,
                autocorrect: widget.field.autocorrect,
                enableSuggestions: widget.field.enableSuggestions,
                textCapitalization: widget.field.textCapitalization,
                inputFormatters: widget.field.inputFormatters,
                style: text,
                cursorColor: style.preferredColor,
                backgroundCursorColor: style.placeholderColor,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                rendererIgnoresPointer: true,
                contextMenuBuilder: morphEditMenuBuilder(context),
                onSubmitted: (_) => widget.onSubmit(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
