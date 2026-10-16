import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/motion.dart';
import 'package:morph_example/proto/menu_route_probe.dart';
import 'package:morph_example/proto/menu_transfer_probe.dart';

const _button = Rect.fromLTWH(24, 80, 44, 44);
const _bounds = Size(402, 874);
const _step = Duration(microseconds: 8333);

class _Observer extends NavigatorObserver {
  final pushed = <Route<Object?>>[];

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) =>
      pushed.add(route);
}

Widget _app(
  GlobalKey<NavigatorState> nav,
  GlobalKey<ProbeMenuSourceState> source, {
  WidgetBuilder? menuBuilder,
  Widget Function(Widget source)? wrapSource,
  List<NavigatorObserver> observers = const [],
}) {
  final button = ProbeMenuSource(
    key: source,
    now: () => Duration(
      microseconds: TestWidgetsFlutterBinding.instance.clock
          .now()
          .microsecondsSinceEpoch,
    ),
    menuBuilder: menuBuilder ?? (_) => const Text('menu'),
  );
  return WidgetsApp(
    color: const Color(0xFFFFFFFF),
    navigatorKey: nav,
    navigatorObservers: observers,
    onGenerateRoute: (_) => PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => wrapSource?.call(button) ?? button,
    ),
  );
}

MorphMenuMotion _reference() => MorphMenuMotion(
  button: _button,
  bounds: _bounds,
  itemCount: 3,
  sourceHeight: 64,
  sourceRadius: 22,
);

void _same(ProbeMenuFrame frame, MorphMenuMotion reference) {
  expect(frame.time, closeTo(reference.time, 1e-9));
  expect(frame.progress, closeTo(reference.progress, 1e-9));
  expect(frame.buttonKick, closeTo(reference.buttonKick, 1e-8));
  expect(frame.menuKick, closeTo(reference.menuKick, 1e-8));
  expect(frame.fusionRadius, closeTo(reference.fusionRadius, 1e-8));
  expect(frame.contentOpacity, closeTo(reference.contentOpacity, 1e-9));
  expect(frame.buttonOpacity, closeTo(reference.buttonLookOpacity, 1e-9));
  for (final (actual, expected) in [
    (frame.button, reference.buttonBlob.rrect),
    (frame.menu, reference.menuBlob.rrect),
  ]) {
    expect(actual.left, closeTo(expected.left, 1e-8));
    expect(actual.top, closeTo(expected.top, 1e-8));
    expect(actual.right, closeTo(expected.right, 1e-8));
    expect(actual.bottom, closeTo(expected.bottom, 1e-8));
    expect(actual.tlRadiusX, closeTo(expected.tlRadiusX, 1e-8));
  }
}

Future<void> _until(
  WidgetTester tester,
  bool Function() done, {
  Duration step = _step,
}) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await tester.pump(step);
  }
  expect(done(), isTrue, reason: 'Motion must finish within 600 frames');
}

void main() {
  testWidgets(
    'input after ten idle seconds does not reuse an old frame timestamp',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final source = GlobalKey<ProbeMenuSourceState>();
      await tester.pumpWidget(_app(nav, source));
      final state = source.currentState!;
      await tester.pump(const Duration(seconds: 10));
      final route = state.open();
      await tester.pump(_step);
      expect(state.frame.time, closeTo(0.008333, 1e-6));
      await _until(tester, () => route.animation!.isCompleted);
      final settledAt = state.frame.time;
      await tester.pump(const Duration(seconds: 10));
      nav.currentState!.pop();
      await tester.pump(_step);
      expect(state.frame.time - settledAt, closeTo(0.008333, 1e-6));
      expect(route.disposed, isFalse);
      await _until(tester, () => route.disposed);
      await _until(tester, () => state.motionSettled);
      await tester.pump(const Duration(seconds: 10));
      final before = state.frame.time;
      final second = state.open();
      await tester.pump(_step);
      expect(state.frame.time - before, closeTo(0.008333, 1e-6));
      nav.currentState!.pop();
      await _until(tester, () => second.disposed);
      await _until(tester, () => state.motionSettled);
    },
  );

  testWidgets('source inside a nested Navigator opens a root PopupRoute', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    final nested = GlobalKey<NavigatorState>();
    final source = GlobalKey<ProbeMenuSourceState>();
    final rootObserver = _Observer();
    final nestedObserver = _Observer();
    await tester.pumpWidget(
      _app(
        nav,
        source,
        observers: [rootObserver],
        wrapSource: (button) => Navigator(
          key: nested,
          observers: [nestedObserver],
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => button,
          ),
        ),
      ),
    );
    await tester.tapAt(_button.center);
    await tester.pump();
    final route = rootObserver.pushed.last as ProbeMenuRoute;
    expect(route.navigator, same(nav.currentState));
    expect(rootObserver.pushed.length, 2);
    expect(nestedObserver.pushed.length, 1);
    expect(source.currentState!.ownsMotion, isFalse);
    nav.currentState!.pop();
    await _until(tester, () => route.disposed);
    await _until(tester, () => source.currentState!.motionSettled);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'route hands the same frame to the source and disposes before tail rest',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final source = GlobalKey<ProbeMenuSourceState>();
      await tester.pumpWidget(_app(nav, source));
      final state = source.currentState!;
      final route = state.open();
      final reference = _reference();
      reference.open(0);
      for (var i = 0; i < 120; i++) {
        await tester.pump(_step);
        reference.advance(route.frame.time);
        _same(route.frame, reference);
      }
      var popped = false;
      unawaited(route.popped.then((_) => popped = true));
      nav.currentState!.pop();
      reference.close(route.closedAt!);
      await tester.pump();
      reference.advance(state.frame.time);
      _same(state.frame, reference);
      expect(popped, isTrue);
      expect(route.animation!.status, AnimationStatus.reverse);
      expect(route.disposed, isFalse);
      while (route.handBack == null) {
        await tester.pump(_step);
        reference.advance(state.frame.time);
        _same(state.frame, reference);
        expect(state.frame.time, lessThan(3));
      }
      final handBack = route.handBack!;
      expect(handBack.after, handBack.before);
      expect(handBack.after.progress, lessThanOrEqualTo(0));
      expect(state.ownsMotion, isTrue);
      expect(state.motionSettled, isFalse);
      await _until(tester, () => route.disposed);
      final at = state.frame.time;
      await tester.pump(_step);
      reference.advance(state.frame.time);
      _same(state.frame, reference);
      expect(state.frame.time - at, closeTo(0.008333, 1e-6));
      final routeFrames = route.motionFrames;
      while (!state.motionSettled) {
        await tester.pump(_step);
        reference.advance(state.frame.time);
        _same(state.frame, reference);
        expect(state.frame.time, lessThan(4));
      }
      expect(route.motionFrames, routeFrames);
      final sourceFrames = state.motionFrames;
      await tester.pump(const Duration(seconds: 1));
      expect(state.motionFrames, sourceFrames);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  for (final step in [const Duration(microseconds: 16667), _step]) {
    for (final delay in [50, 300, 550]) {
      testWidgets(
        'reopen at ${delay}ms, frame ${step.inMicroseconds}us keeps one owner',
        (tester) async {
          final nav = GlobalKey<NavigatorState>();
          final source = GlobalKey<ProbeMenuSourceState>();
          var builds = 0;
          await tester.pumpWidget(
            _app(
              nav,
              source,
              menuBuilder: (_) {
                builds++;
                return const Text('menu');
              },
            ),
          );
          final state = source.currentState!;
          final first = state.open();
          await _until(tester, () => first.animation!.isCompleted, step: step);
          expect(builds, 1);
          nav.currentState!.pop();
          var elapsed = Duration.zero;
          while (elapsed.inMilliseconds < delay) {
            await tester.pump(step);
            elapsed += step;
          }
          expect(state.ownsMotion, delay == 550);
          expect(state.motionSettled, isFalse);
          final before = state.frame;
          final next = state.open();
          expect(identical(next, first), isFalse);
          expect(state.frame.time, before.time);
          expect(state.frame.progress, closeTo(before.progress, 1e-9));
          expect(state.frame.buttonKick, closeTo(before.buttonKick, 1e-8));
          expect(state.ownsMotion, isFalse);
          final stoppedAt = first.motionFrames;
          await tester.pump(step);
          await _until(tester, () => first.disposed, step: step);
          expect(first.motionFrames, stoppedAt);
          await _until(tester, () => next.animation!.isCompleted, step: step);
          expect(next.pageBuilds, 1);
          expect(builds, 2);
          nav.currentState!.pop();
          await _until(tester, () => next.disposed, step: step);
          await _until(tester, () => state.motionSettled, step: step);
          expect(state.ownsMotion, isTrue);
          expect(tester.binding.transientCallbackCount, 0);
        },
      );
    }
  }

  testWidgets(
    'PopScope veto prevents closing; barrier and closing input use SDK behavior',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final source = GlobalKey<ProbeMenuSourceState>();
      final canPop = ValueNotifier<bool>(false);
      addTearDown(canPop.dispose);
      var taps = 0;
      final homeFocus = FocusNode();
      final menuFocus = FocusNode();
      addTearDown(homeFocus.dispose);
      addTearDown(menuFocus.dispose);
      await tester.pumpWidget(
        _app(
          nav,
          source,
          wrapSource: (button) => Focus(
            focusNode: homeFocus,
            autofocus: true,
            child: GestureDetector(
              behavior: .opaque,
              onTap: () => taps++,
              child: button,
            ),
          ),
          menuBuilder: (_) => ValueListenableBuilder<bool>(
            valueListenable: canPop,
            builder: (_, allowed, _) => PopScope<void>(
              canPop: allowed,
              child: Focus(
                focusNode: menuFocus,
                autofocus: true,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      final route = source.currentState!.open();
      await _until(tester, () => route.animation!.isCompleted);
      expect(menuFocus.hasFocus, isTrue);
      await tester.tapAt(const Offset(390, 500));
      await tester.pump();
      expect(route.closing, isFalse);
      expect(route.animation!.isCompleted, isTrue);
      expect(taps, 0);
      canPop.value = true;
      await tester.pump();
      await tester.tapAt(const Offset(390, 500));
      await tester.pump();
      expect(route.closing, isTrue);
      expect(menuFocus.hasFocus, isFalse);
      expect(route.disposed, isFalse);
      await tester.tapAt(const Offset(390, 500));
      expect(taps, 1);
      await _until(tester, () => route.disposed);
      await _until(tester, () => source.currentState!.motionSettled);
      expect(homeFocus.hasFocus, isTrue);
    },
  );

  testWidgets(
    'unmounted source leaves a live route that closes without touching its State',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final source = GlobalKey<ProbeMenuSourceState>();
      final shown = ValueNotifier<bool>(true);
      addTearDown(shown.dispose);
      await tester.pumpWidget(
        _app(
          nav,
          source,
          wrapSource: (button) => ValueListenableBuilder<bool>(
            valueListenable: shown,
            builder: (_, value, _) => value ? button : const SizedBox.expand(),
          ),
        ),
      );
      final route = source.currentState!.open();
      await tester.pump(const Duration(milliseconds: 100));
      shown.value = false;
      await tester.pump();
      expect(source.currentState, isNull);
      await _until(tester, () => route.animation!.isCompleted);
      nav.currentState!.pop();
      await _until(tester, () => route.disposed);
      expect(route.handBack, isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'forced removal restores an idle source and permits another open',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final source = GlobalKey<ProbeMenuSourceState>();
      await tester.pumpWidget(_app(nav, source));
      final state = source.currentState!;
      final first = state.open();
      await tester.pump(const Duration(milliseconds: 100));
      nav.currentState!.removeRoute(first);
      await tester.pump();
      expect(first.disposed, isTrue);
      expect(state.ownsMotion, isTrue);
      expect(state.motionSettled, isTrue);
      expect(tester.binding.transientCallbackCount, 0);
      final second = state.open();
      await _until(tester, () => second.animation!.isCompleted);
      nav.currentState!.pop();
      await _until(tester, () => second.disposed);
      await _until(tester, () => state.motionSettled);
    },
  );

  testWidgets(
    'disposing the whole Navigator during motion releases both clocks',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final source = GlobalKey<ProbeMenuSourceState>();
      await tester.pumpWidget(_app(nav, source));
      final route = source.currentState!.open();
      await tester.pump(_step);
      await tester.pumpWidget(const SizedBox());
      expect(route.disposed, isTrue);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'twenty cycles including early pop leave no active ticker or overlay',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final source = GlobalKey<ProbeMenuSourceState>();
      await tester.pumpWidget(_app(nav, source));
      final state = source.currentState!;
      final routes = <ProbeMenuRoute>[];
      for (var cycle = 0; cycle < 20; cycle++) {
        final route = state.open();
        routes.add(route);
        expect(state.open(), same(route));
        if (cycle.isEven) {
          await tester.pump(_step);
        } else {
          await _until(tester, () => route.animation!.isCompleted);
        }
        nav.currentState!.pop();
        await _until(tester, () => route.disposed);
        await _until(tester, () => state.motionSettled);
        expect(find.byType(Flow), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
      expect(routes.every((route) => route.disposed), isTrue);
      final samples = state.motionFrames;
      await tester.pump(const Duration(seconds: 5));
      expect(state.motionFrames, samples);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editor State survives motion and a covering route; Escape dismisses',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final source = GlobalKey<ProbeMenuSourceState>();
      final editorKey = GlobalKey<EditableTextState>();
      final controller = TextEditingController(text: 'first');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      var builds = 0;
      await tester.pumpWidget(
        _app(
          nav,
          source,
          menuBuilder: (_) {
            builds++;
            return EditableText(
              key: editorKey,
              controller: controller,
              focusNode: focus,
              autofocus: true,
              style: const TextStyle(color: Color(0xFF000000), fontSize: 16),
              cursorColor: const Color(0xFF000000),
              backgroundCursorColor: const Color(0xFFFFFFFF),
            );
          },
        ),
      );
      final route = source.currentState!.open();
      await tester.pump(_step);
      final editorState = editorKey.currentState;
      await _until(tester, () => route.animation!.isCompleted);
      expect(editorKey.currentState, same(editorState));
      controller.text = 'edited';
      final cover = PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => const SizedBox.expand(),
      );
      unawaited(nav.currentState!.push<void>(cover));
      await tester.pump();
      expect(editorKey.currentState, same(editorState));
      nav.currentState!.pop();
      await tester.pump();
      await tester.pump();
      expect(editorKey.currentState, same(editorState));
      expect(controller.text, 'edited');
      expect(focus.hasFocus, isTrue);
      expect(builds, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(route.closing, isTrue);
      expect(focus.hasFocus, isFalse);
      await _until(tester, () => route.disposed);
      await _until(tester, () => source.currentState!.motionSettled);
      expect(editorKey.currentState, isNull);
    },
  );
}
