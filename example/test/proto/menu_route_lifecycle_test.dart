// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph_example/proto/menu_route_probe.dart';

const _button = Rect.fromLTWH(24, 80, 44, 44);
const _step = Duration(microseconds: 8333);

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await tester.pump(_step);
  }
  expect(done(), isTrue);
}

class _Observer extends NavigatorObserver {
  final events = <(String, Route<Object?>)>[];

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) =>
      events.add(('push', route));

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) =>
      events.add(('pop', route));
}

class _Aware extends RouteAware {
  final events = <String>[];

  @override
  void didPushNext() => events.add('covered');

  @override
  void didPopNext() => events.add('uncovered');
}

class _Harness {
  final root = GlobalKey<NavigatorState>();
  final nested = GlobalKey<NavigatorState>();
  final source = GlobalKey<ProbeMenuSourceState>();
  final observer = _Observer();
  final nestedObserver = _Observer();
  final routeObserver = RouteObserver<ModalRoute<void>>();
  late PageRoute<void> home;
  late PageRoute<void> local;
  int builds = 0;
  final pointers = <PointerEvent>[];

  Widget app(
    WidgetTester tester, {
    required WidgetBuilder menuBuilder,
    bool pointerInput = true,
    bool useNested = false,
  }) => WidgetsApp(
    color: const Color(0xFFFFFFFF),
    navigatorKey: root,
    navigatorObservers: [observer, routeObserver],
    onGenerateRoute: (_) {
      home = PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) {
          final button = ProbeMenuSource(
            key: source,
            pointerInput: pointerInput,
            onSample: (sample) {
              if (sample.event case final event?) pointers.add(event);
            },
            now: () => Duration(
              microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
            ),
            menuBuilder: (context) {
              builds++;
              return menuBuilder(context);
            },
          );
          if (!useNested) return button;
          return Navigator(
            key: nested,
            observers: [nestedObserver],
            onGenerateRoute: (_) {
              local = PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                pageBuilder: (_, _, _) => button,
              );
              return local;
            },
          );
        },
      );
      return home;
    },
  );
}

void main() {
  testWidgets(
    'hidden preparation is a real root route and cancellation is visible',
    (tester) async {
      final h = _Harness();
      await tester.pumpWidget(
        h.app(
          tester,
          useNested: true,
          menuBuilder: (_) => const SizedBox.expand(),
        ),
      );
      final aware = _Aware();
      h.routeObserver.subscribe(aware, h.home);
      final gesture = await tester.startGesture(_button.center);
      final route = h.source.currentState!.activeRoute!;
      expect(h.observer.events, [('push', h.home), ('push', route)]);
      expect(aware.events, ['covered']);
      expect(h.home.isCurrent, isFalse);
      expect(h.local.isCurrent, isTrue);
      expect(route.isCurrent, isTrue);
      expect(h.builds, 0);
      expect(route.requestFocus, isFalse);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.cancel();
      await _until(tester, () => route.disposed);
      expect(h.observer.events.last, ('pop', route));
      expect(aware.events, ['covered', 'uncovered']);
      expect(h.home.isCurrent, isTrue);
      expect(h.nestedObserver.events, [('push', h.local)]);
      expect(h.builds, 0);
      expect(tester.binding.transientCallbackCount, 0);
      h.routeObserver.unsubscribe(aware);
    },
  );

  testWidgets('root Back cancels unmounted preparation without building menu', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(
      h.app(tester, menuBuilder: (_) => const SizedBox.expand()),
    );
    final gesture = await tester.startGesture(_button.center);
    final route = h.source.currentState!.activeRoute!;
    var completed = false;
    unawaited(h.root.currentState!.maybePop().then((_) => completed = true));
    await tester.pump();
    await _until(tester, () => completed && route.disposed);
    await gesture.up();
    await _until(tester, () => h.source.currentState!.motionSettled);
    expect(h.builds, 0);
    expect(h.source.currentState!.activeRoute, isNull);
    expect(h.home.isCurrent, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('abandoned hidden press consumes move and up before disposal', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(
      h.app(tester, menuBuilder: (_) => const SizedBox.expand()),
    );
    final gesture = await tester.startGesture(_button.center);
    final route = h.source.currentState!.activeRoute!;
    await h.root.currentState!.maybePop();
    expect(route.closing, isTrue);
    expect(route.disposed, isFalse);
    await gesture.moveBy(const Offset(0, 8));
    await gesture.up();
    expect(route.disposed, isFalse);
    expect(h.builds, 0);
    await _until(tester, () => route.disposed);
    await _until(tester, () => h.source.currentState!.motionSettled);
    expect(h.source.currentState!.activeRoute, isNull);
    expect(h.builds, 0);
    await tester.tapAt(_button.center);
    final next = h.source.currentState!.activeRoute!;
    await _until(tester, () => next.animation!.isCompleted);
    h.root.currentState!.pop();
    await _until(tester, () => next.disposed);
    await _until(tester, () => h.source.currentState!.motionSettled);
    expect(h.builds, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('new down during abandoned preparation cannot rearm its model', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(
      h.app(tester, menuBuilder: (_) => const SizedBox.expand()),
    );
    final original = await tester.startGesture(_button.center);
    final route = h.source.currentState!.activeRoute!;
    await h.root.currentState!.maybePop();
    await original.up();
    final absorbed = await tester.startGesture(_button.center);
    await absorbed.up();
    expect(route.disposed, isFalse);
    await _until(tester, () => route.disposed);
    await _until(tester, () => h.source.currentState!.motionSettled);
    expect(h.source.currentState!.activeRoute, isNull);
    expect(h.builds, 0);
    await tester.tapAt(_button.center);
    final next = h.source.currentState!.activeRoute!;
    await _until(tester, () => next.animation!.isCompleted);
    h.root.currentState!.pop();
    await _until(tester, () => next.disposed);
    await _until(tester, () => h.source.currentState!.motionSettled);
    expect(h.builds, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('nested raw hold keeps pointer and mounts policy on root route', (
    tester,
  ) async {
    final h = _Harness();
    BuildContext? menuContext;
    await tester.pumpWidget(
      h.app(
        tester,
        useNested: true,
        menuBuilder: (context) {
          menuContext = context;
          return const SizedBox.expand();
        },
      ),
    );
    final gesture = await tester.startGesture(_button.center);
    final route = h.source.currentState!.activeRoute!;
    await _until(tester, () => menuContext != null);
    expect(Navigator.of(menuContext!), same(h.root.currentState));
    expect(ModalRoute.of(menuContext!), same(route));
    expect(Navigator.of(h.source.currentContext!), same(h.nested.currentState));
    expect(h.home.isCurrent, isFalse);
    expect(h.local.isCurrent, isTrue);
    await gesture.moveBy(const Offset(0, 8));
    await gesture.up();
    expect(h.pointers, [
      isA<PointerDownEvent>(),
      isA<PointerMoveEvent>(),
      isA<PointerUpEvent>(),
    ]);
    expect(h.observer.events, [('push', h.home), ('push', route)]);
    expect(h.nestedObserver.events, [('push', h.local)]);
    await h.root.currentState!.maybePop();
    await _until(tester, () => route.disposed);
    await _until(tester, () => h.source.currentState!.motionSettled);
    expect(h.home.isCurrent, isTrue);
    expect(h.local.isCurrent, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final change in [
    'cover',
    'cover-uncover',
    'remove',
    'replace',
    'pop',
    'unmount',
  ]) {
    testWidgets('first-mount waiting is canceled by $change', (tester) async {
      final h = _Harness();
      await tester.pumpWidget(
        h.app(
          tester,
          pointerInput: false,
          menuBuilder: (_) => const SizedBox.expand(),
        ),
      );
      final route = h.source.currentState!.open();
      var completed = false;
      unawaited(h.root.currentState!.maybePop().then((_) => completed = true));
      switch (change) {
        case 'cover':
        case 'cover-uncover':
          unawaited(
            h.root.currentState!.push<void>(
              PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                pageBuilder: (_, _, _) => const SizedBox.expand(),
              ),
            ),
          );
          if (change == 'cover-uncover') h.root.currentState!.pop();
        case 'pop':
          h.root.currentState!.pop();
        case 'replace':
          unawaited(
            h.root.currentState!.pushReplacement<void, void>(
              PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                pageBuilder: (_, _, _) => const SizedBox.expand(),
              ),
            ),
          );
        case 'remove':
          h.root.currentState!.removeRoute(route);
        case 'unmount':
          await tester.pumpWidget(const SizedBox.shrink());
      }
      await tester.pump();
      await _until(tester, () => completed);
      if (change == 'cover' || change == 'cover-uncover') {
        expect(route.closing, isFalse);
        expect(route.disposed, isFalse);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  for (final allowed in [false, true]) {
    testWidgets('pre-mount maybePop waits for revealed policy: $allowed', (
      tester,
    ) async {
      final h = _Harness();
      final results = <bool>[];
      await tester.pumpWidget(
        h.app(
          tester,
          pointerInput: false,
          menuBuilder: (_) => PopScope<void>(
            canPop: allowed,
            onPopInvokedWithResult: (didPop, _) => results.add(didPop),
            child: const SizedBox.expand(),
          ),
        ),
      );
      final route = h.source.currentState!.open();
      var completed = false;
      unawaited(h.root.currentState!.maybePop().then((_) => completed = true));
      expect(h.builds, 0);
      expect(route.closing, isFalse);
      await tester.pump();
      await _until(tester, () => completed);
      expect(h.builds, 1);
      expect(results, [allowed]);
      expect(route.closing, allowed);
      if (!allowed) h.root.currentState!.pop();
      await _until(tester, () => route.disposed);
      await _until(tester, () => h.source.currentState!.motionSettled);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets('first mount discovers async guard and coalesces SDK requests', (
    tester,
  ) async {
    final h = _Harness();
    final permission = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(
      h.app(
        tester,
        pointerInput: false,
        menuBuilder: (_) => WillPopScope(
          onWillPop: () {
            calls++;
            return permission.future;
          },
          child: const SizedBox.expand(),
        ),
      ),
    );
    final route = h.source.currentState!.open();
    final first = h.root.currentState!.maybePop();
    final second = h.root.currentState!.maybePop();
    expect(calls, 0);
    await tester.pump();
    await _until(tester, () => calls == 1);
    expect(route.closing, isFalse);
    permission.complete(true);
    await tester.pump();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(calls, 1);
    await _until(tester, () => route.disposed);
    await _until(tester, () => h.source.currentState!.motionSettled);
    expect(h.observer.events.where((event) => event.$1 == 'pop'), hasLength(1));
  });

  testWidgets(
    'coarse first frame mounts policy before early pointer dismissal',
    (tester) async {
      final h = _Harness();
      final results = <bool>[];
      await tester.pumpWidget(
        h.app(
          tester,
          menuBuilder: (_) => PopScope<void>(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) => results.add(didPop),
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.tapAt(_button.center);
      final route = h.source.currentState!.activeRoute!;
      await tester.tapAt(const Offset(350, 500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(h.builds, 1);
      expect(results, [false]);
      expect(route.closing, isFalse);
      expect(route.disposed, isFalse);
      h.root.currentState!.pop();
      await _until(tester, () => route.disposed);
      await _until(tester, () => h.source.currentState!.motionSettled);
    },
  );
}
