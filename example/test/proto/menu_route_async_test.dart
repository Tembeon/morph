import 'dart:async';
import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/motion.dart';
import 'package:morph/src/widgets/menu_motion.dart'
    show morphMenuSetCloseAdmission;
import 'package:morph_example/proto/menu_route_probe.dart';

const _button = Rect.fromLTWH(24, 80, 44, 44);
const _step = Duration(microseconds: 8333);

Future<void> _until(
  WidgetTester tester,
  bool Function() done, {
  Duration step = _step,
}) async {
  for (var i = 0; i < 1200 && !done(); i++) {
    await tester.pump(step);
  }
  expect(done(), isTrue);
}

class _Harness {
  _Harness({this.onSample, this.step = _step});

  final ValueChanged<ProbeMenuSample>? onSample;
  final Duration step;
  final nav = GlobalKey<NavigatorState>();
  final source = GlobalKey<ProbeMenuSourceState>();
  final shown = ValueNotifier(true);
  final canPop = ValueNotifier(true);
  final requests = <Completer<bool>>[];
  VoidCallback? onRequest;

  Widget app(WidgetTester tester) => WidgetsApp(
    color: const Color(0xFFFFFFFF),
    navigatorKey: nav,
    onGenerateRoute: (_) => PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (_, visible, _) => visible
            ? ProbeMenuSource(
                key: source,
                onSample: onSample,
                pointerInput: true,
                now: () => Duration(
                  microseconds: tester.binding.clock
                      .now()
                      .microsecondsSinceEpoch,
                ),
                menuBuilder: (_) => WillPopScope(
                  onWillPop: () {
                    final request = Completer<bool>();
                    requests.add(request);
                    onRequest?.call();
                    return request.future;
                  },
                  child: ValueListenableBuilder<bool>(
                    valueListenable: canPop,
                    builder: (_, allowed, _) => PopScope<void>(
                      canPop: allowed,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    ),
  );

  Future<ProbeMenuRoute> open(WidgetTester tester) async {
    await tester.pumpWidget(app(tester));
    await tester.tapAt(_button.center);
    final route = source.currentState!.activeRoute!;
    await _until(tester, () => route.animation!.isCompleted, step: step);
    return route;
  }

  Future<void> request(WidgetTester tester) async {
    final before = requests.length;
    await tester.tapAt(const Offset(350, 500));
    await _until(tester, () => requests.length > before, step: step);
  }

  void dispose() {
    for (final request in requests) {
      if (!request.isCompleted) request.complete(false);
    }
    shown.dispose();
    canPop.dispose();
  }
}

MorphMenuMotion _reference() => MorphMenuMotion(
  button: _button,
  bounds: const Size(402, 874),
  itemCount: 3,
  sourceHeight: 64,
  sourceRadius: 22,
);

void _applyReference(MorphMenuMotion motion, ProbeMenuSample sample) {
  switch (sample.kind) {
    case .frame:
      motion.advance(sample.time);
    case .open:
      motion.open(sample.time);
    case .close:
      motion.close(sample.time);
    case .ignoredPointer:
      break;
    case .pointer:
      switch (sample.event!) {
        case PointerDownEvent(:final position):
          motion.pointerDown(sample.time, position);
        case PointerMoveEvent(:final position):
          motion.pointerMove(sample.time, position);
        case PointerUpEvent(:final position):
          motion.pointerUp(sample.time, position);
        case PointerCancelEvent():
          motion.pointerCancel(sample.time);
      }
  }
  expect(sample.frame.time, closeTo(motion.time, 1e-9));
  for (final (actual, expected) in [
    (sample.frame.progress, motion.progress),
    (sample.frame.menuKick, motion.menuKick),
    (sample.frame.buttonKick, motion.buttonKick),
    (sample.frame.fusionRadius, motion.fusionRadius),
    (sample.frame.contentOpacity, motion.contentOpacity),
    (sample.frame.buttonOpacity, motion.buttonLookOpacity),
  ]) {
    expect(actual, closeTo(expected, 1e-8));
  }
  for (final (actual, expected) in [
    (sample.frame.button, motion.buttonBlob.rrect),
    (sample.frame.menu, motion.menuBlob.rrect),
  ]) {
    expect(actual.left, closeTo(expected.left, 1e-8));
    expect(actual.top, closeTo(expected.top, 1e-8));
    expect(actual.right, closeTo(expected.right, 1e-8));
    expect(actual.bottom, closeTo(expected.bottom, 1e-8));
    expect(actual.tlRadiusX, closeTo(expected.tlRadiusX, 1e-8));
  }
}

void main() {
  for (final history in [false, true]) {
    testWidgets(
      'two SDK requests consume one permission once, history=$history',
      (tester) async {
        final host = _Harness();
        addTearDown(host.dispose);
        final route = await host.open(tester);
        var removed = false;
        if (history) {
          route.addLocalHistoryEntry(
            LocalHistoryEntry(onRemove: () => removed = true),
          );
        }
        final first = host.nav.currentState!.maybePop();
        final second = host.nav.currentState!.maybePop();
        expect(host.requests, hasLength(1));
        host.requests.single.complete(true);
        await tester.pump();
        expect(await first, isTrue);
        expect(await second, isTrue);
        if (history) {
          expect(removed, isTrue);
          expect(route.closing, isFalse);
          expect(route.frame.progress, closeTo(1, 1e-3));
          host.nav.currentState!.pop();
        }
        await _until(tester, () => route.disposed);
        await _until(tester, () => host.source.currentState!.motionSettled);
        expect(host.nav.currentState!.canPop(), isFalse);
      },
    );
  }

  for (final rate in [60, 120]) {
    for (final dilation in [1.0, 5.0]) {
      for (final waiting in ['opening', 'settled idle']) {
        testWidgets(
          '$waiting permission preserves current-state physics at $rate Hz / $dilation x',
          (tester) async {
            final previousDilation = timeDilation;
            timeDilation = dilation;
            try {
              final step = Duration(microseconds: (1e6 / rate).round());
              final reference = _reference();
              morphMenuSetCloseAdmission(reference, (_) => false);
              var samples = 0;
              final host = _Harness(
                step: step,
                onSample: (sample) {
                  _applyReference(reference, sample);
                  samples++;
                },
              );
              addTearDown(host.dispose);
              await tester.pumpWidget(host.app(tester));
              await tester.tapAt(_button.center);
              final route = host.source.currentState!.activeRoute!;
              await _until(
                tester,
                () => find.byType(WillPopScope).evaluate().isNotEmpty,
                step: step,
              );
              if (waiting == 'settled idle') {
                await _until(
                  tester,
                  () => route.animation!.isCompleted,
                  step: step,
                );
              }
              await host.request(tester);
              final requested = route.closeRequestedAt!;
              final before = route.frame.progress;
              if (waiting == 'opening') {
                for (var i = 0; i < (0.07 * dilation * rate).ceil(); i++) {
                  await tester.pump(step);
                }
                expect(
                  (route.frame.progress - before).abs(),
                  greaterThan(1e-3),
                );
                final gesture = await tester.startGesture(
                  route.frame.menu.outerRect.center,
                );
                await gesture.moveBy(const Offset(4, 8));
                await tester.pump(step);
                await gesture.up();
                await tester.pump(
                  Duration(microseconds: (80000 * dilation).round()),
                );
                expect(host.requests, hasLength(1));
              } else {
                await _until(
                  tester,
                  () => host.source.currentState!.motionSettled,
                  step: step,
                );
                final frames = route.motionFrames;
                await tester.pump(const Duration(seconds: 10));
                expect(route.motionFrames, frames);
              }
              expect(route.closing, isFalse);
              final lastSample = route.frame.time;
              host.requests.single.complete(true);
              await tester.pump();
              await _until(tester, () => route.closing, step: step);
              expect(route.deferredClose, isTrue);
              expect(route.closeRequestedAt, requested);
              expect(route.closedAt, greaterThanOrEqualTo(lastSample));
              expect(route.closedAt! - lastSample, lessThan(0.05));
              expect(route.closedAt, greaterThan(requested));
              await _until(tester, () => route.disposed, step: step);
              await _until(
                tester,
                () => host.source.currentState!.motionSettled,
                step: step,
              );
              expect(tester.binding.transientCallbackCount, 0);
              // ignore: avoid_print
              print(
                'P2_ASYNC_TIME ${jsonEncode({'rate': rate, 'dilation': dilation, 'waiting': waiting, 'requestedAt': requested, 'lastSampleAtApproval': lastSample, 'closedAt': route.closedAt, 'samples': samples})}',
              );
            } finally {
              timeDilation = previousDilation;
            }
          },
        );
      }
    }
  }

  testWidgets(
    'a reentrant SDK request shares the guard future already being invoked',
    (tester) async {
      final host = _Harness();
      addTearDown(host.dispose);
      Future<bool>? back;
      host.onRequest = () => back = host.nav.currentState!.maybePop();
      final route = await host.open(tester);
      await host.request(tester);
      expect(host.requests, hasLength(1));
      host.requests.single.complete(true);
      await tester.pump();
      expect(await back, isTrue);
      await _until(tester, () => route.disposed);
      await _until(tester, () => host.source.currentState!.motionSettled);
      expect(host.nav.currentState!.canPop(), isFalse);
    },
  );

  testWidgets(
    'programmatic local-history pop cancels an earlier pending approval',
    (tester) async {
      final host = _Harness();
      addTearDown(host.dispose);
      final route = await host.open(tester);
      await host.request(tester);
      var removed = false;
      route.addLocalHistoryEntry(
        LocalHistoryEntry(onRemove: () => removed = true),
      );
      host.nav.currentState!.pop();
      expect(removed, isTrue);
      expect(route.closing, isFalse);
      host.requests.single.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(route.closing, isFalse);
      await host.request(tester);
      host.requests.last.complete(true);
      await tester.pump();
      await _until(tester, () => route.disposed);
      await _until(tester, () => host.source.currentState!.motionSettled);
    },
  );

  for (final origin in ['pointer first', 'SDK first']) {
    testWidgets(
      '$origin shares permission with concurrent maybePop and commits once',
      (tester) async {
        final host = _Harness();
        addTearDown(host.dispose);
        final route = await host.open(tester);
        Future<bool>? back;
        if (origin == 'pointer first') {
          await host.request(tester);
          back = host.nav.currentState!.maybePop();
        } else {
          back = host.nav.currentState!.maybePop();
          await tester.pump();
          await tester.tapAt(const Offset(350, 500));
          await tester.pump(const Duration(milliseconds: 80));
        }
        expect(host.requests, hasLength(1));
        host.requests.single.complete(true);
        await tester.pump();
        expect(await back, isTrue);
        await _until(tester, () => route.disposed);
        await _until(tester, () => host.source.currentState!.motionSettled);
        expect(host.nav.currentState!.canPop(), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a throwing guard reports once, retains the menu and permits retry',
    (tester) async {
      final host = _Harness();
      addTearDown(host.dispose);
      final route = await host.open(tester);
      await host.request(tester);
      host.requests.single.completeError(StateError('permission failed'));
      await tester.pump();
      expect(tester.takeException(), isA<StateError>());
      expect(tester.takeException(), isNull);
      expect(route.closing, isFalse);
      await host.request(tester);
      host.requests.last.complete(true);
      await tester.pump();
      await _until(tester, () => route.disposed);
      await _until(tester, () => host.source.currentState!.motionSettled);
    },
  );

  testWidgets('a pending guard is coalesced and refusal permits retry', (
    tester,
  ) async {
    final host = _Harness();
    addTearDown(host.dispose);
    final route = await host.open(tester);
    await host.request(tester);
    await tester.tapAt(const Offset(350, 500));
    await tester.pump(const Duration(milliseconds: 100));
    expect(host.requests, hasLength(1));
    expect(route.closing, isFalse);
    host.requests.single.complete(false);
    await tester.pump();
    await host.request(tester);
    host.requests.last.complete(true);
    await tester.pump();
    await _until(tester, () => route.disposed);
    await _until(tester, () => host.source.currentState!.motionSettled);
  });

  for (final change in [
    'cover',
    'cover and uncover',
    'replace',
    'remove',
    'unmount',
  ]) {
    testWidgets('$change invalidates a pending dismissal', (tester) async {
      final host = _Harness();
      addTearDown(host.dispose);
      final route = await host.open(tester);
      await host.request(tester);
      final cover = PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => const SizedBox.expand(),
      );
      switch (change) {
        case 'cover':
        case 'cover and uncover':
          unawaited(host.nav.currentState!.push<void>(cover));
          await tester.pump();
          if (change == 'cover and uncover') {
            host.nav.currentState!.pop();
            await tester.pump();
          }
        case 'replace':
          unawaited(host.nav.currentState!.pushReplacement<void, void>(cover));
          await tester.pump();
        case 'remove':
          host.nav.currentState!.removeRoute(route);
          await _until(tester, () => route.disposed);
        case 'unmount':
          await tester.pumpWidget(const SizedBox.shrink());
      }
      host.requests.single.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(route.closing, isFalse);
      if (change == 'cover' || change == 'replace') {
        expect(cover.isCurrent, isTrue);
      } else if (change == 'cover and uncover') {
        expect(route.isCurrent, isTrue);
        expect(route.frame.progress, closeTo(1, 1e-3));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('source loss keeps an already presented route permission valid', (
    tester,
  ) async {
    final host = _Harness();
    addTearDown(host.dispose);
    final route = await host.open(tester);
    await host.request(tester);
    host.shown.value = false;
    await tester.pump();
    expect(host.source.currentState, isNull);
    host.requests.single.complete(true);
    await tester.pump();
    await _until(tester, () => route.disposed);
    expect(route.handBack, isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'programmatic pop bypasses pending permission without closing its replacement',
    (tester) async {
      final host = _Harness();
      addTearDown(host.dispose);
      final first = await host.open(tester);
      await host.request(tester);
      host.nav.currentState!.pop();
      expect(first.closing, isTrue);
      final replacement = host.source.currentState!.open();
      await tester.pump();
      host.requests.single.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(replacement.closing, isFalse);
      expect(replacement.isCurrent, isTrue);
      host.nav.currentState!.pop();
      await _until(tester, () => replacement.disposed);
      await _until(tester, () => host.source.currentState!.motionSettled);
    },
  );

  testWidgets(
    'approval rechecks PopScope and local history before motion closes',
    (tester) async {
      final host = _Harness();
      addTearDown(host.dispose);
      final route = await host.open(tester);
      await host.request(tester);
      host.canPop.value = false;
      await tester.pump();
      host.requests.last.complete(true);
      await tester.pump();
      expect(route.closing, isFalse);
      host.canPop.value = true;
      await tester.pump();
      await host.request(tester);
      var removed = false;
      route.addLocalHistoryEntry(
        LocalHistoryEntry(onRemove: () => removed = true),
      );
      host.requests.last.complete(true);
      await tester.pump();
      expect(removed, isTrue);
      expect(route.closing, isFalse);
      expect(route.frame.progress, closeTo(1, 1e-3));
      await host.request(tester);
      host.requests.last.complete(true);
      await tester.pump();
      await _until(tester, () => route.disposed);
      await _until(tester, () => host.source.currentState!.motionSettled);
    },
  );

  testWidgets(
    'outside dismissal awaits SDK permission before changing motion',
    (tester) async {
      final source = GlobalKey<ProbeMenuSourceState>();
      final permission = Completer<bool>();
      var requests = 0;
      addTearDown(() {
        if (!permission.isCompleted) permission.complete(false);
      });
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFFFFFFFF),
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => ProbeMenuSource(
              key: source,
              pointerInput: true,
              now: () => Duration(
                microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
              ),
              menuBuilder: (_) => WillPopScope(
                onWillPop: () {
                  requests++;
                  return permission.future;
                },
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.tapAt(_button.center);
      final route = source.currentState!.activeRoute!;
      await _until(tester, () => route.animation!.isCompleted);
      await tester.tapAt(const Offset(350, 500));
      await tester.pump(const Duration(milliseconds: 80));
      expect(requests, 1);
      expect(route.closing, isFalse);
      permission.complete(false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(route.closing, isFalse);
      expect(route.frame.progress, closeTo(1, 1e-3));
    },
  );
}

// ignore_for_file: deprecated_member_use, implementation_imports, invalid_use_of_internal_member
