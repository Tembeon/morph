import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// How long a touch must stay down before its control owns it, the delay
/// a UIKit scroll view waits before it delivers a touch to its content.
@internal
const Duration morphTouchOwnershipDelay = Duration(milliseconds: 150);

/// A gesture-arena member that claims a control's touches the way UIKit
/// hands touches to a control inside a scroll view.
///
/// Every pointer joins the arena on contact and is claimed when it has
/// stayed down for [delay], or, with an [axis], as soon as it travels
/// past the touch slop along that axis. A claimed pointer belongs to the
/// control for the rest of its contact: the arena rejects every other
/// member, so an enclosing scrollable never takes it. A pointer some
/// other member wins first, such as a scrollable's drag after a quick
/// swipe, is reported through [onLost] while it is still down.
///
/// With [claimsOnDelay] false the delay only arms the claim: a pointer
/// that stayed inside the touch slop for the whole delay is claimed by
/// its first move past the slop, so a still press keeps losing to the
/// recognizers of the content below it (a tap, a long press) while a
/// held finger that starts to wander is never taken by a scrollable.
@internal
class MorphTouchRecognizer extends OneSequenceGestureRecognizer {
  /// Creates the recognizer.
  MorphTouchRecognizer({
    super.debugOwner,
    super.allowedButtonsFilter,
    this.delay = morphTouchOwnershipDelay,
    this.claimsOnDelay = true,
  });

  /// How long a pointer stays down before it is claimed.
  final Duration delay;

  /// Whether the [delay] claims a pointer by itself, rather than arming
  /// the claim for the pointer's first move past the touch slop.
  final bool claimsOnDelay;

  /// The axis whose drag claims the pointers added from now on past the
  /// touch slop, or null when only the [delay] does.
  Axis? axis;

  /// Called when the arena gives a pointer to this recognizer.
  ValueChanged<int>? onOwned;

  /// Called when another arena member wins a pointer that is still down.
  ValueChanged<int>? onLost;

  final Map<int, _Touch> _touches = {};

  /// Whether [pointer] is down and owned by this recognizer.
  bool owns(int pointer) => _touches[pointer]?.owned ?? false;

  /// Claims [pointer] at once if it is still undecided.
  void claim(int pointer) {
    final touch = _touches[pointer];
    if (touch == null || touch.owned) return;
    resolvePointer(pointer, GestureDisposition.accepted);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    final pointer = event.pointer;
    _touches[pointer]?.timer?.cancel();
    _touches[pointer] = _Touch(
      origin: event.localPosition,
      axis: axis,
      slop: computeHitSlop(event.kind, gestureSettings),
      timer: Timer(delay, () => _matured(pointer)),
    );
  }

  void _matured(int pointer) {
    final touch = _touches[pointer];
    if (touch == null) return;
    touch.timer = null;
    if (claimsOnDelay) {
      claim(pointer);
    } else if (!touch.wandered) {
      touch.armed = true;
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    final touch = _touches[event.pointer];
    if (touch != null && !touch.owned && event is PointerMoveEvent) {
      final delta = event.localPosition - touch.origin;
      final travel = switch (touch.axis) {
        Axis.horizontal => delta.dx.abs(),
        Axis.vertical => delta.dy.abs(),
        null => 0.0,
      };
      final past = delta.distance > touch.slop;
      if (travel > touch.slop || (touch.armed && past)) {
        claim(event.pointer);
      } else if (past) {
        touch.wandered = true;
      }
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _touches.remove(event.pointer)?.timer?.cancel();
    }
    stopTrackingIfPointerNoLongerDown(event);
  }

  @override
  void acceptGesture(int pointer) {
    final touch = _touches[pointer];
    if (touch == null || touch.owned) return;
    touch.timer?.cancel();
    touch.timer = null;
    touch.owned = true;
    onOwned?.call(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    final touch = _touches.remove(pointer);
    if (touch == null) return;
    touch.timer?.cancel();
    stopTrackingPointer(pointer);
    onLost?.call(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void dispose() {
    for (final touch in _touches.values) {
      touch.timer?.cancel();
    }
    _touches.clear();
    super.dispose();
  }

  @override
  String get debugDescription => 'morph touch';
}

class _Touch {
  _Touch({
    required this.origin,
    required this.axis,
    required this.slop,
    required this.timer,
  });

  final Offset origin;
  final Axis? axis;
  final double slop;
  Timer? timer;
  bool owned = false;
  bool wandered = false;
  bool armed = false;
}

/// A raw pointer listener for a measured control that takes part in the
/// gesture arena the way a UIKit control takes part in a scroll view.
///
/// It reports pointer events like a [Listener], so the control reacts on
/// contact, and enters every touch into the gesture arena through a
/// [MorphTouchRecognizer]. The control owns a touch once it has been
/// held for [morphTouchOwnershipDelay], or, for a control with a
/// [dragAxis], once it drags past the touch slop along that axis; an
/// owned touch keeps going to the control however it moves, and no
/// enclosing scrollable takes it. The drag axis claims only while no
/// enclosing [Scrollable] scrolls along the same axis - there the delay
/// alone decides, as it does in UIKit. A touch the arena gives to
/// someone else first, such as a list's drag after a quick swipe, is
/// reported as cancelled at its last position and the rest of its
/// events are dropped: a swipe that scrolls a list never toggles,
/// presses or selects the control it started on.
@internal
class MorphTouchListener extends StatefulWidget {
  /// Creates the listener.
  const MorphTouchListener({
    required this.child,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onPointerCancel,
    this.onPointerLost,
    this.dragAxis,
    this.enabled = true,
    this.behavior = HitTestBehavior.deferToChild,
    super.key,
  });

  /// Called when a pointer comes into contact.
  final PointerDownEventListener? onPointerDown;

  /// Called when a tracked pointer moves.
  final PointerMoveEventListener? onPointerMove;

  /// Called when a tracked pointer leaves contact.
  final PointerUpEventListener? onPointerUp;

  /// Called when a tracked pointer is cancelled, by the platform or by
  /// another gesture that won it.
  final PointerCancelEventListener? onPointerCancel;

  /// Called instead of [onPointerCancel] when another gesture won a
  /// tracked pointer the control never owned; null reports the loss
  /// through [onPointerCancel].
  final PointerCancelEventListener? onPointerLost;

  /// The axis the control is dragged along, or null for a control that
  /// is only pressed.
  final Axis? dragAxis;

  /// Whether the control takes its touches into the gesture arena; a
  /// disabled control still hears them but leaves them to the gestures
  /// around it.
  final bool enabled;

  /// How the listener behaves during hit testing.
  final HitTestBehavior behavior;

  /// The control.
  final Widget child;

  @override
  State<MorphTouchListener> createState() => _MorphTouchListenerState();
}

class _MorphTouchListenerState extends State<MorphTouchListener> {
  late final MorphTouchRecognizer _arena = MorphTouchRecognizer(
    debugOwner: this,
  );
  final Map<int, PointerEvent> _down = {};
  final Set<int> _yielded = {};

  @override
  void initState() {
    super.initState();
    _arena.onLost = _lost;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _arena.gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
  }

  @override
  void dispose() {
    _arena.dispose();
    super.dispose();
  }

  Axis? _claimAxis() {
    final axis = widget.dragAxis;
    if (axis == null) return null;
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      if (axisDirectionToAxis(scrollable.axisDirection) == axis) return null;
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    return axis;
  }

  void _lost(int pointer) {
    final event = _down.remove(pointer);
    if (event == null) return;
    _yielded.add(pointer);
    final report = widget.onPointerLost ?? widget.onPointerCancel;
    report?.call(
      PointerCancelEvent(
        timeStamp: event.timeStamp,
        pointer: event.pointer,
        kind: event.kind,
        device: event.device,
        position: event.position,
      ).transformed(event.transform),
    );
  }

  void _pointerDown(PointerDownEvent event) {
    _yielded.remove(event.pointer);
    _down[event.pointer] = event;
    widget.onPointerDown?.call(event);
    if (!widget.enabled) return;
    _arena.axis = _claimAxis();
    _arena.addPointer(event);
  }

  void _pointerMove(PointerMoveEvent event) {
    if (_yielded.contains(event.pointer)) return;
    if (_down.containsKey(event.pointer)) _down[event.pointer] = event;
    widget.onPointerMove?.call(event);
  }

  void _pointerUp(PointerUpEvent event) {
    if (_yielded.remove(event.pointer)) return;
    _down.remove(event.pointer);
    widget.onPointerUp?.call(event);
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (_yielded.remove(event.pointer)) return;
    _down.remove(event.pointer);
    widget.onPointerCancel?.call(event);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: widget.behavior,
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerCancel,
      child: widget.child,
    );
  }
}
