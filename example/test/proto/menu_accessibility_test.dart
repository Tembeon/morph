import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph_example/proto/menu_route_probe.dart';
import 'package:morph/motion.dart';

const _step = Duration(microseconds: 8333);
const _button = Rect.fromLTWH(24, 80, 44, 44);

class _Harness {
  final navigator = GlobalKey<NavigatorState>();
  final source = GlobalKey<ProbeMenuSourceState>();
  final nested = GlobalKey<NavigatorState>();
  final samples = <ProbeMenuSample>[];
  Widget Function(Widget)? decorateMenu;
  ValueChanged<ProbeMenuSample>? observe;
  MorphMenuMotion Function()? createMotion;
  final canPop = ValueNotifier(true);
  final focus = FocusNode();
  int builds = 0;
  int backgroundTaps = 0;
  int popNotifications = 0;

  Widget app(
    WidgetTester tester, {
    bool pointer = true,
    bool useNested = false,
  }) => WidgetsApp(
    color: const Color(0xFFFFFFFF),
    navigatorKey: navigator,
    onGenerateRoute: (_) => PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => useNested
          ? Navigator(
              key: nested,
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                pageBuilder: (_, _, _) => page(tester, pointer: pointer),
              ),
            )
          : page(tester, pointer: pointer),
    ),
  );

  Widget page(WidgetTester tester, {required bool pointer}) => Stack(
    fit: .expand,
    children: [
      Semantics(
        label: 'Background',
        button: true,
        onTap: () => backgroundTaps++,
        child: const SizedBox.expand(),
      ),
      Focus(
        focusNode: focus,
        autofocus: true,
        child: ProbeMenuSource(
          key: source,
          pointerInput: pointer,
          createMotion: createMotion,
          onSample: (sample) {
            samples.add(sample);
            observe?.call(sample);
          },
          now: () => Duration(
            microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
          ),
          menuBuilder: (_) {
            builds++;
            final content = ValueListenableBuilder<bool>(
              valueListenable: canPop,
              builder: (_, allowed, _) => PopScope<void>(
                canPop: allowed,
                onPopInvokedWithResult: (_, _) => popNotifications++,
                child: Semantics(
                  label: 'Menu content',
                  container: true,
                  child: const SizedBox.expand(),
                ),
              ),
            );
            return decorateMenu?.call(content) ?? content;
          },
        ),
      ),
    ],
  );

  Future<ProbeMenuRoute> open(WidgetTester tester) async {
    await tester.tapAt(_button.center);
    final route = source.currentState!.activeRoute!;
    await _until(tester, () => route.animation!.isCompleted);
    return route;
  }

  Future<void> finish(WidgetTester tester, ProbeMenuRoute route) async {
    await _until(tester, () => route.disposed);
    if (source.currentState case final state?) {
      await _until(tester, () => state.motionSettled);
    }
    expect(tester.binding.transientCallbackCount, 0);
  }

  void dispose() {
    focus.dispose();
    canPop.dispose();
  }
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await tester.pump(_step);
  }
  expect(done(), isTrue);
}

Rect _semanticRect(SemanticsNode node) {
  var rect = node.rect;
  SemanticsNode? current = node;
  while (current != null) {
    final transform = current.transform;
    if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
    current = current.parent;
  }
  return rect;
}

void _testSemantics(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    final semantics = tester.ensureSemantics();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body(tester);
    } finally {
      semantics.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  _testSemantics(
    'semantic activation opens the raw pointer source without a gesture',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await tester.pumpWidget(h.app(tester));
      final source = find.semantics.byLabel('Open prototype menu');
      expect(source, findsOneWidget);
      final node = source.evaluate().single;
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isExpanded, ui.Tristate.isFalse);
      tester.semantics.tap(source);
      await tester.pump();
      final route = h.source.currentState!.activeRoute!;
      await _until(tester, () => route.animation!.isCompleted);
      expect(h.builds, 1);
      expect(h.samples.where((s) => s.kind == .pointer), isEmpty);
      expect(h.samples.where((s) => s.kind == .open), hasLength(1));
      expect(find.semantics.byLabel('Menu content'), findsOneWidget);
      h.navigator.currentState!.pop();
      await h.finish(tester, route);
    },
  );

  _testSemantics(
    'hidden preparation keeps page semantics until actual reveal',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await tester.pumpWidget(h.app(tester));
      await tester.pump();
      expect(h.focus.hasFocus, isTrue);
      final hold = await tester.startGesture(_button.center);
      final route = h.source.currentState!.activeRoute!;
      await tester.pump(const Duration(milliseconds: 50));
      expect(h.builds, 0);
      expect(find.semantics.byLabel('Background'), findsOneWidget);
      expect(find.semantics.byLabel('Menu content'), findsNothing);
      expect(h.focus.hasFocus, isTrue);
      await hold.cancel();
      await h.finish(tester, route);
      expect(find.semantics.byLabel('Background'), findsOneWidget);
    },
  );

  for (final pointer in [false, true]) {
    _testSemantics(
      'revealed popup owns scoped semantics and hides page: pointer=$pointer',
      (tester) async {
        final h = _Harness();
        addTearDown(h.dispose);
        await tester.pumpWidget(h.app(tester, pointer: pointer));
        final route = await h.open(tester);
        expect(find.semantics.byLabel('Background'), findsNothing);
        expect(find.semantics.byLabel('Menu content'), findsOneWidget);
        expect(
          find.semantics.byPredicate(
            (node) => node.flagsCollection.scopesRoute,
          ),
          findsOneWidget,
        );
        expect(
          find.semantics.byPredicate((node) => node.flagsCollection.namesRoute),
          findsOneWidget,
        );
        h.navigator.currentState!.pop();
        await h.finish(tester, route);
        expect(find.semantics.byLabel('Background'), findsOneWidget);
        expect(h.focus.hasFocus, isTrue);
      },
    );

    _testSemantics(
      'semantic dismiss honors PopScope then closes once: pointer=$pointer',
      (tester) async {
        final h = _Harness();
        addTearDown(h.dispose);
        h.canPop.value = false;
        await tester.pumpWidget(h.app(tester, pointer: pointer));
        final route = await h.open(tester);
        final dismiss = find.semantics.byPredicate(
          (node) => node.getSemanticsData().hasAction(SemanticsAction.dismiss),
        );
        expect(dismiss, findsOneWidget);
        tester.semantics.performAction(dismiss, SemanticsAction.dismiss);
        await tester.pump();
        expect(route.closing, isFalse);
        expect(h.popNotifications, 1);
        h.canPop.value = true;
        await tester.pump();
        tester.semantics.performAction(dismiss, SemanticsAction.dismiss);
        await tester.pump();
        expect(route.closing, isTrue);
        expect(h.popNotifications, 2);
        await h.finish(tester, route);
      },
    );
  }

  _testSemantics(
    'logical pop removes obsolete menu semantics before landing tail',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await tester.pumpWidget(h.app(tester));
      final route = await h.open(tester);
      h.navigator.currentState!.pop();
      await tester.pump();
      expect(route.disposed, isFalse);
      expect(find.semantics.byLabel('Menu content'), findsNothing);
      expect(find.semantics.byLabel('Background'), findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel('Background'));
      expect(h.backgroundTaps, 1);
      await h.finish(tester, route);
    },
  );

  _testSemantics('semantic bounds follow painted menu during opening frames', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.app(tester));
    await tester.tapAt(_button.center);
    final route = h.source.currentState!.activeRoute!;
    var compared = 0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(_step);
      final nodes = find.semantics.byLabel('Menu content').evaluate();
      if (nodes.isEmpty || route.frame.contentOpacity <= 0.01) continue;
      final physical = _semanticRect(nodes.single);
      final ratio = tester.view.devicePixelRatio;
      final actual = Rect.fromLTRB(
        physical.left / ratio,
        physical.top / ratio,
        physical.right / ratio,
        physical.bottom / ratio,
      );
      final expected = route.frame.menu.outerRect;
      expect(actual.left, closeTo(expected.left, 1e-6));
      expect(actual.top, closeTo(expected.top, 1e-6));
      expect(actual.width, closeTo(expected.width, 1e-6));
      expect(actual.height, closeTo(expected.height, 1e-6));
      compared++;
    }
    expect(compared, greaterThan(20));
    h.navigator.currentState!.pop();
    await h.finish(tester, route);
  });

  for (final nested in [false, true]) {
    _testSemantics(
      'semantic activation takes over own hidden hold: nested=$nested',
      (tester) async {
        final h = _Harness();
        addTearDown(h.dispose);
        await tester.pumpWidget(h.app(tester, useNested: nested));
        final hold = await tester.startGesture(_button.center);
        final route = h.source.currentState!.activeRoute!;
        await tester.pump(const Duration(milliseconds: 50));
        expect(h.builds, 0);
        tester.semantics.tap(find.semantics.byLabel('Open prototype menu'));
        final delivered = h.samples.where((s) => s.kind == .pointer).length;
        await hold.up();
        await _until(tester, () => route.animation!.isCompleted);
        expect(h.source.currentState!.activeRoute, same(route));
        expect(
          h.samples.where((s) => s.kind == .pointer),
          hasLength(delivered),
        );
        expect(h.samples.where((s) => s.kind == .open), hasLength(1));
        expect(h.builds, 1);
        h.navigator.currentState!.pop();
        await h.finish(tester, route);
      },
    );

    _testSemantics(
      'stale source action cannot open below a cover: nested=$nested',
      (tester) async {
        final h = _Harness();
        addTearDown(h.dispose);
        await tester.pumpWidget(h.app(tester, useNested: nested));
        final node = find.semantics
            .byLabel('Open prototype menu')
            .evaluate()
            .single;
        final owner = node.owner!;
        final cover = PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const SizedBox.expand(),
        );
        final navigator = nested
            ? h.nested.currentState!
            : h.navigator.currentState!;
        unawaited(navigator.push<void>(cover));
        owner.performAction(node.id, SemanticsAction.tap);
        await tester.pump();
        expect(h.source.currentState!.activeRoute, isNull);
        expect(h.builds, 0);
        expect(cover.isCurrent, isTrue);
        navigator.pop();
        await tester.pump();
      },
    );
  }

  for (final popFirst in [false, true]) {
    _testSemantics(
      'stale dismiss cannot pop a covering route: popped=$popFirst',
      (tester) async {
        final h = _Harness();
        addTearDown(h.dispose);
        await tester.pumpWidget(h.app(tester));
        final route = await h.open(tester);
        final node = find.semantics
            .byPredicate(
              (node) =>
                  node.getSemanticsData().hasAction(SemanticsAction.dismiss),
            )
            .evaluate()
            .single;
        final owner = node.owner!;
        if (popFirst) h.navigator.currentState!.pop();
        final cover = PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const SizedBox.expand(),
        );
        unawaited(h.navigator.currentState!.push<void>(cover));
        owner.performAction(node.id, SemanticsAction.dismiss);
        await tester.pump();
        expect(cover.isCurrent, isTrue);
        h.navigator.currentState!.pop();
        await tester.pump();
        if (!popFirst) h.navigator.currentState!.pop();
        await h.finish(tester, route);
      },
    );
  }

  _testSemantics(
    'concurrent semantic dismiss shares async permission and pops once',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      final permission = Completer<bool>();
      var calls = 0;
      // ignore: deprecated_member_use
      h.decorateMenu = (child) => WillPopScope(
        onWillPop: () {
          calls++;
          return permission.future;
        },
        child: child,
      );
      await tester.pumpWidget(h.app(tester));
      final route = await h.open(tester);
      final dismiss = find.semantics.byPredicate(
        (node) => node.getSemanticsData().hasAction(SemanticsAction.dismiss),
      );
      tester.semantics.performAction(dismiss, SemanticsAction.dismiss);
      tester.semantics.performAction(dismiss, SemanticsAction.dismiss);
      await tester.pump();
      expect(calls, 1);
      expect(route.closing, isFalse);
      permission.complete(true);
      await tester.pump();
      expect(h.popNotifications, 1);
      expect(route.closing, isTrue);
      await h.finish(tester, route);
    },
  );

  _testSemantics(
    'semantic dismiss consumes local history before closing menu',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await tester.pumpWidget(h.app(tester));
      final route = await h.open(tester);
      var removed = 0;
      route.addLocalHistoryEntry(LocalHistoryEntry(onRemove: () => removed++));
      final dismiss = find.semantics.byPredicate(
        (node) => node.getSemanticsData().hasAction(SemanticsAction.dismiss),
      );
      tester.semantics.performAction(dismiss, SemanticsAction.dismiss);
      await tester.pump();
      expect(removed, 1);
      expect(route.closing, isFalse);
      tester.semantics.performAction(dismiss, SemanticsAction.dismiss);
      await tester.pump();
      expect(route.closing, isTrue);
      await h.finish(tester, route);
    },
  );

  _testSemantics(
    'removed source page cannot activate its retained hidden popup',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFFFFFFFF),
          navigatorKey: h.navigator,
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => const SizedBox.expand(),
          ),
        ),
      );
      final sourcePage = PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => h.page(tester, pointer: true),
      );
      unawaited(h.navigator.currentState!.push<void>(sourcePage));
      await tester.pump();
      final hold = await tester.startGesture(_button.center);
      final route = h.source.currentState!.activeRoute!;
      await tester.pump(const Duration(milliseconds: 50));
      final node = find.semantics
          .byLabel('Open prototype menu')
          .evaluate()
          .single;
      final owner = node.owner!;
      h.navigator.currentState!.removeRoute(sourcePage);
      expect(sourcePage.isActive, isFalse);
      expect(h.source.currentState, isNotNull);
      owner.performAction(node.id, SemanticsAction.tap);
      expect(h.samples.where((s) => s.kind == .open), isEmpty);
      expect(h.builds, 0);
      await hold.cancel();
      await h.finish(tester, route);
    },
  );

  _testSemantics(
    'own hidden popup does not exempt a newly covered nested page',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await tester.pumpWidget(h.app(tester, useNested: true));
      final hold = await tester.startGesture(_button.center);
      final route = h.source.currentState!.activeRoute!;
      await tester.pump(const Duration(milliseconds: 50));
      final node = find.semantics
          .byLabel('Open prototype menu')
          .evaluate()
          .single;
      final owner = node.owner!;
      final cover = PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => const SizedBox.expand(),
      );
      unawaited(h.nested.currentState!.push<void>(cover));
      owner.performAction(node.id, SemanticsAction.tap);
      expect(h.samples.where((s) => s.kind == .open), isEmpty);
      await hold.cancel();
      await tester.pump();
      expect(h.builds, 0);
      h.nested.currentState!.pop();
      await h.finish(tester, route);
    },
  );

  _testSemantics('cover from held cancellation aborts semantic activation', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.app(tester));
    final hold = await tester.startGesture(_button.center);
    final route = h.source.currentState!.activeRoute!;
    await tester.pump(const Duration(milliseconds: 50));
    final cover = PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => const SizedBox.expand(),
    );
    h.observe = (sample) {
      if (sample.kind == .cancelInput) {
        h.observe = null;
        unawaited(h.navigator.currentState!.push<void>(cover));
      }
    };
    tester.semantics.tap(find.semantics.byLabel('Open prototype menu'));
    expect(h.samples.where((s) => s.kind == .open), isEmpty);
    await hold.up();
    await tester.pump();
    expect(cover.isCurrent, isTrue);
    expect(h.builds, 0);
    var coverFinished = false;
    unawaited(cover.completed.then((_) => coverFinished = true));
    h.navigator.currentState!.pop();
    await _until(tester, () => coverFinished);
    if (!route.closing) h.navigator.currentState!.pop();
    await h.finish(tester, route);
  });

  _testSemantics(
    'removal from semantic open observation stops stale publication',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await tester.pumpWidget(h.app(tester));
      h.observe = (sample) {
        if (sample.kind == .open) {
          h.observe = null;
          h.navigator.currentState!.removeRoute(
            h.source.currentState!.activeRoute!,
          );
        }
      };
      tester.semantics.tap(find.semantics.byLabel('Open prototype menu'));
      await tester.pump();
      expect(h.source.currentState!.activeRoute, isNull);
      expect(h.builds, 0);
      expect(tester.binding.transientCallbackCount, 0);
      final next = await h.open(tester);
      h.navigator.currentState!.pop();
      await h.finish(tester, next);
    },
  );

  _testSemantics(
    'covered hidden cancellation retains the entire press relaxation',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      final models = <MorphMenuMotion>[];
      MorphMenuMotion motion() => MorphMenuMotion(
        button: _button,
        bounds: const Size(402, 874),
        itemCount: 3,
        sourceHeight: 64,
        sourceRadius: 22,
      );
      final reference = motion();
      h.createMotion = () {
        if (models.isNotEmpty) expect(models.last.isSettled, isTrue);
        final model = motion();
        models.add(model);
        return model;
      };
      final cover = PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => const SizedBox.expand(),
      );
      var compared = 0;
      h.observe = (sample) {
        switch (sample.kind) {
          case .frame:
            reference.advance(sample.time);
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
              default:
                fail('Only pointer commands belong to this replay');
            }
          case .cancelInput:
            reference.pointerCancel(sample.time);
            unawaited(h.navigator.currentState!.push<void>(cover));
          case .close:
            reference.close(sample.time);
          case .open:
            fail('The canceled hidden press must never open');
          case .ignoredPointer:
            return;
        }
        expect(models.first.pressScale, closeTo(reference.pressScale, 1e-9));
        expect(models.first.time, closeTo(reference.time, 1e-9));
        compared++;
      };
      await tester.pumpWidget(h.app(tester));
      final hold = await tester.startGesture(_button.center);
      final route = h.source.currentState!.activeRoute!;
      await tester.pump(const Duration(milliseconds: 50));
      expect(models.first.pressScale, isNot(closeTo(1, 1e-4)));
      tester.semantics.tap(find.semantics.byLabel('Open prototype menu'));
      await hold.up();
      await _until(tester, () => route.disposed);
      expect(models.first.isSettled, isTrue);
      expect(compared, greaterThan(10));
      expect(cover.isCurrent, isTrue);
      expect(h.builds, 0);
      h.observe = null;
      h.navigator.currentState!.pop();
      await tester.pump();
      await h.finish(tester, route);
    },
  );
}
