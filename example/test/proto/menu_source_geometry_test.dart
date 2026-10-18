import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/motion.dart';
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph_example/proto/menu_route_probe.dart';

const _button = Rect.fromLTWH(24, 80, 44, 44);
const _bounds = Size(402, 874);
const _step = Duration(microseconds: 8333);

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await tester.pump(_step);
  }
  expect(done(), isTrue);
}

class _Observer extends NavigatorObserver {
  final routes = <ProbeMenuRoute>[];

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    if (route is ProbeMenuRoute) routes.add(route);
  }
}

class _Harness {
  _Harness({
    this.overlaySize = _bounds,
    this.scrolling = false,
    this.sourceHeight = 64,
    this.pointerInput = true,
    this.localMediaQuery,
  });

  final Size overlaySize;
  final bool scrolling;
  final double sourceHeight;
  final bool pointerInput;
  final MediaQueryData? localMediaQuery;
  final source = GlobalKey<ProbeMenuSourceState>();
  final navigator = GlobalKey<NavigatorState>();
  final scene = GlobalKey();
  final observer = _Observer();
  final offset = ValueNotifier(const Offset(80, 40));
  final sourceTransform = ValueNotifier(Matrix4.identity());
  final rootTransform = ValueNotifier(Matrix4.identity());
  final offstage = ValueNotifier(false);
  final scroll = ScrollController();
  final models = <MorphMenuMotion>[];
  final selected = <int>[];
  final samples = <ProbeMenuSample>[];
  ValueChanged<MorphMenuMotion>? ready;
  ValueChanged<ProbeMenuSample>? observe;

  MorphMenuMotion get model => models.last;

  Widget sourceWidget(WidgetTester tester) {
    final child = RepaintBoundary(
      child: ValueListenableBuilder<Offset>(
        valueListenable: offset,
        builder: (_, offset, child) => Padding(
          padding: EdgeInsets.only(left: offset.dx, top: offset.dy),
          child: child,
        ),
        child: ValueListenableBuilder<Matrix4>(
          valueListenable: sourceTransform,
          builder: (_, matrix, child) =>
              Transform(transform: matrix, child: child),
          child: ValueListenableBuilder<bool>(
            valueListenable: offstage,
            builder: (_, hidden, child) =>
                Offstage(offstage: hidden, child: child),
            child: RepaintBoundary(
              child: ProbeMenuSource.measured(
                key: source,
                button: _button,
                pointerInput: pointerInput,
                sourceHeight: sourceHeight,
                now: () => Duration(
                  microseconds: tester.binding.clock
                      .now()
                      .microsecondsSinceEpoch,
                ),
                onMotionReady: (motion) {
                  models.add(motion);
                  motion.onSelected = selected.add;
                  ready?.call(motion);
                },
                onSample: (sample) {
                  samples.add(sample);
                  observe?.call(sample);
                },
                menuBuilder: (_) => Column(
                  children: [
                    const SizedBox(height: 10),
                    for (var i = 0; i < 3; i++)
                      SizedBox(key: ValueKey('row$i'), width: 250, height: 42),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return switch (localMediaQuery) {
      final data? => MediaQuery(data: data, child: child),
      null => child,
    };
  }

  Widget app(WidgetTester tester) => RepaintBoundary(
    key: scene,
    child: ValueListenableBuilder<Matrix4>(
      valueListenable: rootTransform,
      builder: (_, matrix, child) => Transform(transform: matrix, child: child),
      child: Align(
        alignment: .topLeft,
        child: SizedBox.fromSize(
          size: overlaySize,
          child: WidgetsApp(
            debugShowCheckedModeBanner: false,
            color: const Color(0xFFFFFFFF),
            navigatorKey: navigator,
            navigatorObservers: [observer],
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (_, _, _) => scrolling
                  ? ListView(
                      controller: scroll,
                      padding: EdgeInsets.zero,
                      children: [
                        const SizedBox(height: 200),
                        SizedBox(height: 600, child: sourceWidget(tester)),
                        const SizedBox(height: 400),
                      ],
                    )
                  : sourceWidget(tester),
            ),
          ),
        ),
      ),
    ),
  );

  Finder get button => find.descendant(
    of: find.byKey(source),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Open prototype menu',
    ),
  );

  Future<void> mount(
    WidgetTester tester, {
    Widget? reference,
    double dpr = 1,
  }) async {
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = Size(reference == null ? 402 : 804, 874) * dpr;
    addTearDown(tester.view.reset);
    addTearDown(dispose);
    await tester.pumpWidget(
      reference == null
          ? app(tester)
          : Row(
              textDirection: .ltr,
              children: [
                SizedBox.fromSize(size: _bounds, child: app(tester)),
                SizedBox.fromSize(size: _bounds, child: reference),
              ],
            ),
    );
  }

  Future<ProbeMenuRoute> open(WidgetTester tester) async {
    final route = source.currentState!.open();
    await _until(tester, () => route.animation!.isCompleted);
    return route;
  }

  Future<void> finish(WidgetTester tester, ProbeMenuRoute route) async {
    navigator.currentState!.pop();
    await _until(tester, () => route.disposed);
    await _until(tester, () => source.currentState!.motionSettled);
    expect(tester.binding.transientCallbackCount, 0);
  }

  void dispose() {
    offset.dispose();
    sourceTransform.dispose();
    rootTransform.dispose();
    offstage.dispose();
    scroll.dispose();
  }
}

Matrix4 _scale(double scale) => Matrix4.diagonal3Values(scale, scale, 1);

Future<List<int>> _pixels(WidgetTester tester, GlobalKey key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final bytes = data.buffer.asUint8List();
    image.dispose();
    return bytes;
  }))!;
}

class _ReferencePainter extends CustomPainter {
  _ReferencePainter(this.motion, Listenable frames) : super(repaint: frames);

  final MorphMenuMotion motion;

  @override
  void paint(Canvas canvas, Size size) {
    // ignore: invalid_use_of_internal_member
    final bar = morphGlassContainerOutline(
      [motion.buttonBlob.rrect],
      12,
      withField: false,
    ).path;
    final carried = motion.silhouetteFor(withField: false);
    final path = carried == null
        ? bar
        : Path.combine(.union, bar, carried.path);
    final paint = Paint();
    paint.color = const Color(0xFF8888AA);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ReferencePainter oldDelegate) =>
      motion != oldDelegate.motion;
}

class _BeforeLayout extends SingleChildRenderObjectWidget {
  const _BeforeLayout({required this.check, required super.child});

  final VoidCallback check;

  @override
  RenderObject createRenderObject(BuildContext context) => _LayoutCheck(check);
}

class _LayoutCheck extends RenderProxyBox {
  _LayoutCheck(this.check);

  final VoidCallback check;
  bool checked = false;

  @override
  void performLayout() {
    if (!checked) {
      checked = true;
      check();
    }
    super.performLayout();
  }
}

void main() {
  testWidgets('safe and keyboard edges are combined without adding them', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    tester.view.viewPadding = const FakeViewPadding(top: 100, bottom: 34);
    tester.view.viewInsets = const FakeViewPadding(bottom: 620);
    await tester.pump();
    final route = await h.open(tester);
    expect(route.frame.menu.top, greaterThanOrEqualTo(100));
    expect(route.frame.menu.bottom, lessThanOrEqualTo(254.01));
    await h.finish(tester, route);
  });

  testWidgets(
    'keyboard-covered source declines explicit and semantic activation',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 760);
      await tester.pump();
      expect(h.source.currentState!.open, throwsStateError);
      tester.widget<Semantics>(h.button).properties.onTap!();
      expect(h.models, isEmpty);
      expect(h.observer.routes, isEmpty);
      expect(h.samples, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'viewport too narrow for measured menu declines before callback',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      tester.view.viewPadding = const FakeViewPadding(right: 160);
      await tester.pump();
      expect(h.source.currentState!.open, throwsStateError);
      expect(h.models, isEmpty);
      expect(h.observer.routes, isEmpty);
    },
  );

  testWidgets('idle viewport recapture reuses model and changes placement', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    final first = await h.open(tester);
    final model = h.model;
    await h.finish(tester, first);
    tester.view.viewPadding = const FakeViewPadding(top: 100);
    tester.view.viewInsets = const FakeViewPadding(bottom: 620);
    await tester.pump();
    final second = await h.open(tester);
    expect(h.model, same(model));
    expect(h.models, hasLength(1));
    expect(second.frame.menu.bottom, lessThanOrEqualTo(254.01));
    await h.finish(tester, second);
  });

  for (final dpr in [1.0, 2.0]) {
    for (final scale in [0.8, 1.0]) {
      testWidgets(
        'viewport projects actual root edges at DPR$dpr scale$scale',
        (tester) async {
          final h = _Harness(overlaySize: const Size(320, 650));
          final root = _scale(scale);
          root.setTranslationRaw(30, 20, 0);
          h.rootTransform.value = root;
          await h.mount(tester, dpr: dpr);
          tester.view.viewPadding = FakeViewPadding(
            left: 50 * dpr,
            top: 100 * dpr,
            right: 20 * dpr,
            bottom: 34 * dpr,
          );
          tester.view.viewInsets = FakeViewPadding(bottom: 600 * dpr);
          await tester.pump();
          await tester.tapAt(tester.getCenter(h.button));
          final route = h.observer.routes.single;
          await _until(tester, () => route.animation!.isCompleted);
          final expected = MorphMenuMotion.place(
            button: _button.shift(const Offset(80, 40)),
            size: const Size(250, 146),
            bounds: const Size(320, 650),
            padding: EdgeInsets.fromLTRB(
              20 / scale,
              80 / scale,
              0,
              650 - 254 / scale,
            ),
          ).rect;
          expect(route.frame.menu.left, closeTo(expected.left, 0.01));
          expect(route.frame.menu.top, closeTo(expected.top, 0.01));
          expect(route.frame.menu.bottom, closeTo(expected.bottom, 0.01));
          await tester.tapAt(
            tester.getCenter(find.byKey(const ValueKey('row1'))),
          );
          await _until(tester, () => route.disposed);
          await _until(tester, () => h.source.currentState!.motionSettled);
          expect(h.selected, [1]);
          expect(route.handBack, isNotNull);
        },
      );
    }
  }

  testWidgets('fabricated local MediaQuery cannot erase system keyboard', (
    tester,
  ) async {
    final h = _Harness(
      localMediaQuery: const MediaQueryData(size: Size(9999, 9999)),
    );
    await h.mount(tester);
    tester.view.viewPadding = const FakeViewPadding(top: 100);
    tester.view.viewInsets = const FakeViewPadding(bottom: 620);
    await tester.pump();
    tester.widget<Semantics>(h.button).properties.onTap!();
    final route = h.observer.routes.single;
    await _until(tester, () => route.animation!.isCompleted);
    expect(route.frame.menu.bottom, lessThanOrEqualTo(254.01));
    await h.finish(tester, route);
  });

  testWidgets(
    'already safe smaller root does not subtract consumed edges twice',
    (tester) async {
      final h = _Harness(overlaySize: const Size(320, 400));
      h.rootTransform.value = Matrix4.translationValues(40, 100, 0);
      await h.mount(tester);
      tester.view.viewPadding = const FakeViewPadding(
        left: 20,
        top: 100,
        right: 20,
        bottom: 34,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 374);
      await tester.pump();
      final route = await h.open(tester);
      final expected = MorphMenuMotion.place(
        button: h.model.button,
        size: const Size(250, 146),
        bounds: const Size(320, 400),
      ).rect;
      expect(route.frame.menu.top, closeTo(expected.top, 0.01));
      expect(route.frame.menu.bottom, closeTo(expected.bottom, 0.01));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await h.finish(tester, route);
      expect(route.handBack, isNotNull);
      expect(h.models, hasLength(1));
    },
  );

  for (final extent in [61.0, 62.0]) {
    testWidgets('minimum row viewport height $extent is respected', (
      tester,
    ) async {
      final h = _Harness();
      await h.mount(tester);
      tester.view.viewPadding = const FakeViewPadding(top: 110);
      tester.view.viewInsets = FakeViewPadding(bottom: 874 - 110 - extent);
      await tester.pump();
      if (extent < 62) {
        expect(h.source.currentState!.open, throwsStateError);
        expect(h.models, isEmpty);
        expect(h.observer.routes, isEmpty);
      } else {
        final route = await h.open(tester);
        expect(route.frame.menu.height, closeTo(62, 0.01));
        expect(route.frame.menu.top, greaterThanOrEqualTo(109.99));
        expect(route.frame.menu.bottom, lessThanOrEqualTo(172.01));
        await h.finish(tester, route);
      }
    });
  }

  for (final insets in [
    const FakeViewPadding(top: 500, bottom: 500),
    const FakeViewPadding(right: 1000),
  ]) {
    testWidgets('empty or inverted physical safe viewport declines $insets', (
      tester,
    ) async {
      final h = _Harness();
      await h.mount(tester);
      tester.view.viewInsets = insets;
      await tester.pump();
      expect(h.source.currentState!.open, throwsStateError);
      expect(h.models, isEmpty);
      expect(h.observer.routes, isEmpty);
    });
  }

  testWidgets('metrics changed by readiness prevent a stale popup push', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    h.ready = (_) =>
        tester.view.viewInsets = const FakeViewPadding(bottom: 620);
    expect(h.source.currentState!.open, throwsStateError);
    expect(h.models, hasLength(1));
    expect(h.observer.routes, isEmpty);
    expect(h.samples, isEmpty);
    h.ready = null;
    await tester.pump();
    final route = await h.open(tester);
    expect(h.models, hasLength(1));
    expect(route.frame.menu.bottom, lessThanOrEqualTo(254.01));
    await h.finish(tester, route);
  });

  testWidgets('shown viewport change retains old model but revokes landing', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    final route = await h.open(tester);
    final old = h.model;
    final time = old.time;
    tester.view.viewInsets = const FakeViewPadding(bottom: 620);
    await tester.pump();
    h.navigator.currentState!.pop();
    await _until(tester, () => route.disposed);
    expect(route.handBack, isNull);
    expect(old.time, greaterThanOrEqualTo(time));
    expect(old.isSettled, isTrue);
    final next = await h.open(tester);
    expect(h.models, hasLength(2));
    expect(next.frame.menu.bottom, lessThanOrEqualTo(254.01));
    await h.finish(tester, next);
  });

  testWidgets('keyboard change cancels hidden held preparation finitely', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    final hold = await tester.startGesture(tester.getCenter(h.button));
    final route = h.observer.routes.single;
    tester.view.viewInsets = const FakeViewPadding(bottom: 620);
    await tester.pump();
    await hold.up();
    await _until(tester, () => route.disposed);
    expect(route.handBack, isNull);
    expect(h.source.currentState!.activeRoute, isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('keyboard change freezes abandoned source tail without ticker', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    final route = await h.open(tester);
    final old = h.model;
    h.navigator.currentState!.pop();
    await _until(tester, () => route.handBack != null);
    expect(old.isSettled, isFalse);
    tester.view.viewInsets = const FakeViewPadding(bottom: 620);
    await tester.pump();
    final time = old.time;
    await tester.pump(const Duration(seconds: 2));
    expect(old.time, time);
    expect(old.isSettled, isFalse);
    expect(h.source.currentState!.motionSettled, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'root leaving physical view revokes endpoint despite equal local map',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      final route = await h.open(tester);
      h.rootTransform.value = Matrix4.translationValues(0, 40, 0);
      await tester.pump();
      h.navigator.currentState!.pop();
      await _until(tester, () => route.disposed);
      expect(route.handBack, isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'asymmetric safe and IME edges use the larger value on each side',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      tester.view.viewPadding = const FakeViewPadding(
        left: 70,
        top: 100,
        right: 60,
        bottom: 34,
      );
      tester.view.viewInsets = const FakeViewPadding(
        left: 20,
        top: 110,
        right: 40,
        bottom: 620,
      );
      await tester.pump();
      final route = await h.open(tester);
      expect(route.frame.menu.left, closeTo(92, 0.01));
      expect(route.frame.menu.top, closeTo(110, 0.01));
      expect(route.frame.menu.bottom, closeTo(254, 0.01));
      await h.finish(tester, route);
    },
  );

  testWidgets('exact fixed menu width fits without squeezing metrics', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    tester.view.viewPadding = const FakeViewPadding(right: 152);
    await tester.pump();
    final route = await h.open(tester);
    expect(h.model.layout.width, 250);
    expect(route.frame.menu.left, closeTo(0, 0.01));
    expect(route.frame.menu.width, closeTo(250, 0.01));
    await h.finish(tester, route);
  });

  testWidgets(
    'finite root scale with overflowing inverse viewport declines before push',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      final root = tester.renderObject<RenderTransform>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Transform &&
              identical(widget.transform, h.rootTransform.value),
        ),
      );
      root.transform = _scale(1e-310);
      try {
        expect(h.source.currentState!.open, throwsStateError);
        expect(h.models, isEmpty);
        expect(h.observer.routes, isEmpty);
        expect(h.samples, isEmpty);
      } finally {
        root.transform = h.rootTransform.value;
      }
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'keyboard change retires held-reopen reservation on the old session',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      final first = await h.open(tester);
      h.navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final hold = await tester.startGesture(tester.getCenter(h.button));
      final reserved = h.observer.routes.last;
      expect(reserved, isNot(same(first)));
      tester.view.viewInsets = const FakeViewPadding(bottom: 620);
      await tester.pump();
      await hold.up();
      await _until(tester, () => reserved.disposed && first.disposed);
      expect(h.observer.routes, [first, reserved]);
      expect(first.handBack, isNull);
      expect(h.models.single.isSettled, isTrue);
      expect(h.source.currentState!.activeRoute, isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'invalid viewport admission retires active endpoint before metrics restore',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      final route = await h.open(tester);
      await _until(tester, () => h.model.isSettled);
      tester.view.viewInsets = const FakeViewPadding(bottom: 760);
      expect(h.source.currentState!.open, throwsStateError);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();
      h.navigator.currentState!.pop();
      await _until(tester, () => route.disposed);
      expect(route.handBack, isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'actual MediaQuery.removeViewInsets does not erase the physical keyboard',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      tester.view.viewPadding = const FakeViewPadding(top: 100);
      tester.view.viewInsets = const FakeViewPadding(bottom: 620);
      await tester.pumpWidget(
        Builder(
          builder: (context) => MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: h.app(tester),
          ),
        ),
      );
      await tester.pump();
      expect(
        MediaQuery.viewInsetsOf(h.source.currentContext!),
        EdgeInsets.zero,
      );
      final route = await h.open(tester);
      expect(route.frame.menu.bottom, lessThanOrEqualTo(254.01));
      await h.finish(tester, route);
    },
  );

  testWidgets(
    'settled frozen source observes viewport on the next input rather than metrics notification',
    (tester) async {
      final h = _Harness(localMediaQuery: const MediaQueryData(size: _bounds));
      await h.mount(tester);
      final route = await h.open(tester);
      await _until(tester, () => h.model.isSettled);
      final sourceFrames = h.source.currentState!.motionFrames;
      expect(tester.binding.transientCallbackCount, 0);
      tester.view.viewInsets = const FakeViewPadding(bottom: 620);
      await tester.pump();
      expect(h.source.currentState!.activeRoute, same(route));
      expect(h.source.currentState!.motionFrames, sourceFrames);
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('row1'))));
      await tester.pump();
      expect(h.source.currentState!.activeRoute, isNull);
      expect(h.selected, isEmpty);
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('row1'))));
      await _until(tester, () => route.disposed);
      expect(route.handBack, isNull);
      expect(h.selected, [1]);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'post-readiness observation retires reentrantly opened stale endpoint',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      ProbeMenuRoute? nested;
      h.ready = (_) {
        nested = h.source.currentState!.open();
        tester.view.viewInsets = const FakeViewPadding(bottom: 760);
      };
      expect(h.source.currentState!.open, throwsStateError);
      expect(nested, isNotNull);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();
      h.ready = null;
      if (nested!.isActive && !nested!.closing) {
        h.navigator.currentState!.pop();
      }
      await _until(tester, () => nested!.disposed);
      expect(nested!.handBack, isNull);
      expect(h.source.currentState!.activeRoute, isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
  for (final scaledRoot in [false, true]) {
    testWidgets(
      'real source hit opens after offset, scaled root: $scaledRoot',
      (tester) async {
        final h = _Harness();
        if (scaledRoot) h.rootTransform.value = _scale(0.8);
        await h.mount(tester);
        await tester.tapAt(tester.getCenter(h.button));
        await tester.pump(const Duration(milliseconds: 300));
        expect(h.model.isOpen, isTrue);
        await h.finish(tester, h.observer.routes.single);
      },
    );
  }

  testWidgets('first route frame starts at the measured source rectangle', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    final physicalButton = tester.getRect(h.button);
    final route = h.source.currentState!.open();
    expect(route.frame.button.outerRect.center, physicalButton.center);
    await h.finish(tester, route);
  });

  for (final dpr in [1.0, 2.0]) {
    testWidgets(
      'actual smaller overlay and global root transform select the right row at DPR$dpr',
      (tester) async {
        final h = _Harness(overlaySize: const Size(320, 650));
        final root = _scale(0.8);
        root.setTranslationRaw(30, 20, 0);
        h.rootTransform.value = root;
        await h.mount(tester, dpr: dpr);
        await tester.tapAt(tester.getCenter(h.button));
        final route = h.observer.routes.single;
        await _until(tester, () => route.animation!.isCompleted);
        expect(h.model.bounds, const Size(320, 650));
        expect(h.model.button, _button.shift(const Offset(80, 40)));
        expect(h.model.layout.width, 250);
        expect(
          tester.getRect(find.byKey(const ValueKey('row1'))).width,
          closeTo(route.frame.menu.width * 0.8, 1e-8),
        );
        await tester.tapAt(
          tester.getCenter(find.byKey(const ValueKey('row1'))),
        );
        await _until(tester, () => route.disposed);
        await _until(tester, () => h.source.currentState!.motionSettled);
        expect(h.selected, [1]);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  testWidgets(
    'source scale changes the source shape without scaling menu metrics',
    (tester) async {
      final h = _Harness();
      h.sourceTransform.value = _scale(1.25);
      await h.mount(tester);
      final physical = tester.getRect(h.button);
      final route = h.source.currentState!.open();
      expect(h.model.button, physical);
      expect(route.frame.button.outerRect, physical);
      await _until(tester, () => route.animation!.isCompleted);
      expect(h.model.layout.width, 250);
      expect(
        tester.getRect(find.byKey(const ValueKey('row1'))).width,
        closeTo(route.frame.menu.width, 1e-8),
      );
      await h.finish(tester, route);
      expect(h.models, hasLength(1));
    },
  );

  testWidgets(
    'held source pointer survives root mapping through row selection',
    (tester) async {
      final h = _Harness();
      h.rootTransform.value = _scale(0.8);
      await h.mount(tester);
      final press = tester.getCenter(h.button);
      final hold = await tester.startGesture(press);
      final route = h.observer.routes.single;
      await _until(tester, () => route.animation!.isCompleted);
      await hold.moveTo(tester.getCenter(find.byKey(const ValueKey('row1'))));
      await hold.up();
      await _until(tester, () => route.disposed);
      await _until(tester, () => h.source.currentState!.motionSettled);
      expect(h.selected, [1]);
      expect(
        h.samples.firstWhere((s) => s.kind == .pointer).event!.position,
        press,
      );
      expect(
        h.samples.where((s) => s.kind == .pointer).map((s) => s.event),
        containsAllInOrder([
          isA<PointerDownEvent>(),
          isA<PointerMoveEvent>(),
          isA<PointerUpEvent>(),
        ]),
      );
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('semantic activation shares measured admission', (tester) async {
    final h = _Harness();
    await h.mount(tester);
    final semantic = tester.widget<Semantics>(h.button);
    semantic.properties.onTap!();
    final route = h.observer.routes.single;
    expect(h.model.button, _button.shift(const Offset(80, 40)));
    await h.finish(tester, route);
  });

  testWidgets('closed rest recaptures idle movement on the same model', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    final first = await h.open(tester);
    await h.finish(tester, first);
    final model = h.model;
    h.offset.value = const Offset(30, 70);
    await tester.pump();
    final next = await h.open(tester);
    expect(h.model, same(model));
    expect(h.models, hasLength(1));
    expect(h.model.button, _button.shift(const Offset(30, 70)));
    await h.finish(tester, next);
  });

  testWidgets('scroll before acquisition uses current paint coordinates', (
    tester,
  ) async {
    final h = _Harness(scrolling: true);
    await h.mount(tester);
    h.scroll.jumpTo(120);
    await tester.pump();
    final physical = tester.getRect(h.button);
    await tester.tapAt(physical.center);
    expect(h.model.button, physical);
    await h.finish(tester, h.observer.routes.single);
  });

  testWidgets('root global movement preserves local model geometry and input', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    final route = await h.open(tester);
    final model = h.model;
    final matrix = _scale(0.8);
    matrix.setTranslationRaw(20, 10, 0);
    h.rootTransform.value = matrix;
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('row1'))));
    await _until(tester, () => route.disposed);
    await _until(tester, () => h.source.currentState!.motionSettled);
    expect(h.models, [model]);
    expect(h.selected, [1]);
    expect(route.handBack, isNotNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  final invalid = <String, Matrix4>{
    'rotation': Matrix4.rotationZ(0.2),
    'anisotropic scale': Matrix4.diagonal3Values(1.1, 0.9, 1),
    'reflection': Matrix4.diagonal3Values(-1, 1, 1),
    'singular': _scale(0),
    'tiny singular': Matrix4.diagonal3Values(1e-10, 0, 1),
    'tiny shear': Matrix4.identity(),
    'perspective': Matrix4.identity(),
    'shear': Matrix4.identity(),
    'nonfinite': Matrix4.identity(),
  };
  invalid['perspective']!.setEntry(3, 1, 0.01);
  invalid['shear']!.setEntry(0, 1, 0.1);
  invalid['tiny shear']!.setEntry(0, 1, 1e-10);
  invalid['nonfinite']!.setEntry(0, 0, double.nan);
  for (final entry in invalid.entries) {
    testWidgets(
      'unsupported ${entry.key} declines before any model input or push',
      (tester) async {
        final h = _Harness();
        await h.mount(tester);
        final transform = tester.renderObject<RenderTransform>(
          find
              .ancestor(
                of: find.byKey(h.source),
                matching: find.byType(Transform),
              )
              .first,
        );
        transform.transform = entry.value;
        expect(h.source.currentState!.open, throwsStateError);
        final semantic = tester.widget<Semantics>(h.button);
        semantic.properties.onTap!();
        final listener = tester.widget<Listener>(
          find.descendant(
            of: find.byKey(h.source),
            matching: find.byType(Listener),
          ),
        );
        listener.onPointerDown!(
          const PointerDownEvent(position: Offset(46, 102)),
        );
        transform.transform = Matrix4.identity();
        await tester.pump(const Duration(seconds: 1));
        expect(h.observer.routes, isEmpty);
        expect(h.models, isEmpty);
        expect(h.samples, isEmpty);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  testWidgets(
    'Offstage and outside-overlay sources reject explicit and semantic open',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      h.offstage.value = true;
      await tester.pump();
      expect(h.source.currentState!.open, throwsStateError);
      h.offstage.value = false;
      h.offset.value = const Offset(390, 40);
      await tester.pump();
      expect(h.source.currentState!.open, throwsStateError);
      tester.widget<Semantics>(h.button).properties.onTap!();
      expect(h.observer.routes, isEmpty);
      expect(h.models, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('unprepared global router never publishes nominal samples', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    await tester.tapAt(const Offset(380, 800));
    await tester.pump();
    expect(h.samples, isEmpty);
    expect(h.models, isEmpty);
    expect(h.observer.routes, isEmpty);
  });

  testWidgets('readiness callback reentry installs only one model and popup', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    ProbeMenuRoute? nested;
    h.ready = (_) => nested = h.source.currentState!.open();
    final route = h.source.currentState!.open();
    expect(nested, same(route));
    expect(h.models, hasLength(1));
    expect(h.observer.routes, [route]);
    await h.finish(tester, route);
  });

  testWidgets('moving a shown endpoint leaves its old popup independent', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    final route = await h.open(tester);
    final oldModel = h.model;
    h.offset.value = const Offset(20, 100);
    await tester.pump();
    h.navigator.currentState!.pop();
    await _until(tester, () => route.disposed);
    expect(route.handBack, isNull);
    expect(oldModel.isSettled, isTrue);
    expect(h.source.currentState!.activeRoute, isNull);
    final next = await h.open(tester);
    expect(h.models, hasLength(2));
    expect(h.model.button, _button.shift(const Offset(20, 100)));
    await h.finish(tester, next);
  });

  testWidgets('moving during hidden hold cancels old preparation finitely', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    final hold = await tester.startGesture(tester.getCenter(h.button));
    final route = h.observer.routes.single;
    final oldModel = h.model;
    h.offset.value = const Offset(20, 100);
    await tester.pump();
    await hold.up();
    await _until(tester, () => route.disposed);
    expect(oldModel.isSettled, isTrue);
    expect(route.handBack, isNull);
    expect(h.observer.routes, [route]);
    expect(h.source.currentState!.activeRoute, isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'moving a source-owned tail abandons it without a hidden ticker',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      final route = await h.open(tester);
      final oldModel = h.model;
      h.navigator.currentState!.pop();
      await _until(tester, () => route.handBack != null);
      expect(oldModel.isSettled, isFalse);
      h.offset.value = const Offset(20, 100);
      await tester.pump();
      final time = oldModel.time;
      await tester.pump(const Duration(seconds: 2));
      expect(oldModel.time, time);
      expect(oldModel.isSettled, isFalse);
      expect(h.source.currentState!.motionSettled, isTrue);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'explicit opening before first layout fails without a queued popup',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      var checks = 0;
      await tester.pumpWidget(
        _BeforeLayout(
          check: () {
            checks++;
            expect(h.source.currentState!.open, throwsStateError);
          },
          child: h.app(tester),
        ),
      );
      expect(checks, 1);
      expect(h.observer.routes, isEmpty);
      expect(h.models, isEmpty);
      expect(h.samples, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'moving a held-reopen reservation retires the exact old attempt',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      final first = await h.open(tester);
      h.navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final hold = await tester.startGesture(tester.getCenter(h.button));
      final reserved = h.observer.routes.last;
      expect(reserved, isNot(same(first)));
      h.offset.value = const Offset(20, 100);
      await tester.pump();
      await hold.up();
      await _until(tester, () => reserved.disposed && first.disposed);
      expect(h.observer.routes, [first, reserved]);
      expect(first.handBack, isNull);
      expect(h.models.single.isSettled, isTrue);
      expect(h.source.currentState!.activeRoute, isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'same-frame land then layout move suppresses the stale source tail through retained paint',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      final route = await h.open(tester);
      final oldModel = h.model;
      final oldCenter = tester.getCenter(h.button);
      var moved = false;
      h.observe = (sample) {
        if (moved ||
            !route.closing ||
            sample.kind != .frame ||
            sample.frame.progress > 0) {
          return;
        }
        moved = true;
        h.sourceTransform.value = Matrix4.translationValues(20, 60, 0);
      };
      h.navigator.currentState!.pop();
      await _until(tester, () => moved);
      expect(route.handBack, isNotNull);
      expect(oldModel.isSettled, isFalse);
      final bytes = await _pixels(tester, h.scene);
      final currentCenter = tester.getCenter(h.button);
      int alpha(Offset point) =>
          bytes[4 * (point.dy.round() * 402 + point.dx.round()) + 3];
      expect(alpha(oldCenter), 0);
      expect(alpha(currentCenter), 255);
      final time = oldModel.time;
      await tester.pump(const Duration(seconds: 2));
      expect(oldModel.time, time);
      expect(oldModel.isSettled, isFalse);
      expect(h.source.currentState!.motionFrames, 0);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  for (final inset in [false, true]) {
    testWidgets(
      'source inverse painting preserves the independent root contour throughout handback tail, inset: $inset',
      (tester) async {
        final h = _Harness();
        h.sourceTransform.value = _scale(1.25);
        final reference = MorphMenuMotion(
          button: const Rect.fromLTWH(110, 140, 55, 55),
          bounds: _bounds,
          itemCount: 3,
          padding: inset
              ? const EdgeInsets.only(top: 100, bottom: 620)
              : EdgeInsets.zero,
          sourceHeight: 80,
          sourceRadius: 27.5,
        );
        final frames = ValueNotifier(0);
        addTearDown(frames.dispose);
        final expectedScene = GlobalKey();
        h.observe = (sample) {
          switch (sample.kind) {
            case .open:
              reference.open(sample.time);
            case .close:
              reference.close(sample.time);
            case .frame:
              reference.advance(sample.time);
            case .pointer:
            case .ignoredPointer:
            case .cancelInput:
              fail('This trace uses explicit open/close only.');
          }
          frames.value++;
        };
        await h.mount(
          tester,
          reference: RepaintBoundary(
            key: expectedScene,
            child: CustomPaint(painter: _ReferencePainter(reference, frames)),
          ),
        );
        if (inset) {
          tester.view.viewPadding = const FakeViewPadding(top: 100);
          tester.view.viewInsets = const FakeViewPadding(bottom: 620);
          await tester.pump();
        }
        final route = await h.open(tester);
        h.navigator.currentState!.pop();
        await _until(tester, () => route.handBack != null);
        var compared = 0;
        do {
          expect(h.source.currentState!.frame.time, reference.time);
          final actual = await _pixels(tester, h.scene);
          final expected = await _pixels(tester, expectedScene);
          expect(actual, orderedEquals(expected));
          compared++;
          if (h.model.isSettled) break;
          await tester.pump(_step);
        } while (compared < 150);
        expect(h.model.isSettled, isTrue);
        expect(compared, greaterThan(1));
        expect(tester.binding.transientCallbackCount, 0);
        final tag = inset ? 'P2_VIEWPORT_SCENE' : 'P2_GEOMETRY_SCENE';
        debugPrint('$tag {"frames":$compared,"changedPixels":0}');
      },
    );
  }

  testWidgets('later layout with valid boxes cannot invoke readiness or push', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    var attempt = false;
    var checks = 0;
    await tester.pumpWidget(
      _BeforeLayout(
        check: () {
          if (!attempt) return;
          checks++;
          expect(h.source.currentState!.open, throwsStateError);
        },
        child: h.app(tester),
      ),
    );
    attempt = true;
    final render = tester.renderObject<_LayoutCheck>(
      find.byType(_BeforeLayout),
    );
    render.checked = false;
    render.markNeedsLayout();
    await tester.pump();
    expect(checks, 1);
    expect(h.models, isEmpty);
    expect(h.observer.routes, isEmpty);
    final route = await h.open(tester);
    await h.finish(tester, route);
  });

  testWidgets('scaled source dimensions cannot overflow into model geometry', (
    tester,
  ) async {
    final h = _Harness(sourceHeight: double.maxFinite);
    h.sourceTransform.value = _scale(2);
    await h.mount(tester);
    expect(h.source.currentState!.open, throwsStateError);
    tester.widget<Semantics>(h.button).properties.onTap!();
    expect(h.models, isEmpty);
    expect(h.samples, isEmpty);
    expect(h.observer.routes, isEmpty);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'recognized tap uses measured geometry without raw pointer transport',
    (tester) async {
      final h = _Harness(pointerInput: false);
      await h.mount(tester);
      await tester.tapAt(tester.getCenter(h.button));
      expect(h.model.button, _button.shift(const Offset(80, 40)));
      final route = h.observer.routes.single;
      await h.finish(tester, route);
      expect(h.models, hasLength(1));
    },
  );

  testWidgets('readiness cover prevents stale semantic continuation', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    late Route<void> cover;
    h.ready = (_) {
      cover = PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => const SizedBox.expand(),
      );
      unawaited(h.navigator.currentState!.push<void>(cover));
    };
    tester.widget<Semantics>(h.button).properties.onTap!();
    await tester.pump();
    expect(cover.isCurrent, isTrue);
    expect(h.observer.routes, isEmpty);
    expect(h.models, hasLength(1));
    expect(h.model.isOpen, isFalse);
    expect(h.samples, isEmpty);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
