import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/motion.dart';
import 'package:morph_example/proto/menu_route_probe.dart';

const _button = Rect.fromLTWH(24, 80, 44, 44);
const _step = Duration(microseconds: 8333);

Future<void> _until(
  WidgetTester tester,
  bool Function() done, {
  Duration step = _step,
}) async {
  for (var i = 0; i < 600 * timeDilation && !done(); i++) {
    await tester.pump(step);
  }
  expect(done(), isTrue);
}

Future<int> _greenPixels(WidgetTester tester, GlobalKey scene) async {
  final boundary =
      scene.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final green = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var count = 0;
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      if (data.getUint8(i + 1) > data.getUint8(i)) count++;
    }
    image.dispose();
    return count;
  });
  return green!;
}

class _Observer extends NavigatorObserver {
  final routes = <ProbeMenuRoute>[];

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    if (route is ProbeMenuRoute) routes.add(route);
  }
}

class _Harness {
  _Harness({this.step = _step, this.useNested = false});

  final Duration step;
  final bool useNested;
  final nested = GlobalKey<NavigatorState>();
  final nav = GlobalKey<NavigatorState>();
  final source = GlobalKey<ProbeMenuSourceState>();
  final scene = GlobalKey();
  final observer = _Observer();
  final samples = <ProbeMenuSample>[];
  final models = <MorphMenuMotion>[];
  final editors = <_EditorState>[];
  final homeFocus = FocusNode();
  final showSource = ValueNotifier(true);
  final selected = <int>[];
  ValueChanged<ProbeMenuSample>? observe;
  bool Function(int presentation)? canPop;
  int builds = 0;

  Widget app(WidgetTester tester) => WidgetsApp(
    color: const Color(0xFFFFFFFF),
    navigatorKey: nav,
    navigatorObservers: [observer],
    builder: (_, child) => RepaintBoundary(key: scene, child: child),
    onGenerateRoute: (_) => PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => useNested
          ? Navigator(
              key: nested,
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                pageBuilder: (_, _, _) => page(tester),
              ),
            )
          : page(tester),
    ),
  );

  Widget page(WidgetTester tester) => Focus(
    focusNode: homeFocus,
    autofocus: true,
    child: ValueListenableBuilder<bool>(
      valueListenable: showSource,
      builder: (_, shown, child) => shown ? child! : const SizedBox.expand(),
      child: ProbeMenuSource(
        key: source,
        pointerInput: true,
        now: () => Duration(
          microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
        ),
        onSample: (sample) {
          samples.add(sample);
          observe?.call(sample);
        },
        createMotion: () {
          final model = MorphMenuMotion(
            button: _button,
            bounds: const Size(402, 874),
            itemCount: 3,
            sourceHeight: 64,
            sourceRadius: 22,
          );
          model.onSelected = selected.add;
          models.add(model);
          return model;
        },
        menuBuilder: (_) {
          builds++;
          return PopScope<void>(
            canPop: canPop?.call(builds) ?? true,
            child: _Editor(onMount: editors.add),
          );
        },
      ),
    ),
  );

  Future<ProbeMenuRoute> closing(WidgetTester tester, {int delay = 40}) async {
    await tester.pumpWidget(app(tester));
    await tester.tapAt(_button.center);
    final route = source.currentState!.activeRoute!;
    await _until(tester, () => route.animation!.isCompleted, step: step);
    await tester.pump();
    nav.currentState!.pop();
    await tester.pump();
    final elapsed = Duration(
      microseconds: (delay * 1000 * timeDilation).round(),
    );
    var pumped = Duration.zero;
    while (pumped < elapsed) {
      await tester.pump(step);
      pumped += step;
    }
    expect(route.handBack, isNull);
    expect(route.disposed, isFalse);
    expect(source.currentState!.ownsMotion, isFalse);
    if (delay == 40) expect(route.frame.contentOpacity, greaterThan(0));
    return route;
  }

  Future<void> finish(WidgetTester tester, ProbeMenuRoute route) async {
    nav.currentState!.pop();
    await _until(tester, () => route.disposed, step: step);
    await _until(tester, () => source.currentState!.motionSettled, step: step);
    expect(tester.binding.transientCallbackCount, 0);
  }

  Route<void> cover() {
    final route = PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => const SizedBox.expand(),
    );
    unawaited(nav.currentState!.push<void>(route));
    return route;
  }

  void dispose() {
    homeFocus.dispose();
    showSource.dispose();
  }
}

class _Editor extends StatefulWidget {
  const _Editor({required this.onMount});

  final ValueChanged<_EditorState> onMount;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final controller = TextEditingController();
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.onMount(this);
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF00FF00),
    child: EditableText(
      controller: controller,
      focusNode: focus,
      autofocus: true,
      style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
      cursorColor: const Color(0xFF000000),
      backgroundCursorColor: const Color(0xFFFFFFFF),
    ),
  );

  @override
  void dispose() {
    focus.dispose();
    controller.dispose();
    super.dispose();
  }
}

void main() {
  for (final rate in [60, 120]) {
    for (final dilation in [1.0, 5.0]) {
      for (final delay in [40, 300]) {
        testWidgets(
          'held reopen ${delay}ms at $rate Hz, ${dilation}x keeps input and model',
          (tester) async {
            final originalDilation = timeDilation;
            timeDilation = dilation;
            try {
              final h = _Harness(
                step: Duration(microseconds: (1e6 / rate).round()),
              );
              addTearDown(h.dispose);
              final reference = MorphMenuMotion(
                button: _button,
                bounds: const Size(402, 874),
                itemCount: 3,
                sourceHeight: 64,
                sourceRadius: 22,
              );
              var compared = 0;
              h.observe = (sample) {
                switch (sample.kind) {
                  case .frame:
                    reference.advance(sample.time);
                  case .open:
                    reference.open(sample.time);
                  case .close:
                    reference.close(sample.time);
                  case .cancelInput:
                    reference.pointerCancel(sample.time);
                  case .ignoredPointer:
                    return;
                  case .pointer:
                    switch (sample.event!) {
                      case PointerDownEvent(:final position):
                        reference.pointerDown(sample.time, position);
                      case PointerMoveEvent(:final position):
                        reference.pointerMove(sample.time, position);
                      case PointerUpEvent(:final position):
                        reference.pointerUp(sample.time, position);
                      case PointerCancelEvent():
                        reference.pointerCancel(sample.time);
                    }
                }
                expect(sample.frame.time, closeTo(reference.time, 1e-9));
                expect(
                  sample.frame.progress,
                  closeTo(reference.progress, 1e-9),
                );
                expect(
                  sample.frame.contentOpacity,
                  closeTo(reference.contentOpacity, 1e-9),
                );
                expect(
                  sample.frame.buttonKick,
                  closeTo(reference.buttonKick, 1e-8),
                );
                expect(
                  sample.frame.menuKick,
                  closeTo(reference.menuKick, 1e-8),
                );
                expect(
                  sample.frame.fusionRadius,
                  closeTo(reference.fusionRadius, 1e-8),
                );
                for (final (actual, expected) in [
                  (sample.frame.button, reference.buttonBlob.rrect),
                  (sample.frame.menu, reference.menuBlob.rrect),
                ]) {
                  expect(actual.left, closeTo(expected.left, 1e-8));
                  expect(actual.top, closeTo(expected.top, 1e-8));
                  expect(actual.right, closeTo(expected.right, 1e-8));
                  expect(actual.bottom, closeTo(expected.bottom, 1e-8));
                  expect(actual.tlRadiusX, closeTo(expected.tlRadiusX, 1e-8));
                }
                compared++;
              };
              final first = await h.closing(tester, delay: delay);
              h.samples.clear();
              final hold = await tester.startGesture(_button.center);
              final next = h.observer.routes.last;
              expect(next, isNot(same(first)));
              expect(h.source.currentState!.activeRoute, same(first));
              await _until(
                tester,
                () => next.animation!.isCompleted,
                step: h.step,
              );
              await hold.moveTo(next.frame.menu.outerRect.center);
              await hold.up();
              final events = h.samples
                  .where((sample) => sample.kind == .pointer)
                  .map((sample) => sample.event);
              expect(events, [
                isA<PointerDownEvent>(),
                isA<PointerMoveEvent>(),
                isA<PointerUpEvent>(),
              ]);
              await _until(tester, () => next.disposed, step: h.step);
              await _until(
                tester,
                () => h.source.currentState!.motionSettled,
                step: h.step,
              );
              expect(h.selected, hasLength(1));
              expect(h.models, hasLength(1));
              expect(compared, greaterThan(40));
              expect(first.handBack == null, delay == 40);
              expect(tester.binding.transientCallbackCount, 0);
            } finally {
              timeDilation = originalDilation;
            }
          },
        );
      }
    }
  }

  testWidgets(
    'new preparation retains painted outgoing content before reveal',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      final first = await h.closing(tester);
      final original = h.editors.single;
      original.controller.text = 'outgoing';
      final hold = await tester.startGesture(_button.center);
      final next = h.observer.routes.last;
      expect(next, isNot(same(first)));
      await tester.pump();
      expect(h.builds, 1);
      expect(original.mounted, isTrue);
      expect(original.controller.text, 'outgoing');
      expect(h.homeFocus.hasFocus, isTrue);
      expect(next.requestFocus, isFalse);
      expect(await _greenPixels(tester, h.scene), greaterThan(0));
      await _until(
        tester,
        () => h.builds == 2 && next.frame.contentOpacity > 0.01,
      );
      expect(await _greenPixels(tester, h.scene), greaterThan(0));
      await _until(tester, () => next.animation!.isCompleted);
      expect(h.editors, hasLength(2));
      final reopened = h.editors.last;
      expect(original.mounted, isFalse);
      expect(reopened.controller.text, isEmpty);
      expect(reopened.focus.hasFocus, isTrue);
      expect(h.builds, 2);
      await hold.cancel();
      await h.finish(tester, next);
    },
  );

  for (final cancellation in [
    'cancel',
    'outside release',
    'Back',
    'Back pending',
    'remove successor',
    'finalize predecessor',
    'source loss',
  ]) {
    testWidgets('reserved reopen terminates on $cancellation', (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      final first = await h.closing(tester);
      final hold = await tester.startGesture(_button.center);
      final reserved = h.observer.routes.last;
      await tester.pump();
      expect(h.source.currentState!.activeRoute, same(first));
      expect(h.builds, 1);
      switch (cancellation) {
        case 'cancel':
          await hold.cancel();
        case 'outside release':
          await hold.moveTo(const Offset(350, 500));
          await hold.up();
        case 'Back':
          expect(await h.nav.currentState!.maybePop(), isTrue);
          await hold.up();
        case 'Back pending':
          await hold.up();
          expect(h.models.single.isOpenPending, isTrue);
          expect(await h.nav.currentState!.maybePop(), isTrue);
          expect(h.models.single.isOpenPending, isFalse);
        case 'remove successor':
          h.nav.currentState!.removeRoute(reserved);
          await tester.pump();
          await hold.up();
        case 'finalize predecessor':
          h.nav.currentState!.finalizeRoute(first);
          await tester.pump();
          await hold.up();
        case 'source loss':
          h.showSource.value = false;
          await tester.pump();
          await hold.up();
      }
      await _until(tester, () => reserved.disposed && first.disposed);
      if (h.source.currentState case final state?) {
        await _until(tester, () => state.motionSettled);
      }
      expect(h.builds, 1);
      expect(h.selected, isEmpty);
      expect(
        h.models,
        hasLength(cancellation == 'finalize predecessor' ? 2 : 1),
      );
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  for (final committed in [false, true]) {
    testWidgets('cover distinguishes held and committed reopen: $committed', (
      tester,
    ) async {
      final h = _Harness();
      addTearDown(h.dispose);
      final first = await h.closing(tester);
      final hold = await tester.startGesture(_button.center);
      final reserved = h.observer.routes.last;
      if (committed) await hold.up();
      final cover = h.cover();
      await tester.pump();
      expect(cover.isCurrent, isTrue);
      if (committed) {
        await _until(tester, () => h.models.single.isSettled);
        expect(h.builds, 1);
        expect(reserved.requestFocus, isFalse);
        expect(h.source.currentState!.activeRoute, same(reserved));
      } else {
        await hold.up();
        await _until(tester, () => reserved.disposed && first.disposed);
        await _until(tester, () => h.source.currentState!.motionSettled);
        expect(h.builds, 1);
      }
      expect(cover.isCurrent, isTrue);
      h.nav.currentState!.pop();
      await tester.pump();
      if (committed) {
        await _until(tester, () => reserved.animation!.isCompleted);
        expect(h.builds, 2);
        expect(h.editors.last.focus.hasFocus, isTrue);
        await h.finish(tester, reserved);
      }
      expect(h.models, hasLength(1));
      expect(h.selected, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets(
    'semantic activation promotes its reserved route on actual owner',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.closing(tester);
        final hold = await tester.startGesture(_button.center);
        final reserved = h.observer.routes.last;
        await tester.pump();
        tester.semantics.tap(find.semantics.byLabel('Open prototype menu'));
        await hold.up();
        await _until(tester, () => reserved.animation!.isCompleted);
        expect(h.source.currentState!.activeRoute, same(reserved));
        expect(h.samples.where((s) => s.kind == .open), hasLength(1));
        expect(h.models, hasLength(1));
        expect(h.builds, 2);
        expect(h.selected, isEmpty);
        await h.finish(tester, reserved);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('fresh successor policy applies before its first dismissal', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.canPop = (presentation) => presentation == 1;
    await h.closing(tester);
    final hold = await tester.startGesture(_button.center);
    final reserved = h.observer.routes.last;
    await _until(tester, () => h.source.currentState!.activeRoute == reserved);
    expect(await h.nav.currentState!.maybePop(), isTrue);
    await tester.pump();
    expect(reserved.closing, isFalse);
    expect(reserved.isCurrent, isTrue);
    await hold.cancel();
    await h.finish(tester, reserved);
  });

  testWidgets('nested cover revokes a hold without another gesture update', (
    tester,
  ) async {
    final h = _Harness(useNested: true);
    addTearDown(h.dispose);
    final first = await h.closing(tester);
    final hold = await tester.startGesture(_button.center);
    final reserved = h.observer.routes.last;
    final cover = PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => const SizedBox.expand(),
    );
    unawaited(h.nested.currentState!.push<void>(cover));
    await tester.pump(const Duration(milliseconds: 500));
    expect(h.builds, 1);
    await _until(tester, () => reserved.disposed && first.disposed);
    await hold.up();
    expect(cover.isCurrent, isTrue);
    expect(h.builds, 1);
    expect(h.selected, isEmpty);
    h.nested.currentState!.pop();
    await tester.pump();
    await _until(tester, () => h.source.currentState!.motionSettled);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'cover from semantic cancellation aborts reservation activation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final h = _Harness();
        addTearDown(h.dispose);
        final first = await h.closing(tester);
        final hold = await tester.startGesture(_button.center);
        final reserved = h.observer.routes.last;
        await tester.pump();
        Route<void>? cover;
        h.observe = (sample) {
          if (sample.kind == .cancelInput) {
            h.observe = null;
            cover = h.cover();
          }
        };
        tester.semantics.tap(find.semantics.byLabel('Open prototype menu'));
        await hold.up();
        await _until(tester, () => reserved.disposed && first.disposed);
        await _until(tester, () => h.source.currentState!.motionSettled);
        expect(cover!.isCurrent, isTrue);
        expect(h.samples.where((s) => s.kind == .open), isEmpty);
        expect(h.builds, 1);
        h.nav.currentState!.pop();
        await tester.pump();
        expect(tester.binding.transientCallbackCount, 0);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'removal at hold opening cannot promote the removed reservation',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      final first = await h.closing(tester);
      final hold = await tester.startGesture(_button.center);
      final reserved = h.observer.routes.last;
      h.observe = (sample) {
        if (sample.kind == .frame && h.models.single.isOpen) {
          h.observe = null;
          h.nav.currentState!.removeRoute(reserved);
        }
      };
      await _until(tester, () => reserved.disposed);
      await hold.up();
      await _until(tester, () => first.disposed);
      await _until(tester, () => h.source.currentState!.motionSettled);
      expect(h.source.currentState!.activeRoute, isNull);
      expect(h.builds, 1);
      expect(h.selected, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('source page removal at opening consumes its reserved attempt', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFFFFFFFF),
        navigatorKey: h.nav,
        navigatorObservers: [h.observer],
        onGenerateRoute: (_) => PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const SizedBox.expand(),
        ),
      ),
    );
    final page = PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => h.page(tester),
    );
    unawaited(h.nav.currentState!.push<void>(page));
    await tester.pump();
    await tester.tapAt(_button.center);
    final first = h.source.currentState!.activeRoute!;
    await _until(tester, () => first.animation!.isCompleted);
    h.nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final hold = await tester.startGesture(_button.center);
    final reserved = h.observer.routes.last;
    h.observe = (sample) {
      if (sample.kind == .frame && h.models.single.isOpen) {
        h.observe = null;
        h.nav.currentState!.removeRoute(page);
      }
    };
    await _until(tester, () => reserved.disposed && first.disposed);
    await hold.up();
    expect(h.source.currentState, isNull);
    expect(h.observer.routes, hasLength(2));
    expect(h.builds, 1);
    expect(h.selected, isEmpty);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
