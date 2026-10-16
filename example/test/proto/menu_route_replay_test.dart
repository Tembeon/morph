import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/motion.dart';
import 'package:morph_example/proto/menu_route_probe.dart';
import 'package:morph_example/proto/menu_transfer_probe.dart';

typedef _Touch = ({double at, double delivered, int phase, Offset position});

class _Recording {
  _Recording(this.name);

  final String name;
  late final rows = [
    for (final line in File(
      '../test/fixtures/ios27-device/menu/$name.jsonl',
    ).readAsLinesSync())
      if (line.trim().isNotEmpty)
        (jsonDecode(line) as Map).cast<String, Object?>(),
  ];

  late final List<_Touch> touches = [
    for (final row in rows)
      if (row['k'] == 'touch')
        (
          at: (row['t']! as num).toDouble(),
          delivered: ((row['delivered_t'] ?? row['t'])! as num).toDouble(),
          phase: row['phase']! as int,
          position: Offset(
            (row['x']! as num).toDouble(),
            (row['y']! as num).toDouble(),
          ),
        ),
  ];

  bool get flex => name.startsWith('drag-out');

  Rect get button => flex
      ? Rect.fromLTWH(179, name.contains('upward') ? 760 : 300, 44, 44)
      : const Rect.fromLTWH(177, 413, 48, 48);

  MorphMenuMotion motion() => MorphMenuMotion(
    button: button,
    bounds: const Size(402, 874),
    padding: const EdgeInsets.only(top: 62, bottom: 34),
    itemCount: flex ? 4 : 3,
    tuning: flex ? const MorphMenuTuning(verticalPadding: 41) : .standard,
  );

  List<int> get selections => [
    for (final row in rows)
      if (row['k'] == 'action')
        const {'Copy': 0, 'Share': 1, 'Delete': 2}[row['title']]!,
  ];
}

class _Observer extends NavigatorObserver {
  final routes = <ProbeMenuRoute>[];

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    if (route is ProbeMenuRoute) routes.add(route);
  }
}

void _same(ProbeMenuFrame actual, MorphMenuMotion reference) {
  expect(actual.time, closeTo(reference.time, 1e-9));
  for (final (a, b) in [
    (actual.progress, reference.progress),
    (actual.contentOpacity, reference.contentOpacity),
    (actual.buttonOpacity, reference.buttonLookOpacity),
  ]) {
    expect(a, closeTo(b, 1e-9));
  }
  for (final (a, b) in [
    (actual.buttonKick, reference.buttonKick),
    (actual.menuKick, reference.menuKick),
    (actual.fusionRadius, reference.fusionRadius),
  ]) {
    expect(a, closeTo(b, 1e-8));
  }
  for (final (a, b) in [
    (actual.button, reference.buttonBlob.rrect),
    (actual.menu, reference.menuBlob.rrect),
  ]) {
    expect(a.left, closeTo(b.left, 1e-8));
    expect(a.top, closeTo(b.top, 1e-8));
    expect(a.right, closeTo(b.right, 1e-8));
    expect(a.bottom, closeTo(b.bottom, 1e-8));
    expect(a.tlRadiusX, closeTo(b.tlRadiusX, 1e-8));
  }
}

void _apply(MorphMenuMotion reference, ProbeMenuSample sample) {
  switch (sample.kind) {
    case .ignoredPointer:
      break;
    case .frame:
      reference.advance(sample.time);
    case .open:
      reference.open(sample.time);
    case .close:
      reference.close(sample.time);
    case .cancelInput:
      reference.pointerCancel(sample.time);
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
  _same(sample.frame, reference);
}

void main() {
  for (final rate in [60, 120]) {
    for (final name in [
      'center3-tap',
      'center3-dismiss',
      'center3-hold700',
      'center3-select',
      'center3-dragselect',
      'center3-closemidopen',
      'center3-reopen2-50',
      'center3-reopen2-350',
      'drag-out-flex',
      'drag-out-upward-flex',
    ]) {
      testWidgets('$name: raw recorded input through root route at $rate Hz', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(402, 874);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final recording = _Recording(name);
        final baselineRoutes =
            tester.binding.pointerRouter.debugGlobalRouteCount;
        final reference = recording.motion();
        final selected = <int>[];
        final expectedSelected = <int>[];
        reference.onSelected = expectedSelected.add;
        final nav = GlobalKey<NavigatorState>();
        final source = GlobalKey<ProbeMenuSourceState>();
        final observer = _Observer();
        var samples = 0;
        var appliedPointers = 0;
        var ignoredPointers = 0;
        final ignoredStreams = <int>{};
        Duration? delivery;
        final pointerOffset = rate == 120
            ? const Duration(seconds: 37)
            : Duration.zero;
        Duration now() =>
            delivery ??
            Duration(
              microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
            );
        await tester.pumpWidget(
          WidgetsApp(
            color: const Color(0xFFFFFFFF),
            navigatorKey: nav,
            navigatorObservers: [observer],
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              pageBuilder: (_, _, _) => ProbeMenuSource(
                key: source,
                button: recording.button,
                pointerInput: true,
                now: now,
                pointerOffset: () => pointerOffset,
                createMotion: () {
                  final motion = recording.motion();
                  motion.onSelected = selected.add;
                  return motion;
                },
                onSample: (sample) {
                  samples++;
                  if (sample.kind == .pointer) appliedPointers++;
                  if (sample.kind == .ignoredPointer) {
                    ignoredPointers++;
                    final event = sample.event!;
                    if (event is PointerDownEvent) {
                      expect(source.currentState!.activeRoute, isNull);
                      expect(
                        recording.button.contains(event.position),
                        isFalse,
                      );
                      ignoredStreams.add(event.pointer);
                    } else {
                      expect(ignoredStreams.contains(event.pointer), isTrue);
                      if (event is PointerUpEvent ||
                          event is PointerCancelEvent) {
                        ignoredStreams.remove(event.pointer);
                      }
                    }
                  }
                  _apply(reference, sample);
                },
                menuBuilder: (_) => const SizedBox.expand(),
              ),
            ),
          ),
        );
        final epoch = now();
        final first = recording.touches.first.at;
        final end = recording.touches.last.delivered - first;
        var next = 0;
        var last = Offset.zero;
        var frame = 1;
        while ((frame - 1) / rate <= end + 2) {
          final frameTime = frame / rate;
          while (next < recording.touches.length &&
              recording.touches[next].delivered - first <= frameTime) {
            final touch = recording.touches[next++];
            final stamp =
                epoch +
                Duration(microseconds: ((touch.at - first) * 1e6).round()) -
                pointerOffset;
            delivery =
                epoch +
                Duration(
                  microseconds: ((touch.delivered - first) * 1e6).round(),
                );
            final PointerEvent event = switch (touch.phase) {
              0 => PointerDownEvent(
                pointer: 1,
                kind: .touch,
                timeStamp: stamp,
                position: touch.position,
                buttons: kPrimaryButton,
              ),
              3 => PointerUpEvent(
                pointer: 1,
                kind: .touch,
                timeStamp: stamp,
                position: touch.position,
              ),
              _ => PointerMoveEvent(
                pointer: 1,
                kind: .touch,
                timeStamp: stamp,
                position: touch.position,
                delta: touch.position - last,
                buttons: kPrimaryButton,
              ),
            };
            await tester.sendEventToBinding(event);
            last = touch.position;
            delivery = null;
          }
          final until = Duration(microseconds: (frameTime * 1e6).round());
          final elapsed = now() - epoch;
          await tester.pump(until - elapsed);
          frame++;
        }
        expect(next, recording.touches.length);
        expect(appliedPointers + ignoredPointers, recording.touches.length);
        expect(ignoredStreams, isEmpty);
        expect(observer.routes, isNotEmpty);
        if (name.contains('reopen')) {
          expect(observer.routes.length, greaterThan(1));
        }
        expect(selected, expectedSelected);
        expect(selected, recording.selections);
        final active = source.currentState!.activeRoute;
        if (active != null && !active.closing) nav.currentState!.pop();
        for (var i = 0; i < rate * 4; i++) {
          if (source.currentState!.motionSettled &&
              observer.routes.every((route) => route.disposed)) {
            break;
          }
          await tester.pump(Duration(microseconds: (1e6 / rate).round()));
        }
        expect(observer.routes.every((route) => route.disposed), isTrue);
        expect(source.currentState!.ownsMotion, isTrue);
        expect(source.currentState!.motionSettled, isTrue);
        expect(tester.binding.transientCallbackCount, 0);
        expect(samples, greaterThan(10));
        debugPrint(
          'P2_REPLAY ${jsonEncode({'recording': name, 'rate': rate, 'pointerOffsetUs': pointerOffset.inMicroseconds, 'touches': next, 'samples': samples, 'routes': observer.routes.length, 'handBacks': observer.routes.where((route) => route.handBack != null).length, 'selected': selected})}',
        );
        await tester.pumpWidget(const SizedBox());
        expect(
          tester.binding.pointerRouter.debugGlobalRouteCount,
          baselineRoutes,
        );
      }, timeout: const Timeout(Duration(seconds: 60)));
    }
  }
}
