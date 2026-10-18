import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph_example/proto/motion_clock_probe.dart';

typedef _Read = ({double clockTime, double frameTime, double microtaskTime});

void main() {
  for (final rate in [60, 120]) {
    for (final dilation in [1.0, 5.0]) {
      for (final writerFirst in [true, false]) {
        testWidgets('input from another ticker at $rate Hz, ${dilation}x, '
            '${writerFirst ? 'writer' : 'reader'} ticks first', (tester) async {
          await tester.pumpWidget(const SizedBox());
          final original = timeDilation;
          timeDilation = dilation;
          var running = true;
          final reader = ProbeMotionClock(
            vsync: const TestVSync(),
            now: () => Duration(
              microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
            ),
            pointerOffset: () => null,
            frameRate: rate.toDouble(),
            onFrame: (_) => (settled: !running, wakeTime: null),
          );
          final reads = <_Read>[];
          final sampled = <double>[];
          final writer = const TestVSync().createTicker((_) {
            final clockTime = reader.time;
            final frameTime = reader.frameTime;
            scheduleMicrotask(() {
              reads.add((
                clockTime: clockTime,
                frameTime: frameTime,
                microtaskTime: reader.time,
              ));
            });
          });
          final frame = Duration(microseconds: (1e6 / rate * dilation).round());
          try {
            if (writerFirst) {
              unawaited(writer.start());
              reader.wake();
            } else {
              reader.wake();
              unawaited(writer.start());
            }
            for (var i = 0; i < 24; i++) {
              await tester.pump(frame);
              sampled.add(reader.time);
            }
            for (var i = 4; i < reads.length; i++) {
              final read = reads[i];
              final now = sampled[i];
              final previous = sampled[i - 1];
              expect(read.microtaskTime, closeTo(now, 1e-9));
              expect(read.frameTime, closeTo(now, 1e-5));
              expect(
                read.clockTime,
                closeTo(writerFirst ? previous : now, 1e-9),
                reason: 'the last sampled time depends on the tick order',
              );
            }
            running = false;
            writer.stop();
            await tester.pump(frame);
            await tester.pump(frame);
            expect(tester.binding.hasScheduledFrame, isFalse);
          } finally {
            writer.dispose();
            reader.dispose();
            timeDilation = original;
          }
        });
      }
    }
  }
}
