import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/clock.dart' show MorphFrameGrid;
import 'package:morph_example/proto/controller_vsync_probe.dart';
import 'package:morph_example/proto/route_probe.dart';

class _CapturedVsync implements TickerProvider {
  _CapturedVsync(this.parent);

  final TickerProvider parent;
  late Ticker ticker;

  @override
  Ticker createTicker(TickerCallback onTick) =>
      ticker = parent.createTicker(onTick);
}

class _DelayedRoute extends ProbeSheetRoute<void> {
  _DelayedRoute()
    : super(
        driver: .sdkController,
        opaque: true,
        builder: (_) => const Text('delayed'),
      );

  late _CapturedVsync vsync;
  Timer? _wake;

  @override
  AnimationController createAnimationController() {
    vsync = _CapturedVsync(navigator!);
    return AnimationController(
      vsync: vsync,
      duration: Duration.zero,
      reverseDuration: Duration.zero,
    );
  }

  @override
  Simulation? createSimulation({required bool forward}) {
    final simulation = super.createSimulation(forward: forward)!;
    return forward ? _Delay(simulation, 0.5) : simulation;
  }

  void doze(Duration duration) {
    vsync.ticker.muted = true;
    _wake = Timer(duration, () => vsync.ticker.muted = false);
  }

  void stop() => controller!.stop();

  @override
  void dispose() {
    _wake?.cancel();
    super.dispose();
  }
}

class _ManagedDelayedRoute extends _DelayedRoute {
  ProbeDozingVsync? _provider;

  @override
  AnimationController createAnimationController() {
    final provider = ProbeDozingVsync(navigator!.context);
    _provider = provider;
    return AnimationController(
      vsync: provider,
      duration: Duration.zero,
      reverseDuration: Duration.zero,
    );
  }

  @override
  void changedExternalState() {
    super.changedExternalState();
    _provider?.refresh(navigator!.context);
  }

  @override
  void doze(Duration duration) => _provider!.doze(duration);

  @override
  void dispose() {
    _provider?.dispose();
    super.dispose();
  }
}

class _Delay extends Simulation {
  _Delay(this.inner, this.delay);

  final Simulation inner;
  final double delay;

  @override
  double x(double time) => inner.x(time < delay ? 0 : time - delay);

  @override
  double dx(double time) => time < delay ? 0 : inner.dx(time - delay);

  @override
  bool isDone(double time) => time >= delay && inner.isDone(time - delay);
}

class _Elapsed extends Simulation {
  @override
  double x(double time) => time;

  @override
  double dx(double time) => 1;

  @override
  bool isDone(double time) => time >= 2;
}

class _OnGrid extends Simulation {
  _OnGrid(this.inner);

  final Simulation inner;
  final grid = MorphFrameGrid();
  double? _raw;
  double _sample = 0;

  double _time(double raw) {
    if (raw != _raw) {
      _raw = raw;
      _sample = grid.snap(raw);
    }
    return _sample;
  }

  @override
  double x(double time) => inner.x(_time(time));

  @override
  double dx(double time) => inner.dx(_time(time));

  @override
  bool isDone(double time) => inner.isDone(_time(time));
}

Widget _app(GlobalKey<NavigatorState> nav, {bool tickerEnabled = true}) =>
    TickerMode(
      enabled: tickerEnabled,
      child: WidgetsApp(
        color: const Color(0xFFFFFFFF),
        navigatorKey: nav,
        onGenerateRoute: (_) => PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const Text('root'),
        ),
      ),
    );

void main() {
  testWidgets('SDK ticker muting dozes without completing pushReplacement', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(nav));
    final old = ProbeSheetRoute<void>(
      opaque: true,
      builder: (_) => const Text('old'),
    );
    nav.currentState!.push<void>(old);
    await tester.pumpAndSettle();
    final route = _DelayedRoute();
    nav.currentState!.pushReplacement<void, void>(route);
    await tester.pump();
    route.doze(const Duration(milliseconds: 500));
    await tester.pump();
    final frames = route.motionFrames;
    await tester.pump(const Duration(milliseconds: 200));
    expect(route.motionFrames, frames);
    expect(old.disposed, isFalse);
    expect(route.animation!.status, AnimationStatus.forward);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(old.disposed, isFalse);
    expect(route.rawProgress, closeTo(0, 1e-9));
    await tester.pump(const Duration(milliseconds: 100));
    expect(route.rawProgress, greaterThan(0));
    expect(old.disposed, isFalse);
    await tester.pumpAndSettle();
    expect(route.motionSettled, isTrue);
    expect(old.disposed, isTrue);
  });

  testWidgets(
    'negative control: stop cancels the push future before visual rest',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(nav));
      final old = ProbeSheetRoute<void>(
        opaque: true,
        builder: (_) => const Text('old'),
      );
      nav.currentState!.push<void>(old);
      await tester.pumpAndSettle();
      final route = _DelayedRoute();
      nav.currentState!.pushReplacement<void, void>(route);
      await tester.pump();
      route.stop();
      await tester.pumpAndSettle();
      expect(route.motionSettled, isFalse);
      expect(old.disposed, isTrue);
      nav.currentState!.removeRoute(route);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('an SDK simulation can sample the measured display grid', (
    tester,
  ) async {
    final raw = AnimationController.unbounded(vsync: const TestVSync());
    final gridded = AnimationController.unbounded(vsync: const TestVSync());
    try {
      raw.animateWith(_Elapsed());
      final simulation = _OnGrid(_Elapsed());
      gridded.animateWith(simulation);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(microseconds: 16667));
      }
      expect(simulation.grid.period, closeTo(0.016667, 1e-9));
      var different = false;
      for (final jitter in [30, -20, 45, -35, 10, -5, 25, -40]) {
        final previous = gridded.value;
        await tester.pump(Duration(microseconds: 16667 + jitter));
        expect(gridded.value - previous, closeTo(0.016667, 1e-9));
        if ((raw.value - gridded.value).abs() > 1e-6) different = true;
        expect(
          (raw.value - gridded.value).abs(),
          lessThan(MorphFrameGrid.reach),
        );
      }
      expect(different, isTrue);
    } finally {
      raw.dispose();
      gridded.dispose();
    }
  });

  testWidgets(
    'negative control: parent TickerMode overrides a naive doze flag',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(nav));
      final route = _DelayedRoute();
      nav.currentState!.push<void>(route);
      await tester.pump();
      route.doze(const Duration(seconds: 1));
      await tester.pumpWidget(_app(nav, tickerEnabled: false));
      final frames = route.motionFrames;
      await tester.pump(const Duration(milliseconds: 50));
      expect(route.motionFrames, frames);
      await tester.pumpWidget(_app(nav));
      await tester.pump(const Duration(milliseconds: 16));
      expect(route.motionFrames, greaterThan(frames));
      expect(route.motionSettled, isFalse);
      nav.currentState!.removeRoute(route);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'coordinated doze survives parent mode changes and retains the old route',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(nav));
      final old = ProbeSheetRoute<void>(
        opaque: true,
        builder: (_) => const Text('old'),
      );
      nav.currentState!.push<void>(old);
      await tester.pumpAndSettle();
      final route = _ManagedDelayedRoute();
      nav.currentState!.pushReplacement<void, void>(route);
      await tester.pump();
      route.doze(const Duration(milliseconds: 500));
      await tester.pumpWidget(_app(nav, tickerEnabled: false));
      final frames = route.motionFrames;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(_app(nav));
      await tester.pump(const Duration(milliseconds: 16));
      expect(route.motionFrames, frames);
      expect(old.disposed, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(milliseconds: 434));
      expect(old.disposed, isFalse);
      expect(route.rawProgress, closeTo(0, 1e-9));
      await tester.pump(const Duration(milliseconds: 100));
      expect(route.rawProgress, greaterThan(0));
      await tester.pumpAndSettle();
      expect(route.motionSettled, isTrue);
      expect(old.disposed, isTrue);
    },
  );

  testWidgets('removing a dozing controller route cancels its wake timer', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(nav));
    final route = _ManagedDelayedRoute();
    nav.currentState!.push<void>(route);
    await tester.pump();
    route.doze(const Duration(milliseconds: 500));
    nav.currentState!.removeRoute(route);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(route.disposed, isTrue);
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('expiry of doze cannot unmute a disabled parent', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(nav));
    final route = _ManagedDelayedRoute();
    nav.currentState!.push<void>(route);
    await tester.pump();
    route.doze(const Duration(milliseconds: 500));
    await tester.pumpWidget(_app(nav, tickerEnabled: false));
    final frames = route.motionFrames;
    await tester.pump(const Duration(milliseconds: 600));
    expect(route.motionFrames, frames);
    expect(route.animation!.status, AnimationStatus.forward);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(_app(nav));
    await tester.pump(const Duration(milliseconds: 16));
    expect(route.motionFrames, greaterThan(frames));
    expect(route.rawProgress, greaterThan(0));
    await tester.pumpAndSettle();
    expect(route.motionSettled, isTrue);
  });
}
// ignore_for_file: invalid_use_of_internal_member
