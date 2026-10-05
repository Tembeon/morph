import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/clock.dart';

/// Hosts a measured control on one clock with one active primary pointer.
///
/// Motions remain pure: subclasses advance them and report settlement to
/// [MorphClock], which sleeps between gestures. Pointer hooks receive motion
/// time, while keyboard focus and cancellation on disable belong to the host.
@internal
abstract class MorphControlHost<T extends StatefulWidget> extends State<T>
    with SingleTickerProviderStateMixin<T>, MorphClock<T> {
  int? _pointer;
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

  /// Whether the keyboard focus ring is visible.
  bool get controlFocused => _focused;

  /// Updates the keyboard focus highlight.
  ValueChanged<bool> get highlightControlFocus => (bool focused) {
    setState(() => _focused = focused);
  };

  /// Whether [event] belongs to the active gesture.
  bool ownsPointer(PointerEvent event) => event.pointer == _pointer;

  /// Whether the primary contact hits this control's handle.
  bool acceptsControlPointer(PointerDownEvent event) => true;

  /// Starts the accepted gesture at motion time [t].
  void onControlDown(double t, PointerDownEvent event);

  /// Moves the active gesture at motion time [t].
  void onControlMove(double t, PointerMoveEvent event);

  /// Releases the active gesture at motion time [t].
  void onControlUp(double t, PointerUpEvent event);

  /// Cancels the active gesture at motion time [t], including on disable.
  void onControlCancel(double t);

  /// Cancels a gesture lost to a scrollable at motion time [t].
  void onControlLost(double t) => onControlCancel(t);

  /// Releases ownership when a gesture ends before its pointer lifts.
  void releaseControlPointer() {
    _pointer = null;
  }

  /// Accepts a primary contact when enabled and no pointer is active.
  void handleDown(PointerDownEvent event) {
    if (!controlEnabled ||
        event.buttons != kPrimaryButton ||
        _pointer != null ||
        !acceptsControlPointer(event)) {
      return;
    }
    _pointer = event.pointer;
    onControlDown(stamp(event), event);
  }

  /// Dispatches a move belonging to the active pointer.
  void handleMove(PointerMoveEvent event) {
    if (!ownsPointer(event)) return;
    onControlMove(_eventTime(event), event);
  }

  /// Releases ownership before dispatching the active pointer's lift.
  void handleUp(PointerUpEvent event) {
    if (!ownsPointer(event)) return;
    releaseControlPointer();
    onControlUp(_eventTime(event), event);
  }

  /// Releases ownership and cancels the active pointer.
  void handleCancel(PointerCancelEvent event) {
    if (!ownsPointer(event)) return;
    releaseControlPointer();
    onControlCancel(_eventTime(event));
  }

  /// Releases ownership and reports loss of the active pointer.
  void handleLost(PointerCancelEvent event) {
    if (!ownsPointer(event)) return;
    releaseControlPointer();
    onControlLost(_eventTime(event));
  }

  double _eventTime(PointerEvent event) =>
      stampPointerUpdates ? stamp(event) : clock;

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
  /// what changes through [setState]; the last build is reused only while
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
    _builtFrom = inputs;
    return _built = buildControl(context);
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!buildsLike(oldWidget)) _stale = true;
    if (!controlEnabled && _pointer != null) {
      releaseControlPointer();
      onControlCancel(clock);
      wake();
    }
  }
}
