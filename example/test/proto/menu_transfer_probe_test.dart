import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/motion.dart';
import 'package:morph_example/proto/menu_transfer_probe.dart';
import 'package:morph_example/proto/motion_clock_probe.dart';

MorphMenuMotion _motion() => MorphMenuMotion(
  button: const Rect.fromLTWH(24, 80, 44, 44),
  sourceHeight: 64,
  sourceRadius: 22,
  itemCount: 3,
  bounds: const Size(402, 874),
);

ProbeMenuFrame _frame(MorphMenuMotion motion) => (
  time: motion.time,
  progress: motion.progress,
  button: motion.buttonBlob.rrect,
  menu: motion.menuBlob.rrect,
  buttonKick: motion.buttonKick,
  menuKick: motion.menuKick,
  contentOpacity: motion.contentOpacity,
  buttonOpacity: motion.buttonLookOpacity,
  fusionRadius: motion.fusionRadius,
);

void _same(ProbeMenuFrame actual, ProbeMenuFrame expected) {
  expect(actual.time, closeTo(expected.time, 1e-9));
  expect(actual.progress, closeTo(expected.progress, 1e-9));
  expect(actual.buttonKick, closeTo(expected.buttonKick, 1e-8));
  expect(actual.menuKick, closeTo(expected.menuKick, 1e-8));
  expect(actual.contentOpacity, closeTo(expected.contentOpacity, 1e-9));
  expect(actual.buttonOpacity, closeTo(expected.buttonOpacity, 1e-9));
  expect(actual.fusionRadius, closeTo(expected.fusionRadius, 1e-8));
  for (final pair in [
    (actual.button, expected.button),
    (actual.menu, expected.menu),
  ]) {
    final (a, b) = pair;
    for (final delta in [
      a.left - b.left,
      a.top - b.top,
      a.right - b.right,
      a.bottom - b.bottom,
      a.tlRadiusX - b.tlRadiusX,
      a.blRadiusX - b.blRadiusX,
    ]) {
      expect(delta, closeTo(0, 1e-8));
    }
  }
}

void main() {
  for (final rate in [60, 120]) {
    for (final sourceOrigin in [0.0, 0.003, 73.0]) {
      for (final reopenDelay in <double?>[null, 0.05, 0.30, 0.55]) {
        test(
          '$rate Hz, source=$sourceOrigin, reopen=$reopenDelay: complete model stays continuous',
          () {
            final reference = _motion();
            final source = ProbeMenuLease(.source);
            final firstRoute = ProbeMenuLease(.route);
            final nextRoute = ProbeMenuLease(.route);
            final transfer = ProbeMenuTransfer(
              motion: _motion(),
              source: source,
              sourceTime: sourceOrigin,
            );
            transfer.open(source, sourceOrigin);
            reference.open(0);
            var active = firstRoute;
            var origin = 123.0;
            var canonicalOrigin = 0.0;
            transfer.transfer(
              source,
              fromTime: sourceOrigin,
              to: active,
              toTime: origin,
            );
            var handedBack = false;
            var handBackCount = 0;
            var reopened = false;
            var closed = false;
            var closedAgain = false;
            double? handBackAt;
            for (var frame = 0; frame <= rate * 4; frame++) {
              final time = frame / rate;
              final local = origin + time - canonicalOrigin;
              expect(transfer.advance(active, local), isTrue);
              reference.advance(time);
              _same(transfer.frame, _frame(reference));
              if (!closed && time >= 1) {
                transfer.close(active, local);
                reference.close(time);
                closed = true;
              }
              if (closed && !handedBack && transfer.readyToHandBack) {
                final before = transfer.frame;
                expect(transfer.isSettled, isFalse);
                expect(
                  transfer.transfer(
                    active,
                    fromTime: local,
                    to: source,
                    toTime: sourceOrigin,
                  ),
                  isTrue,
                );
                _same(transfer.frame, before);
                active = source;
                origin = sourceOrigin;
                canonicalOrigin = time;
                handBackAt = time;
                handedBack = true;
                handBackCount++;
              }
              if (closed &&
                  !reopened &&
                  reopenDelay != null &&
                  time >= 1 + reopenDelay) {
                final current = origin + time - canonicalOrigin;
                if (reopenDelay <= 0.30) {
                  expect(active.kind, ProbeMenuOwnerKind.route);
                }
                if (reopenDelay == 0.55) {
                  expect(active, same(source));
                  expect(transfer.isSettled, isFalse);
                }
                transfer.open(active, current);
                reference.open(time);
                expect(
                  transfer.transfer(
                    active,
                    fromTime: current,
                    to: nextRoute,
                    toTime: 0.011,
                  ),
                  isTrue,
                );
                active = nextRoute;
                origin = 0.011;
                canonicalOrigin = time;
                reopened = true;
                handedBack = false;
                _same(transfer.frame, _frame(reference));
              }
              if (reopened && !closedAgain && time >= 2) {
                transfer.close(active, origin + time - canonicalOrigin);
                reference.close(time);
                closedAgain = true;
              }
            }
            expect(handedBack, isTrue);
            expect(handBackAt, greaterThan(1));
            expect(transfer.isSettled, isTrue);
            expect(transfer.owner, same(source));
            expect(handBackCount, reopenDelay == 0.55 ? 2 : 1);
            if (reopenDelay != null) expect(reopened, isTrue);
          },
        );
      }
    }
  }

  test(
    'callbacks from an earlier route lease cannot write after a route-to-route reopen',
    () {
      final source = ProbeMenuLease(.source);
      final route = ProbeMenuLease(.route);
      final reopened = ProbeMenuLease(.route);
      final motion = ProbeMenuTransfer(
        motion: _motion(),
        source: source,
        sourceTime: 0,
      );
      motion.open(source, 0);
      motion.transfer(source, fromTime: 0, to: route, toTime: 10);
      motion.advance(route, 10.15);
      motion.close(route, 10.15);
      motion.advance(route, 10.20);
      motion.open(route, 10.20);
      motion.transfer(route, fromTime: 10.20, to: reopened, toTime: 0);
      final before = motion.frame;
      expect(motion.advance(route, 1000), isFalse);
      expect(motion.close(route, 1000), isFalse);
      expect(motion.open(route, 1000), isFalse);
      expect(
        motion.transfer(route, fromTime: 1000, to: source, toTime: 0),
        isFalse,
      );
      expect(motion.frame, before);
      expect(motion.owner, same(reopened));
    },
  );

  for (final dilation in [1.0, 5.0]) {
    for (final dozing in [false, true]) {
      for (final anchored in [false, true]) {
        testWidgets(
          '${anchored ? 'frame anchor' : 'negative control: plain wake'}, dozing=$dozing, dilation=$dilation at first source frame',
          (tester) async {
            await tester.pumpWidget(const SizedBox());
            final source = ProbeMenuLease(.source);
            final route = ProbeMenuLease(.route);
            final reference = _motion();
            final transfer = ProbeMenuTransfer(
              motion: _motion(),
              source: source,
              sourceTime: 0,
            );
            transfer.open(source, 0);
            reference.open(0);
            transfer.transfer(source, fromTime: 0, to: route, toTime: 0);
            var warming = true;
            final clock = ProbeMotionClock(
              vsync: const TestVSync(),
              now: () => SchedulerBinding.instance.currentSystemFrameTimeStamp,
              pointerOffset: () => Duration.zero,
              onFrame: (time) {
                transfer.advance(source, time);
                final ownsModel = identical(transfer.owner, source);
                return (
                  settled:
                      !warming && (ownsModel ? transfer.isSettled : !dozing),
                  wakeTime: !warming && dozing && !ownsModel
                      ? time + 0.5
                      : null,
                );
              },
            );
            final originalDilation = timeDilation;
            timeDilation = dilation;
            final frameDuration = Duration(
              microseconds: (8333 * dilation).round(),
            );
            try {
              clock.wake();
              for (var i = 0; i < 8; i++) {
                await tester.pump(frameDuration);
              }
              warming = false;
              await tester.pump(frameDuration);
              var handBack = -1.0;
              var sourceAnchor = 0.0;
              for (var frame = 0; frame < 240; frame++) {
                final time = frame / 120;
                tester.binding.addPostFrameCallback((_) {
                  transfer.advance(route, time);
                  reference.advance(time);
                  if (frame == 120) {
                    transfer.close(route, time);
                    reference.close(time);
                  }
                  if (!transfer.readyToHandBack) return;
                  sourceAnchor = anchored
                      ? clock.resumeFromFrame(
                          SchedulerBinding.instance.currentSystemFrameTimeStamp,
                        )
                      : clock.time;
                  transfer.transfer(
                    route,
                    fromTime: time,
                    to: source,
                    toTime: sourceAnchor,
                  );
                  handBack = time;
                });
                tester.binding.scheduleFrame();
                await tester.pump(frameDuration);
                if (handBack >= 0) break;
              }
              expect(handBack, greaterThan(1));
              if (!anchored) clock.wake();
              await tester.pump(frameDuration);
              if (anchored) {
                reference.advance(handBack + 0.008333);
                _same(transfer.frame, _frame(reference));
                expect(clock.time, closeTo(sourceAnchor + 0.008333, 1e-9));
              } else if (dozing) {
                expect(transfer.frame.time, greaterThan(handBack + 0.05));
              } else {
                expect(clock.time, sourceAnchor);
                expect(transfer.frame.time, closeTo(handBack, 1e-9));
              }
            } finally {
              clock.dispose();
              timeDilation = originalDilation;
            }
          },
        );
      }
    }
  }
}
