import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/press.dart';

/// Hosts a measured control on one clock with one active primary pointer.
///
/// Motions remain pure: subclasses advance them and report settlement to
/// [MorphClock], which sleeps between gestures. The host is the
/// [MorphPressTarget] of the control's [MorphPress] and follows its press
/// with a [MorphPressTracker]; pointer hooks receive motion time, while
/// keyboard focus and cancellation on disable belong to the host.
@internal
abstract class MorphControlHost<T extends StatefulWidget> extends State<T>
    with SingleTickerProviderStateMixin<T>, MorphClock<T>
    implements MorphPressTarget {
  final MorphPressTracker _press = MorphPressTracker();
  bool _focused = false;

  /// Whether this control accepts a new pointer gesture.
  ///
  /// This can differ from keyboard availability: a disabled tab still swells
  /// its bar without selecting an item.
  bool get controlEnabled;

  /// Whether moves and releases advance the event clock before a frame.
  ///
  /// Repeat-only controls use the latest frame for these events instead.
  bool get stampPointerUpdates => true;

  /// How far outside the control's box a press still counts as inside
  /// [press]; infinite by default, so a press never leaves.
  double get pressSlop => .infinity;

  /// The press of the active pointer.
  @protected
  MorphPressTracker get press => _press;

  /// Whether the keyboard focus ring is visible.
  bool get controlFocused => _focused;

  /// Updates the keyboard focus highlight.
  ValueChanged<bool> get highlightControlFocus => (bool focused) {
    setState(() => _focused = focused);
  };

  /// Whether [event] belongs to the active gesture.
  bool ownsPointer(PointerEvent event) => _press.owns(event.pointer);

  /// Whether the primary contact hits this control's handle.
  bool acceptsControlPointer(PointerDownEvent event) => true;

  /// Starts the accepted gesture at motion time [t].
  void onControlDown(double t, PointerDownEvent event);

  /// Moves the active gesture at motion time [t].
  void onControlMove(double t, PointerMoveEvent event);

  /// Releases the active gesture at motion time [t].
  void onControlUp(double t, PointerUpEvent event);

  /// Releases the active gesture beyond [pressSlop] at motion time [t];
  /// a release like any other unless the control overrides it.
  void onControlUpOutside(double t, PointerUpEvent event) =>
      onControlUp(t, event);

  /// Cancels the active gesture at motion time [t], including on disable.
  void onControlCancel(double t);

  /// Cancels a gesture lost to a scrollable at motion time [t].
  void onControlLost(double t) => onControlCancel(t);

  /// Releases ownership when a gesture ends before its pointer lifts.
  void releaseControlPointer() => _press.release();

  /// Accepts a primary contact when enabled and no pointer is active.
  @override
  void pressDown(PointerDownEvent event) {
    if (!controlEnabled ||
        !_press.accepts(event.pointer, event.buttons) ||
        !acceptsControlPointer(event)) {
      return;
    }
    final slop = pressSlop;
    _press.slop = slop;
    _press.down(
      event.pointer,
      event.buttons,
      event.localPosition,
      size: slop.isFinite ? _size() : Size.zero,
    );
    onControlDown(stamp(event), event);
    deliverMotionEvents();
  }

  Size _size() {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size : Size.zero;
  }

  /// Dispatches a move belonging to the active pointer.
  @override
  void pressMove(PointerMoveEvent event) {
    if (!ownsPointer(event)) return;
    _press.move(event.pointer, event.localPosition);
    onControlMove(_eventTime(event), event);
    deliverMotionEvents();
  }

  /// Releases ownership before dispatching the active pointer's lift,
  /// inside or beyond [pressSlop].
  @override
  void pressUp(PointerUpEvent event) {
    switch (_press.up(event.pointer, event.localPosition)) {
      case null:
        return;
      case .inside:
        onControlUp(_eventTime(event), event);
      case .outside:
        onControlUpOutside(_eventTime(event), event);
    }
    deliverMotionEvents();
  }

  /// Releases ownership and cancels the active pointer.
  @override
  void pressCancel(PointerCancelEvent event) {
    if (_press.cancel(event.pointer, .platform) == null) return;
    onControlCancel(_eventTime(event));
    deliverMotionEvents();
  }

  /// Releases ownership and reports loss of the active pointer.
  @override
  void pressLost(PointerCancelEvent event) {
    if (_press.cancel(event.pointer, .scroll) == null) return;
    onControlLost(_eventTime(event));
    deliverMotionEvents();
  }

  double _eventTime(PointerEvent event) =>
      stampPointerUpdates ? stamp(event) : clock;

  bool Function()? _reconcile;
  bool Function()? _reconcileDefer;

  /// Calls [apply] after the current frame, once however often this is
  /// called before then, so the parent's callbacks and the rebuild they
  /// cause have run: a parent that rejects or adjusts a reported value is
  /// reconciled with the motion. The latest [apply] and [defer] win.
  ///
  /// While [defer] answers true, the call moves to the end of the next
  /// frame; a control defers while its gesture leads the value. [apply]
  /// returns whether it changed the motion, which then wakes the clock.
  void reconcileAfterFrame(bool Function() apply, {bool Function()? defer}) {
    final pending = _reconcile != null;
    _reconcile = apply;
    _reconcileDefer = defer;
    if (!pending) _scheduleReconcile();
  }

  void _scheduleReconcile() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_reconcileDefer?.call() ?? false) {
        _scheduleReconcile();
        return;
      }
      final apply = _reconcile;
      _reconcile = null;
      _reconcileDefer = null;
      if (apply != null && apply()) wake();
    });
  }

  Widget? _built;
  bool _stale = true;
  Object? _builtFrom;

  /// Whether the control built from [oldWidget] is the one the current
  /// widget builds: every field the build reads compares equal, and
  /// callbacks count only by whether they are set, since the control calls
  /// the current widget's. False by default: every update builds again.
  @protected
  bool buildsLike(T oldWidget) => false;

  /// The state the build reads besides the widget, the dependencies and
  /// what changes through [setState], read after [buildControl] so state
  /// the build itself settles counts; the last build is reused only while
  /// it compares equal.
  @protected
  Object? get buildInputs => null;

  /// Builds the control. [build] hands back the last result while the
  /// widget builds alike, no dependency changed, [setState] was not called
  /// and [buildInputs] compare equal: the parent rebuilding the control
  /// unchanged then costs nothing below it.
  @protected
  Widget buildControl(BuildContext context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stale = true;
  }

  @override
  void setState(VoidCallback fn) {
    _stale = true;
    super.setState(fn);
  }

  @override
  void reassemble() {
    _stale = true;
    super.reassemble();
  }

  @override
  Widget build(BuildContext context) {
    final built = _built;
    final inputs = buildInputs;
    if (built != null && !_stale && inputs == _builtFrom) return built;
    _stale = false;
    final control = buildControl(context);
    _builtFrom = buildInputs;
    return _built = control;
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!buildsLike(oldWidget)) _stale = true;
    if (!controlEnabled && _press.cancelActive(.disabled) != null) {
      onControlCancel(clock);
      wake();
    }
  }
}
