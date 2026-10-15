import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/motion.dart' show MorphZoomMotion;
// ignore: implementation_imports
import 'package:morph/src/widgets/clock.dart';

/// The two SDK integration strategies compared by prototype P1.
enum ProbeRouteDriver {
  /// A route-owned clock publishes a separate SDK animation.
  projected,

  /// The SDK controller samples the measured motion as a simulation.
  sdkController,
}

/// A reduced zoom sheet for lifecycle experiments, outside the package API.
class ProbeSheetRoute<T> extends PageRoute<T> {
  /// Creates a sheet with a stable content subtree and measured zoom motion.
  ProbeSheetRoute({
    required this.builder,
    this.driver = ProbeRouteDriver.projected,
    this.source = const Rect.fromLTWH(120, 220, 140, 48),
    this.eventAge = Duration.zero,
    this.opaque = false,
    super.settings,
  });

  /// Builds the content once per dependency or structural change.
  final WidgetBuilder builder;

  /// The mechanism supplying the route animation.
  final ProbeRouteDriver driver;

  /// The source rectangle in the navigator's coordinate space.
  final Rect source;

  /// Injected input delivery lag; platform timestamp conversion is outside P1.
  final Duration eventAge;

  @override
  final bool opaque;

  MorphZoomMotion _motion = MorphZoomMotion();
  final _projection = _RouteAnimation();
  final _frames = ValueNotifier<int>(0);
  final _grid = MorphFrameGrid();
  final _pushSignal = _SettleSignal();
  Ticker? _ticker;
  double _time = 0;
  double _base = 0;
  bool _opening = true;

  /// The measured motion time of the last sample.
  double get motionTime => _time;

  /// The raw center progress, including overshoot.
  double get rawProgress => _motion.centerProgress(_time);

  /// Whether all measured channels have settled.
  bool get motionSettled => _motion.isSettled;

  /// How many page builds the SDK requested.
  int pageBuilds = 0;

  /// How many motion frames were published.
  int motionFrames = 0;

  /// Whether disposal has completed.
  bool disposed = false;

  /// Samples the measured rectangle without changing the motion.
  Rect rectangle(Rect destination) => _motion.rect(_time, source, destination);

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  bool get finishedWhenPopped => false;

  @override
  bool get maintainState => true;

  @override
  bool get barrierDismissible => !opaque;

  @override
  Color? get barrierColor => opaque ? null : const Color(0x33000000);

  @override
  String get barrierLabel => 'Dismiss prototype sheet';

  @override
  Animation<double> createAnimation() => switch (driver) {
    .projected => _projection,
    .sdkController => super.createAnimation(),
  };

  @override
  void install() {
    super.install();
    if (driver == .projected) {
      _ticker = navigator!.createTicker(_tick);
    } else {
      controller!.addListener(_publishControllerSample);
    }
  }

  @override
  Simulation? createSimulation({required bool forward}) {
    if (driver == .projected) return null;
    _opening = forward;
    if (forward) {
      _motion.open(_time);
      _time += eventAge.inMicroseconds / 1e6;
    } else {
      _motion.close(_time);
    }
    return _ZoomSimulation(_motion, _time);
  }

  @override
  TickerFuture didPush() {
    if (driver == .sdkController) return super.didPush();
    _opening = true;
    _motion.open(_time);
    _time += eventAge.inMicroseconds / 1e6;
    _motion.advance(_time);
    _projection.update(rawProgress, .forward);
    final settled = _pushSignal.start();
    super.didPush();
    _wake();
    return settled;
  }

  @override
  void didAdd() {
    super.didAdd();
    _showImmediately();
  }

  @override
  void didReplace(Route<Object?>? oldRoute) {
    super.didReplace(oldRoute);
    if (oldRoute is! ProbeSheetRoute<Object?> || oldRoute.motionSettled) {
      _showImmediately();
      return;
    }
    _motion = oldRoute._motion;
    _time = oldRoute._time;
    _opening = oldRoute._opening;
    oldRoute._ticker?.stop();
    oldRoute.controller!.stop();
    oldRoute._pushSignal.complete();
    if (driver == .projected) {
      _projection.update(rawProgress, _opening ? .forward : .reverse);
      _wake();
    } else {
      final simulation = _ZoomSimulation(_motion, _time);
      if (_opening) {
        controller!.animateWith(simulation);
      } else {
        controller!.animateBackWith(simulation);
      }
    }
  }

  void _showImmediately() {
    _ticker?.stop();
    _pushSignal.complete();
    _motion = MorphZoomMotion();
    _motion.open(-10);
    _motion.advance(0);
    _time = 0;
    _opening = true;
    if (driver == .sdkController) controller!.value = 1;
    _projection.update(1, .completed);
    _frames.value++;
  }

  @override
  bool didPop(T? result) {
    final popped = super.didPop(result);
    if (!popped || driver == .sdkController) return popped;
    _pushSignal.complete();
    _opening = false;
    _motion.close(_time);
    _projection.update(rawProgress, .reverse);
    _wake();
    return true;
  }

  void _wake() {
    final ticker = _ticker!;
    if (ticker.isActive) return;
    _base = _time;
    ticker.start();
  }

  void _tick(Duration elapsed) {
    _time = _grid.snap(_base + elapsed.inMicroseconds / 1e6);
    _motion.advance(_time);
    final settled = _motion.isSettled;
    final status = settled
        ? (_opening ? AnimationStatus.completed : AnimationStatus.dismissed)
        : (_opening ? AnimationStatus.forward : AnimationStatus.reverse);
    _projection.update(settled ? (_opening ? 1 : 0) : rawProgress, status);
    motionFrames++;
    _frames.value++;
    if (settled) {
      _ticker!.stop();
      _pushSignal.complete();
    }
  }

  void _publishControllerSample() {
    _time = _motion.time;
    motionFrames++;
    _frames.value++;
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    pageBuilds++;
    return LayoutBuilder(
      builder: (context, constraints) {
        final destination = opaque
            ? Offset.zero & constraints.biggest
            : Rect.fromLTWH(
                8,
                constraints.maxHeight * 0.4,
                constraints.maxWidth - 16,
                constraints.maxHeight * 0.6 - 8,
              );
        return Flow(
          delegate: _SheetFlow(this, destination, _frames),
          children: [builder(context)],
        );
      },
    );
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _pushSignal.dispose();
    controller!.removeListener(_publishControllerSample);
    _frames.dispose();
    super.dispose();
    _projection.dispose();
    disposed = true;
  }
}

class _SheetFlow extends FlowDelegate {
  _SheetFlow(this.route, this.destination, Listenable frames)
    : super(repaint: frames);

  final ProbeSheetRoute<Object?> route;
  final Rect destination;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints.tight(destination.size);

  @override
  void paintChildren(FlowPaintingContext context) {
    final rect = route.rectangle(destination);
    final scale = MorphZoomMotion.contentScale(rect, destination.size);
    final transform = Matrix4.translationValues(rect.left, rect.top, 0);
    transform.scaleByDouble(scale, scale, 1, 1);
    context.paintChild(0, transform: transform);
  }

  @override
  bool shouldRepaint(_SheetFlow oldDelegate) =>
      route != oldDelegate.route || destination != oldDelegate.destination;
}

class _RouteAnimation extends Animation<double> with ChangeNotifier {
  final _statusListeners = <AnimationStatusListener>[];
  double _value = 0;
  AnimationStatus _status = .dismissed;

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

class _SettleSignal {
  final _ticker = Ticker((_) {});

  TickerFuture start() {
    _ticker.muted = true;
    return _ticker.start();
  }

  void complete() => _ticker.stop(canceled: false);

  void dispose() => _ticker.dispose();
}

class _ZoomSimulation extends Simulation {
  _ZoomSimulation(this.motion, this.base);

  final MorphZoomMotion motion;
  final double base;

  @override
  double x(double time) {
    motion.advance(base + time);
    if (motion.isSettled) return motion.isOpening ? 1 : 0;
    return motion.centerProgress(base + time);
  }

  @override
  double dx(double time) {
    const step = 1e-6;
    return (motion.centerProgress(base + time + step) -
            motion.centerProgress(base + time - step)) /
        (2 * step);
  }

  @override
  bool isDone(double time) {
    motion.advance(base + time);
    return motion.isSettled;
  }
}
