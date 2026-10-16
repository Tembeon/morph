import 'dart:async';
import 'dart:developer' show Timeline;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/motion.dart';
import 'package:morph_example/proto/menu_transfer_probe.dart';
import 'package:morph_example/proto/motion_clock_probe.dart';

/// A reduced source/menu pair for Navigator ownership experiments.
class ProbeMenuSource extends StatefulWidget {
  /// Uses fixed geometry so the experiment isolates route and clock lifetime.
  const ProbeMenuSource({
    required this.menuBuilder,
    this.button = const Rect.fromLTWH(24, 80, 44, 44),
    this.bounds = const Size(402, 874),
    this.now,
    super.key,
  });

  /// Builds stable menu content in the root route.
  final WidgetBuilder menuBuilder;

  /// The source's rectangle in root navigator coordinates.
  final Rect button;

  /// The fixed available presentation size.
  final Size bounds;

  /// Engine-clock time at input delivery; tests supply their fake clock.
  final Duration Function()? now;

  @override
  State<ProbeMenuSource> createState() => ProbeMenuSourceState();
}

/// Source controls and observations for the P2 host harness.
class ProbeMenuSourceState extends State<ProbeMenuSource>
    with SingleTickerProviderStateMixin {
  late final _MenuSession _session;

  /// The complete model's most recent sampled frame.
  ProbeMenuFrame get frame => _session.transfer.frame;

  /// Whether the source currently owns the model.
  bool get ownsMotion => identical(_session.transfer.owner, _session.source);

  /// Whether every model channel is at rest.
  bool get motionSettled => _session.transfer.isSettled;

  /// How many frames the source clock has sampled.
  int get motionFrames => _session.sourceFrames;

  @override
  void initState() {
    super.initState();
    _session = _MenuSession(this, widget.button, widget.bounds, widget.now);
  }

  /// Opens on the root navigator, or reverses the current closing owner.
  ProbeMenuRoute open() {
    final current = _session.activeRoute;
    if (current != null && !current.closing) return current;
    final route = ProbeMenuRoute._(_session, widget.menuBuilder);
    unawaited(Navigator.of(context, rootNavigator: true).push<void>(route));
    return route;
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: .expand,
    children: [
      IgnorePointer(
        child: CustomPaint(painter: _MenuPainter(_session, _session.source)),
      ),
      Positioned.fromRect(
        rect: widget.button,
        child: GestureDetector(behavior: .opaque, onTap: open),
      ),
    ],
  );

  @override
  void dispose() {
    _session.detachSource();
    super.dispose();
  }
}

class _MenuSession {
  _MenuSession(
    TickerProvider vsync,
    this.button,
    this.bounds,
    Duration Function()? now,
  ) : now = now ?? _engineNow {
    transfer = _newMotion();
    sourceClock = ProbeMotionClock(
      vsync: vsync,
      now: this.now,
      pointerOffset: () => Duration.zero,
      onFrame: (time) {
        if (!transfer.advance(source, time)) {
          return (settled: true, wakeTime: null);
        }
        sourceFrames++;
        frames.value++;
        return (settled: transfer.isSettled, wakeTime: null);
      },
    );
  }

  final Rect button;
  final Size bounds;
  final Duration Function() now;
  final source = ProbeMenuLease(.source);
  final frames = ValueNotifier<int>(0);
  final _routes = <ProbeMenuRoute>{};
  late ProbeMenuTransfer transfer;
  ProbeMotionClock? sourceClock;
  ProbeMenuRoute? activeRoute;
  int sourceFrames = 0;

  ProbeMenuTransfer _newMotion() => ProbeMenuTransfer(
    motion: MorphMenuMotion(
      button: button,
      bounds: bounds,
      itemCount: 3,
      sourceHeight: 64,
      sourceRadius: 22,
    ),
    source: source,
    sourceTime: sourceClock?.time ?? 0,
  );

  void acquire(ProbeMenuRoute route) {
    final previous = activeRoute;
    final previousClock = previous?._clock ?? sourceClock!;
    final lease = transfer.owner;
    transfer.open(lease, previousClock.time);
    transfer.transfer(
      lease,
      fromTime: previousClock.time,
      to: route._lease,
      toTime: 0,
    );
    previousClock.pause();
    _routes.add(route);
    activeRoute = route;
    previous?._relinquish();
    route._clock.resumeAt(now());
    frames.value++;
  }

  bool land(ProbeMenuRoute route, double localTime) {
    final clock = sourceClock;
    if (clock == null) return false;
    final before = transfer.frame;
    final anchor = clock.resumeAt(
      SchedulerBinding.instance.currentSystemFrameTimeStamp,
    );
    transfer.transfer(
      route._lease,
      fromTime: localTime,
      to: source,
      toTime: anchor,
    );
    route.handBack = (before: before, after: transfer.frame);
    activeRoute = null;
    frames.value++;
    return true;
  }

  void detachSource() {
    sourceClock!.dispose();
    sourceClock = null;
    _disposeIfUnused();
  }

  void routeDisposed(ProbeMenuRoute route) {
    _routes.remove(route);
    if (identical(activeRoute, route)) {
      activeRoute = null;
      if (sourceClock != null) {
        // Forced removal skips visual closing, as Navigator.removeRoute does.
        transfer = _newMotion();
        frames.value++;
      }
    }
    _disposeIfUnused();
  }

  void _disposeIfUnused() {
    if (sourceClock == null && _routes.isEmpty) frames.dispose();
  }
}

/// A real PopupRoute driven by the same menu model the source later resumes.
class ProbeMenuRoute extends PopupRoute<void> {
  ProbeMenuRoute._(this._session, this._builder);

  final _MenuSession _session;
  final WidgetBuilder _builder;
  final _lease = ProbeMenuLease(.route);
  final _projection = _MenuAnimation();
  final _pushSignal = Ticker((_) {});
  late final ProbeMotionClock _clock;

  /// Whether logical pop has started closing this presentation.
  bool closing = false;

  /// Whether Navigator has disposed this route.
  bool disposed = false;

  /// How many model samples this route has written.
  int motionFrames = 0;

  /// How many times the route content page was built.
  int pageBuilds = 0;

  /// The frame on each side of the ownership change, before any next tick.
  ({ProbeMenuFrame before, ProbeMenuFrame after})? handBack;

  /// The shared model's latest frame, including the source's landing tail.
  ProbeMenuFrame get frame => _session.transfer.frame;

  /// The canonical model time at logical closing.
  double? closedAt;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  bool get finishedWhenPopped => false;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  String get barrierLabel => 'Dismiss prototype menu';

  @override
  Animation<double> createAnimation() => _projection;

  @override
  void install() {
    super.install();
    _clock = ProbeMotionClock(
      vsync: navigator!,
      now: _session.now,
      pointerOffset: () => Duration.zero,
      onFrame: _sample,
    );
  }

  @override
  TickerFuture didPush() {
    super.didPush();
    _pushSignal.muted = true;
    final signal = _pushSignal.start();
    _session.acquire(this);
    _projection.update(frame.progress, .forward);
    return signal;
  }

  @override
  bool didPop(void result) {
    final popped = super.didPop(result);
    if (!popped) return false;
    closing = true;
    _pushSignal.stop(canceled: false);
    _session.transfer.close(_lease, _clock.time);
    closedAt = frame.time;
    _projection.update(frame.progress, .reverse);
    _clock.resumeAt(_session.now());
    return true;
  }

  ProbeFrameOutcome _sample(double time) {
    if (!_session.transfer.advance(_lease, time)) {
      return (settled: true, wakeTime: null);
    }
    motionFrames++;
    final settled = _session.transfer.isSettled;
    if (closing &&
        ((_session.transfer.readyToHandBack && _session.land(this, time)) ||
            settled)) {
      _projection.update(0, .dismissed);
      return (settled: true, wakeTime: null);
    }
    _projection.update(
      settled ? 1 : frame.progress,
      closing ? .reverse : (settled ? .completed : .forward),
    );
    _session.frames.value++;
    if (settled) _pushSignal.stop(canceled: false);
    return (settled: settled, wakeTime: null);
  }

  void _relinquish() {
    _pushSignal.stop(canceled: false);
    _projection.update(0, .dismissed);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    pageBuilds++;
    return Stack(
      fit: .expand,
      children: [
        IgnorePointer(
          child: CustomPaint(painter: _MenuPainter(_session, _lease)),
        ),
        Flow(
          delegate: _MenuContentFlow(_session, _lease),
          children: [_builder(context)],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _clock.dispose();
    _pushSignal.dispose();
    super.dispose();
    _projection.dispose();
    disposed = true;
    _session.routeDisposed(this);
  }
}

class _MenuPainter extends CustomPainter {
  _MenuPainter(this.session, this.lease) : super(repaint: session.frames);

  final _MenuSession session;
  final ProbeMenuLease lease;

  @override
  void paint(Canvas canvas, Size size) {
    if (!identical(session.transfer.owner, lease)) return;
    final frame = session.transfer.frame;
    final paint = Paint();
    paint.color = const Color(0xFF8888AA);
    canvas.drawRRect(frame.button, paint);
    if (lease.kind == .route) {
      paint.color = const Color(0xFFCCCCDD);
      canvas.drawRRect(frame.menu, paint);
    }
  }

  @override
  bool shouldRepaint(_MenuPainter oldDelegate) =>
      session != oldDelegate.session || lease != oldDelegate.lease;
}

class _MenuContentFlow extends FlowDelegate {
  _MenuContentFlow(this.session, this.lease) : super(repaint: session.frames);

  final _MenuSession session;
  final ProbeMenuLease lease;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      const BoxConstraints.tightFor(width: 250, height: 146);

  @override
  void paintChildren(FlowPaintingContext context) {
    if (!identical(session.transfer.owner, lease)) return;
    final frame = session.transfer.frame;
    final rect = frame.menu.outerRect;
    final size = context.getChildSize(0)!;
    final matrix = Matrix4.translationValues(rect.left, rect.top, 0);
    matrix.scaleByDouble(
      rect.width / size.width,
      rect.height / size.height,
      1,
      1,
    );
    context.paintChild(
      0,
      transform: matrix,
      opacity: frame.contentOpacity.clamp(0.0, 1.0),
    );
  }

  @override
  bool shouldRepaint(_MenuContentFlow oldDelegate) =>
      session != oldDelegate.session || lease != oldDelegate.lease;
}

class _MenuAnimation extends Animation<double> with ChangeNotifier {
  final _statuses = <AnimationStatusListener>[];
  double _value = 0;
  AnimationStatus _status = .dismissed;

  @override
  double get value => _value;

  @override
  AnimationStatus get status => _status;

  @override
  void addStatusListener(AnimationStatusListener listener) =>
      _statuses.add(listener);

  @override
  void removeStatusListener(AnimationStatusListener listener) =>
      _statuses.remove(listener);

  void update(double value, AnimationStatus status) {
    final next = value.clamp(0.0, 1.0);
    final changed = next != _value;
    final statusChanged = status != _status;
    _value = next;
    _status = status;
    if (changed) notifyListeners();
    if (statusChanged) {
      for (final listener in List.of(_statuses)) {
        listener(status);
      }
    }
  }
}

Duration _engineNow() => Duration(microseconds: Timeline.now);
