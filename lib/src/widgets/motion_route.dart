import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// A route whose widget motion determines when a pop finishes.
@internal
mixin MorphMotionRouteMixin<T> on TransitionRoute<T> {
  bool _motionFinished = false;

  /// Whether the current presentation uses a widget motion.
  bool get usesMotionRoute => true;

  /// Starts dismissal and returns whether a mounted view drives it.
  bool leaveMotionRoute();

  /// Resolves the result of a dismissal.
  T? motionRouteResult(T? result) => result;

  /// Receives the result before dismissal starts.
  void motionRouteDidPop(T? result) {}

  /// Runs after the route's dismissal finishes.
  void motionRouteDidFinish() {}

  /// Dismisses this route, preserving routes pushed above it.
  void popMotionRoute([T? result]) {
    final nav = navigator;
    if (nav == null || !isActive) return;
    if (isCurrent) {
      nav.maybePop<T>(result);
    } else {
      final resolved = motionRouteResult(result);
      motionRouteDidPop(resolved);
      nav.removeRoute(this, resolved);
      _finishCallback();
    }
  }

  @override
  bool didPop(T? result) {
    if (!usesMotionRoute) return super.didPop(result);
    final resolved = motionRouteResult(result);
    final popped = super.didPop(resolved);
    if (!popped) return false;
    motionRouteDidPop(resolved);
    controller?.stop();
    if (!leaveMotionRoute()) finishMotionRoute();
    return true;
  }

  /// Finalizes a popped route once its widget motion rests.
  void finishMotionRoute() {
    final c = controller;
    if (c != null && !isActive && c.value != 0) c.value = 0;
    _finishCallback();
  }

  void _finishCallback() {
    if (_motionFinished) return;
    _motionFinished = true;
    motionRouteDidFinish();
  }
}
