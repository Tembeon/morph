import 'package:flutter_test/flutter_test.dart';
import 'package:morph_example/proto/motion_clock_probe.dart';

void main() {
  for (final fromListener in [false, true]) {
    for (final settled in [false, true]) {
      testWidgets(
        'clock disposal from ${fromListener ? 'listener' : 'sample'} with settled=$settled stops publication',
        (tester) async {
          var samples = 0;
          var notifications = 0;
          late final ProbeMotionClock clock;
          clock = ProbeMotionClock(
            vsync: const TestVSync(),
            now: () => Duration(
              microseconds: tester.binding.clock.now().microsecondsSinceEpoch,
            ),
            pointerOffset: () => null,
            onFrame: (_) {
              samples++;
              if (!fromListener) clock.dispose();
              return (settled: settled, wakeTime: settled ? null : 10);
            },
          );
          clock.frames.addListener(() {
            notifications++;
            if (fromListener) clock.dispose();
          });
          clock.wake();
          await tester.pump();
          await tester.pump(const Duration(seconds: 20));
          expect(samples, 1);
          expect(notifications, fromListener ? 1 : 0);
          expect(tester.binding.transientCallbackCount, 0);
        },
      );
    }
  }
}
