import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The lifecycle of a route whose presentation motion lives in its page.
///
/// With [projectsMotion] the route's [animation] follows the phases of
/// the page's motion instead of the route controller: it is forward while
/// the page opens, completed once it rests open, reverse while it leaves
/// and dismissed when it is gone, which finalizes the route. [didPush]'s
/// future completes at the open's rest, so a `pushReplacement` keeps the
/// replaced route until the new one is visibly in place.
///
/// Only the status follows the motion. The value is 1 from the push until
/// the route is gone; a value that moved with the motion would rebuild
/// the route's modal scaffolding on every frame it changed.
@internal
mixin MorphMotionRouteMixin<T> on TransitionRoute<T> {
  bool _motionFinished = false;
  late final _MotionProjection _projection = _MotionProjection();
  Ticker? _settle;

  /// Whether the route runs its presentation in its page.
  bool get usesMotionRoute => true;

  /// Whether [animation] projects the page's motion.
  bool get projectsMotion => false;

  /// Starts the page's leaving motion; false when there is no page to
  /// leave, which finishes the route at once.
  bool leaveMotionRoute();

  /// The result a pop completes with.
  T? motionRouteResult(T? result) => result;

  /// Called when the route is popped, with its resolved result.
  void motionRouteDidPop(T? result) {}

  /// Called once when the route's leaving motion has finished.
  void motionRouteDidFinish() {}

  @override
  Animation<double> createAnimation() =>
      projectsMotion ? _projection : super.createAnimation();

  @override
  bool get finishedWhenPopped =>
      projectsMotion ? false : super.finishedWhenPopped;

  @override
  TickerFuture didPush() {
    if (!projectsMotion) return super.didPush();
    _projection.update(1, AnimationStatus.forward);
    final settle = _settle = Ticker((_) {});
    settle.muted = true;
    final opened = settle.start();
    super.didPush();
    return opened;
  }

  @override
  void didAdd() {
    super.didAdd();
    if (projectsMotion) _projection.update(1, AnimationStatus.completed);
  }

  @override
  void didReplace(Route<Object?>? oldRoute) {
    super.didReplace(oldRoute);
    if (projectsMotion) _projection.update(1, AnimationStatus.completed);
  }

  /// Reports that the page's open motion came to rest.
  void reportMotionOpened() {
    if (!projectsMotion || !isActive) return;
    if (_projection.status == AnimationStatus.reverse) return;
    _projection.update(1, AnimationStatus.completed);
    _completeSettle();
  }

  /// Pops this route if it is current, or removes it from under the
  /// routes above it, with [result].
  Future<void> popMotionRoute([T? result]) async {
    final nav = navigator;
    if (nav == null || !isActive) return;
    if (isCurrent) {
      await nav.maybePop<T>(result);
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
    if (projectsMotion) {
      _completeSettle();
      _projection.update(_projection.value, AnimationStatus.reverse);
    }
    if (!leaveMotionRoute()) finishMotionRoute();
    return true;
  }

  /// Ends the route once its leaving motion has finished.
  void finishMotionRoute() {
    if (projectsMotion) {
      _completeSettle();
      if (!isActive) _projection.update(0, AnimationStatus.dismissed);
    } else {
      final c = controller;
      if (c != null && !isActive && c.value != 0) c.value = 0;
    }
    _finishCallback();
  }

  void _completeSettle() {
    final settle = _settle;
    if (settle != null && settle.isActive) settle.stop(canceled: false);
  }

  void _finishCallback() {
    if (_motionFinished) return;
    _motionFinished = true;
    motionRouteDidFinish();
  }

  @override
  void dispose() {
    _settle?.dispose();
    super.dispose();
    if (projectsMotion) _projection.dispose();
  }
}

class _MotionProjection extends Animation<double> with ChangeNotifier {
  final _statusListeners = <AnimationStatusListener>[];
  double _value = 0;
  AnimationStatus _status = AnimationStatus.dismissed;

  @override
  double get value => _value;

  @override
  AnimationStatus get status => _status;

  @override
  void addStatusListener(AnimationStatusListener listener) =>
      _statusListeners.add(listener);

  @override
  void removeStatusListener(AnimationStatusListener listener) =>
      _statusListeners.remove(listener);

  void update(double value, AnimationStatus status) {
    final next = value.clamp(0.0, 1.0);
    final changed = next != _value;
    final statusChanged = status != _status;
    _value = next;
    _status = status;
    if (changed) notifyListeners();
    if (statusChanged) {
      for (final listener in List.of(_statusListeners)) {
        listener(status);
      }
    }
  }
}
