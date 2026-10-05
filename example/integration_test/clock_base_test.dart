import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph_example/lab/lab_clocks.dart';

/// Which clock the engine's frame time stamps, the Dart clocks and the
/// pointer time stamps count in on the device.
///
/// Every frame for four seconds logs the frame's vsync stamp
/// (`currentSystemFrameTimeStamp`) next to the Dart timeline clock and
/// the Darwin uptime (CLOCK_UPTIME_RAW, the base of UITouch.timestamp)
/// and monotonic (CLOCK_MONOTONIC_RAW) clocks read at the frame callback,
/// plus the FrameTimings. Build a profile app (`flutter build ios
/// --profile -t integration_test/clock_base_test.dart`), launch it with
/// devicectl and pull `tmp/clock/report.json` from the app's data
/// container.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('clock base', semanticsEnabled: false, (
    WidgetTester tester,
  ) async {
    final frames = <Map<String, Object?>>[];
    final timings = <Map<String, Object?>>[];
    void onTimings(List<FrameTiming> list) {
      for (final timing in list) {
        timings.add({
          'vsync_us': timing.timestampInMicroseconds(FramePhase.vsyncStart),
          'build_start_us': timing.timestampInMicroseconds(
            FramePhase.buildStart,
          ),
          'build_finish_us': timing.timestampInMicroseconds(
            FramePhase.buildFinish,
          ),
          'raster_start_us': timing.timestampInMicroseconds(
            FramePhase.rasterStart,
          ),
          'raster_finish_us': timing.timestampInMicroseconds(
            FramePhase.rasterFinish,
          ),
        });
      }
    }

    SchedulerBinding.instance.addTimingsCallback(onTimings);
    await tester.pumpWidget(const _Spinner());
    final ticker = Ticker((Duration elapsed) {
      final scheduler = SchedulerBinding.instance;
      frames.add({
        'frame_source_us': scheduler.currentSystemFrameTimeStamp.inMicroseconds,
        'frame_us': scheduler.currentFrameTimeStamp.inMicroseconds,
        'timeline_us': Timeline.now,
        'uptime_us': labUptimeMicros(),
        'monotonic_us': labMonotonicMicros(),
      });
    });
    ticker.start();
    await tester.pump(const Duration(seconds: 4));
    ticker.dispose();
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    final out = Directory('${Directory.systemTemp.path}/clock');
    out.createSync(recursive: true);
    File('${out.path}/report.json').writeAsStringSync(
      const JsonEncoder.withIndent(
        ' ',
      ).convert({'frames': frames, 'timings': timings}),
    );
  });
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: Center(child: CircularProgressIndicator()));
  }
}
