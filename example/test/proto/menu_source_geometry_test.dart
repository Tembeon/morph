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
  });

  final Size overlaySize;
  final bool scrolling;
  final double sourceHeight;
  final bool pointerInput;
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

  Widget sourceWidget(WidgetTester tester) => RepaintBoundary(
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
                microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
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

  testWidgets(
    'source inverse painting preserves the independent root contour throughout handback tail',
    (tester) async {
      final h = _Harness();
      h.sourceTransform.value = _scale(1.25);
      final reference = MorphMenuMotion(
        button: const Rect.fromLTWH(110, 140, 55, 55),
        bounds: _bounds,
        itemCount: 3,
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
      debugPrint('P2_GEOMETRY_SCENE {"frames":$compared,"changedPixels":0}');
    },
  );

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
