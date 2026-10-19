import 'package:flutter/foundation.dart';

/// A control's motion: its host advances it to the time of a frame or of
/// an input and reads it there, then delivers the events it raised.
///
/// A command (a touch, a value set by the app) takes its own time and
/// advances the motion to it first; reads take no time and answer for
/// [time]. Events of type [E] queue until [drainEvents]: the host drains
/// them after each command, before its input handler returns, and after
/// each frame's [advance], before the frame is published, so callbacks and
/// haptics keep the order and the synchrony of the input that caused them.
abstract interface class MorphMotion<E extends Object> {
  /// The time the motion was last advanced to, in seconds.
  double get time;

  /// Advances the motion to [t]; an earlier [t] changes nothing.
  void advance(double t);

  /// Whether nothing visible moves any more.
  bool get isSettled;

  /// The time before which the motion changes nothing on its own, or null
  /// when it changes every frame.
  double? get wakeTime;

  /// Lands what remains of a settled motion on its targets.
  void settle();

  /// The events raised since the last call, oldest first.
  List<E> drainEvents();
}

/// The queue behind [MorphMotion.drainEvents].
mixin MorphMotionEvents<E extends Object> {
  final List<E> _events = [];

  /// Queues [event] for the host.
  @protected
  void emit(E event) => _events.add(event);

  /// The events raised since the last call, oldest first.
  List<E> drainEvents() {
    if (_events.isEmpty) return const [];
    final drained = List<E>.of(_events);
    _events.clear();
    return drained;
  }
}
