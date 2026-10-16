import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/motion.dart';
import 'package:morph_example/proto/menu_route_probe.dart';

const _button = Rect.fromLTWH(24, 80, 44, 44);
const _step = Duration(microseconds: 8333);

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await tester.pump(_step);
  }
  expect(done(), isTrue);
}

class _Harness {
  final root = GlobalKey<NavigatorState>();
  final nested = GlobalKey<NavigatorState>();
  final source = GlobalKey<ProbeMenuSourceState>();
  final focus = FocusNode();
  final samples = <ProbeMenuSample>[];
  final selected = <int>[];
  final models = <MorphMenuMotion>[];
  int topDowns = 0;
  int builds = 0;
  VoidCallback? onSelected;
  VoidCallback? onTracked;

  Widget app(WidgetTester tester, {bool useNested = false}) => WidgetsApp(
    color: const Color(0xFFFFFFFF),
    navigatorKey: root,
    onGenerateRoute: (_) => PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => content(tester, useNested: useNested),
    ),
  );

  Widget content(WidgetTester tester, {bool useNested = false}) {
    final button = Focus(
      focusNode: focus,
      autofocus: true,
      child: ProbeMenuSource(
        key: source,
        pointerInput: true,
        now: () => Duration(
          microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
        ),
        onSample: samples.add,
        createMotion: () {
          final model = MorphMenuMotion(
            button: _button,
            bounds: const Size(402, 874),
            itemCount: 3,
            sourceHeight: 64,
            sourceRadius: 22,
          );
          model.onSelected = (index) {
            selected.add(index);
            onSelected?.call();
          };
          model.onTrackedHighlight = () => onTracked?.call();
          models.add(model);
          return model;
        },
        menuBuilder: (_) {
          builds++;
          return const SizedBox.expand();
        },
      ),
    );
    if (!useNested) return button;
    return Navigator(
      key: nested,
      onGenerateRoute: (_) => PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => button,
      ),
    );
  }

  Future<ProbeMenuRoute> open(WidgetTester tester) async {
    await tester.tapAt(_button.center);
    final route = source.currentState!.activeRoute!;
    await _until(tester, () => route.animation!.isCompleted);
    return route;
  }

  Route<void> cover({bool opaque = true}) {
    final route = PageRouteBuilder<void>(
      opaque: opaque,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => Listener(
        behavior: .opaque,
        onPointerDown: (_) => topDowns++,
        child: const SizedBox.expand(),
      ),
    );
    unawaited(root.currentState!.push<void>(route));
    return route;
  }

  Future<void> close(WidgetTester tester, ProbeMenuRoute route) async {
    root.currentState!.pop();
    await _until(tester, () => route.disposed);
    await _until(tester, () => source.currentState!.motionSettled);
    expect(tester.binding.transientCallbackCount, 0);
  }
}

class _RootDelegate extends RouterDelegate<Object>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Object> {
  _RootDelegate(this.navigatorKey, this.home);

  @override
  final GlobalKey<NavigatorState> navigatorKey;
  final WidgetBuilder home;

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    onGenerateRoute: (_) => PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => home(context),
    ),
  );

  @override
  Future<void> setNewRoutePath(Object configuration) async {}
}

class _ChildDelegate extends RouterDelegate<Object> with ChangeNotifier {
  _ChildDelegate(this.child);

  final Widget child;
  int backCalls = 0;

  @override
  Widget build(BuildContext context) => child;

  @override
  Future<bool> popRoute() async {
    backCalls++;
    return true;
  }

  @override
  Future<void> setNewRoutePath(Object configuration) async {}
}

void main() {
  testWidgets(
    'covered closed source cannot acquire a pointer from another page',
    (tester) async {
      final h = _Harness();
      addTearDown(h.focus.dispose);
      await tester.pumpWidget(h.app(tester));
      h.cover();
      await tester.pump();
      h.samples.clear();
      await tester.tapAt(_button.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(h.topDowns, 1);
      expect(h.samples.where((s) => s.kind == .pointer), isEmpty);
      expect(h.source.currentState!.activeRoute, isNull);
      expect(h.models.single.isArming, isFalse);
      expect(h.builds, 0);
    },
  );

  for (final opaque in [false, true]) {
    testWidgets(
      'covered open menu ignores the top page gesture, opaque=$opaque',
      (tester) async {
        final h = _Harness();
        addTearDown(h.focus.dispose);
        await tester.pumpWidget(h.app(tester));
        final route = await h.open(tester);
        h.cover(opaque: opaque);
        await tester.pump();
        h.samples.clear();
        final gesture = await tester.startGesture(
          route.frame.menu.outerRect.center,
        );
        await gesture.moveBy(const Offset(0, 8));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 500));
        expect(h.topDowns, 1);
        expect(h.samples.where((s) => s.kind == .pointer), isEmpty);
        expect(h.selected, isEmpty);
        expect(route.closing, isFalse);
        h.root.currentState!.pop();
        await tester.pump();
        await tester.tapAt(route.frame.menu.outerRect.center);
        await _until(tester, () => route.disposed);
        await _until(tester, () => h.source.currentState!.motionSettled);
        expect(h.selected, hasLength(1));
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  for (final fromSource in [false, true]) {
    for (final immediateUncover in [false, true]) {
      testWidgets(
        'cover revokes held input: source=$fromSource, uncover=$immediateUncover',
        (tester) async {
          final h = _Harness();
          addTearDown(h.focus.dispose);
          await tester.pumpWidget(h.app(tester));
          late final TestGesture gesture;
          late final ProbeMenuRoute route;
          if (fromSource) {
            gesture = await tester.startGesture(_button.center);
            route = h.source.currentState!.activeRoute!;
            await _until(tester, () => route.animation!.isCompleted);
            await gesture.moveTo(route.frame.menu.outerRect.center);
          } else {
            route = await h.open(tester);
            gesture = await tester.startGesture(
              route.frame.menu.outerRect.center,
            );
          }
          expect(h.models.single.highlighted, isNotNull);
          h.cover();
          expect(h.models.single.highlighted, isNull);
          if (immediateUncover) h.root.currentState!.pop();
          await tester.pump();
          await gesture.moveBy(const Offset(0, 8));
          await gesture.up();
          await tester.pump(const Duration(milliseconds: 500));
          expect(h.selected, isEmpty);
          expect(route.closing, isFalse);
          expect(h.models.single.glowOpacity, 0);
          if (!immediateUncover) {
            h.root.currentState!.pop();
            await tester.pump();
          }
          await tester.tapAt(route.frame.menu.outerRect.center);
          await _until(tester, () => route.disposed);
          await _until(tester, () => h.source.currentState!.motionSettled);
          expect(h.selected, hasLength(1));
        },
      );
    }
  }

  testWidgets(
    'cover preserves an action already committed by a valid release',
    (tester) async {
      final h = _Harness();
      addTearDown(h.focus.dispose);
      await tester.pumpWidget(h.app(tester));
      final route = await h.open(tester);
      await tester.tapAt(route.frame.menu.outerRect.center);
      expect(h.selected, isEmpty);
      h.cover();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(h.selected, hasLength(1));
      expect(route.closing, isFalse);
      expect(route.isCurrent, isFalse);
      h.root.currentState!.pop();
      await tester.pump();
      await h.close(tester, route);
    },
  );

  testWidgets(
    'cover from tracked highlight cancels relaxation after command exits',
    (tester) async {
      final h = _Harness();
      addTearDown(h.focus.dispose);
      await tester.pumpWidget(h.app(tester));
      final route = await h.open(tester);
      h.onTracked = () {
        h.onTracked = null;
        h.cover();
      };
      final gesture = await tester.startGesture(
        route.frame.menu.outerRect.center,
      );
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(h.selected, isEmpty);
      expect(h.models.single.highlighted, isNull);
      expect(h.models.single.glowOpacity, 0);
      h.root.currentState!.pop();
      await tester.pump();
      await h.close(tester, route);
    },
  );

  testWidgets('due action cover prevents a new release from committing', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.focus.dispose);
    await tester.pumpWidget(h.app(tester));
    final route = await h.open(tester);
    h.onSelected = () {
      if (h.selected.length == 1) h.cover();
    };
    final first = await tester.createGesture();
    await first.down(route.frame.menu.outerRect.center);
    await first.up(timeStamp: const Duration(milliseconds: 10));
    final second = await tester.createGesture();
    await second.down(
      route.frame.menu.outerRect.center,
      timeStamp: const Duration(milliseconds: 20),
    );
    await second.up(timeStamp: const Duration(milliseconds: 100));
    expect(h.selected, hasLength(1));
    expect(route.isCurrent, isFalse);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(h.selected, hasLength(1));
    expect(route.closing, isFalse);
    h.root.currentState!.pop();
    await tester.pump();
    await h.close(tester, route);
  });

  for (final opaque in [false, true]) {
    testWidgets('covered source tail honors SDK TickerMode, opaque=$opaque', (
      tester,
    ) async {
      final h = _Harness();
      addTearDown(h.focus.dispose);
      await tester.pumpWidget(h.app(tester, useNested: true));
      final route = await h.open(tester);
      h.root.currentState!.pop();
      await _until(tester, () => route.handBack != null);
      expect(h.source.currentState!.motionSettled, isFalse);
      h.cover(opaque: opaque);
      await tester.pump();
      h.samples.clear();
      await tester.tapAt(_button.center);
      if (opaque) {
        final frames = h.source.currentState!.motionFrames;
        await tester.pump(const Duration(seconds: 1));
        expect(h.source.currentState!.motionFrames, frames);
        expect(h.source.currentState!.motionSettled, isFalse);
        h.root.currentState!.pop();
        await tester.pump();
      }
      await _until(tester, () => h.source.currentState!.motionSettled);
      expect(h.samples.where((s) => s.kind == .pointer), isEmpty);
      expect(h.source.currentState!.activeRoute, isNull);
      expect(h.topDowns, 1);
      expect(route.disposed, isTrue);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets(
    'force removal inside tracking skips stale observation and old clock',
    (tester) async {
      final h = _Harness();
      addTearDown(h.focus.dispose);
      await tester.pumpWidget(h.app(tester));
      final route = await h.open(tester);
      h.samples.clear();
      h.onTracked = () {
        h.onTracked = null;
        h.root.currentState!.removeRoute(route);
      };
      final gesture = await tester.startGesture(
        route.frame.menu.outerRect.center,
      );
      await gesture.up();
      await tester.pump();
      expect(route.disposed, isTrue);
      expect(h.source.currentState!.activeRoute, isNull);
      expect(h.samples.where((s) => s.kind == .pointer), isEmpty);
      expect(h.models, hasLength(2));
      final next = await h.open(tester);
      await h.close(tester, next);
      expect(h.selected, isEmpty);
    },
  );

  testWidgets(
    'frame callback removal does not publish a replacement model as the old route',
    (tester) async {
      final h = _Harness();
      addTearDown(h.focus.dispose);
      await tester.pumpWidget(h.app(tester));
      final route = await h.open(tester);
      h.onSelected = () {
        h.onSelected = null;
        h.root.currentState!.removeRoute(route);
      };
      await tester.tapAt(route.frame.menu.outerRect.center);
      h.samples.clear();
      await _until(tester, () => route.disposed);
      expect(h.models, hasLength(2));
      expect(
        h.samples.where((s) => s.kind == .frame && s.frame.time == 0),
        isEmpty,
      );
      expect(h.source.currentState!.motionSettled, isTrue);
      expect(h.selected, hasLength(1));
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'another source cannot acquire through a hidden current preparation',
    (tester) async {
      final root = GlobalKey<NavigatorState>();
      final first = GlobalKey<ProbeMenuSourceState>();
      final second = GlobalKey<ProbeMenuSourceState>();
      var builds = 0;
      Widget button(GlobalKey<ProbeMenuSourceState> key, Rect bounds) =>
          ProbeMenuSource(
            key: key,
            button: bounds,
            pointerInput: true,
            now: () => Duration(
              microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
            ),
            menuBuilder: (_) {
              builds++;
              return const SizedBox.expand();
            },
          );
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFFFFFFFF),
          navigatorKey: root,
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => Stack(
              children: [
                button(first, _button),
                button(second, const Rect.fromLTWH(220, 80, 44, 44)),
              ],
            ),
          ),
        ),
      );
      final hold = await tester.startGesture(_button.center);
      final route = first.currentState!.activeRoute!;
      await tester.pump(const Duration(milliseconds: 50));
      final other = await tester.startGesture(const Offset(242, 102));
      await other.up();
      expect(first.currentState!.activeRoute, same(route));
      expect(second.currentState!.activeRoute, isNull);
      expect(second.currentState!.motionFrames, 0);
      await hold.cancel();
      await _until(tester, () => route.disposed);
      expect(builds, 0);
      expect(second.currentState!.motionFrames, 0);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  for (final childPriority in [false, true]) {
    testWidgets(
      'Router platform Back follows dispatcher priority: child=$childPriority',
      (tester) async {
        final h = _Harness();
        addTearDown(h.focus.dispose);
        final dispatcher = RootBackButtonDispatcher();
        final childDispatcher = dispatcher.createChildBackButtonDispatcher();
        final child = _ChildDelegate(h.content(tester, useNested: true));
        final delegate = _RootDelegate(
          h.root,
          (_) => childPriority
              ? Router<Object>(
                  routerDelegate: child,
                  backButtonDispatcher: childDispatcher,
                )
              : child.child,
        );
        addTearDown(delegate.dispose);
        addTearDown(child.dispose);
        await tester.pumpWidget(
          WidgetsApp.router(
            color: const Color(0xFFFFFFFF),
            routerDelegate: delegate,
            backButtonDispatcher: dispatcher,
          ),
        );
        if (childPriority) childDispatcher.takePriority();
        final hold = await tester.startGesture(_button.center);
        final route = h.source.currentState!.activeRoute!;
        await tester.pump(const Duration(milliseconds: 50));
        await tester.binding.handlePopRoute();
        if (childPriority) {
          expect(child.backCalls, 1);
          expect(route.closing, isFalse);
          expect(route.isCurrent, isTrue);
          await hold.cancel();
        } else {
          expect(child.backCalls, 0);
          expect(route.closing, isTrue);
          await hold.up();
        }
        await _until(tester, () => route.disposed);
        expect(h.builds, 0);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  for (final nested in [false, true]) {
    testWidgets(
      'revealed Escape uses root popup SDK action with nested=$nested',
      (tester) async {
        final h = _Harness();
        addTearDown(h.focus.dispose);
        await tester.pumpWidget(h.app(tester, useNested: nested));
        final route = await h.open(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _until(tester, () => route.disposed);
        await _until(tester, () => h.source.currentState!.motionSettled);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  for (final nested in [false, true]) {
    for (final keyboard in [false, true]) {
      testWidgets(
        'characterization: hidden ${keyboard ? 'Escape' : 'platform Back'} with nested=$nested',
        (tester) async {
          final h = _Harness();
          addTearDown(h.focus.dispose);
          await tester.pumpWidget(h.app(tester, useNested: nested));
          await tester.pump();
          expect(h.focus.hasFocus, isTrue);
          final gesture = await tester.startGesture(_button.center);
          final route = h.source.currentState!.activeRoute!;
          await tester.pump(const Duration(milliseconds: 50));
          if (keyboard) {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pump();
            expect(route.closing, isFalse);
            expect(h.focus.hasFocus, isTrue);
            expect(route.requestFocus, isFalse);
            await gesture.cancel();
          } else {
            await tester.binding.handlePopRoute();
            await gesture.up();
          }
          await _until(tester, () => route.disposed);
          expect(h.builds, 0);
          expect(h.source.currentState!.activeRoute, isNull);
          expect(tester.binding.transientCallbackCount, 0);
        },
      );
    }
  }
}
