import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/touch_listener.dart';

/// Why a press ended without a release.
@internal
enum MorphPressLoss {
  /// The platform cancelled the pointer.
  platform,

  /// Another gesture, such as an enclosing scrollable's drag, won the
  /// pointer before the control owned it.
  scroll,

  /// The control turned disabled under the finger.
  disabled,
}

/// A crossing of a press's extended bounds, UIKit's drag-exit and
/// drag-enter.
@internal
enum MorphPressEdge {
  /// The finger left the extended bounds.
  exit,

  /// The finger came back inside the extended bounds.
  enter,
}

/// Where a released press ended, UIKit's touch-up-inside and
/// touch-up-outside.
@internal
enum MorphPressEnd {
  /// The finger lifted inside the extended bounds.
  inside,

  /// The finger lifted outside the extended bounds.
  outside,
}

/// Follows one press the way a `UIControl` tracks a touch, without widgets.
///
/// It takes one pointer at a time, and only one pressing exactly
/// [buttons]; every other pointer is ignored until the press ends. The
/// press is inside while the finger stays within the control's box
/// inflated by [slop]; [move] reports the exit and enter edges, [up]
/// whether the release was inside, and [cancel] why a press ended without
/// one. With an infinite [slop] the press never leaves its bounds.
@internal
class MorphPressTracker {
  /// Creates an idle tracker.
  MorphPressTracker({this.buttons = kPrimaryButton, this.slop = .infinity});

  /// The buttons a pointer presses to start a press.
  final int buttons;

  /// How far outside the control's box the finger still counts as inside;
  /// 0 is the exact box. It applies from the next [down].
  double slop;

  int? _pointer;
  Rect _bounds = Rect.zero;
  bool _inside = false;
  MorphPressLoss? _loss;

  /// The tracked pointer, or null while idle.
  int? get pointer => _pointer;

  /// Whether a press is being tracked.
  bool get isTracking => _pointer != null;

  /// Whether the tracked press is inside its extended bounds; false while
  /// idle.
  bool get inside => _pointer != null && _inside;

  /// Why the latest press ended without a release, or null when it was
  /// released or one is being tracked.
  MorphPressLoss? get loss => _loss;

  /// The extended bounds of the tracked press, in the control's
  /// coordinates.
  Rect get bounds => _bounds;

  /// Whether [pointer] is the tracked pointer.
  bool owns(int pointer) => _pointer != null && _pointer == pointer;

  /// Whether a contact of [pointer] pressing [buttons] would start a press.
  bool accepts(int pointer, int buttons) =>
      _pointer == null && buttons == this.buttons;

  /// Starts a press of [pointer] at [local] on a control of [size], and
  /// returns whether it was accepted; a finite [slop] needs the [size].
  bool down(int pointer, int buttons, Offset local, {Size size = Size.zero}) {
    if (!accepts(pointer, buttons)) return false;
    _pointer = pointer;
    _bounds = (Offset.zero & size).inflate(slop);
    _inside = true;
    _loss = null;
    return true;
  }

  /// Moves the tracked press to [local] and returns the edge it crossed,
  /// or null when it crossed none or [pointer] is not tracked.
  MorphPressEdge? move(int pointer, Offset local) {
    if (!owns(pointer)) return null;
    final inside = _bounds.contains(local);
    if (inside == _inside) return null;
    _inside = inside;
    return inside ? .enter : .exit;
  }

  /// Ends the tracked press with a release at [local] and returns where it
  /// ended, or null when [pointer] is not tracked.
  MorphPressEnd? up(int pointer, Offset local) {
    if (!owns(pointer)) return null;
    move(pointer, local);
    final inside = _inside;
    release();
    return inside ? .inside : .outside;
  }

  /// Ends the tracked press of [pointer] for [why] and returns it, or null
  /// when [pointer] is not tracked.
  MorphPressLoss? cancel(int pointer, MorphPressLoss why) {
    if (!owns(pointer)) return null;
    release();
    return _loss = why;
  }

  /// Ends whatever press is tracked for [why] and returns it, or null
  /// while idle.
  MorphPressLoss? cancelActive(MorphPressLoss why) {
    final pointer = _pointer;
    return pointer == null ? null : cancel(pointer, why);
  }

  /// Forgets the tracked press without a release or a loss, for a gesture
  /// that ended before its pointer lifted.
  void release() {
    _pointer = null;
    _inside = false;
  }
}

/// What [MorphPress] reports a control's pointer events to.
@internal
abstract interface class MorphPressTarget {
  /// A pointer came into contact, or was handed over by the arena.
  void pressDown(PointerDownEvent event);

  /// A pointer moved.
  void pressMove(PointerMoveEvent event);

  /// A pointer lifted.
  void pressUp(PointerUpEvent event);

  /// The platform cancelled a pointer.
  void pressCancel(PointerCancelEvent event);

  /// Another gesture won a pointer the control never owned.
  void pressLost(PointerCancelEvent event);
}

/// The one input path of a pressable control: keyboard focus and
/// activation, semantics and touches in the gesture arena.
///
/// The control takes keyboard focus while [enabled] and [focusable]: Space and Enter call
/// [onActivate], what a tap does; the left and right arrows, and the up
/// and down arrows when [verticalSteps], call [onStep] with the visual
/// direction (-1 for left or down). [onHighlight] reports whether the
/// keyboard focus ring should show, which is while the control has focus
/// and the keyboard drives it; with [focusRing] the ring is drawn here
/// around [child]. With [semantics] the control is annotated with them.
/// With a [target] every touch goes through a [MorphTouchListener] with
/// [dragAxis], [delaysInScrollable] and [behavior], and reaches the
/// target, which tracks its press with a [MorphPressTracker].
///
/// The focus node sits under the nearest enclosing [Focus] or
/// [FocusScope] and follows it when that widget changes its node.
///
/// It adds no render object besides the [semantics], the focus
/// annotation (unless [focusSemantics] or [focusable] is false) and the
/// touch listener, and builds again only when the ring it draws turns on
/// or off: the ring
/// is inserted only while it shows, with [child] kept across the
/// insertion, so a surface that repaints every frame pays nothing for
/// being focusable.
@internal
class MorphPress extends StatefulWidget {
  /// Creates the input path around [child].
  const MorphPress({
    required this.child,
    this.target,
    this.enabled = true,
    this.focusable = true,
    this.touchEnabled,
    this.onActivate,
    this.onStep,
    this.verticalSteps = false,
    this.onHighlight,
    this.focusRing = false,
    this.focusSemantics = true,
    this.semantics,
    this.semanticsContainer = false,
    this.explicitChildNodes = false,
    this.dragAxis,
    this.delaysInScrollable = false,
    this.behavior = HitTestBehavior.deferToChild,
    this.withdrawn,
    super.key,
  });

  /// Whether the control is on its way out of the screen, or null for one
  /// that stays: while it reads true the control takes no keyboard focus
  /// and gives up the focus it has, without a build.
  final ValueListenable<bool>? withdrawn;

  /// Where touches go, or null for a control that tracks them itself.
  final MorphPressTarget? target;

  /// Whether the control takes focus, and touches unless [touchEnabled]
  /// says otherwise.
  final bool enabled;

  /// Whether the control takes keyboard focus at all; false leaves the
  /// focus to a [child] that takes it itself.
  final bool focusable;

  /// Whether touches enter the gesture arena; null follows [enabled].
  final bool? touchEnabled;

  /// Called on Space or Enter: what a tap does.
  final VoidCallback? onActivate;

  /// Called on an arrow key with the visual direction.
  final ValueChanged<int>? onStep;

  /// Whether the up and down arrows step too.
  final bool verticalSteps;

  /// Called when the keyboard focus ring should show or hide.
  final ValueChanged<bool>? onHighlight;

  /// Whether the focus ring is drawn around [child] here.
  final bool focusRing;

  /// Whether the focus is reported to accessibility services as a
  /// focusable node; false for a control whose own [Semantics] above
  /// excludes what is below it.
  final bool focusSemantics;

  /// The semantics of the control, or null for none added here.
  final SemanticsProperties? semantics;

  /// Whether [semantics] form a node of their own.
  final bool semanticsContainer;

  /// Whether the children of the [semantics] node stay separate nodes.
  final bool explicitChildNodes;

  /// The axis the control is dragged along, or null for a pressed one.
  final Axis? dragAxis;

  /// Whether a touch inside a [Scrollable] is held back until the control
  /// owns it.
  final bool delaysInScrollable;

  /// How the touch listener behaves during hit testing.
  final HitTestBehavior behavior;

  /// The control.
  final Widget child;

  @override
  StatefulElement createElement() => _MorphPressElement(this);

  @override
  State<MorphPress> createState() => _MorphPressState();
}

// The enclosing focus scope notifies its dependents on every focus change
// under it, such as a menu or sheet opening over the control. What the
// state reads from inherited widgets (the parent focus node and the
// navigation mode) needs no build, so a changed dependency is applied
// here instead of marking the element dirty, which is all the skipped
// super does. The state's build reads no other inherited widget.
class _MorphPressElement extends StatefulElement {
  _MorphPressElement(MorphPress super.widget);

  @override
  // ignore: must_call_super
  void didChangeDependencies() =>
      (state as _MorphPressState)._dependenciesChanged();
}

const List<SingleActivator> _activators = [
  SingleActivator(LogicalKeyboardKey.space),
  SingleActivator(LogicalKeyboardKey.enter),
];

const List<(SingleActivator, int, bool)> _steps = [
  (SingleActivator(LogicalKeyboardKey.arrowLeft), -1, false),
  (SingleActivator(LogicalKeyboardKey.arrowRight), 1, false),
  (SingleActivator(LogicalKeyboardKey.arrowDown), -1, true),
  (SingleActivator(LogicalKeyboardKey.arrowUp), 1, true),
];

// The focus node is attached here rather than through a [Focus] widget:
// a [Focus] rebuilds itself and its inherited scope whenever an ancestor
// blocks or unblocks focus (every menu or sheet that opens over the
// control) and paints a semantics annotation, while this rebuilds only
// when the ring it draws turns on or off.
class _MorphPressState extends State<MorphPress> {
  final GlobalKey _child = GlobalKey();
  late final FocusNode _node = FocusNode(debugLabel: 'MorphPress');
  late final FocusAttachment _attachment = _node.attach(
    context,
    onKeyEvent: _key,
  );
  bool _hasFocus = false;
  bool _highlighted = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_focusChanged);
    FocusManager.instance.addHighlightModeListener(_modeChanged);
    widget.withdrawn?.addListener(_withdrawnChanged);
  }

  void _withdrawnChanged() => _node.canRequestFocus = _canRequestFocus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependenciesChanged();
  }

  void _dependenciesChanged() {
    _reparent();
    _node.canRequestFocus = _canRequestFocus;
  }

  @override
  void didUpdateWidget(MorphPress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.withdrawn, widget.withdrawn)) {
      oldWidget.withdrawn?.removeListener(_withdrawnChanged);
      widget.withdrawn?.addListener(_withdrawnChanged);
      _node.canRequestFocus = _canRequestFocus;
    }
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.focusable != widget.focusable) {
      _node.canRequestFocus = _canRequestFocus;
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted) _update();
      });
    }
  }

  @override
  void deactivate() {
    super.deactivate();
    _attachment.reparent();
  }

  @override
  void dispose() {
    widget.withdrawn?.removeListener(_withdrawnChanged);
    FocusManager.instance.removeHighlightModeListener(_modeChanged);
    _node.removeListener(_focusChanged);
    _attachment.detach();
    _node.dispose();
    super.dispose();
  }

  void _reparent() =>
      _attachment.reparent(parent: Focus.maybeOf(context, scopeOk: true));

  void _modeChanged(FocusHighlightMode mode) => _update();

  void _focusChanged() {
    if (_node.hasFocus == _hasFocus) return;
    _hasFocus = _node.hasFocus;
    _update();
  }

  void _update() {
    final show =
        widget.enabled &&
        _hasFocus &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    if (show == _highlighted) return;
    if (widget.focusRing) {
      setState(() => _highlighted = show);
    } else {
      _highlighted = show;
    }
    widget.onHighlight?.call(show);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final activate = widget.onActivate;
    if (activate != null &&
        _activators.any((SingleActivator a) => a.accepts(event, keyboard))) {
      activate();
      return KeyEventResult.handled;
    }
    final step = widget.onStep;
    if (step != null) {
      for (final (activator, delta, vertical) in _steps) {
        if (vertical && !widget.verticalSteps) continue;
        if (!activator.accepts(event, keyboard)) continue;
        step(delta);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  bool get _canRequestFocus =>
      widget.focusable &&
      !(widget.withdrawn?.value ?? false) &&
      switch (MediaQuery.maybeNavigationModeOf(context)) {
        NavigationMode.directional => true,
        NavigationMode.traditional || null => widget.enabled,
      };

  SemanticsProperties _focusSemantics() {
    final focusable = _node.canRequestFocus;
    return SemanticsProperties(
      onFocus: defaultTargetPlatform != TargetPlatform.iOS && focusable
          ? _node.requestFocus
          : null,
      focused: focusable ? _node.hasPrimaryFocus : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    _reparent();
    var child = widget.child;
    if (widget.focusRing) {
      child = KeyedSubtree(key: _child, child: child);
      if (_highlighted) child = MorphFocusRing(visible: true, child: child);
    }
    final target = widget.target;
    if (target != null) {
      child = MorphTouchListener(
        enabled: widget.touchEnabled ?? widget.enabled,
        dragAxis: widget.dragAxis,
        delaysInScrollable: widget.delaysInScrollable,
        behavior: widget.behavior,
        onPointerDown: target.pressDown,
        onPointerMove: target.pressMove,
        onPointerUp: target.pressUp,
        onPointerCancel: target.pressCancel,
        onPointerLost: target.pressLost,
        child: child,
      );
    }
    final semantics = widget.semantics;
    if (semantics != null) {
      child = Semantics.fromProperties(
        container: widget.semanticsContainer,
        explicitChildNodes: widget.explicitChildNodes,
        properties: semantics,
        child: child,
      );
    }
    if (!widget.focusSemantics || !widget.focusable) return child;
    return MorphLiveSemantics(
      live: _node,
      propertiesOf: _focusSemantics,
      child: child,
    );
  }
}
