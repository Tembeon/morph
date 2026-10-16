import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph_example/proto/menu_route_probe.dart';

const _button = Rect.fromLTWH(24, 80, 44, 44);

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await tester.pump(const Duration(microseconds: 8333));
  }
  expect(done(), isTrue);
}

Widget _app(
  WidgetTester tester,
  GlobalKey<NavigatorState> nav,
  GlobalKey<ProbeMenuSourceState> source, {
  required WidgetBuilder menuBuilder,
  ValueChanged<ProbeMenuSample>? onSample,
  Widget Function(Widget)? home,
}) => WidgetsApp(
  color: const Color(0xFFFFFFFF),
  navigatorKey: nav,
  onGenerateRoute: (_) => PageRouteBuilder<void>(
    transitionDuration: Duration.zero,
    pageBuilder: (_, _, _) {
      final widget = ProbeMenuSource(
        key: source,
        pointerInput: true,
        now: () => Duration(
          microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
        ),
        pointerOffset: () => null,
        onSample: onSample,
        menuBuilder: menuBuilder,
      );
      return home?.call(widget) ?? widget;
    },
  ),
);

void main() {
  testWidgets(
    'holding the source during its landing tail preserves move and up',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final source = GlobalKey<ProbeMenuSourceState>();
      final events = <PointerEvent>[];
      await tester.pumpWidget(
        _app(
          tester,
          nav,
          source,
          onSample: (sample) {
            if (sample.event case final event?) events.add(event);
          },
          menuBuilder: (_) => const SizedBox.expand(),
        ),
      );
      await tester.tapAt(_button.center);
      final first = source.currentState!.activeRoute!;
      await _until(tester, () => first.animation!.isCompleted);
      nav.currentState!.pop();
      await _until(tester, () => first.handBack != null);
      expect(source.currentState!.motionSettled, isFalse);
      events.clear();
      final gesture = await tester.startGesture(_button.center);
      final next = source.currentState!.activeRoute!;
      await _until(tester, () => next.animation!.isCompleted);
      await gesture.moveTo(next.frame.menu.outerRect.center);
      await gesture.up();
      expect(events, [
        isA<PointerDownEvent>(),
        isA<PointerMoveEvent>(),
        isA<PointerUpEvent>(),
      ]);
      await _until(tester, () => next.closing);
      await _until(tester, () => next.disposed);
      await _until(tester, () => source.currentState!.motionSettled);
    },
  );

  testWidgets(
    'negative control: a late Navigator push cancels the held pointer stream',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final events = <PointerEvent>[];
      void observe(PointerEvent event) {
        if (event is PointerDownEvent ||
            event is PointerMoveEvent ||
            event is PointerUpEvent ||
            event is PointerCancelEvent) {
          events.add(event);
        }
      }

      tester.binding.pointerRouter.addGlobalRoute(observe);
      addTearDown(
        () => tester.binding.pointerRouter.removeGlobalRoute(observe),
      );
      Timer? timer;
      addTearDown(() => timer?.cancel());
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFFFFFFFF),
          navigatorKey: nav,
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => Listener(
              behavior: .opaque,
              onPointerDown: (_) {
                timer = Timer(const Duration(milliseconds: 220), () {
                  unawaited(
                    nav.currentState!.push<void>(
                      PageRouteBuilder<void>(
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                        pageBuilder: (_, _, _) => const SizedBox.expand(),
                      ),
                    ),
                  );
                });
              },
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(_button.center);
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 80));
      await gesture.up();
      expect(events, [isA<PointerDownEvent>(), isA<PointerCancelEvent>()]);
      nav.currentState!.pop();
      await tester.pump();
    },
  );

  testWidgets(
    'pending route defers menu content and focus until measured opening',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final source = GlobalKey<ProbeMenuSourceState>();
      final homeFocus = FocusNode();
      final menuFocus = FocusNode();
      addTearDown(homeFocus.dispose);
      addTearDown(menuFocus.dispose);
      var builds = 0;
      await tester.pumpWidget(
        _app(
          tester,
          nav,
          source,
          home: (child) =>
              Focus(focusNode: homeFocus, autofocus: true, child: child),
          menuBuilder: (_) {
            builds++;
            return Focus(
              focusNode: menuFocus,
              autofocus: true,
              child: const SizedBox.expand(),
            );
          },
        ),
      );
      await tester.pump();
      expect(homeFocus.hasFocus, isTrue);
      final gesture = await tester.startGesture(_button.center);
      final route = source.currentState!.activeRoute!;
      await tester.pump(const Duration(milliseconds: 100));
      expect(builds, 0);
      expect(route.requestFocus, isFalse);
      expect(homeFocus.hasFocus, isTrue);
      expect(menuFocus.hasFocus, isFalse);
      await _until(tester, () => builds == 1);
      await tester.pump();
      expect(route.requestFocus, isTrue);
      expect(menuFocus.hasFocus, isTrue);
      await gesture.up();
      nav.currentState!.pop();
      await _until(tester, () => route.disposed);
      await _until(tester, () => source.currentState!.motionSettled);
    },
  );

  testWidgets(
    'real cancellation before hold removes the hidden route without showing content',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final source = GlobalKey<ProbeMenuSourceState>();
      var builds = 0;
      var cancels = 0;
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFFFFFFFF),
          navigatorKey: nav,
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => ProbeMenuSource(
              key: source,
              pointerInput: true,
              now: () => Duration(
                microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
              ),
              onSample: (sample) {
                if (sample.event is PointerCancelEvent) cancels++;
              },
              menuBuilder: (_) {
                builds++;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(_button.center);
      final route = source.currentState!.activeRoute!;
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.cancel();
      await _until(tester, () => route.disposed);
      expect(cancels, 1);
      expect(builds, 0);
      expect(source.currentState!.ownsMotion, isTrue);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('secondary button does not prepare a menu route', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    final source = GlobalKey<ProbeMenuSourceState>();
    await tester.pumpWidget(
      _app(tester, nav, source, menuBuilder: (_) => const SizedBox.expand()),
    );
    final gesture = await tester.startGesture(
      _button.center,
      kind: .mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(source.currentState!.activeRoute, isNull);
    expect(source.currentState!.motionFrames, 0);
    await gesture.up();
  });

  testWidgets(
    'negative control: model-driven pointer close currently bypasses PopScope',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final source = GlobalKey<ProbeMenuSourceState>();
      await tester.pumpWidget(
        _app(
          tester,
          nav,
          source,
          menuBuilder: (_) =>
              const PopScope<void>(canPop: false, child: SizedBox.expand()),
        ),
      );
      await tester.tapAt(_button.center);
      final route = source.currentState!.activeRoute!;
      await _until(tester, () => route.animation!.isCompleted);
      expect(route.popDisposition, RoutePopDisposition.doNotPop);
      await tester.tapAt(const Offset(350, 500));
      await _until(tester, () => route.closing);
      await _until(tester, () => route.disposed);
      await _until(tester, () => source.currentState!.motionSettled);
    },
  );
}
