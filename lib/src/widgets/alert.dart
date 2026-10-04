import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/themes.dart';
import 'package:morph/src/widgets/alert_motion.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/motion_route.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_button.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

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
  /// [MorphAlertStyle.disabledLabelColor]; a disabled preferred button
  /// shows the plain fill instead of the accent and keeps its semibold
  /// title.
  final bool enabled;
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
  });

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
class MorphAlertStyle {
  /// Creates a style; the defaults are the iOS light appearance.
  const MorphAlertStyle({
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
  static const light = MorphAlertStyle();

  /// The dark appearance, as UIKit renders it.
  static const dark = MorphAlertStyle(
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

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphAlertStyle resolve(
    BuildContext context,
    MorphAlertStyle? explicit,
  ) =>
      explicit ??
      MorphWidgetsTheme.maybeOf(context)?.alert ??
      switch (morphBrightnessOf(context)) {
        Brightness.dark => dark,
        Brightness.light => light,
      };
}

/// Shows an alert that moves like an iOS 27 UIAlertController, and
/// completes with the action the user chose.
///
/// The alert fades in over a dimming while it shrinks into place, and
/// fades out when it leaves; see [MorphAlertMotion]. It is 320 points
/// wide and centered in the room the safe area and the keyboard leave.
/// Two actions sit side by side, the cancel action first; more stack,
/// the cancel action last. A touch anywhere on the alert lifts the whole
/// platter like a glass button (a dragging finger pulls it a quarter as
/// far, [MorphAlertTuning.platterPull]), the button under the finger
/// highlights, and the finger may slide to another button before it
/// lifts. The
/// future completes when the alert starts to leave; the chosen action's
/// [MorphAlertAction.onPressed] runs once it is gone. A tap outside does
/// nothing, as in UIKit; Escape chooses the cancel action and Return the
/// preferred one.
Future<MorphAlertAction?> showMorphAlert(
  BuildContext context, {
  String? title,
  String? message,
  List<MorphAlertAction> actions = const [],
  List<MorphAlertTextField> textFields = const [],
  MorphAlertStyle? style,
  bool useRootNavigator = true,
}) {
  final route = MorphAlertRoute(
    title: title,
    message: message,
    actions: actions,
    textFields: textFields,
    style: style,
  );
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
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
  MorphAlertStyle? style,
  bool useRootNavigator = true,
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
    style: style,
    actionSheet: true,
    source: source,
  );
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  route._themes = MorphThemeCarrier(anchor ?? context, to: navigator.context);
  return navigator.push(route);
}

/// The route [showMorphAlert] and [showMorphActionSheet] push: the alert
/// as a real navigator route, so the back button, `Navigator.pop` and pop
/// scopes work as on any route.
class MorphAlertRoute extends PopupRoute<MorphAlertAction>
    with MorphMotionRouteMixin<MorphAlertAction> {
  /// Creates the route.
  MorphAlertRoute({
    this.title,
    this.message,
    this.actions = const [],
    this.textFields = const [],
    this.style,
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
  final MorphAlertStyle? style;

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
    final view = _AlertView(route: this);
    return _themes?.install(view) ?? view;
  }

  @override
  MorphAlertAction? motionRouteResult(MorphAlertAction? result) =>
      result ?? _cancel;

  @override
  void motionRouteDidPop(MorphAlertAction? result) => _chosen = result;

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

/// The actions in the order they show: the cancel action first in a row,
/// last in a column, and left out of a popover.
List<MorphAlertAction> _ordered(
  List<MorphAlertAction> actions, {
  required bool row,
  required bool popover,
}) {
  final cancel = [
    for (final a in actions)
      if (a.style == MorphAlertActionStyle.cancel) a,
  ];
  final rest = [
    for (final a in actions)
      if (a.style != MorphAlertActionStyle.cancel) a,
  ];
  if (popover) return rest;
  return row ? [...cancel, ...rest] : [...rest, ...cancel];
}

TextStyle _buttonText(MorphAlertAction action, MorphAlertStyle style) =>
    MorphTypography.resolve(
      MorphTypography.alertAction.copyWith(
        height: MorphAlertTuning.textHeight,
        fontWeight: action.isPreferred
            ? MorphAlertTuning.preferredWeight
            : null,
        color: !action.enabled
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

MorphGlassButtonMotion _platterPress() {
  final motion = MorphGlassButtonMotion(size: Size.zero);
  motion.pull = MorphAlertTuning.platterPull;
  motion.stretch = MorphAlertTuning.platterStretch;
  return motion;
}

class _AlertViewState extends State<_AlertView>
    with SingleTickerProviderStateMixin<_AlertView>, MorphClock<_AlertView> {
  late final MorphAlertMotion? _alert = widget.route.isPopover
      ? null
      : MorphAlertMotion();
  late final MorphPopoverMotion? _popover = widget.route.isPopover
      ? MorphPopoverMotion()
      : null;
  final MorphGlassButtonMotion _press = _platterPress();
  final GlobalKey _card = GlobalKey();
  final List<GlobalKey> _buttonKeys = [];
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
  int? _highlighted;
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
    super.dispose();
  }

  @override
  void advanceMotion(double t) {
    _alert?.advance(t);
    _popover?.advance(t);
    _press.advance(t);
    final gone = _alert?.isDismissed ?? _popover?.isDismissed ?? false;
    if (_leaving && gone) _route.finishMotionRoute();
  }

  @override
  bool get motionSettled =>
      (_alert?.isSettled ?? true) &&
      (_popover?.isSettled ?? true) &&
      _press.isSettled;

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    _alert?.dismiss(clock);
    _popover?.dismiss(clock);
    if (_press.isPressed) _press.pointerCancel(clock);
    _pointer = null;
    setState(() => _highlighted = null);
    wake();
  }

  void _choose(MorphAlertAction action) {
    if (_leaving || !action.enabled) return;
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
        return _shown[i].enabled ? i : null;
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
    _press.reducedMotion = morphReducedMotionOf(context);
    if (!_route.isPopover) _press.pointerDown(stamp(event), local);
    setState(() => _highlighted = _buttonAt(event.position));
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final local = _cardLocal(event.position);
    if (local == null) return;
    _press.pointerMove(stamp(event), local);
    final over = _buttonAt(event.position);
    if (over != _highlighted) setState(() => _highlighted = over);
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final local = _cardLocal(event.position) ?? Offset.zero;
    _press.pointerUp(stamp(event), local);
    final chosen = _buttonAt(event.position);
    setState(() => _highlighted = null);
    if (chosen != null) _choose(_shown[chosen]);
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _press.pointerCancel(stamp(event));
    setState(() => _highlighted = null);
  }

  @override
  Widget build(BuildContext context) {
    final style = MorphAlertStyle.resolve(context, _route.style);
    final media = MediaQuery.of(context);
    final popover = _route.isPopover;
    final rowCandidate =
        !popover && _route.actions.length == 2 && !_route.actionSheet;
    final scaler = media.textScaler;
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final width = popover
        ? MorphAlertTuning.popoverWidth
        : math.min(
            MorphAlertTuning.width,
            media.size.width - 2 * MorphAlertTuning.screenMargin,
          );
    final row = rowCandidate && _fitsInRow(width, style, scaler, direction);
    _shown = _ordered(_route.actions, row: row, popover: popover);
    while (_buttonKeys.length < _shown.length) {
      _buttonKeys.add(GlobalKey());
    }
    final card = _AlertCard(
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
      onChoose: _choose,
      onSubmit: _return,
      frames: frames,
      opacity: _opacity,
    );
    final interactive = Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: ListenableBuilder(
        listenable: frames,
        builder: (BuildContext context, Widget? child) {
          final lean = _press.lean;
          final transform = Matrix4.translationValues(lean.dx, lean.dy, 0);
          transform.multiply(
            Matrix4.diagonal3Values(_press.scaleX, _press.scaleY, 1),
          );
          return Transform(
            transform: transform,
            alignment: Alignment.center,
            child: child,
          );
        },
        child: card,
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
    final padding = EdgeInsets.fromLTRB(
      media.padding.left,
      media.padding.top,
      media.padding.right,
      math.max(media.padding.bottom, media.viewInsets.bottom),
    );
    return MediaQuery(
      data: media.copyWith(
        textScaler: scaler.clamp(maxScaleFactor: MorphAlertTuning.maxTextScale),
      ),
      child: DefaultTextStyle(
        style: MorphTypography.resolve(
          TextStyle(
            fontSize: MorphAlertTuning.textFontSize,
            color: style.labelColor,
          ),
        ),
        child: popover
            ? _popoverLayout(context, keyed, style, padding, direction)
            : _alertLayout(context, keyed, style, padding),
      ),
    );
  }

  double _opacity() {
    final t = _alert?.time ?? _popover?.time ?? 0;
    return (_alert?.opacity(t) ?? _popover?.opacity(t) ?? 1).clamp(0.0, 1.0);
  }

  bool _fitsInRow(
    double width,
    MorphAlertStyle style,
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
    MorphAlertStyle style,
    EdgeInsets padding,
  ) {
    final motion = _alert!;
    return ListenableBuilder(
      listenable: frames,
      child: card,
      builder: (BuildContext context, Widget? child) {
        final t = motion.time;
        final dim =
            style.dimmingColor.a *
            MorphAlertTuning.dimmingOpacity *
            motion.dimming(t);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _cancelOutside,
                child: ColoredBox(
                  color: style.dimmingColor.withValues(alpha: dim),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: padding,
                child: Center(
                  child: Transform.scale(
                    scale: motion.scale(t),
                    child: IgnorePointer(
                      ignoring: motion.isDismissing,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _popoverLayout(
    BuildContext context,
    Widget card,
    MorphAlertStyle style,
    EdgeInsets padding,
    TextDirection direction,
  ) {
    final motion = _popover!;
    final source = _route.source!;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _cancelOutside,
          ),
        ),
        Positioned.fill(
          child: Flow(
            delegate: _PopoverFlow(
              motion: motion,
              frames: frames,
              source: source,
              origin: () => _overlayOrigin(context),
              padding: padding,
              direction: direction,
            ),
            children: [
              CustomPaint(
                painter: _ArrowPainter(color: style.platterColor),
                child: const SizedBox(
                  width: MorphPopoverTuning.arrowWidth,
                  height: MorphPopoverTuning.arrowLength,
                ),
              ),
              IgnorePointer(ignoring: motion.isDismissing, child: card),
            ],
          ),
        ),
      ],
    );
  }

  Offset _overlayOrigin(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) return box.localToGlobal(Offset.zero);
    return Offset.zero;
  }
}

class _PopoverFlow extends FlowDelegate {
  _PopoverFlow({
    required this.motion,
    required Listenable frames,
    required this.source,
    required this.origin,
    required this.padding,
    required this.direction,
  }) : super(repaint: frames);

  final MorphPopoverMotion motion;
  final Rect source;
  final Offset Function() origin;
  final EdgeInsets padding;
  final TextDirection direction;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) {
    if (i == 0) return const BoxConstraints();
    return BoxConstraints(
      maxWidth: MorphAlertTuning.popoverWidth,
      maxHeight: math.max(0, constraints.maxHeight - padding.vertical),
    );
  }

  @override
  void paintChildren(FlowPaintingContext context) {
    final size = context.getChildSize(1);
    if (size == null) return;
    final placement = morphPlacePopover(
      size: size,
      source: source.shift(-origin()),
      screen: context.size,
      padding: padding,
      textDirection: direction,
    );
    final t = motion.time;
    final s = motion.scale(t);
    final anchor = placement.anchor;
    final opacity = motion.opacity(t);
    Matrix4 around(Offset at) {
      final m = Matrix4.translationValues(anchor.dx, anchor.dy, 0);
      m.multiply(Matrix4.diagonal3Values(s, s, 1));
      m.multiply(
        Matrix4.translationValues(at.dx - anchor.dx, at.dy - anchor.dy, 0),
      );
      return m;
    }

    final content = placement.content;
    const w = MorphPopoverTuning.arrowWidth;
    final arrow = Matrix4.identity();
    final c = placement.arrowCenter;
    switch (placement.edge) {
      case MorphPopoverArrowEdge.bottom:
        arrow.setFrom(around(Offset(c - w / 2, content.bottom)));
      case MorphPopoverArrowEdge.top:
        arrow.setFrom(around(Offset(c + w / 2, content.top)));
        arrow.multiply(Matrix4.rotationZ(math.pi));
      case MorphPopoverArrowEdge.left:
        arrow.setFrom(around(Offset(content.left, c - w / 2)));
        arrow.multiply(Matrix4.rotationZ(math.pi / 2));
      case MorphPopoverArrowEdge.right:
        arrow.setFrom(around(Offset(content.right, c + w / 2)));
        arrow.multiply(Matrix4.rotationZ(-math.pi / 2));
    }
    if (opacity <= 0) return;
    context.paintChild(0, transform: arrow, opacity: opacity);
    context.paintChild(1, transform: around(content.topLeft));
  }

  @override
  bool shouldRepaint(_PopoverFlow oldDelegate) =>
      oldDelegate.source != source ||
      oldDelegate.padding != padding ||
      oldDelegate.direction != direction ||
      oldDelegate.motion != motion;

  @override
  bool shouldRelayout(_PopoverFlow oldDelegate) =>
      oldDelegate.padding != padding;
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    path.moveTo(-1, 0);
    path.cubicTo(w * 0.18, 0, w * 0.26, h * 0.12, w * 0.36, h * 0.42);
    path.lineTo(w * 0.44, h * 0.86);
    path.quadraticBezierTo(w / 2, h * 1.06, w * 0.56, h * 0.86);
    path.lineTo(w * 0.64, h * 0.42);
    path.cubicTo(w * 0.74, h * 0.12, w * 0.82, 0, w + 1, 0);
    path.close();
    final paint = Paint();
    paint.color = color;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) => oldDelegate.color != color;
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
  final int? highlighted;
  final MorphAlertStyle style;
  final double radius;
  final ValueChanged<MorphAlertAction> onChoose;
  final VoidCallback onSubmit;
  final Listenable frames;
  final double Function() opacity;

  @override
  Widget build(BuildContext context) {
    final glass = MorphGlass.maybeOf(context);
    final brightness = morphBrightnessOf(context);
    final title = this.title;
    final message = this.message;
    final both = title != null && message != null;
    final single = (title ?? message) != null && !both;
    final textWidth = width - 2 * MorphAlertTuning.textInset;
    final header = <Widget>[
      if (title != null)
        Text(
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
      if (both) const SizedBox(height: MorphAlertTuning.titleGap),
      if (message != null)
        Text(
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
    ];
    final fieldWidgets = <Widget>[
      for (var i = 0; i < fields.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: MorphAlertTuning.buttonGap),
          child: _AlertField(
            field: fields[i],
            controller: controllers[i],
            style: style,
            autofocus: i == 0,
            onSubmit: onSubmit,
          ),
        ),
    ];
    final buttons = [
      for (var i = 0; i < actions.length; i++)
        _AlertButton(
          key: buttonKeys[i],
          action: actions[i],
          highlighted: highlighted == i,
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
              padding: EdgeInsets.only(
                top: fieldWidgets.isEmpty && hasHeader
                    ? MorphAlertTuning.buttonInset
                    : fieldWidgets.isEmpty
                    ? MorphAlertTuning.buttonInset
                    : MorphAlertTuning.fieldBottom,
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
    final clipped = ListenableBuilder(
      listenable: frames,
      builder: (BuildContext context, Widget? child) =>
          Opacity(opacity: opacity(), child: child),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: scroll,
      ),
    );
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) =>
                  ListenableBuilder(
                    listenable: frames,
                    builder: (BuildContext context, Widget? _) {
                      final shape = RRect.fromRectAndRadius(
                        Offset.zero & box.biggest,
                        Radius.circular(radius),
                      );
                      if (glass == null) {
                        return CustomPaint(
                          painter: _PlatterPainter(
                            style: style,
                            shape: shape,
                            opacity: opacity(),
                          ),
                        );
                      }
                      return glass.buildSurface(
                        context,
                        MorphGlassSurface(
                          kind: MorphGlassKind.menu,
                          shape: shape,
                          color: style.platterColor,
                          brightness: brightness,
                          opacity: opacity(),
                        ),
                      );
                    },
                  ),
            ),
          ),
          clipped,
        ],
      ),
    );
  }
}

class _PlatterPainter extends CustomPainter {
  const _PlatterPainter({
    required this.style,
    required this.shape,
    required this.opacity,
  });

  final MorphAlertStyle style;
  final RRect shape;
  final double opacity;

  Color _faded(Color c) => c.withValues(alpha: c.a * opacity);

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint();
    shadow.color = _faded(style.shadowColor);
    shadow.maskFilter = const MaskFilter.blur(
      BlurStyle.normal,
      MorphAlertTuning.flatShadowSigma,
    );
    canvas.drawRRect(
      shape.shift(const Offset(0, MorphAlertTuning.flatShadowOffset)),
      shadow,
    );
    final fill = Paint();
    fill.color = _faded(style.platterColor);
    canvas.drawRRect(shape, fill);
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
    required this.highlighted,
    required this.style,
    required this.onChoose,
    super.key,
  });

  final MorphAlertAction action;
  final bool highlighted;
  final MorphAlertStyle style;
  final ValueChanged<MorphAlertAction> onChoose;

  @override
  State<_AlertButton> createState() => _AlertButtonState();
}

class _AlertButtonState extends State<_AlertButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final style = widget.style;
    final base = action.isPreferred && action.enabled
        ? style.preferredColor
        : style.buttonColor;
    final fill = widget.highlighted
        ? base.withValues(alpha: base.a * MorphAlertTuning.pressedFillOpacity)
        : base;
    void activate() => widget.onChoose(action);
    return MorphControlFocus(
      enabled: action.enabled,
      onHighlight: (bool focused) => setState(() => _focused = focused),
      onActivate: activate,
      child: Semantics(
        container: true,
        button: true,
        enabled: action.enabled,
        label: action.title,
        onTap: action.enabled ? activate : null,
        child: ExcludeSemantics(
          child: MorphFocusRing(
            visible: _focused,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: MorphAlertTuning.buttonHeight,
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: MorphAlertTuning.buttonTextInset,
              ),
              decoration: ShapeDecoration(
                color: fill,
                shape: const StadiumBorder(),
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
    );
  }
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
  final MorphAlertStyle style;
  final bool autofocus;
  final VoidCallback onSubmit;

  @override
  State<_AlertField> createState() => _AlertFieldState();
}

class _AlertFieldState extends State<_AlertField> {
  final FocusNode _focus = FocusNode(debugLabel: 'MorphAlertTextField');

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
              listenable: controller,
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
            label: placeholder,
            child: EditableText(
              controller: controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              obscureText: widget.field.obscureText,
              keyboardType: widget.field.keyboardType,
              style: text,
              cursorColor: style.preferredColor,
              backgroundCursorColor: style.placeholderColor,
              maxLines: 1,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => widget.onSubmit(),
            ),
          ),
        ],
      ),
    );
  }
}
